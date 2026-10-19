import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:tracker_alarm/features/alarm/alarm_screens.dart';
import 'package:tracker_alarm/models/destination_alarm.dart';
import 'package:tracker_alarm/providers/app_providers.dart';
import 'package:tracker_alarm/services/location_service.dart';

import 'helpers/alarm_fakes.dart';

class _FixedLocation extends LocationService {
  _FixedLocation(this.fix);
  final Position fix;
  @override
  Future<Position> current() async => fix;
  @override
  Stream<Position> visibleUpdates() => const Stream.empty();
}

Future<void> _showAlarm(
  WidgetTester tester, {
  required DateTime Function() now,
  required Position fix,
  bool repeatWaiting = false,
  bool monitoringProblem = false,
}) async {
  final native = FakeNative();
  await native.multiRegister(
    DestinationAlarm(
      id: 'active',
      place: stationA,
      radius: 500,
      vibration: true,
      sound: 'Bell',
      startedAt: now(),
      repeatDays: repeatWaiting ? 1 : 0,
    ),
  );
  native.entry('active')['distanceReady'] = !repeatWaiting;
  native.entry('active')['lastGpsFixAt'] = now().millisecondsSinceEpoch;
  if (monitoringProblem) {
    native.entry('active').addAll({
      'monitoringHealthy': false,
      'monitoringMessage': 'Waiting for GPS accuracy before alerting.',
    });
  }
  final location = _FixedLocation(fix);
  final controller = AlarmController(
    MemoryStorage(),
    native,
    location,
    HistoryController(MemoryStorage()),
  );
  await controller.restore();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        alarmProvider.overrideWith((ref) => controller),
        locationProvider.overrideWith(
          (ref) => LocationController(location)..position = fix,
        ),
      ],
      child: MaterialApp(home: ActiveAlarmScreen(now: now)),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('old visible position is labeled last known and ages on screen', (
    tester,
  ) async {
    var now = DateTime(2026, 10, 19, 12);
    final fix = positionAt(10.1, 76.8);
    // Use a position timestamp aligned with the test clock.
    final timedFix = Position(
      latitude: fix.latitude,
      longitude: fix.longitude,
      timestamp: now,
      accuracy: fix.accuracy,
      altitude: fix.altitude,
      altitudeAccuracy: fix.altitudeAccuracy,
      heading: fix.heading,
      headingAccuracy: fix.headingAccuracy,
      speed: fix.speed,
      speedAccuracy: fix.speedAccuracy,
    );
    await _showAlarm(tester, now: () => now, fix: timedFix);
    expect(find.text('On the way'), findsOneWidget);
    now = now.add(const Duration(seconds: 60));
    await tester.pump(const Duration(seconds: 15));
    expect(find.text('Waiting for a fresh GPS position'), findsOneWidget);
    expect(find.textContaining('Last known:'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('repeat waiting day takes priority over the GPS zone message', (
    tester,
  ) async {
    final now = DateTime.now();
    await _showAlarm(
      tester,
      now: () => now,
      fix: positionAt(stationA.latitude, stationA.longitude),
      repeatWaiting: true,
    );
    expect(
      find.text('Waiting for the next selected repeat day'),
      findsOneWidget,
    );
    expect(find.text('Inside alert zone'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('active screen explains unreliable GPS before the route status', (
    tester,
  ) async {
    final now = DateTime.now();
    await _showAlarm(
      tester,
      now: () => now,
      fix: positionAt(10.1, 76.8),
      monitoringProblem: true,
    );
    expect(
      find.text('Waiting for GPS accuracy before alerting.'),
      findsOneWidget,
    );
    expect(find.text('On the way'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
