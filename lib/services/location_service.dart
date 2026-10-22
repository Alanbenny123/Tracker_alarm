import 'dart:async';

import 'package:geolocator/geolocator.dart';

class LocationService {
  Future<void> _requireLocationReady() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationException('Turn on location services to use GPS.');
    }
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      throw const LocationException(
        'Location permission is off. Tap Enable location to turn it on.',
      );
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationException(
        'Location permission is blocked. Enable it in app settings.',
      );
    }
  }

  Future<Position> current() async {
    await _requireLocationReady();
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
    } on TimeoutException {
      throw const LocationException(
        'GPS could not find your position yet. Try again outside or near a window.',
      );
    }
  }

  /// Registration checks settings but does not wait for a GPS fix. Native
  /// tracking obtains a fresh position after the alarm has been saved.
  Future<void> ensureReady() => _requireLocationReady();

  Stream<Position> visibleUpdates() => Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    ),
  );

  double distance(Position position, double latitude, double longitude) =>
      Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        latitude,
        longitude,
      );
}

class LocationException implements Exception {
  const LocationException(this.message);
  final String message;
  @override
  String toString() => message;
}
