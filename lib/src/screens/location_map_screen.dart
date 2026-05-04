import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:peerchat_secure/src/utils/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';

import '../services/tile_cache_service.dart';

import '../models/location_payload.dart';
import '../services/offline_map_service.dart';
import '../theme.dart';
import 'menu/offline_maps_screen.dart';
import '../services/location_service.dart';

class LocationMapScreen extends StatefulWidget {
  final LocationPayload? location;
  final bool isSelectionMode;
  final Function(LocationPayload)? onLocationSelected;

  const LocationMapScreen({
    super.key,
    this.location,
    this.isSelectionMode = false,
    this.onLocationSelected,
  });

  @override
  State<LocationMapScreen> createState() => _LocationMapScreenState();
}

class _LocationMapScreenState extends State<LocationMapScreen> {
  final OfflineMapService _offlineMapService = const OfflineMapService();
  final LocationService _locationService = LocationService();
  OfflineMapSettings _settings = const OfflineMapSettings.defaults();
  bool _isLoading = true;
  LocationPayload? _myLocationPayload;
  Position? _myLocation;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _fetchMyLocation();
  }

  Future<void> _fetchMyLocation() async {
    try {
      final location = await _locationService.currentLocation();
      if (mounted) {
        setState(() {
          _myLocationPayload = location;
          _myLocation = Position(
            latitude: location.latitude,
            longitude: location.longitude,
            timestamp: DateTime.fromMillisecondsSinceEpoch(location.timestamp),
            accuracy: location.accuracyMeters ?? 0.0,
            altitude: 0,
            heading: 0,
            speed: 0,
            speedAccuracy: 0,
            altitudeAccuracy: 0,
            headingAccuracy: 0,
          );
        });
      }
    } catch (e) {
      // Ignore location fetch errors silently for map view
    }
  }

  Future<void> _loadSettings() async {
    final settings = await _offlineMapService.loadSettings();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _isLoading = false;
    });
  }

  LocationPayload? get _currentDisplayLocation =>
      widget.location ?? _myLocationPayload;

  bool get _isCoveredByOfflinePack {
    final loc = _currentDisplayLocation;
    if (loc == null) return false;
    
    final centerLat = _settings.centerLatitude;
    final centerLng = _settings.centerLongitude;
    if (!_settings.downloaded || centerLat == null || centerLng == null) {
      return false;
    }
    final distance = LocationPayload.distanceMeters(
      fromLatitude: centerLat,
      fromLongitude: centerLng,
      toLatitude: loc.latitude,
      toLongitude: loc.longitude,
    );
    return distance <= _settings.radiusKm * 1000;
  }

  Future<void> _openExternalMap() async {
    final loc = _currentDisplayLocation;
    if (loc == null) return;
    
    final uri = Uri.parse('geo:${loc.mapsQuery}?q=${loc.mapsQuery}');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No map app available')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final covered = _isCoveredByOfflinePack;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isSelectionMode ? 'Send Location' : 'Location',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: 'Offline maps',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const OfflineMapsScreen()),
              );
              await _loadSettings();
            },
            icon: const Icon(Icons.download_for_offline_rounded),
          ),
        ],
      ),
      body: _isLoading && widget.isSelectionMode && _myLocation == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        children: [
          if (_currentDisplayLocation != null)
            AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  children: [
                    FlutterMap(
                      options: MapOptions(
                        initialCenter: LatLng(
                          _currentDisplayLocation!.latitude,
                          _currentDisplayLocation!.longitude,
                        ),
                        initialZoom: 14,
                        minZoom: 2,
                        maxZoom: 18,
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.peerchat.secure',
                          tileProvider: CachedTileProvider(
                            centerLat: _settings.centerLatitude,
                            centerLng: _settings.centerLongitude,
                            radiusKm: _settings.radiusKm.toDouble(),
                          ),
                        ),
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: LatLng(
                                _currentDisplayLocation!.latitude,
                                _currentDisplayLocation!.longitude,
                              ),
                              width: 80,
                              height: 80,
                              child: const Icon(
                                Icons.location_on_rounded,
                                color: AppTheme.warning,
                                size: 40,
                              ),
                            ),
                            if (_myLocation != null && !widget.isSelectionMode)
                              Marker(
                                point: LatLng(
                                  _myLocation!.latitude,
                                  _myLocation!.longitude,
                                ),
                                width: 80,
                                height: 80,
                                child: const Icon(
                                  Icons.person_pin_circle_rounded,
                                  color: AppTheme.primary,
                                  size: 40,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              covered
                                  ? Icons.offline_pin_rounded
                                  : Icons.cloud_off_rounded,
                              color: covered
                                  ? AppTheme.success
                                  : AppTheme.warning,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                covered
                                    ? 'Using downloaded offline area'
                                    : 'Offline street tiles not installed for this point',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 14),
          if (_currentDisplayLocation != null) ...[
            _InfoTile(
              icon: Icons.pin_drop_rounded,
              title: 'Coordinates',
              value: _currentDisplayLocation!.coordinateLabel,
            ),
            if (_currentDisplayLocation!.accuracyMeters != null)
              _InfoTile(
                icon: Icons.gps_fixed_rounded,
                title: 'Accuracy',
                value: '~${_currentDisplayLocation!.accuracyMeters!.round()} m',
              ),
            if (_myLocation != null && !widget.isSelectionMode)
              _InfoTile(
                icon: Icons.straighten_rounded,
                title: 'Distance from you',
                value: '${(Geolocator.distanceBetween(_myLocation!.latitude, _myLocation!.longitude, _currentDisplayLocation!.latitude, _currentDisplayLocation!.longitude) / 1000).toStringAsFixed(2)} km',
              ),
            _InfoTile(
              icon: Icons.offline_bolt_rounded,
              title: 'Offline map',
              value: _isLoading
                  ? 'Checking...'
                  : covered
                      ? '${_settings.radiusKm} km pack available'
                      : 'Download a pack centered near this area',
            ),
          ],
          const SizedBox(height: 12),
          if (widget.isSelectionMode)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _currentDisplayLocation == null ? null : () {
                  widget.onLocationSelected?.call(_currentDisplayLocation!);
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.send_rounded),
                label: Text(
                  'Send This Location',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _openExternalMap,
                    icon: const Icon(Icons.map_rounded),
                    label: const Text('Open Map App'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const OfflineMapsScreen(),
                        ),
                      );
                      await _loadSettings();
                    },
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('Offline Maps'),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;

  const _InfoTile({
    required this.icon,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bgSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w700,
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
