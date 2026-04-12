import 'dart:async';
import 'package:flutter/material.dart';
import 'package:peerchat_secure/src/theme.dart';
import 'package:peerchat_secure/src/services/web_share_service.dart';

class WebShareLogScreen extends StatefulWidget {
  final WebShareService service;
  
  const WebShareLogScreen({
    super.key, 
    required this.service,
  });

  @override
  State<WebShareLogScreen> createState() => _WebShareLogScreenState();
}

class _WebShareLogScreenState extends State<WebShareLogScreen> {
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

  @override
  Widget build(BuildContext context) {
    final activeTransfers = widget.service.activeTransfers;
    final log = widget.service.eventLog;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transfer Log'),
        flexibleSpace: Container(decoration: const BoxDecoration(gradient: AppTheme.appBarGradient)),
        actions: [
          if (log.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_rounded, color: Colors.white),
              onPressed: () {
                setState(() {
                  widget.service.clearLog();
                });
              },
              tooltip: 'Clear Log',
            ),
        ],
      ),
      body: (activeTransfers.isEmpty && log.isEmpty) 
          ? _buildEmptyState() 
          : _buildLogList(activeTransfers.toList(), log),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history, size: 72, color: AppTheme.textSecondary.withValues(alpha: 0.2)),
          const SizedBox(height: 20),
          Text('No transfer history yet', 
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 18, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildLogList(List<String> activeTransfers, List<String> log) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      children: [
        if (activeTransfers.isNotEmpty) ...[
          _buildSectionHeader('ACTIVE TRANSFERS', AppTheme.primary),
          const SizedBox(height: 12),
          ...activeTransfers.map((name) => _buildActiveTransferCard(name)),
          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 24),
        ],

        if (log.isNotEmpty) ...[
          _buildSectionHeader('LOG HISTORY', AppTheme.textSecondary.withValues(alpha: 0.7)),
          const SizedBox(height: 16),
          ...log.asMap().entries.map((entry) => _buildLogEntry(entry.key, entry.value)),
        ],
      ],
    );
  }

  Widget _buildSectionHeader(String title, Color color) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(title, 
        style: TextStyle(
          color: color, 
          fontWeight: FontWeight.w800, 
          fontSize: 12,
          letterSpacing: 1.5,
        )
      ),
    );
  }

  Widget _buildActiveTransferCard(String name) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 3, valueColor: AlwaysStoppedAnimation(AppTheme.primary)),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, 
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                const SizedBox(height: 4),
                const Text('Transferring data...', 
                  style: TextStyle(color: AppTheme.primary, fontSize: 13, fontWeight: FontWeight.w600, fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogEntry(int idx, String text) {
    final isSent = text.contains('Sent:');
    final isReceived = text.contains('Received:');
    final isSuccess = isSent || isReceived;
    final isHot = text.contains('Receiving:') || text.contains('Sending:');
    
    final successColor = AppTheme.online; // Emerald Gradient
    final iconColor = isSuccess ? successColor : (isHot ? AppTheme.primary : AppTheme.textSecondary.withValues(alpha: 0.5));
    final textColor = isSuccess ? successColor : (isHot ? AppTheme.textPrimary : AppTheme.textSecondary);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isHot ? AppTheme.primary.withValues(alpha: 0.05) : AppTheme.bgSurface.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isSuccess 
            ? successColor.withValues(alpha: 0.2) 
            : (isHot ? AppTheme.primary.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05)),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            isSuccess ? Icons.check_circle_rounded : (isHot ? Icons.sync_rounded : Icons.info_outline_rounded), 
            size: 18, 
            color: iconColor,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                height: 1.3,
                fontWeight: isSuccess ? FontWeight.w700 : FontWeight.w500,
                color: textColor,
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(Icons.close_rounded, size: 16, color: AppTheme.danger.withValues(alpha: 0.5)),
            onPressed: () => setState(() => widget.service.removeLogEntry(idx)),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
