import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/location_payload.dart';

/// Internal tile coordinate container used only by [TileCacheService].
class DownloadTile {
  final int z;
  final int x;
  final int y;

  const DownloadTile(this.z, this.x, this.y);
}

class TileCacheService {
  static final HttpClient _httpClient = HttpClient()
    ..connectionTimeout = const Duration(seconds: 5);
  static const String _tileBaseUrl = 'https://tile.openstreetmap.org';
  static const String _cacheFolderName = 'map_tiles_v1';

  const TileCacheService();

  Future<String> get _cachePath async {
    final docDir = await getApplicationDocumentsDirectory();
    final path = p.join(docDir.path, _cacheFolderName);
    final directory = Directory(path);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return path;
  }

  String _getFilePath(String cacheRoot, int z, int x, int y) {
    return p.join(cacheRoot, '$z', '$x', '$y.png');
  }

  Future<File?> getCachedTile(int z, int x, int y) async {
    final root = await _cachePath;
    final file = File(_getFilePath(root, z, x, y));
    if (await file.exists()) {
      return file;
    }
    return null;
  }

  Future<void> downloadTile(int z, int x, int y) async {
    final root = await _cachePath;
    final filePath = _getFilePath(root, z, x, y);
    final file = File(filePath);

    if (await file.exists()) return;

    await file.parent.create(recursive: true);

    final url = '$_tileBaseUrl/$z/$x/$y.png';
    try {
      final request = await _httpClient.getUrl(Uri.parse(url));
      request.headers.set('User-Agent', 'PeerChat/1.0 (Privacy-first P2P app)');
      final response = await request.close().timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final sink = file.openWrite();
        await response.pipe(sink);
      }
    } catch (e) {
      // Individual tile failures are non-fatal; the tile will simply be absent offline.
      assert(() {
        debugPrint('TileCacheService: failed to download tile $z/$x/$y: $e');
        return true;
      }());
    }
  }

  Future<Uint8List?> fetchTileBytes(int z, int x, int y) async {
    final url = '$_tileBaseUrl/$z/$x/$y.png';
    try {
      final request = await _httpClient.getUrl(Uri.parse(url));
      request.headers.set('User-Agent', 'PeerChat/1.0 (Privacy-first P2P app)');
      final response = await request.close().timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final bytes = await response.fold<List<int>>([], (p, e) => p..addAll(e));
        return Uint8List.fromList(bytes);
      }
    } catch (e) {
      debugPrint('TileCacheService: failed to fetch tile bytes $z/$x/$y: $e');
    }
    return null;
  }

  List<DownloadTile> getTilesInRadius({
    required double centerLat,
    required double centerLng,
    required double radiusKm,
    required int minZoom,
    required int maxZoom,
  }) {
    final List<DownloadTile> tiles = [];

    for (int z = minZoom; z <= maxZoom; z++) {
      final centerTileX = _lonToTileX(centerLng, z);
      final centerTileY = _latToTileY(centerLat, z);

      final metersPerPixel =
          156543.03392 * cos(centerLat * pi / 180) / pow(2, z);
      final metersPerTile = metersPerPixel * 256;
      final tileRadius = (radiusKm * 1000 / metersPerTile).ceil() + 1;

      for (int x = centerTileX - tileRadius;
          x <= centerTileX + tileRadius;
          x++) {
        for (int y = centerTileY - tileRadius;
            y <= centerTileY + tileRadius;
            y++) {
          if (x < 0 || y < 0) continue;
          final maxTile = pow(2, z).toInt();
          if (x >= maxTile || y >= maxTile) continue;
          tiles.add(DownloadTile(z, x, y));
        }
      }
    }

    return tiles;
  }

  int _lonToTileX(double lon, int z) {
    return ((lon + 180) / 360 * pow(2, z)).floor();
  }

  int _latToTileY(double lat, int z) {
    return ((1 - log(tan(lat * pi / 180) + 1 / cos(lat * pi / 180)) / pi) /
            2 *
            pow(2, z))
        .floor();
  }

  double _tileXToLon(int x, int z) {
    return x / pow(2, z) * 360 - 180;
  }

  double _tileYToLat(int y, int z) {
    final n = pi - 2 * pi * y / pow(2, z);
    return 180 / pi * atan(0.5 * (exp(n) - exp(-n)));
  }

  Future<void> clearCache() async {
    final root = await _cachePath;
    final directory = Directory(root);
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  Future<int> getCacheSizeMiB() async {
    try {
      final root = await _cachePath;
      final directory = Directory(root);
      if (!await directory.exists()) return 0;

      int totalBytes = 0;
      await for (final entity in directory.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          totalBytes += await entity.length();
        }
      }
      return (totalBytes / (1024 * 1024)).round();
    } catch (e) {
      return 0;
    }
  }
}

