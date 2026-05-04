import 'dart:async';
import 'package:geolocator/geolocator.dart';

import '../models/location_payload.dart';

class LocationService {
  Future<LocationPayload> currentLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const LocationServiceException('Location services are disabled');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw const LocationServiceException('Location permission denied');
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationServiceException(
        'Location permission permanently denied',
      );
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 25),
        ),
      );

      return LocationPayload(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters: position.accuracy.isFinite ? position.accuracy : null,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );
    } on TimeoutException {
      // Fallback: try to get the last known position if current position times out
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        return LocationPayload(
          latitude: lastKnown.latitude,
          longitude: lastKnown.longitude,
          accuracyMeters: lastKnown.accuracy.isFinite ? lastKnown.accuracy : null,
          timestamp: lastKnown.timestamp.millisecondsSinceEpoch,
        );
      }
      throw const LocationServiceException(
        'Location timeout: Could not get a GPS fix. Try moving near a window or outdoors.',
      );
    } catch (e) {
      throw LocationServiceException('Location error: $e');
    }
  }
}

class LocationServiceException implements Exception {
  final String message;
  const LocationServiceException(this.message);

  @override
  String toString() => message;
}
