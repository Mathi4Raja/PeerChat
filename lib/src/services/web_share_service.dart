import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:mime/mime.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

class UploadRequest {
  final String id;
  final String filename;
  final int size;
  
  UploadRequest({required this.id, required this.filename, required this.size});
}


class WebShareService {
  HttpServer? _server;
  final List<PlatformFile> _sharedFiles = [];
  bool _isRunning = false;
  
  final _eventController = StreamController<String>.broadcast();
  Stream<String> get onEvent => _eventController.stream;
  
  final List<String> _eventLog = [];
  List<String> get eventLog => _eventLog;

  final _uploadRequestController = StreamController<UploadRequest>.broadcast();
  Stream<UploadRequest> get onUploadRequest => _uploadRequestController.stream;

  final Map<String, Completer<bool>> _pendingApprovals = {};
  final Set<String> _approvedTokens = {};
  final Set<String> _activeTransfers = {};
  final Set<String> _completedPaths = {};
  final _uuid = const Uuid();


  bool get isRunning => _isRunning;
  List<PlatformFile> get sharedFiles => _sharedFiles;
  Set<String> get activeTransfers => _activeTransfers;

  bool isDownloaded(String path) => _completedPaths.contains(path);

  String? _localIp;
  String? get currentUrl => _localIp != null ? 'http://$_localIp:8080' : null;

  void addFiles(List<PlatformFile> files) {
    for (var f in files) {
      if (!_sharedFiles.where((sf) => sf.path == f.path).isNotEmpty) {
        _sharedFiles.add(f);
      }
    }
  }

  void removeFile(PlatformFile file) {
    _sharedFiles.removeWhere((f) => f.path == file.path);
    _cleanupIfTemp(file.path);
  }

  void clearLog() {
    _eventLog.clear();
    _eventController.add('LOG_UPDATED');
  }

  void removeLogEntry(int index) {
    if (index >= 0 && index < _eventLog.length) {
      _eventLog.removeAt(index);
      _eventController.add('LOG_UPDATED');
    }
  }

  void respondToUpload(String requestId, bool accepted) {
    final completer = _pendingApprovals.remove(requestId);
    if (completer != null) {
      completer.complete(accepted);
    }
  }


  void _addEvent(String message) {
    final timestamp = DateTime.now().toString().substring(11, 16);
    final logEntry = "[$timestamp] $message";
    _eventLog.insert(0, logEntry);
    if (_eventLog.length > 50) _eventLog.removeLast();
    _eventController.add(logEntry);
  }

  void _cleanupIfTemp(String? path) {
    if (path == null) return;
    // file_picker typically uses 'cache/file_picker' on Android/iOS
    if (path.contains('cache/file_picker') || path.contains('tmp/')) {
      try {
        final file = File(path);
        if (file.existsSync()) {
          file.deleteSync();
          debugPrint("Cleaned up temp file: $path");
        }
      } catch (e) {
        debugPrint("Error cleaning up temp file: $e");
      }
    }
  }


  Future<void> startServer() async {
    if (_isRunning) return;

    try {
      _localIp = await _getLocalIp();
      _server = await HttpServer.bind(InternetAddress.anyIPv4, 8080);
      _isRunning = true;

      _server!.listen(_handleRequest);
    } catch (e) {
      debugPrint("Error starting server: $e");
      _isRunning = false;
      rethrow;
    }
  }

  Future<void> stopServer() async {
    if (!_isRunning) return;
    
    // Cleanup any lingering temp files
    for (var file in _sharedFiles) {
      _cleanupIfTemp(file.path);
    }
    _sharedFiles.clear();

    await _server?.close();
    _server = null;
    _isRunning = false;
    _addEvent("Sharing server stopped");
  }


