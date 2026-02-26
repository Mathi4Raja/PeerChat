import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import '../config/protocol_config.dart';
import '../utils/file_size_formatter.dart';

class ReceivedFilesHistoryScreen extends StatefulWidget {
  const ReceivedFilesHistoryScreen({super.key});

  @override
  State<ReceivedFilesHistoryScreen> createState() =>
      _ReceivedFilesHistoryScreenState();
}

class _ReceivedFilesHistoryScreenState
    extends State<ReceivedFilesHistoryScreen> {
  bool _isLoading = true;
  List<File> _files = [];
  String? _directoryPath;

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    setState(() {
      _isLoading = true;
    });

    final docsDir = await getApplicationDocumentsDirectory();
    final dir = Directory(
      '${docsDir.path}${Platform.pathSeparator}${FileTransferPathConfig.fallbackReceivedFolderName}',
    );

    final files = <File>[];
    if (await dir.exists()) {
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is File) {
          files.add(entity);
        }
      }
      files.sort(
        (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
      );
    }

    if (!mounted) return;
    setState(() {
      _directoryPath = dir.path;
      _files = files;
      _isLoading = false;
    });
  }

  Future<void> _openFile(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File not found on device')),
      );
      await _loadFiles();
      return;
    }

    final result = await OpenFilex.open(path);
    if (!mounted) return;
    if (result.type != ResultType.done) {
      final reason = result.message.trim();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            reason.isEmpty
                ? 'Unable to open the file'
                : 'Unable to open file: $reason',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Received Files'),
        actions: [
          IconButton(
            onPressed: _loadFiles,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_directoryPath != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                    child: Text(
                      'App storage: $_directoryPath',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                Expanded(
                  child: _files.isEmpty
                      ? const Center(
                          child:
                              Text('No received files in app-private storage'),
                        )
                      : ListView.builder(
                          itemCount: _files.length,
                          itemBuilder: (context, index) {
                            final file = _files[index];
                            final stat = file.statSync();
                            final name =
                                file.path.split(Platform.pathSeparator).last;
                            final modified = stat.modified;
                            return ListTile(
                              leading: const Icon(Icons.insert_drive_file),
                              title: Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                '${formatFileSizeBy1024(stat.size)} • ${modified.year}-${modified.month.toString().padLeft(2, '0')}-${modified.day.toString().padLeft(2, '0')} ${modified.hour.toString().padLeft(2, '0')}:${modified.minute.toString().padLeft(2, '0')}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: TextButton(
                                onPressed: () => _openFile(file.path),
                                child: const Text('Open'),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
