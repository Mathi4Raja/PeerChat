import 'dart:async';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'tile_cache_service.dart';

class OfflineMapConfig {
  static const int minRadiusKm = 10;
  static const int maxRadiusKm = 50;
  static const int defaultRadiusKm = 20;
  static const int minZoom = 0;
  static const int defaultMaxVectorZoom = 15;
  static const int minVectorZoom = 14;
  static const int maxVectorZoom = 15;
  static const int storageWarningMiB = 250;
}

class OfflineMapSettings {
  final int radiusKm;
  final int maxVectorZoom;
  final bool downloaded;
  final int? downloadedAt;
  final double? centerLatitude;
  final double? centerLongitude;
  final int? estimatedSizeMiB;

  const OfflineMapSettings({
    required this.radiusKm,
    required this.maxVectorZoom,
    required this.downloaded,
    this.downloadedAt,
    this.centerLatitude,
    this.centerLongitude,
    this.estimatedSizeMiB,
  });

  const OfflineMapSettings.defaults()
      : radiusKm = OfflineMapConfig.defaultRadiusKm,
        maxVectorZoom = OfflineMapConfig.defaultMaxVectorZoom,
        downloaded = false,
        downloadedAt = null,
        centerLatitude = null,
        centerLongitude = null,
        estimatedSizeMiB = null;

  OfflineMapSettings copyWith({
    int? radiusKm,
    int? maxVectorZoom,
    bool? downloaded,
    int? downloadedAt,
    double? centerLatitude,
    double? centerLongitude,
    int? estimatedSizeMiB,
  }) {
    return OfflineMapSettings(
      radiusKm: radiusKm ?? this.radiusKm,
      maxVectorZoom: maxVectorZoom ?? this.maxVectorZoom,
      downloaded: downloaded ?? this.downloaded,
      downloadedAt: downloadedAt ?? this.downloadedAt,
      centerLatitude: centerLatitude ?? this.centerLatitude,
      centerLongitude: centerLongitude ?? this.centerLongitude,
      estimatedSizeMiB: estimatedSizeMiB ?? this.estimatedSizeMiB,
    );
  }
}

class OfflineMapEstimate {
  final int lowMiB;
  final int highMiB;
  final int approximateRasterTileCount;
  final bool exceedsWarning;

  const OfflineMapEstimate({
    required this.lowMiB,
    required this.highMiB,
    required this.approximateRasterTileCount,
    required this.exceedsWarning,
  });

  String get label => '$lowMiB-$highMiB MB';
}

class OfflineMapService {
  static const String _radiusKey = 'offline_map_radius_km_v1';
  static const String _zoomKey = 'offline_map_vector_zoom_v1';
  static const String _downloadedKey = 'offline_map_downloaded_v1';
  static const String _downloadedAtKey = 'offline_map_downloaded_at_v1';
  static const String _centerLatKey = 'offline_map_center_lat_v1';
  static const String _centerLngKey = 'offline_map_center_lng_v1';
  static const String _estimatedSizeKey = 'offline_map_estimated_mib_v1';

  final FlutterSecureStorage _storage;
  final TileCacheService _tileCacheService;

  const OfflineMapService({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
    TileCacheService tileCacheService = const TileCacheService(),
  })  : _storage = storage,
        _tileCacheService = tileCacheService;

  Future<OfflineMapSettings> loadSettings() async {
    final radius = _clampRadius(await _readInt(_radiusKey));
    final zoom = _clampZoom(await _readInt(_zoomKey));
    return OfflineMapSettings(
      radiusKm: radius,
      maxVectorZoom: zoom,
      downloaded: await _readBool(_downloadedKey),
      downloadedAt: await _readInt(_downloadedAtKey),
      centerLatitude: await _readDouble(_centerLatKey),
      centerLongitude: await _readDouble(_centerLngKey),
      estimatedSizeMiB: await _readInt(_estimatedSizeKey),
    );
  }

  Future<void> saveRadiusKm(int radiusKm) async {
    await _storage.write(
      key: _radiusKey,
      value: _clampRadius(radiusKm).toString(),
    );
  }

  Future<void> saveMaxVectorZoom(int zoom) async {
    await _storage.write(
      key: _zoomKey,
      value: _clampZoom(zoom).toString(),
    );
  }

