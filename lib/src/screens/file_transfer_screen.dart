import 'dart:io';
import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../models/file_transfer.dart';
import '../models/runtime_profile.dart';
import '../services/file_transfer_service.dart';
import 'received_files_history_screen.dart';

class FileTransferScreen extends StatefulWidget {
  final String peerId;

  const FileTransferScreen({super.key, required this.peerId});

  @override
  State<FileTransferScreen> createState() => _FileTransferScreenState();
}

class _FileTransferScreenState extends State<FileTransferScreen> {
  StreamSubscription<FileTransferSession>? _transferUpdateSubscription;
  final Set<String> _shownTransferSuccess = {};

  @override
  void initState() {
    super.initState();
    final appState = Provider.of<AppState>(context, listen: false);
    _transferUpdateSubscription =
        appState.fileTransferService.onTransferUpdate.listen((session) {
      if (!mounted) return;
      if (session.peerId != widget.peerId) return;
      if (session.state != FileTransferState.completed) return;
      if (session.direction != TransferDirection.receiving) return;

      final key = '${session.fileId}:recv';
      if (_shownTransferSuccess.contains(key)) return;
      _shownTransferSuccess.add(key);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'File received and saved: ${session.metadata.fileName}',
          ),
        ),
      );
    });
  }

  @override
  void dispose() {
    _transferUpdateSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final service = appState.fileTransferService;
    final canSendToPeer = appState.canSendFileToPeer(widget.peerId);
    final remoteProfile = appState.peerRuntimeProfile(widget.peerId);
    final sessions = service
        .transfersForPeer(widget.peerId)
        .where((s) =>
            s.state != FileTransferState.completed &&
            s.state != FileTransferState.cancelled)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('File Transfer'),
        actions: [
          IconButton(
            icon: const Icon(Icons.upload_file),
            onPressed: canSendToPeer ? () => _pickAndSend(service) : null,
          ),
        ],
      ),
      body: !appState.allowsFileTransfers
          ? const Center(
              child: Text(
                'File transfer is disabled in the current profile.',
                textAlign: TextAlign.center,
              ),
            )
          : !canSendToPeer && sessions.isEmpty
              ? Center(
                  child: Text(
                    remoteProfile == RuntimeProfile.normalMesh
                        ? 'Peer is in Mesh profile.\nFile transfer is unavailable.'
                        : remoteProfile == RuntimeProfile.emergencyBattery
                            ? 'Peer is in Battery Saver profile.\nFile transfer is unavailable.'
                            : 'File transfer unavailable for this peer.',
                    textAlign: TextAlign.center,
                  ),
                )
              : sessions.isEmpty
                  ? const Center(
                      child: Text(
                        'No active transfers for this peer.\nUse the upload icon to send files.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.builder(
                      itemCount: sessions.length,
                      itemBuilder: (context, index) =>
                          _buildCard(service, sessions[index]),
                    ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Received Files',
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const ReceivedFilesHistoryScreen(),
            ),
          );
        },
        child: const Icon(Icons.folder_open_rounded),
      ),
    );
  }

  Future<void> _pickAndSend(FileTransferService service) async {
    final appState = Provider.of<AppState>(context, listen: false);
    if (!appState.canSendFileToPeer(widget.peerId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('File transfer unavailable for this peer')),
      );
      return;
    }
    final result = await FilePicker.platform.pickFiles(allowMultiple: false);
    if (!mounted || result == null || result.files.isEmpty) return;
    final filePath = result.files.single.path;
    if (filePath == null || !File(filePath).existsSync()) return;
    await service.sendFile(peerId: widget.peerId, filePath: filePath);
    if (mounted) setState(() {});
  }

  Widget _buildCard(FileTransferService service, FileTransferSession session) {
    final progressPercent = (session.progress * 100).toStringAsFixed(1);
    final isSender = session.direction == TransferDirection.sending;
    final statusText = (!isSender && session.state == FileTransferState.paused)
        ? 'Sender paused sending'
        : session.state.name;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              session.metadata.fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
                '${session.chunkTracker.receivedCount}/${session.metadata.totalChunks} chunks'),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: session.progress),
            const SizedBox(height: 6),
            Text(
              'Status: $statusText • $progressPercent%',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                if (isSender && session.state == FileTransferState.transferring)
                  OutlinedButton(
                    onPressed: () => service.pauseTransfer(session.fileId),
                    child: const Text('Pause'),
                  ),
                if (isSender &&
                    (session.state == FileTransferState.paused ||
                        session.state == FileTransferState.failed))
                  OutlinedButton(
                    onPressed: () => service.resumeTransfer(session.fileId),
                    child: const Text('Resume'),
                  ),
                OutlinedButton(
                  onPressed: () => service.cancelTransfer(session.fileId),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
