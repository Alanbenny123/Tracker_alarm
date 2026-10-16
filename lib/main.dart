import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';

import 'features/alarm/alarm_screens.dart';
import 'features/home/home_screen.dart';
import 'features/help/guide_screen.dart';
import 'features/map/destination_picker_screen.dart';
import 'models/alarm_setup_args.dart';
import 'models/place.dart';
import 'models/travel_mode.dart';
import 'providers/app_providers.dart';
import 'services/shared_location_service.dart';
import 'widgets/alarm_status_listener.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: TrackerAlarmApp()));
}

class TrackerAlarmApp extends ConsumerStatefulWidget {
  const TrackerAlarmApp({super.key});
  @override
  ConsumerState<TrackerAlarmApp> createState() => _TrackerAlarmAppState();
}

class _TrackerAlarmAppState extends ConsumerState<TrackerAlarmApp>
    with WidgetsBindingObserver {
  final _shareService = SharedLocationService();
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  bool _handlingShare = false;
  bool _shareQueued = false;
  bool _resolvingSharedLocation = false;
  bool _shareCancelled = false;
  late final GoRouter router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder:
            (context, state) => HomeScreen(
              initialIndex: switch (state.uri.queryParameters['tab']) {
                'alarms' => 1,
                'saved' => 2,
                'history' => 3,
                'settings' => 4,
                _ => 0,
              },
            ),
      ),
      GoRoute(path: '/guide', builder: (context, state) => const GuideScreen()),
      GoRoute(
        path: '/pick',
        builder:
            (context, state) => DestinationPickerScreen(
              key: ObjectKey(state.extra),
              initialQuery:
                  state.extra is String ? state.extra as String : null,
              initialMode:
                  state.extra is TravelMode
                      ? state.extra as TravelMode
                      : state.extra is DestinationReselectArgs
                      ? (state.extra as DestinationReselectArgs).mode
                      : null,
              returnSelection: state.extra is DestinationReselectArgs,
            ),
      ),
      GoRoute(
        path: '/setup',
        builder: (context, state) {
          final extra = state.extra!;
          final args =
              extra is AlarmSetupArgs
                  ? extra
                  : AlarmSetupArgs(
                    place: extra as Place,
                    mode: TravelMode.other,
                  );
          return AlarmSetupScreen(
            key: ObjectKey(state.extra),
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
        builder: (context, state) => const ActiveAlarmScreen(),
      ),
      GoRoute(
        path: '/triggered',
        builder: (context, state) => const AlarmTriggeredScreen(),
      ),
    ],
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SharedLocationService.channel.setMethodCallHandler((call) async {
      if (call.method == 'sharedText') await _takeSharedLocation();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _takeSharedLocation();
    });
  }

  Future<void> _takeSharedLocation() async {
    if (_handlingShare) {
      _shareQueued = true;
      return;
    }
    _handlingShare = true;
    try {
      final text = await _shareService.takePendingShare();
      if (text == null || text.isEmpty) return;
      _shareCancelled = false;
      final loadingTimer = Stopwatch()..start();
      if (mounted) setState(() => _resolvingSharedLocation = true);
      final place = await _shareService.parse(text);
      const minimumVisibleTime = Duration(milliseconds: 400);
      if (loadingTimer.elapsed < minimumVisibleTime) {
        await Future<void>.delayed(minimumVisibleTime - loadingTimer.elapsed);
      }
      if (!mounted || _shareCancelled) return;
      if (place == null) {
        final query = _shareService.fallbackQuery(text);
        if (query != null) {
          router.go('/pick', extra: query);
          _messengerKey.currentState?.showSnackBar(
            const SnackBar(
              content: Text(
                'This link has no exact coordinates. Confirm the shared place in search results.',
              ),
            ),
          );
        } else {
          router.go('/pick');
          _messengerKey.currentState?.showSnackBar(
            const SnackBar(
              content: Text(
                'The shared link could not be opened. Search for the place or tap the map.',
              ),
            ),
          );
        }
      } else {
        router.go('/setup', extra: place);
      }
    } on PlatformException {
      // Sharing is available only on Android.
    } finally {
      _handlingShare = false;
      if (mounted && _resolvingSharedLocation) {
        setState(() => _resolvingSharedLocation = false);
      }
      if (_shareQueued && mounted) {
        _shareQueued = false;
        unawaited(_takeSharedLocation());
      }
    }
  }

  void _cancelSharedLocation() {
    _shareCancelled = true;
    _shareService.cancel();
    setState(() => _resolvingSharedLocation = false);
  }

  @override
  void dispose() {
    _shareService.cancel();
    WidgetsBinding.instance.removeObserver(this);
    SharedLocationService.channel.setMethodCallHandler(null);
    router.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(locationProvider).refreshAndTrack();
    } else if (state != AppLifecycleState.inactive) {
      ref.read(locationProvider).stopVisibleUpdates();
    }
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(settingsProvider.select((s) => s.theme));
    return AlarmStatusListener(
      controller: ref.read(alarmProvider),
      child: MaterialApp.router(
        scaffoldMessengerKey: _messengerKey,
        title: 'Destination Alarm',
        debugShowCheckedModeBanner: false,
        theme: createAppTheme(Brightness.light),
        darkTheme: createAppTheme(Brightness.dark),
        themeMode: switch (mode) {
          ThemeModeSetting.light => ThemeMode.light,
          ThemeModeSetting.dark => ThemeMode.dark,
          _ => ThemeMode.system,
        },
        builder:
            (context, child) => Stack(
              children: [
                child ?? const SizedBox.shrink(),
                if (_resolvingSharedLocation) ...[
                  const ModalBarrier(dismissible: false, color: Colors.black54),
                  Center(
                    child: Card(
                      margin: const EdgeInsets.all(24),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Semantics(
                          liveRegion: true,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const CircularProgressIndicator(
                                semanticsLabel: 'Opening shared location',
                              ),
                              const SizedBox(height: 20),
                              const Text(
                                'Opening Google Maps location…',
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Resolving the shared link. This can take up to 12 seconds.',
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 12),
                              TextButton(
                                onPressed: _cancelSharedLocation,
                                child: const Text('Cancel'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
        routerConfig: router,
      ),
    );
  }
}

ThemeData createAppTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF236A68),
    brightness: brightness,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: const AppBarTheme(centerTitle: false),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
  );
}
