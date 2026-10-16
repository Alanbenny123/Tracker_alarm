import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:tracker_alarm/models/destination_alarm.dart';
import 'package:tracker_alarm/models/place.dart';
import 'package:tracker_alarm/models/repeat_schedule.dart';
import 'package:tracker_alarm/providers/app_providers.dart';
import 'package:tracker_alarm/services/geofence_service.dart';
import 'package:tracker_alarm/services/location_service.dart';
import 'package:tracker_alarm/services/storage_service.dart';

class MemoryStorage extends StorageService {
  final strings = <String, String>{};
  List<TripRecord> records = [];
  @override
  Future<String?> getString(String key) async => strings[key];
  @override
  Future<void> setString(String key, String value) async =>
      strings[key] = value;
  @override
  Future<List<TripRecord>> history() async => records;
  @override
  Future<void> setHistory(List<TripRecord> trips) async => records = trips;
}

class FakeNative extends GeofenceService {
  final states = <Map<String, dynamic>>[];
  final triggeredIds = <String>[];
  AlarmRequirements requirementsState = const AlarmRequirements(
    preciseLocation: true,
    backgroundLocation: true,
    notifications: true,
    batteryOptimizationOff: true,
  );
  @override
  Future<AlarmRequirements> requirements() async => requirementsState;
  @override
  Future<List<Map<String, dynamic>>> multiStates() async =>
      states.map((state) => Map<String, dynamic>.from(state)).toList();
  @override
  Future<void> multiEnsure() async {}
  @override
  Future<void> multiUpdateRepeat(String id, int days) async {
    entry(id)['repeatDays'] = days;
  }

  @override
  Future<void> multiRegister(DestinationAlarm alarm) async {
    states.add({
      'id': alarm.id,
      'name': alarm.place.name,
      'address': alarm.place.address,
      'latitude': alarm.place.latitude,
      'longitude': alarm.place.longitude,
      'radius': alarm.radius,
      'vibration': alarm.vibration,
      'sound': alarm.sound,
      'startedAt': alarm.startedAt.millisecondsSinceEpoch,
      if (alarm.alertAt != null)
        'alertAt': alarm.alertAt!.millisecondsSinceEpoch,
      'repeatDays': alarm.repeatDays,
      'leadMinutes': alarm.leadMinutes,
      if (alarm.repeatStartDay != null)
        'repeatStartDay': alarm.repeatStartDay!.millisecondsSinceEpoch,
      'status': 'active',
      'timeFired': false,
      'distanceFired': false,
      'triggerReason': 'distance',
    });
  }

  Map<String, dynamic> entry(String id) =>
      states.firstWhere((state) => state['id'] == id);
  @override
  Future<void> multiTrigger(String id) async {
    triggeredIds.add(id);
    entry(id)['distanceFired'] = true;
    entry(id)['status'] = 'triggered';
    entry(id)['triggerReason'] = 'distance';
    entry(id)['triggeredAt'] = triggeredIds.length;
  }

  @override
  Future<void> multiDismiss(String id) async {
    final alarm = entry(id);
    alarm['status'] =
        alarm['distanceFired'] == true &&
                (!alarm.containsKey('alertAt') || alarm['timeFired'] == true)
            ? 'completed'
            : 'active';
  }

