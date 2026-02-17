import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../app_state.dart';
import '../models/peer.dart';

class AddPeerScreen extends StatefulWidget {
  const AddPeerScreen({super.key});

  @override
  State<AddPeerScreen> createState() => _AddPeerScreenState();
}

class _AddPeerScreenState extends State<AddPeerScreen> {
  final TextEditingController _peerKeyController = TextEditingController();
  String? _scanned;
  bool _showScanner = false;
  final MobileScannerController _scannerController = MobileScannerController();

  @override
  void dispose() {
    _peerKeyController.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    
    if (_showScanner) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Scan QR Code'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () {
              setState(() {
                _showScanner = false;
              });
            },
          ),
        ),
        body: MobileScanner(
          controller: _scannerController,
          onDetect: (capture) {
            final List<Barcode> barcodes = capture.barcodes;
            for (final barcode in barcodes) {
              if (barcode.rawValue != null) {
                final scannedKey = barcode.rawValue!;
                _handleScannedKey(scannedKey, appState);
                break;
              }
            }
          },
        ),
      );
    }
    
    return Scaffold(
      appBar: AppBar(title: const Text('Add Peer')),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Add a peer by scanning their QR code or entering their public key',
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                
                // Scan QR Code Button
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _showScanner = true;
                    });
                  },
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Scan QR Code'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                  ),
                ),
                
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 16),
                
                const Text('Or paste peer public key manually:'),
                const SizedBox(height: 8),
                TextField(
                  controller: _peerKeyController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'Paste public key here',
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () {
                    final text = _peerKeyController.text.trim();
                    if (text.isNotEmpty) {
                      _handleScannedKey(text, appState);
                    }
                  },
                  child: const Text('Add Peer'),
                ),
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 16),
                const Text(
                  'Your QR Code',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Show this to others so they can add you',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                if (appState.publicKey != null)
                  Center(child: QrImageView(data: appState.publicKey!, size: 200))
                else
                  const Center(child: CircularProgressIndicator()),
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
    if (key.isEmpty || key.length < 20) {
      _showMessage('Invalid peer key', isError: true);
      return;
    }
    
    // Create a peer entry
    final peer = Peer(
      id: key,
      displayName: 'Manually Added Peer',
      address: 'manual',
      lastSeen: DateTime.now().millisecondsSinceEpoch,
      hasApp: true, // Assume they have the app if sharing QR code
    );
    
    // Save to database
    await appState.db.upsertPeer(peer);
    
    // Reload peers
    appState.peers = await appState.db.allPeers();
    appState.notifyListeners();
    
    _showMessage('Peer added successfully!');
    
    // Close scanner or clear text field
    if (_showScanner) {
      setState(() {
        _showScanner = false;
      });
    } else {
      _peerKeyController.clear();
    }
  }
  
  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }
}
