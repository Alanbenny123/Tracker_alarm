import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tracker_alarm/features/alarm/alarm_actions.dart';
import 'package:tracker_alarm/features/alarm/alarm_screens.dart';
import 'package:tracker_alarm/features/alarm/test_alarm_button.dart';
import 'package:tracker_alarm/main.dart';
import 'package:tracker_alarm/models/alarm_setup_args.dart';
import 'package:tracker_alarm/models/destination_alarm.dart';
import 'package:tracker_alarm/models/travel_mode.dart';
import 'package:tracker_alarm/providers/app_providers.dart';
import 'package:tracker_alarm/services/geofence_service.dart';

import 'helpers/alarm_fakes.dart';
import 'helpers/raw_memory_storage.dart';

void main() {
  testWidgets('setup warns when the GPS fix is wider than the alert radius', (
    tester,
  ) async {
    final store = RawMemoryStorage();
    final fix = Position(
      latitude: 9.9,
      longitude: 76.7,
      timestamp: DateTime.now(),
      accuracy: 800,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageProvider.overrideWith((ref) => store),
          geofenceProvider.overrideWithValue(FakeNative()),
          locationProvider.overrideWith(
            (ref) => LocationController(FakeLocation())..position = fix,
          ),
        ],
        child: const MaterialApp(
          home: AlarmSetupScreen(place: stationA, mode: TravelMode.bus),
        ),
      ),
    );
    await tester.pump();
    await _scrollTo(tester, find.text('GPS accuracy is wider than this radius'));
    expect(find.textContaining('±800 m'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('metro setup warns about underground GPS loss', (tester) async {
    final store = RawMemoryStorage();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageProvider.overrideWith((ref) => store),
          geofenceProvider.overrideWithValue(FakeNative()),
          locationServiceProvider.overrideWithValue(FakeLocation()),
        ],
        child: const MaterialApp(
          home: AlarmSetupScreen(place: stationA, mode: TravelMode.metro),
        ),
      ),
    );
    await tester.pump();
    await _scrollTo(tester, find.text('Metro GPS warning'));
    expect(find.text('Metro GPS warning'), findsOneWidget);
    expect(
      find.textContaining('weak or unavailable underground'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'repeat, sound and unit choices remain reachable on small screens',
    (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = RawMemoryStorage();
      final native = FakeNative();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storageProvider.overrideWith((ref) => store),
            geofenceProvider.overrideWithValue(native),
            locationServiceProvider.overrideWithValue(FakeLocation()),
          ],
          child: MaterialApp(
            theme: createAppTheme(Brightness.light),
            builder:
                (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: const TextScaler.linear(2)),
                  child: child!,
                ),
            home: const AlarmSetupScreen(place: stationA, mode: TravelMode.bus),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Scroll in the margin so the form moves instead of panning the map.
      Future<void> reveal(Finder target) async {
        for (var i = 0; i < 30 && target.evaluate().isEmpty; i++) {
          await tester.dragFrom(const Offset(5, 350), const Offset(0, -230));
          await tester.pumpAndSettle();
        }
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
      }

      await reveal(find.text('m'));
      await tester.tap(find.text('m'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Kilometres (km)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kilometres (km)'));
      await tester.pumpAndSettle();
      expect(find.text('km'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await reveal(find.text('Repeat'));
      await tester.tap(find.text('Repeat'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Sun'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sun'));
      await tester.ensureVisible(find.text('Save'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Sun'), findsOneWidget);
      await reveal(find.text('Alarm sound'));
      await tester.tap(find.text('Alarm sound'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Wake up'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Wake up'));
      await tester.pumpAndSettle();
      expect(find.text('Wake up'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test('alarm names survive storage and leave destination names intact', () {
    final alarm = _alarm();
    final copy = DestinationAlarm.fromJson(alarm.toJson());
    expect(copy.label, 'Commute');
    expect(copy.displayName, 'Commute');
    expect(copy.place.name, 'Station A');
    final unnamed = DestinationAlarm.fromJson({...alarm.toJson(), 'label': ''});
    expect(unnamed.displayName, 'Station A');
  });

  test(
    'paused alarms remain listed without triggering or entering history',
    () async {
      final store = RawMemoryStorage();
      final native = FakeNative();
      await native.multiRegister(_alarm());
      await native.pauseAlarm('existing', true);
      final history = HistoryController(store);
      final controller = AlarmController(
        store,
        native,
        FakeLocation(),
        history,
      );
      await controller.restore();
      expect(controller.status, 'paused');
      expect(history.trips, isEmpty);
      await controller.checkVisiblePosition(positionAt(9.9, 76.7));
      expect(native.triggeredIds, isEmpty);
      await controller.pauseAlarm('existing', false);
      await controller.checkVisiblePosition(positionAt(9.9, 76.7));
      expect(native.triggeredIds, ['existing']);
    },
  );

  test(
    'editing and naming preserve alarm identity and other destinations',
    () async {
      final store = RawMemoryStorage();
      final native = FakeNative();
      await native.multiRegister(_alarm());
      final other = DestinationAlarm(
        id: 'other',
        place: stationB,
        radius: 500,
        vibration: true,
        sound: 'Bell',
        startedAt: DateTime.now(),
      );
      await native.multiRegister(other);
      final controller = AlarmController(
        store,
        native,
        FakeLocation(),
        HistoryController(store),
      );
      await controller.restore();
      await controller.renameAlarm('existing', 'Work');
      await controller.updateAlarm(
        'existing',
        stationB,
        900,
        true,
        'Digital',
        0,
        'Work',
      );
      expect(controller.alarms, hasLength(2));
      expect(native.updatedIds, ['existing']);
      expect(native.entry('existing')['label'], 'Work');
      expect(native.entry('existing')['radius'], 900);
      expect(native.entry('other')['radius'], 500);
    },
  );

  test(
    'GPS freshness, accuracy and next repeat changes reach listeners',
    () async {
      final store = RawMemoryStorage();
      final native = FakeNative();
      await native.multiRegister(_alarm());
      final controller = AlarmController(
        store,
        native,
        FakeLocation(),
        HistoryController(store),
      );
      await controller.restore();
      final fix = DateTime(2026, 10, 16, 12, 30);
      final next = DateTime(2026, 10, 19);
      native.entry('existing').addAll({
        'lastGpsFixAt': fix.millisecondsSinceEpoch,
        'gpsAccuracy': 12.0,
        'nextRepeatAt': next.millisecondsSinceEpoch,
      });
      await controller.syncStatus();
      expect(controller.selected!.lastGpsFixAt, fix);
      expect(controller.selected!.gpsAccuracy, 12);
      expect(controller.selected!.nextRepeatAt, next);
      var changes = 0;
      controller.addListener(() => changes++);
      native.entry('existing')['gpsAccuracy'] = 8.0;
      await controller.syncStatus();
      expect(changes, 1);
    },
  );

  testWidgets(
    'duplicate reviews copied settings before creating an independent alarm',
    (tester) async {
      final store = RawMemoryStorage();
      final native = FakeNative();
      await native.multiRegister(_alarm());
      final history = HistoryController(store);
      final controller = AlarmController(
        store,
        native,
        FakeLocation(),
        history,
      );
      await controller.restore();
      final router = _router(controller);
      await tester.pumpWidget(_app(store, native, controller, history, router));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Manage Commute'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Duplicate'));
      await tester.pumpAndSettle();
      expect(find.text('Duplicate alarm'), findsOneWidget);
      await _scrollTo(tester, find.widgetWithText(TextField, 'Commute'));
      expect(find.widgetWithText(TextField, 'Commute'), findsOneWidget);
      await _scrollTo(tester, find.widgetWithText(TextField, '700'));
      expect(find.widgetWithText(TextField, '700'), findsOneWidget);
      expect(controller.alarms, hasLength(1));
      await _scrollTo(tester, find.text('Start alarm'));
      await tester.tap(find.text('Start alarm'));
      await tester.pumpAndSettle();
      expect(controller.alarms, hasLength(2));
      expect(
        controller.alarms.map((entry) => entry.alarm.id).toSet(),
        hasLength(2),
      );
      expect(
        controller.alarms.every(
          (entry) =>
              entry.alarm.radius == 700 &&
              entry.alarm.sound == 'Bell' &&
              !entry.alarm.vibration,
        ),
        isTrue,
      );
      await tester.pumpWidget(const SizedBox());
      router.dispose();
    },
  );

  testWidgets(
    'edit screen saves the existing alarm instead of registering a new one',
    (tester) async {
      final store = RawMemoryStorage();
      final native = FakeNative();
      await native.multiRegister(_alarm());
      final history = HistoryController(store);
      final controller = AlarmController(
        store,
        native,
        FakeLocation(),
        history,
      );
      await controller.restore();
      final router = _router(controller);
      await tester.pumpWidget(_app(store, native, controller, history, router));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Manage Commute'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit destination and settings'));
      await tester.pumpAndSettle();
      await _scrollTo(tester, find.widgetWithText(TextField, 'Commute'));
      await tester.enterText(
        find.widgetWithText(TextField, 'Commute'),
        'Return trip',
      );
      tester.testTextInput.hide();
      await tester.pump();
      await _scrollTo(tester, find.text('Save changes'));
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(native.updatedIds, ['existing']);
      expect(controller.alarms, hasLength(1));
      expect(controller.active!.label, 'Return trip');
      await tester.pumpWidget(const SizedBox());
      router.dispose();
    },
  );

  testWidgets(
    'test alarm uses chosen audio without needing GPS or changing destinations',
    (tester) async {
      final store = RawMemoryStorage();
      final native =
          FakeNative()
            ..requirementsState = const AlarmRequirements(
              preciseLocation: false,
              backgroundLocation: false,
              notifications: true,
              batteryOptimizationOff: false,
              fullScreenAlarms: true,
            );
      await native.multiRegister(_alarm());
      final settings =
          SettingsController(store)
            ..sound = 'Digital'
            ..vibration = false;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsProvider.overrideWith((ref) => settings),
            geofenceProvider.overrideWithValue(native),
          ],
          child: const MaterialApp(home: Scaffold(body: TestAlarmButton())),
        ),
      );
      await tester.tap(find.text('Test alarm'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start test'));
      await tester.pumpAndSettle();
      expect(native.testSounds, ['Digital']);
      expect(native.testVibrations, [false]);
      expect(native.states.single['id'], 'existing');
      await tester.tap(find.text('Stop test'));
      await tester.pumpAndSettle();
      expect(native.testStops, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

DestinationAlarm _alarm() => DestinationAlarm(
  id: 'existing',
  label: 'Commute',
  place: stationA,
  radius: 700,
  vibration: false,
  sound: 'Bell',
  startedAt: DateTime.now(),
);
GoRouter _router(AlarmController controller) => GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder:
          (_, _) => Scaffold(
            body: Consumer(
              builder:
                  (context, ref, child) =>
                      AlarmActions(entry: ref.watch(alarmProvider).selected!),
            ),
          ),
    ),
    GoRoute(
      path: '/setup',
      builder: (_, state) {
        final args = state.extra! as AlarmSetupArgs;
        return AlarmSetupScreen(
          place: args.place,
          mode: args.mode,
          initialAlarm: args.initialAlarm,
          editing: args.editing,
          duplicating: args.duplicating,
        );
      },
    ),
    GoRoute(
      path: '/active',
      builder: (_, _) => const Scaffold(body: Text('Saved view')),
    ),
  ],
);
Widget _app(
  RawMemoryStorage store,
  FakeNative native,
  AlarmController controller,
  HistoryController history,
  GoRouter router,
) => ProviderScope(
  overrides: [
    storageProvider.overrideWith((ref) => store),
    geofenceProvider.overrideWithValue(native),
    alarmProvider.overrideWith((ref) => controller),
    historyProvider.overrideWith((ref) => history),
    locationServiceProvider.overrideWithValue(FakeLocation()),
  ],
  child: MaterialApp.router(
    theme: createAppTheme(Brightness.light),
    routerConfig: router,
  ),
);

Future<void> _scrollTo(WidgetTester tester, Finder target) async {
  // Drag in the form margin, outside the interactive map's pan recognizer.
  for (var i = 0; i < 15 && target.evaluate().isEmpty; i++) {
    await tester.dragFrom(const Offset(5, 500), const Offset(0, -350));
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}
