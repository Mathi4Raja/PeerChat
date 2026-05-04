import 'dart:math';

class LocationPayload {
  final double latitude;
  final double longitude;
  final double? accuracyMeters;
  final int timestamp;
  final String? label;

  const LocationPayload({
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.accuracyMeters,
    this.label,
  });

  bool get isValid =>
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180;

  String get coordinateLabel =>
      '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}';

  String get mapsQuery =>
      '${latitude.toStringAsFixed(6)},${longitude.toStringAsFixed(6)}';

  Map<String, Object?> toWireMap() {
    return {
      'lat': latitude,
      'lng': longitude,
      'ts': timestamp,
      if (accuracyMeters != null) 'acc': accuracyMeters,
      if (label != null && label!.trim().isNotEmpty) 'label': label!.trim(),
    };
  }

  static LocationPayload? fromWireValue(Object? value) {
    if (value is! Map) return null;
    final latitude = _readDouble(value['lat']);
    final longitude = _readDouble(value['lng']);
    final timestamp = _readInt(value['ts']);
    if (latitude == null || longitude == null || timestamp == null) {
      return null;
    }

    final payload = LocationPayload(
      latitude: latitude,
      longitude: longitude,
      timestamp: timestamp,
      accuracyMeters: _readDouble(value['acc']),
      label: _readNonEmptyString(value['label']),
    );
    return payload.isValid ? payload : null;
  }

  static double distanceMeters({
    required double fromLatitude,
    required double fromLongitude,
    required double toLatitude,
    required double toLongitude,
  }) {
    const earthRadiusMeters = 6371008.8;
    final fromLat = _radians(fromLatitude);
    final toLat = _radians(toLatitude);
    final deltaLat = _radians(toLatitude - fromLatitude);
    final deltaLng = _radians(toLongitude - fromLongitude);
    final a = sin(deltaLat / 2) * sin(deltaLat / 2) +
        cos(fromLat) *
            cos(toLat) *
            sin(deltaLng / 2) *
            sin(deltaLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadiusMeters * c;
  }

  static double _radians(double degrees) => degrees * pi / 180;

  static double? _readDouble(Object? value) {
    if (value is num && value.isFinite) return value.toDouble();
    return null;
  }

  static int? _readInt(Object? value) {
    if (value is int) return value;
    if (value is num && value.isFinite) return value.toInt();
    return null;
  }

  static String? _readNonEmptyString(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