  Future<String?> _getLocalIp() async {
    try {
      for (var interface in await NetworkInterface.list()) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            return addr.address;
          }
        }
      }
    } catch (e) {
      debugPrint("Error getting local IP: $e");
    }
    return null;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      if (request.method == 'GET' && request.uri.path == '/') {
        request.response
          ..headers.contentType = ContentType.html
          ..write(_generateHtml());
        await request.response.close();
        return;
      }

      if (request.method == 'GET' && request.uri.path == '/download') {
        final id = request.uri.queryParameters['id'];
        if (id != null) {
          final idx = int.tryParse(id);
          if (idx != null && idx >= 0 && idx < _sharedFiles.length) {
              final fileInfo = _sharedFiles[idx];
              final file = File(fileInfo.path!);
              
              if (await file.exists()) {
                request.response.headers.contentType = ContentType.binary;
                request.response.headers.add('Content-Disposition', 'attachment; filename="${fileInfo.name}"');
                request.response.headers.add('Content-Length', fileInfo.size);
                
                _activeTransfers.add(fileInfo.name);
                _addEvent("Sending: ${fileInfo.name}");
                
                await request.response.addStream(file.openRead());
                await request.response.close();
                
                if (fileInfo.path != null) {
                  _completedPaths.add(fileInfo.path!);
                }
                
                _activeTransfers.remove(fileInfo.name);
                _addEvent("Sent: ${fileInfo.name}");
                return;
              }
          }
        }
        request.response.statusCode = HttpStatus.notFound;
        request.response.write("File not found");
        await request.response.close();
        return;
      }

      if (request.method == 'POST' && request.uri.path == '/request_upload') {
        final content = await utf8.decodeStream(request);
        final data = jsonDecode(content);
        final filename = data['filename'] as String;
        final size = data['size'] as int;
        
        final requestId = _uuid.v4();
        final completer = Completer<bool>();
        _pendingApprovals[requestId] = completer;
        
        _uploadRequestController.add(UploadRequest(
          id: requestId, 
          filename: filename, 
          size: size
        ));
        
        final accepted = await completer.future.timeout(
          const Duration(minutes: 2), 
          onTimeout: () => false
        );
        
        if (accepted) {
          final token = _uuid.v4();
          _approvedTokens.add(token);
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({'status': 'accepted', 'token': token}));
        } else {
          request.response
            ..statusCode = HttpStatus.forbidden
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({'status': 'rejected', 'message': 'Upload rejected by host'}));
        }
        await request.response.close();
        return;
      }

      if (request.method == 'POST' && request.uri.path == '/upload') {
        final token = request.uri.queryParameters['token'];
        if (token == null || !_approvedTokens.contains(token)) {
          request.response
            ..statusCode = HttpStatus.unauthorized
            ..write("Missing or invalid upload token")
            ..close();
          return;
        }
        _approvedTokens.remove(token);

        final contentType = request.headers.contentType;
        if (contentType != null && contentType.primaryType == 'multipart') {
          await _handleFileUpload(request, contentType.parameters['boundary']!);
          request.response
            ..statusCode = HttpStatus.ok
            ..write("Upload complete")
            ..close();
          return;
        }
        request.response.statusCode = HttpStatus.badRequest;
        request.response.write("Bad request");
        await request.response.close();
        return;
      }

      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    } catch (e) {
      debugPrint("Server error: $e");
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (_) {}
    }
  }

  Future<void> _handleFileUpload(HttpRequest request, String boundary) async {
    final transformer = MimeMultipartTransformer(boundary);
    final parts = request.cast<List<int>>().transform(transformer);

    await for (final part in parts) {
      final contentDisposition = part.headers['content-disposition'];
      if (contentDisposition != null && contentDisposition.contains('filename=')) {
        final RegExp regex = RegExp(r'filename="([^"]+)"');
        final match = regex.firstMatch(contentDisposition);
        if (match != null) {
          final filename = match.group(1)!;
          
          Directory? dir;
          if (Platform.isAndroid) {
            dir = Directory('/storage/emulated/0/Download');
            if (!await dir.exists()) {
              dir = await getApplicationDocumentsDirectory();
            }
          } else {
            dir = await getApplicationDocumentsDirectory();
          }
          
          final savedFilePath = p.join(dir.path, filename);
          final sink = File(savedFilePath).openWrite();
          
          _activeTransfers.add(filename);
          _addEvent("Receiving: $filename");
          
          await part.pipe(sink);
          
          _activeTransfers.remove(filename);
          _addEvent("Received: $filename");
          debugPrint("Saved uploaded file to $savedFilePath");
        }
      }
    }
  }

  String _generateHtml() {
    final filesHtml = _sharedFiles.asMap().entries.map((entry) {
      final idx = entry.key;
      final file = entry.value;
      return '''
        <div class="file-card">
          <div class="file-info">
            <span class="file-name">${file.name}</span>
            <span class="file-size">${(file.size / 1024 / 1024).toStringAsFixed(2)} MB</span>
          </div>
          <a href="/download?id=$idx" class="btn btn-download">Download</a>
        </div>
      ''';
    }).join('\n');

    return '''
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>PeerChat Web Share</title>
    <style>
        :root {
            --bg-deep: #181626;
            --bg-card: #262438;
            --bg-surface: #383554;
            --primary: #8B5CF6;
            --primary-hover: #7C3AED;
            --text-primary: #F5F3FF;
            --text-secondary: #D4D0E0;
            --font-family: 'Inter', system-ui, sans-serif;
        }

        body {
            margin: 0;
            padding: 0;
            background-color: var(--bg-deep);
            color: var(--text-primary);
            font-family: var(--font-family);
            -webkit-font-smoothing: antialiased;
            display: flex;
            flex-direction: column;
            align-items: center;
            min-height: 100vh;
        }

        header {
            width: 100%;
            background: linear-gradient(180deg, var(--bg-deep) 0%, var(--bg-card) 100%);
            padding: 2rem 1rem;
            text-align: center;
            border-bottom: 1px solid rgba(255, 255, 255, 0.05);
            box-sizing: border-box;
        }

        header h1 {
            margin: 0;
            font-weight: 700;
            letter-spacing: -0.02em;
        }

        .container {
            max-width: 600px;
            width: 100%;
            padding: 2rem 1rem;
            box-sizing: border-box;
        }

        .section {
            background-color: var(--bg-card);
            border-radius: 16px;
            padding: 1.5rem;
            margin-bottom: 2rem;
            box-shadow: 0 4px 20px rgba(0, 0, 0, 0.2);
            border: 1px solid rgba(255, 255, 255, 0.05);
        }

        .section h2 {
            margin-top: 0;
            font-size: 1.25rem;
            border-bottom: 1px solid var(--bg-surface);
            padding-bottom: 0.75rem;
            margin-bottom: 1rem;
        }

        .file-card {
            background-color: var(--bg-surface);
            padding: 1rem;
            border-radius: 12px;
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 0.75rem;
        }

        .file-card:last-child {
            margin-bottom: 0;
        }

        .file-info {
            display: flex;
            flex-direction: column;
            gap: 0.25rem;
            overflow: hidden;
            margin-right: 1rem;
        }

        .file-name {
            font-weight: 600;
            font-size: 1rem;
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
        }

        .file-size {
            font-size: 0.85rem;
            color: var(--text-secondary);
        }

        .btn {
            background-color: var(--primary);
            color: white;
            text-decoration: none;
            padding: 0.5rem 1rem;
            border-radius: 8px;
            font-weight: 600;
            font-size: 0.9rem;
            transition: background-color 0.2s;
            border: none;
            cursor: pointer;
            display: inline-block;
            text-align: center;
        }

        .btn:hover {
            background-color: var(--primary-hover);
        }

        .upload-form {
            display: flex;
            flex-direction: column;
            gap: 1.5rem;
        }

        .file-input-wrapper {
            position: relative;
            width: 100%;
        }

        .file-input {
            position: absolute;
            width: 100%;
            height: 100%;
            opacity: 0;
            cursor: pointer;
            z-index: 2;
        }

        .file-input-label {
            display: block;
            width: 100%;
            padding: 2.5rem 1.5rem;
            background-color: var(--bg-surface);
            border: 2px dashed rgba(255, 255, 255, 0.15);
            border-radius: 16px;
            text-align: center;
            box-sizing: border-box;
            color: var(--text-secondary);
            transition: all 0.2s;
            position: relative;
            z-index: 1;
        }

        .file-input:hover + .file-input-label {
            border-color: var(--primary);
            background-color: rgba(139, 92, 246, 0.05);
            color: var(--text-primary);
        }

        .status-overlay {
            display: none;
            position: fixed;
            top: 0;
            left: 0;
            right: 0;
            bottom: 0;
            background-color: rgba(24, 22, 38, 0.9);
            backdrop-filter: blur(8px);
            z-index: 1000;
            flex-direction: column;
            justify-content: center;
            align-items: center;
            padding: 2rem;
            text-align: center;
        }

        .status-card {
            background-color: var(--bg-card);
            padding: 2.5rem;
            border-radius: 24px;
            max-width: 400px;
            width: 100%;
            border: 1px solid rgba(255, 255, 255, 0.1);
            box-shadow: 0 20px 40px rgba(0,0,0,0.5);
        }

        .progress-container {
            width: 100%;
            height: 8px;
            background-color: var(--bg-surface);
            border-radius: 4px;
            margin: 1.5rem 0;
            overflow: hidden;
            display: none;
        }

        .progress-bar {
            height: 100%;
            width: 0%;
            background-color: var(--primary);
            transition: width 0.1s;
        }

        .loader {
            width: 48px;
            height: 48px;
            border: 4px solid var(--bg-surface);
            border-top: 4px solid var(--primary);
            border-radius: 50%;
            animation: spin 1s linear infinite;
            margin-bottom: 1.5rem;
        }

        @keyframes spin {
            0% { transform: rotate(0deg); }
            100% { transform: rotate(360deg); }
        }

        .btn-cancel {
            background-color: transparent;
            border: 1px solid rgba(255, 255, 255, 0.2);
            margin-top: 1rem;
        }

        .btn-cancel:hover {
            background-color: rgba(255, 255, 255, 0.05);
        }

        .empty-state {
            text-align: center;
            color: var(--text-secondary);
            padding: 2rem 0;
        }
    </style>
</head>
<body>
    <header>
        <h1>PeerChat WebShare</h1>
    </header>

    <div class="container">
        <div class="section">
            <h2>Available Files to Download</h2>
            ${_sharedFiles.isEmpty ? '<div class="empty-state">No files shared currently.</div>' : filesHtml}
        </div>

        <div class="section">
            <h2>Upload a File to Phone</h2>
            <div class="upload-form">
                <div class="file-input-wrapper">
                    <input class="file-input" type="file" id="fileSelector">
                    <div class="file-input-label" id="dropLabel">
                        <svg style="width: 32px; height: 32px; margin-bottom: 0.5rem; opacity: 0.6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7 16a4 4 0 01-.88-7.903A5 5 0 1115.9 6L16 6a5 5 0 011 9.9M15 13l-3-3m0 0l-3 3m3-3v12"/>
                        </svg>
                        <br>
                        <span id="fileName">Select or drag a file to upload</span>
                    </div>
                </div>
                <button class="btn" id="uploadBtn" style="width: 100%; font-size: 1rem; padding: 0.75rem;">Upload File</button>
            </div>
        </div>
    </div>

    <!-- Upload Status Overlay -->
    <div class="status-overlay" id="statusOverlay">
        <div class="status-card">
            <div class="loader" id="statusLoader"></div>
            <h3 id="statusTitle">Waiting for Approval</h3>
            <p id="statusDesc" style="color: var(--text-secondary); font-size: 0.9rem;">
                Please wait for the host to accept the transfer...
            </p>
            
            <div class="progress-container" id="progressContainer">
                <div class="progress-bar" id="progressBar"></div>
            </div>
            <div id="progressText" style="font-size: 0.8rem; margin-top: -0.5rem; margin-bottom: 1rem; display: none">0%</div>

            <button class="btn btn-cancel" id="cancelBtn">Cancel</button>
        </div>
    </div>

    <script>
        const fileSelector = document.getElementById('fileSelector');
        const fileName = document.getElementById('fileName');
        const uploadBtn = document.getElementById('uploadBtn');
        const statusOverlay = document.getElementById('statusOverlay');
        const statusTitle = document.getElementById('statusTitle');
        const statusDesc = document.getElementById('statusDesc');
        const statusLoader = document.getElementById('statusLoader');
        const progressContainer = document.getElementById('progressContainer');
        const progressBar = document.getElementById('progressBar');
        const progressText = document.getElementById('progressText');
        const cancelBtn = document.getElementById('cancelBtn');

        let currentRequest = null;

        fileSelector.onchange = () => {
            if (fileSelector.files.length > 0) {
                fileName.innerText = fileSelector.files[0].name;
            }
        };

        uploadBtn.onclick = async () => {
            if (fileSelector.files.length === 0) {
                alert('Please select a file first');
                return;
            }

            const file = fileSelector.files[0];
            
            // Show overlay
            statusOverlay.style.display = 'flex';
            statusTitle.innerText = 'Requesting Approval';
            statusDesc.innerText = `Waiting for host to accept "\${file.name}"...`;
            statusLoader.style.display = 'block';
            progressContainer.style.display = 'none';
            progressText.style.display = 'none';

            try {
                // Step 1: Handshake
                const response = await fetch('/request_upload', {
                    method: 'POST',
                    body: JSON.stringify({
                        filename: file.name,
                        size: file.size
                    })
                });

                const result = await response.json();

                if (result.status === 'accepted') {
                    // Step 2: Upload with Token
                    startUpload(file, result.token);
                } else {
                    showError('Upload Rejected', result.message || 'The host declined your transfer request.');
                }
            } catch (e) {
                showError('Connection Error', 'Failed to communicate with the phone.');
            }
        };

        function startUpload(file, token) {
            statusTitle.innerText = 'Uploading...';
            statusDesc.innerText = `Sending "\${file.name}"`;
            statusLoader.style.display = 'none';
            progressContainer.style.display = 'block';
            progressText.style.display = 'block';

            const xhr = new XMLHttpRequest();
            currentRequest = xhr;

            xhr.upload.onprogress = (e) => {
                if (e.lengthComputable) {
                    const percent = Math.round((e.loaded / e.total) * 100);
                    progressBar.style.width = percent + '%';
                    progressText.innerText = percent + '%';
                }
            };

            xhr.onload = () => {
                if (xhr.status === 200) {
                    statusTitle.innerText = 'Upload Complete';
                    statusDesc.innerText = 'File successfully saved to phone.';
                    cancelBtn.innerText = 'Close';
                    cancelBtn.onclick = () => location.reload();
                } else {
                    showError('Upload Failed', 'Server returned ' + xhr.status);
                }
            };

            xhr.onerror = () => showError('Upload Failed', 'Check your connection.');

            const formData = new FormData();
            formData.append('file', file);

            xhr.open('POST', `/upload?token=\${token}`);
            xhr.send(formData);
        }

        function showError(title, message) {
            statusTitle.innerText = title;
            statusDesc.innerText = message;
            statusLoader.style.display = 'none';
            progressContainer.style.display = 'none';
            progressText.style.display = 'none';
            cancelBtn.innerText = 'Close';
            cancelBtn.onclick = () => statusOverlay.style.display = 'none';
        }

        cancelBtn.onclick = () => {
            if (currentRequest) currentRequest.abort();
            statusOverlay.style.display = 'none';
        };
    </script>
</body>
</html>
''';
  }
}
