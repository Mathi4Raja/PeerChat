import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:peerchat_secure/src/utils/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:io';
import 'dart:ui' as ui;

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
  bool _hasInternet = true;
  LocationPayload? _myLocationPayload;
  Position? _myLocation;
  final MapController _mapController = MapController();
  double _rotation = 0.0;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _fetchMyLocation();
    _checkInternet();
  }

  Future<void> _checkInternet() async {
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 3));
      if (mounted) {
        setState(() {
          _hasInternet = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _hasInternet = false;
        });
      }
    }
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
    final hasDisplayLocation = _currentDisplayLocation != null;
    final orientation = MediaQuery.of(context).orientation;
    final isLandscape = orientation == Orientation.landscape;
    final safePadding = MediaQuery.of(context).padding;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isSelectionMode ? 'Send Location' : 'Location',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
        elevation: 0,
        backgroundColor: AppTheme.bgSurface.withValues(alpha: 0.8),
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
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // 1. Full Screen Map Layer
          if (hasDisplayLocation)
            FlutterMap(
              options: MapOptions(
                initialCenter: LatLng(
                  _currentDisplayLocation!.latitude,
                  _currentDisplayLocation!.longitude,
                ),
                initialZoom: 14,
                minZoom: 2,
                maxZoom: 18,
                onMapEvent: (event) {
                  setState(() {
                    _rotation = event.camera.rotation;
                  });
                },
              ),
              mapController: _mapController,
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
            )
          else
            Container(
              color: AppTheme.bgSurface,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(strokeWidth: 2),
                    const SizedBox(height: 24),
                    Text(
                      'Acquiring GPS Signal...',
                      style: GoogleFonts.inter(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Establish a clear line of sight to the sky',
                      style: GoogleFonts.inter(
                        color: AppTheme.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // 2. Connectivity / Blind State Overlay
          if (hasDisplayLocation && !_hasInternet && !covered)
            Container(
              color: Colors.black.withValues(alpha: 0.85),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_off_rounded, color: AppTheme.warning, size: 64),
                      const SizedBox(height: 20),
                      Text(
                        'Map Unavailable',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Offline cache and internet connection are missing for this location.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          color: AppTheme.textSecondary,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 32),
                      OutlinedButton.icon(
                        onPressed: _checkInternet,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Retry Connection'),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // 3. Status Badges (Top Right)
          if (hasDisplayLocation)
            Positioned(
              top: safePadding.top + 70,
              right: 16 + (isLandscape ? safePadding.right : 0),
              child: _GlassOverlay(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      covered ? Icons.offline_pin_rounded : Icons.cloud_off_rounded,
                      size: 14,
                      color: covered ? AppTheme.success : AppTheme.warning,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      covered ? 'Offline Ready' : 'Live Data Required',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // 3.5 North-Facing Compass
          if (hasDisplayLocation)
            Positioned(
              top: safePadding.top + 125,
              right: 16 + (isLandscape ? safePadding.right : 0),
              child: GestureDetector(
                onTap: () {
                  _mapController.rotate(0);
                },
                child: _GlassOverlay(
                  padding: const EdgeInsets.all(8),
                  child: Transform.rotate(
                    angle: -(_rotation * (3.14159 / 180)),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Icon(
                          Icons.navigation_rounded,
                          size: 24,
                          color: AppTheme.warning.withValues(alpha: 0.9),
                        ),
                        Text(
                          'N',
                          style: GoogleFonts.inter(
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // 4 & 5. Unified Tactical Footer (Selection Mode) or Metadata Card (View Mode)
          Positioned(
            left: 16 + (isLandscape ? safePadding.left : 0),
            right: 16 + (isLandscape ? safePadding.right : 0),
            bottom: 24 + safePadding.bottom,
            child: widget.isSelectionMode
                ? _buildUnifiedSelectionFooter(hasDisplayLocation, isLandscape)
                : _buildSeparateMetadataView(hasDisplayLocation, isLandscape),
          ),
        ],
      ),
    );
  }

  Widget _buildUnifiedSelectionFooter(bool hasDisplayLocation, bool isLandscape) {
    return _GlassOverlay(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: hasDisplayLocation
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'COORDINATES',
                            style: GoogleFonts.inter(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.textSecondary,
                              letterSpacing: 1.0,
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: _openExternalMap,
                            child: Icon(
                              Icons.open_in_new_rounded,
                              size: 12,
                              color: AppTheme.primary.withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 1),
                      Text(
                        _currentDisplayLocation!.coordinateLabel,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      if (_currentDisplayLocation!.accuracyMeters != null)
                        Text(
                          '±${_currentDisplayLocation!.accuracyMeters!.round()}m accuracy',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            color: AppTheme.primary.withValues(alpha: 0.9),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  )
                : Row(
                    children: [
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Acquiring GPS...',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
          ),
          const SizedBox(width: 12),
          Container(
            height: 32,
            width: 1,
            color: Colors.white.withValues(alpha: 0.1),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: !hasDisplayLocation
                ? null
                : () {
                    widget.onLocationSelected?.call(_currentDisplayLocation!);
                    Navigator.pop(context);
                  },
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.send_rounded, size: 16),
                const SizedBox(width: 8),
                Text(
                  'Send',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeparateMetadataView(bool hasDisplayLocation, bool isLandscape) {
    return _GlassOverlay(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: hasDisplayLocation
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'COORDINATES',
                        style: GoogleFonts.inter(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textSecondary,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        _currentDisplayLocation!.coordinateLabel,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      if (_currentDisplayLocation!.accuracyMeters != null)
                        Text(
                          '±${_currentDisplayLocation!.accuracyMeters!.round()}m accuracy',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            color: AppTheme.primary.withValues(alpha: 0.9),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  )
                : _buildHardwareLoadingRow(),
          ),
          const SizedBox(width: 12),
          Container(
            height: 40,
            width: 1,
            color: Colors.white.withValues(alpha: 0.1),
          ),
          const SizedBox(width: 12),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _CompactIconButton(
                onPressed: _openExternalMap,
                icon: Icons.map_rounded,
                tooltip: 'Open External',
              ),
              const SizedBox(height: 8),
              _CompactIconButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const OfflineMapsScreen()),
                ),
                icon: Icons.settings_rounded,
                tooltip: 'Offline Maps',
              ),
            ],
          ),
        ],
      ),
    );
  }


  Widget _buildHardwareLoadingRow() {
    return Row(
      children: [
        const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 12),
        Text(
          'Waiting for GPS hardware...',
          style: GoogleFonts.inter(
            fontSize: 13,
            color: AppTheme.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _GlassOverlay extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;

  const _GlassOverlay({
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _CompactIconButton extends StatelessWidget {
  final VoidCallback onPressed;
  final IconData icon;
  final String tooltip;

  const _CompactIconButton({
    required this.onPressed,
    required this.icon,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Tooltip(
          message: tooltip,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Icon(
              icon,
              size: 18,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
