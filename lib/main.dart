import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';

import 'features/alarm/alarm_screens.dart';
import 'features/home/home_screen.dart';
import 'features/map/destination_picker_screen.dart';
import 'models/place.dart';
import 'providers/app_providers.dart';
import 'services/shared_location_service.dart';

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
  late final GoRouter router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
      GoRoute(
        path: '/pick',
        builder:
            (context, state) =>
                DestinationPickerScreen(initialQuery: state.extra as String?),
      ),
      GoRoute(
        path: '/setup',
        builder:
            (context, state) => AlarmSetupScreen(place: state.extra! as Place),
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _takeSharedLocation());
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
      final place = await _shareService.parse(text);
      if (!mounted) return;
      if (ref.read(alarmProvider).active != null) {
        _messengerKey.currentState?.showSnackBar(
          const SnackBar(
            content: Text(
              'Cancel the current alarm before choosing a shared destination.',
            ),
          ),
        );
      } else if (place == null) {
        final query =
            _shareService.searchQuery(text) ?? _shareService.resolvedQuery;
        if (query != null) {
          router.go('/pick', extra: query);
          _messengerKey.currentState?.showSnackBar(
            const SnackBar(
              content: Text('Choose the shared place from search results.'),
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
      if (_shareQueued) {
        _shareQueued = false;
        unawaited(_takeSharedLocation());
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SharedLocationService.channel.setMethodCallHandler(null);
    router.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(alarmProvider).syncStatus();
      ref.read(locationProvider).refreshAndTrack();
    } else if (state == AppLifecycleState.paused) {
      ref.read(locationProvider).stopVisibleUpdates();
    }
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(settingsProvider.select((s) => s.theme));
    ThemeData theme(Brightness brightness) {
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(54),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      );
    }

    return MaterialApp.router(
      scaffoldMessengerKey: _messengerKey,
      title: 'Destination Alarm',
      debugShowCheckedModeBanner: false,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      themeMode: switch (mode) {
        ThemeModeSetting.light => ThemeMode.light,
        ThemeModeSetting.dark => ThemeMode.dark,
        _ => ThemeMode.system,
      },
      routerConfig: router,
    );
  }
}
