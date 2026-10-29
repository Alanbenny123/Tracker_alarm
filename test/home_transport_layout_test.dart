import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:tracker_alarm/features/home/home_screen.dart';
import 'package:tracker_alarm/providers/app_providers.dart';

import 'helpers/alarm_fakes.dart';

class _VisibleLocation extends FakeLocation {
  @override
  Stream<Position> visibleUpdates() => const Stream.empty();
}

void main() {
  testWidgets('three transport choices fit a phone row with larger text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = MemoryStorage();
    final location = _VisibleLocation();
    final history = HistoryController(store);
    final alarms = AlarmController(store, FakeNative(), location, history);
    await alarms.restore();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageProvider.overrideWith((ref) => store),
          historyProvider.overrideWith((ref) => history),
          alarmProvider.overrideWith((ref) => alarms),
          locationServiceProvider.overrideWithValue(location),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.4)),
            child: child!,
          ),
          home: const HomeScreen(),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Offline maps'), findsOneWidget);
    expect(find.text('Railway'), findsOneWidget);
    final bus = tester.getTopLeft(find.text('Bus'));
    final metro = tester.getTopLeft(find.text('Metro'));
    final railway = tester.getTopLeft(find.text('Railway'));
    final other = tester.getTopLeft(find.text('Other'));
    expect(bus.dx, lessThan(metro.dx));
    expect(metro.dx, lessThan(railway.dx));
    expect((bus.dy - metro.dy).abs(), lessThan(50));
    expect((metro.dy - railway.dy).abs(), lessThan(50));
    expect(other.dy, greaterThan(railway.dy));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