  @override
  Future<void> multiFinish(String id, String status) async =>
      entry(id)['status'] = status;
  @override
  Future<void> multiForget(String id) async =>
      states.removeWhere((state) => state['id'] == id);
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

class FakeLocation extends LocationService {
  @override
  Future<Position> current() async => positionAt(0, 0);
}

class NeverCalledLocation extends LocationService {
  bool called = false;
  @override
  Future<Position> current() async {
    called = true;
    throw StateError('GPS should not be queried');
  }
}

const stationA = Place(
  name: 'Station A',
  address: 'Town',
  latitude: 9.9,
  longitude: 76.7,
);
const stationB = Place(
  name: 'Station B',
  address: 'Town',
  latitude: 9.91,
  longitude: 76.71,
);
const stationNearby = Place(
  name: 'Closer station',
  address: 'Town',
  latitude: 9.9005,
  longitude: 76.7005,
);

void main() {
  test(
    'native monitoring failures and GPS health reach the alarm UI state',
    () async {
      final storage = MemoryStorage();
      final native = FakeNative();
      final controller = AlarmController(
        storage,
        native,
        FakeLocation(),
        HistoryController(storage),
      );
      await controller.restore();
      await controller.start(stationA, 500, true, 'Bell');
      native.entry(controller.active!.id).addAll({
        'monitoringHealthy': false,
        'monitoringMessage': 'GPS subscription failed',
        'gpsStatus': 'Waiting for GPS',
        'geofenceStatus': 'Unavailable',
      });
      await controller.syncStatus();
      expect(controller.selected!.monitoringHealthy, isFalse);
      expect(controller.selected!.monitoringMessage, 'GPS subscription failed');
      expect(controller.selected!.gpsStatus, 'Waiting for GPS');
      expect(controller.selected!.geofenceStatus, 'Unavailable');
    },
  );

  test(
    'separate alarms can target the same and different destinations',
    () async {
      final storage = MemoryStorage();
      final native = FakeNative();
      final controller = AlarmController(
        storage,
        native,
        FakeLocation(),
        HistoryController(storage),
      );
      await controller.restore();

      await controller.start(stationA, 250, true, 'Bell');
      await controller.start(stationA, 500, false, 'Beep');
      await controller.start(stationB, 100, true, 'Digital');
      expect(controller.alarms.map((e) => e.alarm.place.name).toList(), [
        'Station A',
        'Station A',
        'Station B',
      ]);
      expect(controller.alarms.map((e) => e.alarm.id).toSet().length, 3);

      final firstId = controller.alarms[0].alarm.id;
      final secondId = controller.alarms[1].alarm.id;
      controller.select(secondId);
      await controller.cancel(firstId);
      expect(controller.alarms.length, 2);
      expect(storage.records.single.status, 'cancelled');
      expect(controller.alarms.map((e) => e.alarm.place.name).toList(), [
        'Station A',
        'Station B',
      ]);
      expect(controller.alarms.first.alarm.id, secondId);
    },
  );

  test(
    'GPS checks every alarm and completed alarm leaves others running',
    () async {
      final storage = MemoryStorage();
      final native = FakeNative();
      final controller = AlarmController(
        storage,
        native,
        FakeLocation(),
        HistoryController(storage),
      );
      await controller.restore();
      await controller.start(stationA, 250, true, 'Bell');
      await controller.start(stationA, 500, true, 'Bell');
      await controller.start(stationB, 100, true, 'Bell');

      await controller.checkVisiblePosition(positionAt(9.9, 76.7));
      expect(native.triggeredIds.length, 2);
      expect(controller.alarms.where((e) => e.status == 'triggered').length, 2);
      await controller.dismissCurrent();
      expect(controller.alarms.length, 2);
      expect(controller.hasTriggered, true);
      await controller.dismissCurrent();
      expect(controller.alarms.length, 1);
      expect(controller.active?.place.name, 'Station B');
      expect(storage.records.length, 2);
    },
  );

  test('reaching the second destination triggers only its alarm', () async {
    final storage = MemoryStorage();
    final native = FakeNative();
    final controller = AlarmController(
      storage,
      native,
      FakeLocation(),
      HistoryController(storage),
    );
    await controller.restore();
    await controller.start(stationA, 100, true, 'Bell');
    await controller.start(stationB, 100, true, 'Bell');
    final secondId = controller.alarms.last.alarm.id;

    await controller.checkVisiblePosition(positionAt(9.91, 76.71));

    expect(native.triggeredIds, [secondId]);
    expect(controller.active?.id, secondId);
    expect(controller.alarms.first.status, 'active');
  });

  test('overlapping alert areas ring the closer destination first', () async {
    final storage = MemoryStorage();
    final native = FakeNative();
    final controller = AlarmController(
      storage,
      native,
      FakeLocation(),
      HistoryController(storage),
    );
    await controller.restore();
    await controller.start(stationA, 200, true, 'Bell');
    await controller.start(stationNearby, 200, true, 'Bell');
    final nearbyId = controller.alarms.last.alarm.id;

    await controller.checkVisiblePosition(positionAt(9.9005, 76.7005));

    expect(native.triggeredIds.first, nearbyId);
    expect(controller.active?.id, nearbyId);
  });

  test(
    'earliest triggered alarm rings before the alarm created first',
    () async {
      final storage = MemoryStorage();
      final native = FakeNative();
      final controller = AlarmController(
        storage,
        native,
        FakeLocation(),
        HistoryController(storage),
      );
      await controller.restore();
      await controller.start(stationA, 100, true, 'Bell');
      await controller.start(stationB, 100, true, 'Bell');
      final firstId = controller.alarms.first.alarm.id;
      final secondId = controller.alarms.last.alarm.id;
      native.entry(firstId)
        ..['status'] = 'triggered'
        ..['distanceFired'] = true
        ..['triggeredAt'] = 200;
      native.entry(secondId)
        ..['status'] = 'triggered'
        ..['distanceFired'] = true
        ..['triggeredAt'] = 100;

      await controller.syncStatus();

      expect(controller.active?.id, secondId);
    },
  );

  test(
    'time alert can be dismissed before distance alert on one alarm',
    () async {
      final storage = MemoryStorage();
      final native = FakeNative();
      final controller = AlarmController(
        storage,
        native,
        FakeLocation(),
        HistoryController(storage),
      );
      await controller.restore();
      await controller.start(
        stationA,
        250,
        true,
        'Bell',
        DateTime.now().add(const Duration(hours: 1)),
      );
      final id = controller.active!.id;
      native.entry(id)['timeFired'] = true;
      native.entry(id)['status'] = 'triggered';
      native.entry(id)['triggerReason'] = 'time';
      await controller.syncStatus();
      await controller.dismissCurrent();
      expect(controller.active?.id, id);
      expect(controller.status, 'active');

      await controller.checkVisiblePosition(positionAt(9.9, 76.7));
      expect(controller.status, 'triggered');
      await controller.dismissCurrent();
      expect(controller.alarms, isEmpty);
      expect(storage.records.single.status, 'completed');
    },
  );

  test('required settings are checked before GPS is queried', () async {
    final storage = MemoryStorage();
    final native =
        FakeNative()
          ..requirementsState = const AlarmRequirements(
            preciseLocation: true,
            backgroundLocation: true,
            notifications: true,
            batteryOptimizationOff: false,
          );
    final location = NeverCalledLocation();
    final controller = AlarmController(
      storage,
      native,
      location,
      HistoryController(storage),
    );
    await controller.restore();
    await expectLater(
      controller.start(stationA, 500, true, 'Bell'),
      throwsA(isA<LocationException>()),
    );
    expect(location.called, false);
    expect(controller.alarms, isEmpty);
  });

  test(
    'repeating alarm keeps its weekdays and waits for an active distance day',
    () async {
      final storage = MemoryStorage();
      final native = FakeNative();
      final controller = AlarmController(
        storage,
        native,
        FakeLocation(),
        HistoryController(storage),
      );
      await controller.restore();
      final alertAt = DateTime.now().add(const Duration(days: 1));
      await controller.start(stationA, 250, true, 'Bell', alertAt, 42, 15);
      final id = controller.active!.id;
      expect(native.entry(id)['repeatDays'], 42);
      expect(native.entry(id)['leadMinutes'], 15);

      native.entry(id)['distanceReady'] = false;
      await controller.syncStatus();
      await controller.checkVisiblePosition(positionAt(9.9, 76.7));
      expect(native.triggeredIds, isEmpty);
    },
  );

  test('distance-only alarm can repeat on selected days', () async {
    final storage = MemoryStorage();
    final native = FakeNative();
    final controller = AlarmController(
      storage,
      native,
      FakeLocation(),
      HistoryController(storage),
    );
    await controller.restore();
    final day = DateTime(2026, 10, 16);
    await controller.start(stationA, 250, true, 'Bell', null, 16, 0, day);

    final alarm = controller.active!;
    expect(alarm.alertAt, isNull);
    expect(alarm.repeatDays, 16);
    expect(alarm.repeatStartDay, day);
    expect(native.entry(alarm.id).containsKey('alertAt'), false);
  });

  test('new distance alarm starts on the next selected weekday', () async {
    final storage = MemoryStorage();
    final native = FakeNative();
    final controller = AlarmController(
      storage,
      native,
      FakeLocation(),
      HistoryController(storage),
    );
    await controller.restore();
    final now = DateTime.now();
    final selectedDay = DateTime(now.year, now.month, now.day + 3);
    final days = 1 << (selectedDay.weekday - 1);

    await controller.start(stationA, 500, true, 'Bell', null, days);

    final alarm = controller.active!;
    expect(alarm.repeatDays, days);
    expect(alarm.repeatStartDay, selectedDay);
    expect(alarm.repeatStartDay, nextRepeatDay(days, alarm.startedAt));
    expect(native.entry(alarm.id)['repeatDays'], days);
    expect(native.entry(alarm.id).containsKey('alertAt'), false);
  });

  test('active alarm can change repeat days without duplication', () async {
    final storage = MemoryStorage();
    final native = FakeNative();
    final controller = AlarmController(
      storage,
      native,
      FakeLocation(),
      HistoryController(storage),
    );
    await controller.restore();
    await controller.start(stationA, 500, true, 'Bell');
    final id = controller.active!.id;

    await controller.setRepeatDays(id, 5);

    expect(controller.alarms, hasLength(1));
    expect(controller.active!.id, id);
    expect(controller.active!.repeatDays, 5);
    expect(controller.active!.place.name, stationA.name);
    expect(controller.active!.radius, 500);
  });
}
