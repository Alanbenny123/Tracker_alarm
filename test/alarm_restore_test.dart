import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:tracker_alarm/models/destination_alarm.dart';
import 'package:tracker_alarm/models/place.dart';
import 'package:tracker_alarm/providers/app_providers.dart';
import 'package:tracker_alarm/services/geofence_service.dart';
import 'package:tracker_alarm/services/location_service.dart';
import 'package:tracker_alarm/services/storage_service.dart';

class MemoryStorage extends StorageService {
  final strings = <String, String>{};
  final doubles = <String, double>{};
  List<TripRecord> records = [];

  @override
  Future<String?> getString(String key) async => strings[key];
  @override
  Future<void> setString(String key, String value) async {
    strings[key] = value;
  }

  @override
  Future<double?> getDouble(String key) async => doubles[key];
  @override
  Future<void> setDouble(String key, double value) async {
    doubles[key] = value;
  }

  @override
  Future<bool?> getBool(String key) async => null;

  @override
  Future<List<TripRecord>> history() async => records;
  @override
  Future<void> setHistory(List<TripRecord> trips) async {
    records = trips;
  }
}

class FakeGeofence extends GeofenceService {
  FakeGeofence(this.nativeStatus, [this.nativeState]);
  String nativeStatus;
  Map<String, dynamic>? nativeState;
  int ensureCalls = 0;
  int triggerCalls = 0;
  int statusCalls = 0;
  AlarmRequirements? requirementsState;

  @override
  Future<AlarmRequirements> requirements() async => requirementsState!;

  @override
  Future<String> status() async {
    statusCalls++;
    return nativeStatus;
  }

  @override
  Future<Map<String, dynamic>?> state() async => nativeState;
  @override
  Future<void> ensure() async {
    ensureCalls++;
  }

  @override
  Future<void> trigger() async {
    triggerCalls++;
    nativeStatus = 'triggered';
  }
}

class NeverCalledLocation extends LocationService {
  bool called = false;

  @override
  Future<Position> current() async {
    called = true;
    throw StateError('GPS should not be queried before required setup');
  }
}

Position positionAt(double latitude, double longitude) => Position(
  latitude: latitude,
  longitude: longitude,
  timestamp: DateTime.now(),
  accuracy: 10,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

void main() {
  test(
    'alarm cannot start before all required Android settings are enabled',
    () async {
      final storage = MemoryStorage();
      final geofence = FakeGeofence('inactive')
        ..requirementsState = const AlarmRequirements(
          preciseLocation: true,
          backgroundLocation: true,
          notifications: true,
          batteryOptimizationOff: false,
        );
      final location = NeverCalledLocation();
      final controller = AlarmController(
        storage,
        geofence,
        location,
        HistoryController(storage),
      );

      await expectLater(
        controller.start(
          const Place(
            name: 'Station',
            address: 'Town',
            latitude: 9.9,
            longitude: 76.7,
          ),
          500,
          true,
          'Bell',
        ),
        throwsA(isA<LocationException>()),
      );

      expect(location.called, isFalse);
      expect(controller.active, isNull);
      expect(controller.error, contains('battery use'));
    },
  );

  test('legacy 2 m default radius migrates to the supported minimum', () async {
    final storage = MemoryStorage()..doubles['default_radius'] = 2.0;
    final settings = SettingsController(storage);

    await settings.load();

    expect(settings.defaultRadius, 100);
    await settings.setRadius(2);
    expect(settings.defaultRadius, 100);
    expect(storage.doubles['default_radius'], 100);
  });

  test(
    'restores an active alarm from native state when Flutter storage is empty',
    () async {
      final storage = MemoryStorage();
      final geofence = FakeGeofence('active', {
        'id': 'native-1',
        'name': 'Station',
        'address': 'Town',
        'latitude': 9.9,
        'longitude': 76.7,
        'radius': 500.0,
        'vibration': true,
        'sound': 'Bell',
        'startedAt': 1791448200000,
      });
      final controller = AlarmController(
        storage,
        geofence,
        LocationService(),
        HistoryController(storage),
      );

      await controller.restore();

      expect(controller.active?.place.name, 'Station');
      expect(controller.active?.radius, 500);
      expect(geofence.ensureCalls, 1);
      expect(storage.strings['active_alarm'], contains('native-1'));
    },
  );

  test(
    'archives a trip stopped from the notification before app restart',
    () async {
      final storage = MemoryStorage();
      final alarm = DestinationAlarm(
        id: 'trip-2',
        place: const Place(
          name: 'Bus stand',
          address: 'Town',
          latitude: 9.9,
          longitude: 76.7,
        ),
        radius: 250,
        vibration: true,
        sound: 'Beep',
        startedAt: DateTime.utc(2026, 10, 8, 8),
      );
      storage.strings['active_alarm'] = jsonEncode(alarm.toJson());
      final controller = AlarmController(
        storage,
        FakeGeofence('completed'),
        LocationService(),
        HistoryController(storage),
      );

      await controller.restore();

      expect(controller.active, isNull);
      expect(storage.records.single.alarm.id, 'trip-2');
      expect(storage.records.single.status, 'completed');
      expect(storage.strings['active_alarm'], isEmpty);
    },
  );

  test(
    'visible GPS updates trigger once after entering the selected radius',
    () async {
      final storage = MemoryStorage();
      final geofence = FakeGeofence('active', {
        'id': 'native-3',
        'name': 'Station',
        'address': 'Town',
        'latitude': 9.9,
        'longitude': 76.7,
        'radius': 500.0,
        'vibration': true,
        'sound': 'Bell',
        'startedAt': 1791448200000,
      });
      final controller = AlarmController(
        storage,
        geofence,
        LocationService(),
        HistoryController(storage),
      );
      await controller.restore();

      await controller.checkVisiblePosition(positionAt(9.92, 76.7));
      expect(geofence.triggerCalls, 0);
      await controller.checkVisiblePosition(positionAt(9.9, 76.7));
      await controller.checkVisiblePosition(positionAt(9.9, 76.7));
      expect(geofence.triggerCalls, 1);
      expect(controller.status, 'triggered');
    },
  );

  test('unchanged native status does not rebuild the active alarm', () async {
    final storage = MemoryStorage();
    final geofence = FakeGeofence('active', {
      'id': 'native-4',
      'name': 'Station',
      'address': 'Town',
      'latitude': 9.9,
      'longitude': 76.7,
      'radius': 500.0,
      'vibration': true,
      'sound': 'Bell',
      'startedAt': 1791448200000,
    });
    final controller = AlarmController(
      storage,
      geofence,
      LocationService(),
      HistoryController(storage),
    );
    await controller.restore();
    var notifications = 0;
    controller.addListener(() => notifications++);

    await controller.syncStatus();
    await controller.syncStatus();

    expect(geofence.statusCalls, 3);
    expect(notifications, 0);
  });
}
