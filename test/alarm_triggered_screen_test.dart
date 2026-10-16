import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tracker_alarm/features/alarm/alarm_screens.dart';
import 'package:tracker_alarm/main.dart';
import 'package:tracker_alarm/providers/app_providers.dart';
import 'package:tracker_alarm/widgets/alarm_status_listener.dart';

import 'helpers/alarm_fakes.dart';

class _CountingNative extends FakeNative {
  int polls = 0;
  final events = StreamController<void>.broadcast(sync: true);
  @override
  Stream<void> get statusChanges => events.stream;
  @override
  Future<void> multiSnooze(String id, int minutes) async {
    entry(id)['status'] = 'snoozed';
    entry(id)['snoozeUntil'] =
        DateTime.now().add(Duration(minutes: minutes)).millisecondsSinceEpoch;
  }

  @override
  Future<List<Map<String, dynamic>>> multiStates() {
    polls++;
    return super.multiStates();
  }
}

void main() {
  testWidgets(
    'small ringing screen and snooze sheet remain usable with large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final storage = MemoryStorage();
      final native = _CountingNative();
      final controller = AlarmController(
        storage,
        native,
        FakeLocation(),
        HistoryController(storage),
      );
      await controller.restore();
      await controller.start(stationA, 500, true, 'Bell');
      final id = controller.active!.id;
      await controller.renameAlarm(
        id,
        'A very long destination name for the morning commute',
      );
      await native.multiTrigger(id);
      await controller.syncStatus();
      final router = _router();
      await tester.pumpWidget(_app(controller, router, textScale: 2.5));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Snooze'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Snooze'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('5 minutes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('5 minutes'));
      await tester.pumpAndSettle();
      expect(native.entry(id)['status'], 'snoozed');
      expect(find.text('Active trip'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      router.dispose();
    },
  );

  testWidgets(
    'ringing screen follows notification dismissal and the next alert',
    (tester) async {
      final storage = MemoryStorage();
      final native = _CountingNative();
      final controller = AlarmController(
        storage,
        native,
        FakeLocation(),
        HistoryController(storage),
      );
      await controller.restore();
      await controller.start(stationA, 500, true, 'Bell');
      await controller.start(stationB, 500, true, 'Bell');
      final first = controller.alarms.first.alarm.id;
      final second = controller.alarms.last.alarm.id;
      await native.multiTrigger(first);
      await controller.syncStatus();
      final router = _router();
      await tester.pumpWidget(_app(controller, router));
      await tester.pump();
      expect(find.text('Station A'), findsOneWidget);
      await tester.pumpAndSettle();
      final beforeIdle = native.polls;
      await tester.pump(const Duration(seconds: 10));
      expect(native.polls, beforeIdle); // No route-level polling timer.

      // Native notification controls act while Flutter's ringing page is visible.
      await native.multiDismiss(first);
      await native.multiTrigger(second);
      native.events.add(null);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(find.text('Station B'), findsOneWidget);
      expect(find.text('Station A'), findsNothing);
      await native.multiDismiss(second);
      native.events.add(null);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('ALARM'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      router.dispose();
    },
  );

  testWidgets(
    'event subscription pauses in background and syncs snooze on resume',
    (tester) async {
      final storage = MemoryStorage();
      final native = _CountingNative();
      final controller = AlarmController(
        storage,
        native,
        FakeLocation(),
        HistoryController(storage),
      );
      await controller.restore();
      await controller.start(stationA, 500, true, 'Bell');
      final id = controller.active!.id;
      await native.multiTrigger(id);
      await controller.syncStatus();
      final router = _router();
      await tester.pumpWidget(_app(controller, router));
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      final beforePause = native.polls;
      native.entry(id)['status'] = 'snoozed';
      await tester.pump(const Duration(seconds: 10));
      expect(native.polls, beforePause);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Active trip'), findsOneWidget);
      final afterResume = native.polls;
      await tester.pump(const Duration(seconds: 10));
      expect(
        native.polls,
        afterResume,
      ); // Ringing page disposed; no leaked timer.
      await tester.pumpWidget(const SizedBox());
      router.dispose();
    },
  );
}

GoRouter _router() => GoRouter(
  initialLocation: '/triggered',
  routes: [
    GoRoute(
      path: '/triggered',
      builder: (_, _) => const AlarmTriggeredScreen(),
    ),
    GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Text('Home'))),
    GoRoute(
      path: '/active',
      builder: (_, _) => const Scaffold(body: Text('Active trip')),
    ),
  ],
);

Widget _app(
  AlarmController controller,
  GoRouter router, {
  double textScale = 1,
}) => ProviderScope(
  overrides: [alarmProvider.overrideWith((ref) => controller)],
  child: AlarmStatusListener(
    controller: controller,
    child: MaterialApp.router(
      theme: createAppTheme(Brightness.light),
      builder:
          (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
      routerConfig: router,
    ),
  ),
);
