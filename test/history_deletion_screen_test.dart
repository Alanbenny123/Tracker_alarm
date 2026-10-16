import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:tracker_alarm/features/home/home_screen.dart';
import 'package:tracker_alarm/main.dart';
import 'package:tracker_alarm/models/destination_alarm.dart';
import 'package:tracker_alarm/providers/app_providers.dart';

import 'helpers/alarm_fakes.dart';
import 'helpers/raw_memory_storage.dart';

class _QuietLocation extends FakeLocation {
  @override
  Stream<Position> visibleUpdates() => const Stream.empty();
}

void main() {
  testWidgets(
    'history deletion requires confirmation and keeps active alarms and saved places',
    (tester) async {
      final store = RawMemoryStorage();
      final ended = DestinationAlarm(
        id: 'ended',
        place: stationA,
        radius: 500,
        vibration: true,
        sound: 'Bell',
        startedAt: DateTime(2026, 10, 16),
      );
      await store.setHistory([
        TripRecord(
          alarm: ended,
          endedAt: DateTime(2026, 10, 16, 12),
          status: 'completed',
        ),
      ]);
      store.values['recovery_history'] = 'damaged history copy';
      await store.setSavedPlaces([stationB.copyWith(id: 'saved')]);
      final native = FakeNative();
      await native.multiRegister(
        DestinationAlarm(
          id: 'active',
          place: stationB,
          radius: 500,
          vibration: true,
          sound: 'Bell',
          startedAt: DateTime(2026, 10, 16),
        ),
      );
      final history = HistoryController(store);
      await history.load();
      final location = _QuietLocation();
      final alarms = AlarmController(store, native, location, history);
      await alarms.restore();
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const HomeScreen(initialIndex: 3),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storageProvider.overrideWith((ref) => store),
            historyProvider.overrideWith((ref) => history),
            alarmProvider.overrideWith((ref) => alarms),
            locationServiceProvider.overrideWithValue(location),
            geofenceProvider.overrideWithValue(native),
          ],
          child: MaterialApp.router(
            theme: createAppTheme(Brightness.light),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Clear trip history'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(history.trips, hasLength(1));
      expect(store.values['recovery_history'], isNotEmpty);
      await tester.tap(find.byTooltip('Clear trip history'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('No trips yet.'), findsOneWidget);
      expect(store.values['recovery_history'], isEmpty);
      expect(native.states.single['id'], 'active');
      expect((await store.savedPlaces()).single.id, 'saved');
      await tester.pumpWidget(const SizedBox());
      router.dispose();
    },
  );
}
