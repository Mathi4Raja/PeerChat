import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:peerchat_secure/src/utils/google_fonts.dart';

import '../../services/offline_map_service.dart';
import '../../theme.dart';

class OfflineMapsScreen extends StatefulWidget {
  const OfflineMapsScreen({super.key});

  @override
  State<OfflineMapsScreen> createState() => _OfflineMapsScreenState();
}

class _OfflineMapsScreenState extends State<OfflineMapsScreen> {
  final OfflineMapService _offlineMapService = const OfflineMapService();
  OfflineMapSettings _settings = const OfflineMapSettings.defaults();
  bool _isLoading = true;
  bool _isLocating = false;
  bool _isDownloading = false;
  double _downloadProgress = 0;
  double? _currentLatitude;
  double? _currentLongitude;
  int _actualSizeMiB = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await _offlineMapService.loadSettings();
    final size = await _offlineMapService.getActualSizeMiB();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _actualSizeMiB = size;
      _isLoading = false;
    });
  }

  OfflineMapEstimate get _estimate => _offlineMapService.estimateStorage(
        radiusKm: _settings.radiusKm,
        maxVectorZoom: _settings.maxVectorZoom,
      );

  Future<void> _setRadius(int radiusKm) async {
    final next = _settings.copyWith(radiusKm: radiusKm);
    setState(() {
      _settings = next;
    });
    await _offlineMapService.saveRadiusKm(radiusKm);
  }

  Future<void> _setZoom(int zoom) async {
    final next = _settings.copyWith(maxVectorZoom: zoom);
    setState(() {
      _settings = next;
    });
    await _offlineMapService.saveMaxVectorZoom(zoom);
  }

  Future<void> _locateCenter() async {
    setState(() {
      _isLocating = true;
    });
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('Location permission denied');
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 12),
        ),
      );
      if (!mounted) return;
      setState(() {
        _currentLatitude = position.latitude;
        _currentLongitude = position.longitude;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLocating = false;
        });
      }
    }
  }

  Future<void> _downloadPack() async {
    if (_currentLatitude == null || _currentLongitude == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please locate center first')),
      );
      return;
    }

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0;
    });

    try {
      final stream = _offlineMapService.downloadPack(
        centerLatitude: _currentLatitude!,
        centerLongitude: _currentLongitude!,
        radiusKm: _settings.radiusKm,
        maxZoom: _settings.maxVectorZoom,
      );

      await for (final progress in stream) {
        if (!mounted) return;
        setState(() {
          _downloadProgress = progress;
        });
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Download complete')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Download failed: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isDownloading = false;
        });
      }
    }
  }

  Future<void> _clearPack() async {
    await _offlineMapService.clearDownloadedPack();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final estimate = _estimate;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Offline Maps',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              children: [
                _StatusPanel(settings: _settings),
                const SizedBox(height: 12),
                _Section(
                  title: 'Download Area',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            '${_settings.radiusKm} km radius',
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '10-50 km',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        value: _settings.radiusKm.toDouble(),
                        min: OfflineMapConfig.minRadiusKm.toDouble(),
                        max: OfflineMapConfig.maxRadiusKm.toDouble(),
                        divisions: 4,
                        label: '${_settings.radiusKm} km',
                        onChanged: (value) {
                          _setRadius(value.round());
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _Section(
                  title: 'Street Detail',
                  child: SegmentedButton<int>(
                    segments: const [
                      ButtonSegment<int>(
                        value: 14,
                        label: Text('Standard'),
                        icon: Icon(Icons.map_outlined),
                      ),
                      ButtonSegment<int>(
                        value: 15,
                        label: Text('Detailed'),
                        icon: Icon(Icons.add_road_rounded),
                      ),
                    ],
                    selected: {_settings.maxVectorZoom},
                    onSelectionChanged: (values) {
                      _setZoom(values.first);
                    },
                  ),
                ),
                const SizedBox(height: 12),
                _Section(
                  title: 'Estimate',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _MetricRow(
                        label: 'Expected vector pack',
                        value: estimate.label,
                      ),
                      _MetricRow(
                        label: 'Equivalent raster tiles',
                        value: '~${estimate.approximateRasterTileCount}',
                      ),
                      if (estimate.exceedsWarning)
                        Container(
                          margin: const EdgeInsets.only(top: 10),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppTheme.warning.withValues(alpha: 0.13),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            'This area may exceed ${OfflineMapConfig.storageWarningMiB} MB in dense cities.',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: AppTheme.warning,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _Section(
                  title: 'Center',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _currentLatitude == null || _currentLongitude == null
                            ? 'Use current location as the center of the offline pack.'
                            : '${_currentLatitude!.toStringAsFixed(5)}, ${_currentLongitude!.toStringAsFixed(5)}',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _isLocating ? null : _locateCenter,
                        icon: _isLocating
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.my_location_rounded),
                        label: Text(_isLocating
                            ? 'Locating...'
                            : 'Use Current Location'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (_isDownloading)
                  Column(
                    children: [
                      LinearProgressIndicator(value: _downloadProgress),
                      const SizedBox(height: 8),
                      Text(
                        'Downloading tiles: ${(_downloadProgress * 100).toStringAsFixed(1)}%',
                        style: GoogleFonts.inter(fontSize: 12),
                      ),
                    ],
                  )
                else
                  ElevatedButton.icon(
                    onPressed: _currentLatitude == null || _isLocating
                        ? null
                        : _downloadPack,
                    icon: const Icon(Icons.download_for_offline_rounded),
                    label: const Text('Download Offline Map'),
                  ),
                const SizedBox(height: 8),
                Text(
                  'Tiles are downloaded from OpenStreetMap. Please use responsibly and only download areas you need for offline use.',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                    height: 1.35,
                  ),
                ),
                if (_settings.downloaded) ...[
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: _clearPack,
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: Text('Remove Downloaded Pack (${_actualSizeMiB > 0 ? "$_actualSizeMiB MB" : "..."})'),
                  ),
                ],
              ],
            ),
    );
  }
}

class _StatusPanel extends StatelessWidget {
  final OfflineMapSettings settings;

  const _StatusPanel({required this.settings});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.accentBorderCard(radius: 14),
      child: Row(
        children: [
          Icon(
            settings.downloaded
                ? Icons.offline_pin_rounded
                : Icons.cloud_off_rounded,
            color: settings.downloaded ? AppTheme.success : AppTheme.warning,
            size: 30,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  settings.downloaded
                      ? 'Offline pack installed'
                      : 'Offline pack not installed',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${settings.radiusKm} km radius, z${settings.maxVectorZoom} vector detail',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;

  const _Section({
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bgSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  final String label;
  final String value;

  const _MetricRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
