import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../app_state.dart';

class IdentityCard extends StatelessWidget {
  const IdentityCard({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final displayName = appState.displayName;
    final pub = appState.publicKey ?? 'Generating...';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Your Identity', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              displayName,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.blue),
            ),
            const SizedBox(height: 4),
            SelectableText(
              pub,
              maxLines: 2,
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            Center(
              child: pub == 'Generating...'
                  ? const CircularProgressIndicator()
                  : QrImageView(
                      data: pub,
                      version: QrVersions.auto,
                      size: 160.0,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
