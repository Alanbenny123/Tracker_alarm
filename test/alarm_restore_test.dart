import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
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
  Future<void> setString(String key, String value) async =>
      strings[key] = value;
  @override
  Future<double?> getDouble(String key) async => doubles[key];
  @override
  Future<void> setDouble(String key, double value) async =>
      doubles[key] = value;
  @override
  Future<bool?> getBool(String key) async => null;
  @override
  Future<List<TripRecord>> history() async => records;
  @override
  Future<void> setHistory(List<TripRecord> trips) async => records = trips;
}

class FakeNative extends GeofenceService {
  FakeNative(this.states);
  final List<Map<String, dynamic>> states;
  int ensureCalls = 0;
  final forgotten = <String>[];
  String legacyStatus = 'inactive';
  @override
  Future<List<Map<String, dynamic>>> multiStates() async =>
      states.map((state) => Map<String, dynamic>.from(state)).toList();
  @override
  Future<void> multiEnsure() async => ensureCalls++;
  @override
  Future<void> multiForget(String id) async {
    forgotten.add(id);
    states.removeWhere((state) => state['id'] == id);
  }

  @override
  Future<String> status() async => legacyStatus;
}

Map<String, dynamic> nativeState(String id, String status) => {
  'id': id,
  'name': 'Station',
  'address': 'Town',
  'latitude': 9.9,
  'longitude': 76.7,
  'radius': 500.0,
  'vibration': true,
  'sound': 'Bell',
  'startedAt': 1791448200000,
  'status': status,
  'timeFired': false,
  'distanceFired': false,
  'triggerReason': 'distance',
};

void main() {
  test('restores all live alarms from native storage', () async {
    final storage = MemoryStorage();
    final native = FakeNative([
      nativeState('one', 'active'),
      nativeState('two', 'snoozed'),
    ]);
    final controller = AlarmController(
      storage,
      native,
      LocationService(),
      HistoryController(storage),
    );
    await controller.restore();
    expect(controller.alarms.length, 2);
    expect(controller.alarms.map((e) => e.alarm.id), ['one', 'two']);
    expect(native.ensureCalls, 1);
  });

  test('archives alarms ended from notifications before app restart', () async {
    final storage = MemoryStorage();
    final native = FakeNative([
      nativeState('one', 'completed'),
      nativeState('two', 'active'),
    ]);
    final controller = AlarmController(
      storage,
      native,
      LocationService(),
      HistoryController(storage),
    );
    await controller.restore();
    expect(controller.alarms.single.alarm.id, 'two');
    expect(storage.records.single.alarm.id, 'one');
    expect(native.forgotten, ['one']);
  });

  test('migrates a legacy finished alarm into history', () async {
    final storage = MemoryStorage();
    final alarm = DestinationAlarm(
      id: 'legacy',
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
    final native = FakeNative([])..legacyStatus = 'completed';
    final controller = AlarmController(
      storage,
      native,
      LocationService(),
      HistoryController(storage),
    );
    await controller.restore();
    expect(storage.records.single.alarm.id, 'legacy');
    expect(storage.strings['active_alarm'], isEmpty);
  });

  test('legacy 2 m default radius migrates to supported minimum', () async {
    final storage = MemoryStorage()..doubles['default_radius'] = 2.0;
    final settings = SettingsController(storage);
    await settings.load();
    expect(settings.defaultRadius, 100);
    await settings.setRadius(2);
    expect(settings.defaultRadius, 100);
  });
}
