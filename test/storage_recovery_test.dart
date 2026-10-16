import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracker_alarm/models/destination_alarm.dart';
import 'package:tracker_alarm/providers/app_providers.dart';
import 'package:tracker_alarm/services/storage_service.dart';

import 'helpers/alarm_fakes.dart';
import 'helpers/raw_memory_storage.dart';

DestinationAlarm savedAlarm(String id) => DestinationAlarm(
  id: id,
  place: stationA,
  radius: 500,
  vibration: true,
  sound: 'Bell',
  startedAt: DateTime(2026, 10, 16),
);
TripRecord trip(String id, [int minute = 0]) => TripRecord(
  alarm: savedAlarm(id),
  endedAt: DateTime(2026, 10, 16, 12, minute),
  status: 'completed',
);

void main() {
  test('one damaged history entry cannot hide valid trips', () async {
    final store = RawMemoryStorage();
    final raw = jsonEncode([
      trip('one').toJson(),
      {'alarm': 'broken'},
      trip('two').toJson(),
    ]);
    store.values['history'] = raw;
    expect((await store.history()).map((trip) => trip.alarm.id), [
      'one',
      'two',
    ]);
    expect(store.values['recovery_history'], raw);
    expect((jsonDecode(store.values['history']!) as List), hasLength(2));
    expect(store.warnings.single, contains('2 valid entries recovered'));
  });

  test('malformed history restores its last good snapshot', () async {
    final store = RawMemoryStorage();
    await store.setHistory([trip('kept')]);
    store.values['history'] = '[broken';
    expect((await store.history()).single.alarm.id, 'kept');
    expect(store.values['recovery_history'], '[broken');
    expect(store.warnings, isNotEmpty);
  });

  test(
    'saved places reject invalid coordinates and missing IDs individually',
    () async {
      final store = RawMemoryStorage();
      store.values['saved_places'] = jsonEncode([
        stationA.copyWith(id: 'valid').toJson(),
        {...stationB.copyWith(id: 'invalid').toJson(), 'latitude': 100},
        stationB.toJson(),
      ]);
      expect((await store.savedPlaces()).single.id, 'valid');
      expect(store.values['recovery_saved_places'], isNotEmpty);
    },
  );

  test(
    'history is bounded and explicit clear removes its recovery copies',
    () async {
      final store = RawMemoryStorage();
      await store.setSavedPlaces([stationA.copyWith(id: 'home')]);
      await store.setHistory([for (var i = 0; i < 105; i++) trip('$i', i)]);
      expect((await store.history()), hasLength(StorageService.historyLimit));
      expect((await store.history()).first.alarm.id, '104');
      expect(
        (jsonDecode(store.values['last_good_history']!) as List),
        hasLength(100),
      );
      store.values['recovery_history'] = 'damaged';
      await store.clearHistory();
      expect(await store.history(), isEmpty);
      expect(store.values['last_good_history'], '[]');
      expect(store.values['recovery_history'], isEmpty);
      expect((await store.savedPlaces()).single.id, 'home');
    },
  );

  test('failed archival keeps the native record and can be retried', () async {
    final store = RawMemoryStorage()..failWrites = true;
    final native = FakeNative();
    await native.multiRegister(savedAlarm('done'));
    native.entry('done')['status'] = 'completed';
    await native.multiRegister(savedAlarm('live'));
    final history = HistoryController(store);
    final controller = AlarmController(store, native, FakeLocation(), history);
    await controller.restore();
    expect(controller.active!.id, 'live');
    expect(native.states.any((entry) => entry['id'] == 'done'), isTrue);
    expect(history.trips, isEmpty);
    expect(history.error, isNotNull);
    store.failWrites = false;
    await controller.syncStatus();
    expect(history.trips.single.alarm.id, 'done');
    expect(native.states.any((entry) => entry['id'] == 'done'), isFalse);
  });

  test(
    'history read errors block destructive writes and retain live alarms',
    () async {
      final store = RawMemoryStorage()..failReadKey = 'history';
      final native = FakeNative();
      await native.multiRegister(savedAlarm('done'));
      native.entry('done')['status'] = 'completed';
      await native.multiRegister(savedAlarm('live'));
      final history = HistoryController(store);
      final controller = AlarmController(
        store,
        native,
        FakeLocation(),
        history,
      );
      await controller.restore();
      expect(controller.active!.id, 'live');
      expect(native.states, hasLength(2));
      expect(store.values.containsKey('history'), isFalse);
      store.failReadKey = null;
      await history.reload();
      await controller.syncStatus();
      expect(native.states, hasLength(1));
      expect(history.trips.single.alarm.id, 'done');
    },
  );

  test(
    'history adds and clear are serialized so pending saves cannot undo deletion',
    () async {
      final store = RawMemoryStorage()..historyWriteGate = Completer<void>();
      final history = HistoryController(store);
      final first = history.add(trip('first'));
      await Future<void>.delayed(Duration.zero);
      final second = history.add(trip('second'));
      final clear = history.clear();
      store.historyWriteGate!.complete();
      await Future.wait([first, second, clear]);
      expect(history.trips, isEmpty);
      expect(await store.history(), isEmpty);
    },
  );

  test(
    'failed place and settings writes do not change displayed values',
    () async {
      final store = RawMemoryStorage();
      final places = PlacesController(store);
      await places.load();
      final settings = SettingsController(store);
      await settings.load();
      store.failWrites = true;
      await expectLater(places.add(stationA, 'Home'), throwsStateError);
      expect(places.places, isEmpty);
      await settings.setSound('Digital');
      expect(settings.sound, 'Default alarm');
      expect(store.warnings, isNotEmpty);
    },
  );

  test('malformed legacy alarm does not hide current native alarms', () async {
    final store = RawMemoryStorage()..values['active_alarm'] = 'broken legacy';
    final native = FakeNative();
    await native.multiRegister(savedAlarm('live'));
    final controller = AlarmController(
      store,
      native,
      FakeLocation(),
      HistoryController(store),
    );
    await controller.restore();
    expect(controller.active!.id, 'live');
    expect(store.values['recovery_active_alarm'], 'broken legacy');
    expect(store.values['active_alarm'], isEmpty);
    expect(controller.error, isNull);
  });
}
