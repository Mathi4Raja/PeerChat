import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';

class MeshStatusCard extends StatelessWidget {
  const MeshStatusCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, child) {
        return FutureBuilder(
          future: appState.meshRouter.stats,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Card(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Center(child: CircularProgressIndicator()),
                ),
              );
            }

            final stats = snapshot.data!;
            
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.router, color: Colors.blue),
                        const SizedBox(width: 8),
                        const Text(
                          'Mesh Network Status',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'P2P',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildStatRow(
                      'Active Routes',
                      stats.totalRoutes.toString(),
                      Icons.route,
                      Colors.green,
                    ),
                    const SizedBox(height: 8),
                    _buildStatRow(
                      'Queued Messages',
                      stats.queuedMessages.toString(),
                      Icons.queue,
                      stats.queuedMessages > 0 ? Colors.orange : Colors.grey,
                    ),
                    const SizedBox(height: 8),
                    _buildStatRow(
                      'Pending Acks',
                      stats.pendingAcks.toString(),
                      Icons.check_circle_outline,
                      stats.pendingAcks > 0 ? Colors.blue : Colors.grey,
                    ),
                    if (stats.blockedPeers > 0) ...[
                      const SizedBox(height: 8),
                      _buildStatRow(
                        'Blocked Peers',
                        stats.blockedPeers.toString(),
                        Icons.block,
                        Colors.red,
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildStatRow(String label, String value, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(fontSize: 14),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}
