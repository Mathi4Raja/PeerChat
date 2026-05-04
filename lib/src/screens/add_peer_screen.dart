import 'package:flutter/material.dart';
import 'package:peerchat_secure/src/utils/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../config/identity_ui_config.dart';
import '../models/peer.dart';
import '../theme.dart';
import 'package:barcode_scan2/barcode_scan2.dart';

class AddPeerScreen extends StatefulWidget {
  const AddPeerScreen({super.key});

  @override
  State<AddPeerScreen> createState() => _AddPeerScreenState();
}

class _AddPeerScreenState extends State<AddPeerScreen> {
  final TextEditingController _peerKeyController = TextEditingController();

  @override
  void dispose() {
    _peerKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Add Peer',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Add a peer by scanning their QR code or pasting their public key below.',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: AppTheme.textSecondary,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 20),

                // ─── QR Scanner Button ───
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      try {
                        final result = await BarcodeScanner.scan();
                        if (result.type == ResultType.Barcode && result.rawContent.isNotEmpty) {
                          _handleScannedKey(result.rawContent, appState);
                        }
                      } catch (e) {
                        _showMessage('Error opening scanner', isError: true);
                      }
                    },
                    icon: const Icon(Icons.qr_code_scanner_rounded),
                    label: const Text('Scan Peer QR'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // ─── Manual Key Entry ───
                Container(
                  decoration: AppTheme.glassCard(),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Paste peer public key',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _peerKeyController,
                        maxLines: 3,
                        style: GoogleFonts.firaCode(
                          fontSize: 12,
                          color: AppTheme.textPrimary,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Paste public key here...',
                          hintStyle: GoogleFonts.firaCode(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            final text = _peerKeyController.text.trim();
                            if (text.isNotEmpty) {
                              _handleScannedKey(text, appState);
                            }
                          },
                          child: const Text('Add Peer'),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 28),

                // ─── Your QR Code ───
                Container(
                  decoration: AppTheme.accentBorderCard(),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.qr_code_2_rounded,
                            size: 18,
                            color: AppTheme.primary.withValues(alpha: 0.8),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Your QR Code',
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Show this to others so they can add you',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (appState.publicKey != null)
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: AppTheme.primary.withValues(alpha: 0.3),
                              width: 2,
                            ),
                          ),
                          child:
                              QrImageView(data: appState.publicKey!, size: 180),
                        )
                      else
                        const SizedBox(
                          height: 180,
                          child: Center(
                            child: CircularProgressIndicator(
                                color: AppTheme.primary),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _handleScannedKey(String key, AppState appState) async {
    // Validate the key (should be base64 encoded)
    if (key.isEmpty || key.length < IdentityUiConfig.manualPeerKeyMinLength) {
      _showMessage('Invalid peer key', isError: true);
      return;
    }

    // Create a peer entry
    final peer = Peer(
      id: key,
      displayName: IdentityUiConfig.manualAddedPeerLabel,
      address: 'manual',
      lastSeen: DateTime.now().millisecondsSinceEpoch,
      hasApp: true,
    );

    // Save to database
    await appState.db.upsertPeer(peer);

    // Reload peers
    appState.peers = await appState.db.allPeers();

    _showMessage('Peer added successfully!');

    _peerKeyController.clear();
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppTheme.danger : AppTheme.online,
      ),
    );
  }
}