class CachedTileProvider extends fm.TileProvider {
  final TileCacheService _tileCacheService = const TileCacheService();
  final double? centerLat;
  final double? centerLng;
  final double? radiusKm;

  CachedTileProvider({
    this.centerLat,
    this.centerLng,
    this.radiusKm,
  });

  @override
  ImageProvider<Object> getImage(
      fm.TileCoordinates coordinates, fm.TileLayer options) {
    return _CachedTileImageProvider(
      z: coordinates.z,
      x: coordinates.x,
      y: coordinates.y,
      tileCacheService: _tileCacheService,
      centerLat: centerLat,
      centerLng: centerLng,
      radiusKm: radiusKm,
    );
  }
}

class _CachedTileImageProvider extends ImageProvider<_CachedTileImageProvider> {
  final int x;
  final int y;
  final int z;
  final TileCacheService tileCacheService;
  final double? centerLat;
  final double? centerLng;
  final double? radiusKm;

  const _CachedTileImageProvider({
    required this.x,
    required this.y,
    required this.z,
    required this.tileCacheService,
    this.centerLat,
    this.centerLng,
    this.radiusKm,
  });

  @override
  Future<_CachedTileImageProvider> obtainKey(ImageConfiguration configuration) {
    return Future.value(this);
  }

  @override
  ImageStreamCompleter loadImage(
    _CachedTileImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode),
      scale: 1.0,
      debugLabel: 'CachedTileImageProvider($z, $x, $y)',
    );
  }

  Future<ui.Codec> _loadAsync(
    _CachedTileImageProvider key,
    ImageDecoderCallback decode,
  ) async {
    var file = await tileCacheService.getCachedTile(z, x, y);

    if (file != null) {
      final bytes = await file.readAsBytes();
      return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
    }

    // Fallback logic: check if we are within the caching zone
    bool isInsideCachingZone = true;
    if (centerLat != null && centerLng != null) {
      final tileLat = tileCacheService._tileYToLat(y, z);
      final tileLon = tileCacheService._tileXToLon(x, z);
      final distanceMeters = LocationPayload.distanceMeters(
        fromLatitude: centerLat!,
        fromLongitude: centerLng!,
        toLatitude: tileLat,
        toLongitude: tileLon,
      );
      // Strict zone enforcement (50km + buffer)
      final allowedRadiusMeters = (radiusKm ?? 50.0).clamp(0.0, 50.0) * 1000 + 2000;
      if (distanceMeters > allowedRadiusMeters) {
        isInsideCachingZone = false;
      }
    }

    if (isInsideCachingZone) {
      // Inside zone: Download and SAVE to disk
      await tileCacheService.downloadTile(z, x, y);
      final newFile = await tileCacheService.getCachedTile(z, x, y);
      if (newFile != null) {
        final bytes = await newFile.readAsBytes();
        return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
      }
    } else {
      // Outside zone: Fetch from network ONLY (do not save to disk)
      final bytes = await tileCacheService.fetchTileBytes(z, x, y);
      if (bytes != null) {
        return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
      }
    }

    // Return a 1×1 transparent PNG placeholder if everything failed
    final transparentBytes = Uint8List.fromList([
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
      0x00,
      0x00,
      0x00,
      0x0D,
      0x49,
      0x48,
      0x44,
      0x52,
      0x00,
      0x00,
      0x00,
      0x01,
      0x00,
      0x00,
      0x00,
      0x01,
      0x08,
      0x06,
      0x00,
      0x00,
      0x00,
      0x1F,
      0x15,
      0xC4,
      0x89,
      0x00,
      0x00,
      0x00,
      0x0A,
      0x49,
      0x44,
      0x41,
      0x54,
      0x08,
      0xD7,
      0x63,
      0x60,
      0x00,
      0x02,
      0x00,
      0x00,
      0x05,
      0x00,
      0x01,
      0x0D,
      0x26,
      0x2D,
      0x33,
      0x00,
      0x00,
      0x00,
      0x00,
      0x49,
      0x45,
      0x4E,
      0x44,
      0xAE,
      0x42,
      0x60,
      0x82,
    ]);
    return decode(await ui.ImmutableBuffer.fromUint8List(transparentBytes));
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _CachedTileImageProvider &&
          x == other.x &&
          y == other.y &&
          z == other.z;

  @override
  int get hashCode => Object.hash(x, y, z);
}
