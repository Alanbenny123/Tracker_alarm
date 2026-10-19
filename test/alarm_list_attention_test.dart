import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:tracker_alarm/features/home/home_screen.dart';
import 'package:tracker_alarm/models/destination_alarm.dart';
import 'package:tracker_alarm/providers/app_providers.dart';

import 'helpers/alarm_fakes.dart';

class _VisibleLocation extends FakeLocation {
  @override
  Stream<Position> visibleUpdates() => const Stream.empty();
}

void main() {
  testWidgets('a scheduled repeat shows monitoring failures on the Alarms tab', (
    tester,
  ) async {
    final store = MemoryStorage();
    final native = FakeNative();
    await native.multiRegister(
      DestinationAlarm(
        id: 'scheduled',
        place: stationA,
        radius: 500,
        vibration: true,
        sound: 'Bell',
        startedAt: DateTime.now(),
        repeatDays: 1,
      ),
    );
    native.entry('scheduled').addAll({
      'distanceReady': false,
      'monitoringHealthy': false,
      'monitoringMessage': 'Tracking notifications are blocked.',
    });
    final location = _VisibleLocation();
    final controller = AlarmController(
      store,
      native,
      location,
      HistoryController(store),
    );
    await controller.restore();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageProvider.overrideWith((ref) => store),
          alarmProvider.overrideWith((ref) => controller),
          locationServiceProvider.overrideWithValue(location),
        ],
        child: const MaterialApp(home: HomeScreen(initialIndex: 1)),
      ),
    );
    await tester.pump();
    expect(find.textContaining('Needs attention'), findsOneWidget);
    expect(find.textContaining('Tracking notifications are blocked.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
