import 'package:geolocator/geolocator.dart';
import 'package:tracker_alarm/models/destination_alarm.dart';
import 'package:tracker_alarm/models/place.dart';
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
    exactAlarms: true,
    fullScreenAlarms: true,
    batteryOptimizationOff: true,
  );
  @override
  Future<AlarmRequirements> requirements() async => requirementsState;
  @override
  Future<List<Map<String, dynamic>>> multiStates() async =>
      states.map((state) => Map<String, dynamic>.from(state)).toList();
  @override
  Future<String?> storageWarning() async => null;
  @override
  Future<void> clearFinished() async => states.removeWhere(
    (entry) => entry['status'] == 'completed' || entry['status'] == 'cancelled',
  );
  @override
  Future<void> clearStorageRecovery() async {}
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
      'label': alarm.label,
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
  final updatedIds = <String>[];
  final testSounds = <String>[];
  final testVibrations = <bool>[];
  int testStops = 0;
  @override
  Future<void> startTestAlarm(String sound, bool vibration) async {
    testSounds.add(sound);
    testVibrations.add(vibration);
  }

  @override
  Future<void> stopTestAlarm() async {
    testStops++;
  }

  @override
  Future<void> renameAlarm(String id, String label) async {
    entry(id)['label'] = label;
  }

  @override
  Future<void> pauseAlarm(String id, bool paused) async {
    entry(id)['status'] = paused ? 'paused' : 'active';
    entry(id)['distanceReady'] = !paused;
  }

  @override
  Future<void> updateAlarm(
    String id,
    Place place,
    double radius,
    bool vibration,
    String sound,
    int repeatDays,
    String label,
  ) async {
    updatedIds.add(id);
    entry(id).addAll({
      'name': place.name,
      'address': place.address,
      'latitude': place.latitude,
      'longitude': place.longitude,
      'radius': radius,
      'vibration': vibration,
      'sound': sound,
      'repeatDays': repeatDays,
      'label': label,
    });
  }

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
  @override
  Future<void> ensureReady() async {}
}

class NeverCalledLocation extends LocationService {
  bool called = false;
  @override
  Future<void> ensureReady() async {
    called = true;
    throw StateError('GPS should not be queried');
  }

  @override
  Future<Position> current() async {
    called = true;
    throw StateError('GPS should not be queried');
  }
}

class NoFixLocation extends LocationService {
  bool called = false;
  @override
  Future<void> ensureReady() async {
    called = true;
  }

  @override
  Future<Position> current() async =>
      throw StateError('Starting an alarm must not wait for a GPS fix');
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
