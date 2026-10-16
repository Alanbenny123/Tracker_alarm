import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tracker_alarm/features/alarm/alarm_screens.dart';
import 'package:tracker_alarm/main.dart';
import 'package:tracker_alarm/providers/app_providers.dart';

import 'helpers/alarm_fakes.dart';

class _CountingNative extends FakeNative {
  int polls = 0;
  @override
  Future<List<Map<String, dynamic>>> multiStates() {
    polls++;
    return super.multiStates();
  }
}

void main() {
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

      // Native notification controls act while Flutter's ringing page is visible.
      await native.multiDismiss(first);
      await native.multiTrigger(second);
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(find.text('Station B'), findsOneWidget);
      expect(find.text('Station A'), findsNothing);
      await native.multiDismiss(second);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('ALARM'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      router.dispose();
    },
  );

  testWidgets(
    'polling pauses in background and syncs snooze immediately on resume',
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

Widget _app(AlarmController controller, GoRouter router) => ProviderScope(
  overrides: [alarmProvider.overrideWith((ref) => controller)],
  child: MaterialApp.router(
    theme: createAppTheme(Brightness.light),
    routerConfig: router,
  ),
);