  Future<OfflineMapSettings> markDownloaded({
    required double centerLatitude,
    required double centerLongitude,
    required int radiusKm,
    required int maxVectorZoom,
  }) async {
    final clampedRadius = _clampRadius(radiusKm);
    final clampedZoom = _clampZoom(maxVectorZoom);
    final estimate = estimateStorage(
      radiusKm: clampedRadius,
      maxVectorZoom: clampedZoom,
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    await _storage.write(key: _downloadedKey, value: 'true');
    await _storage.write(key: _downloadedAtKey, value: now.toString());
    await _storage.write(key: _centerLatKey, value: centerLatitude.toString());
    await _storage.write(key: _centerLngKey, value: centerLongitude.toString());
    await _storage.write(
      key: _estimatedSizeKey,
      value: estimate.highMiB.toString(),
    );
    await saveRadiusKm(clampedRadius);
    await saveMaxVectorZoom(clampedZoom);
    return OfflineMapSettings(
      radiusKm: clampedRadius,
      maxVectorZoom: clampedZoom,
      downloaded: true,
      downloadedAt: now,
      centerLatitude: centerLatitude,
      centerLongitude: centerLongitude,
      estimatedSizeMiB: estimate.highMiB,
    );
  }

  Stream<double> downloadPack({
    required double centerLatitude,
    required double centerLongitude,
    required int radiusKm,
    required int maxZoom,
  }) async* {
    final tiles = _tileCacheService.getTilesInRadius(
      centerLat: centerLatitude,
      centerLng: centerLongitude,
      radiusKm: radiusKm.toDouble(),
      minZoom: OfflineMapConfig.minZoom,
      maxZoom: maxZoom,
    );

    if (tiles.isEmpty) {
      yield 1.0;
      return;
    }

    int downloaded = 0;
    const int concurrency = 4;
    for (int i = 0; i < tiles.length; i += concurrency) {
      final batch = tiles.skip(i).take(concurrency);
      await Future.wait(batch.map(
          (tile) => _tileCacheService.downloadTile(tile.z, tile.x, tile.y)));
      downloaded += batch.length;
      yield downloaded / tiles.length;
    }

    await markDownloaded(
      centerLatitude: centerLatitude,
      centerLongitude: centerLongitude,
      radiusKm: radiusKm,
      maxVectorZoom: maxZoom,
    );
  }

  Future<void> clearDownloadedPack() async {
    await _tileCacheService.clearCache();
    await _storage.write(key: _downloadedKey, value: 'false');
    await _storage.delete(key: _downloadedAtKey);
    await _storage.delete(key: _centerLatKey);
    await _storage.delete(key: _centerLngKey);
    await _storage.delete(key: _estimatedSizeKey);
  }

  Future<int> getActualSizeMiB() async {
    return await _tileCacheService.getCacheSizeMiB();
  }

  OfflineMapEstimate estimateStorage({
    required int radiusKm,
    required int maxVectorZoom,
  }) {
    final radius = _clampRadius(radiusKm);
    final zoom = _clampZoom(maxVectorZoom);

    final rasterTiles = _approximateRasterTiles(
      radiusKm: radius,
      maxZoom: zoom,
      latitude: 20,
    );

    final radiusFactor = pow(radius / OfflineMapConfig.defaultRadiusKm, 2);
    final zoomFactor = zoom == 15 ? 1.0 : 0.45;
    final low = max(15, (40 * radiusFactor * zoomFactor).round());
    final high = max(low + 20, (150 * radiusFactor * zoomFactor).round());

    return OfflineMapEstimate(
      lowMiB: low,
      highMiB: high,
      approximateRasterTileCount: rasterTiles,
      exceedsWarning: high >= OfflineMapConfig.storageWarningMiB,
    );
  }

  int _approximateRasterTiles({
    required int radiusKm,
    required int maxZoom,
    required double latitude,
  }) {
    const earthCircumferenceMeters = 40075016.68557849;
    final diameterMeters = radiusKm * 2000.0;
    final latitudeScale = cos(latitude * pi / 180);
    var total = 0;
    for (var zoom = 0; zoom <= maxZoom; zoom++) {
      final edgeMeters =
          earthCircumferenceMeters * latitudeScale / pow(2, zoom);
      final tilesAcross = (diameterMeters / edgeMeters).ceil() + 1;
      total += tilesAcross * tilesAcross;
    }
    return total;
  }

  int _clampRadius(int? radiusKm) {
    final radius = radiusKm ?? OfflineMapConfig.defaultRadiusKm;
    return radius
        .clamp(OfflineMapConfig.minRadiusKm, OfflineMapConfig.maxRadiusKm)
        .toInt();
  }

  int _clampZoom(int? zoom) {
    final value = zoom ?? OfflineMapConfig.defaultMaxVectorZoom;
    return value
        .clamp(OfflineMapConfig.minVectorZoom, OfflineMapConfig.maxVectorZoom)
        .toInt();
  }

  Future<int?> _readInt(String key) async {
    final raw = await _storage.read(key: key);
    return raw == null ? null : int.tryParse(raw);
  }

  Future<double?> _readDouble(String key) async {
    final raw = await _storage.read(key: key);
    return raw == null ? null : double.tryParse(raw);
  }

  Future<bool> _readBool(String key) async {
    return await _storage.read(key: key) == 'true';
  }
}
