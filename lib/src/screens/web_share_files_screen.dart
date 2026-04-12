import 'dart:async';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:peerchat_secure/src/theme.dart';
import 'package:peerchat_secure/src/services/web_share_service.dart';
import 'package:peerchat_secure/src/screens/web_share_asset_picker.dart';


class WebShareHostedFilesScreen extends StatefulWidget {
  final WebShareService service;
  
  const WebShareHostedFilesScreen({
    super.key, 
    required this.service,
  });

  @override
  State<WebShareHostedFilesScreen> createState() => _WebShareHostedFilesScreenState();
}

class _WebShareHostedFilesScreenState extends State<WebShareHostedFilesScreen> {
  StreamSubscription? _eventSubscription;

  @override
  void initState() {
    super.initState();
    _eventSubscription = widget.service.onEvent.listen((event) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    super.dispose();
  }

  Future<void> _pickFiles() async {
    final result = await Navigator.of(context).push<List<PlatformFile>>(
      MaterialPageRoute(builder: (_) => const WebShareAssetPicker()),
    );
    
    if (result != null && result.isNotEmpty) {
      setState(() {
        widget.service.addFiles(result);
      });
    }
  }


  void _removeFile(PlatformFile file) {
    setState(() {
      widget.service.removeFile(file);
    });
  }

  @override
  Widget build(BuildContext context) {
    final files = widget.service.sharedFiles;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hosted Files'),
        flexibleSpace: Container(decoration: const BoxDecoration(gradient: AppTheme.appBarGradient)),
      ),
      body: files.isEmpty ? _buildEmptyState() : _buildFilesList(files),
      floatingActionButton: FloatingActionButton(
        onPressed: _pickFiles,
        backgroundColor: AppTheme.primary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_upload_outlined, size: 72, color: AppTheme.textSecondary.withValues(alpha: 0.2)),
          const SizedBox(height: 20),
          Text('No files hosted for sharing', 
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 18, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildFilesList(List<PlatformFile> files) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      itemCount: files.length,
      itemBuilder: (context, index) {
        final file = files[index];
        final isDone = widget.service.isDownloaded(file.path ?? '');

        return Card(
          elevation: 0,
          color: AppTheme.bgSurface,
          margin: const EdgeInsets.only(bottom: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: Icon(
              isDone ? Icons.check_circle : Icons.insert_drive_file, 
              color: isDone ? AppTheme.online : AppTheme.accent, 
              size: 28
            ),
            title: Text(file.name, 
              style: TextStyle(
                fontWeight: FontWeight.w600, 
                fontSize: 16,
                color: isDone ? AppTheme.online : AppTheme.textPrimary,
              ),
              maxLines: 1, 
              overflow: TextOverflow.ellipsis
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('${(file.size / 1024 / 1024).toStringAsFixed(2)} MB',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)
              ),
            ),
            trailing: IconButton(
              icon: Icon(Icons.delete_outline, color: AppTheme.danger.withValues(alpha: 0.8)),
              onPressed: () => _removeFile(file),
            ),
          ),
        );
      },
    );
  }
}
