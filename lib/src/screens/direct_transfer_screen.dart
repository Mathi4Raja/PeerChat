import 'dart:async';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../models/file_transfer.dart';
import '../theme.dart';
import '../utils/name_generator.dart';
import '../utils/google_fonts.dart';
import 'web_share_asset_picker.dart';
import '../services/file_transfer_service.dart';

class DirectTransferScreen extends StatefulWidget {
  final String peerId;

  const DirectTransferScreen({
    super.key,
    required this.peerId,
  });

  @override
  State<DirectTransferScreen> createState() => _DirectTransferScreenState();
}

class _DirectTransferScreenState extends State<DirectTransferScreen> {
  StreamSubscription? _progressSubscription;
  StreamSubscription? _completedSubscription;
  List<Map<String, dynamic>> _history = [];
  bool _isLoadingHistory = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
    
    final appState = Provider.of<AppState>(context, listen: false);
    _progressSubscription = appState.fileTransferService.onProgress.listen((session) {
      if (session.peerId == widget.peerId) {
        if (mounted) setState(() {});
      }
    });

    // Also listen for completions to refresh history
    _completedSubscription = appState.fileTransferService.onTransferCompleted.listen((session) {
      if (session.peerId == widget.peerId) {
        _loadHistory();
      }
    });
  }

  @override
  void dispose() {
    _progressSubscription?.cancel();
    _completedSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final appState = Provider.of<AppState>(context, listen: false);
    final history = await appState.db.getFileTransfersForPeer(widget.peerId);
    if (mounted) {
      setState(() {
        _history = history;
        _isLoadingHistory = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final peerDisplayName = NameGenerator.generateShortName(widget.peerId);
    
    // Filter active sessions for this peer
    final activeSessions = appState.fileTransferService.activeSessions.values
        .where((s) => s.peerId == widget.peerId)
        .toList();

    return Scaffold(
      backgroundColor: AppTheme.bgDeep,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Files & Transfers', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 18)),
            Text(peerDisplayName, style: GoogleFonts.inter(fontSize: 12, color: AppTheme.primary, fontWeight: FontWeight.w600)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_box_rounded),
            onPressed: () => _pickAndSendFiles(appState),
            tooltip: 'Add Files',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadHistory,
        color: AppTheme.primary,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (activeSessions.isNotEmpty) ...[
              _buildSectionHeader('ACTIVE TRANSFERS'),
              const SizedBox(height: 12),
              ...activeSessions.map((session) => _buildActiveTransferCard(session, appState)),
              const SizedBox(height: 24),
            ],
            
            _buildSectionHeader('HISTORY'),
            const SizedBox(height: 12),
            if (_isLoadingHistory)
              const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
            else if (_history.isEmpty && activeSessions.isEmpty)
              _buildEmptyState()
            else
              ..._history.map((sessionData) => _buildHistoryItem(sessionData, appState)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _pickAndSendFiles(appState),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add_rounded),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        color: AppTheme.textSecondary.withValues(alpha: 0.5),
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        children: [
          const SizedBox(height: 60),
          Icon(Icons.folder_open_rounded, size: 64, color: AppTheme.textSecondary.withValues(alpha: 0.1)),
          const SizedBox(height: 16),
          Text('No files shared yet', style: GoogleFonts.inter(color: AppTheme.textSecondary, fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          Text('Tap "Add Files" to start sharing', style: GoogleFonts.inter(color: AppTheme.textSecondary.withValues(alpha: 0.5), fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildActiveTransferCard(FileTransferSession session, AppState appState) {
    final progress = session.progress;
    final isOutgoing = !session.isIncoming;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: (isOutgoing ? Colors.blue : Colors.purple).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isOutgoing ? Icons.upload_rounded : Icons.download_rounded,
                  color: isOutgoing ? Colors.blue : Colors.purple,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.metadata.name,
                      style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      isOutgoing ? 'Sending...' : 'Receiving...',
                      style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${(progress * 100).toStringAsFixed(1)}%',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w800, color: AppTheme.primary, fontSize: 13),
                  ),
                  if (session.speedMBps > 0)
                    Text(
                      '${session.speedMBps.toStringAsFixed(1)} MB/s',
                      style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textSecondary.withValues(alpha: 0.7)),
                    ),
                  if (session.speedMBps > 0 && session.remainingTime != Duration.zero)
                    Text(
                      'ETA: ${_formatDuration(session.remainingTime)}',
                      style: GoogleFonts.inter(fontSize: 9, color: AppTheme.success.withValues(alpha: 0.8), fontWeight: FontWeight.w600),
                    ),
                ],
              ),
              const SizedBox(width: 8),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                icon: Icon(Icons.close_rounded, size: 18, color: AppTheme.textSecondary.withValues(alpha: 0.4)),
                onPressed: () => appState.fileTransferService.abortTransfer(session.fileId),
                tooltip: 'Abort Transfer',
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.white.withValues(alpha: 0.05),
              color: AppTheme.primary,
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${(session.metadata.size * progress / 1024 / 1024).toStringAsFixed(1)} / ${(session.metadata.size / 1024 / 1024).toStringAsFixed(1)} MB',
                style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textSecondary.withValues(alpha: 0.5)),
              ),
              if (session.status == FileTransferStatus.paused)
                Text(
                  'PAUSED',
                  style: GoogleFonts.inter(fontSize: 10, color: AppTheme.warning, fontWeight: FontWeight.w700),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryItem(Map<String, dynamic> data, AppState appState) {
    final isIncoming = data['is_incoming'] == 1;
    final status = FileTransferStatus.values[data['status']];
    final size = data['file_size'] as int;
    final timestamp = data['timestamp'] as int;
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    
    IconData icon;
    Color color;
    
    switch (status) {
      case FileTransferStatus.completed:
        icon = Icons.check_circle_outline_rounded;
        color = Colors.green;
        break;
      case FileTransferStatus.failed:
        icon = Icons.error_outline_rounded;
        color = AppTheme.danger;
        break;
      case FileTransferStatus.rejected:
        icon = Icons.block_flipped;
        color = AppTheme.textSecondary;
        break;
      default:
        icon = Icons.access_time_rounded;
        color = AppTheme.warning;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.bgCard.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.03)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Icon(
          isIncoming ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
          size: 18,
          color: AppTheme.textSecondary.withValues(alpha: 0.5),
        ),
        title: Text(
          data['file_name'],
          style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${(size / 1024 / 1024).toStringAsFixed(2)} MB • ${_formatDate(date)}',
          style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (status == FileTransferStatus.completed)
              IconButton(
                icon: const Icon(Icons.visibility_outlined, size: 20, color: Colors.blue),
                onPressed: () => appState.fileTransferService.openFile(data['id']),
                tooltip: 'Open File',
              ),
            if (status == FileTransferStatus.failed || 
                status == FileTransferStatus.aborted || 
                status == FileTransferStatus.rejected)
              IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 20, color: AppTheme.primary),
                onPressed: () => appState.fileTransferService.resumeTransfer(data['id']),
                tooltip: 'Resume/Retry',
              ),
            IconButton(
              icon: Icon(Icons.delete_outline_rounded, size: 20, color: AppTheme.textSecondary.withValues(alpha: 0.5)),
              onPressed: () async {
                await appState.fileTransferService.deleteTransfer(data['id']);
                _loadHistory();
              },
              tooltip: 'Delete Log',
            ),
            const SizedBox(width: 4),
            Icon(icon, color: color, size: 20),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    if (date.day == now.day && date.month == now.month && date.year == now.year) {
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    }
    return '${date.day}/${date.month}';
  }

  Future<void> _pickAndSendFiles(AppState appState) async {
    final result = await Navigator.of(context).push<List<PlatformFile>>(
      MaterialPageRoute(
        builder: (_) => const WebShareAssetPicker(
          allowMultiple: true,
          title: 'Select Files to Send',
          confirmLabel: 'Send',
        ),
      ),
    );

    if (result == null || result.isEmpty) return;

    for (final file in result) {
      if (file.path != null) {
        try {
          await appState.fileTransferService.startTransfer(widget.peerId, file.path!);
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed: ${file.name}'), backgroundColor: AppTheme.danger),
            );
          }
        }
      }
    }
    
    if (mounted) setState(() {});
  }

  String _formatDuration(Duration d) {
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
    if (d.inMinutes > 0) return '${d.inMinutes}m ${d.inSeconds.remainder(60)}s';
    return '${d.inSeconds}s';
  }
}
