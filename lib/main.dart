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
import 'models/shared_place_search_args.dart';
import 'models/travel_mode.dart';
import 'providers/app_providers.dart';
import 'services/shared_location_service.dart';
import 'widgets/alarm_status_listener.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: TrackerAlarmApp()));
}

class TrackerAlarmApp extends ConsumerStatefulWidget {
  const TrackerAlarmApp({super.key, this.sharedLocationService});
  final SharedLocationService? sharedLocationService;
  @override
  ConsumerState<TrackerAlarmApp> createState() => _TrackerAlarmAppState();
}

class _TrackerAlarmAppState extends ConsumerState<TrackerAlarmApp>
    with WidgetsBindingObserver {
  late final _shareService =
      widget.sharedLocationService ?? SharedLocationService();
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  bool _handlingShare = false;
  bool _shareQueued = false;
  bool _resolvingSharedLocation = false;
  bool _shareCancelled = false;
  late final GoRouter router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => HomeScreen(
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
        builder: (context, state) => DestinationPickerScreen(
          key: ObjectKey(state.extra),
          initialQuery: state.extra is SharedPlaceSearchArgs
              ? (state.extra as SharedPlaceSearchArgs).query
              : state.extra is String
              ? state.extra as String
              : null,
          sharedPlace: state.extra is SharedPlaceSearchArgs,
          initialMode: state.extra is TravelMode
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
          final args = extra is AlarmSetupArgs
              ? extra
              : AlarmSetupArgs(place: extra as Place, mode: TravelMode.other);
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

  Future<void> _takeSharedLocation({String? retryText}) async {
    if (_handlingShare) {
      // A newer Android share replaces the previous destination. Do not
      // navigate to the old result while the new share waits to be read.
      _shareQueued = true;
      _shareCancelled = true;
      _shareService.cancel();
      return;
    }
    _handlingShare = true;
    String? sharedText;
    try {
      final text = retryText ?? await _shareService.takePendingShare();
      sharedText = text;
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
          router.go('/pick', extra: SharedPlaceSearchArgs(query));
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
    } on SharedLocationException catch (error) {
      if (mounted && !_shareCancelled) {
        _messengerKey.currentState?.showSnackBar(
          SnackBar(
            content: Text(error.message),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: () {
                unawaited(_takeSharedLocation(retryText: sharedText));
              },
            ),
          ),
        );
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
        builder: (context, child) => Stack(
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
  final dark = brightness == Brightness.dark;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: dark ? Colors.white : Colors.black,
        brightness: brightness,
      ).copyWith(
        primary: dark ? Colors.white : Colors.black,
        onPrimary: dark ? Colors.black : Colors.white,
        primaryContainer: dark
            ? const Color(0xFF303030)
            : const Color(0xFFE5E5E5),
        onPrimaryContainer: dark ? Colors.white : Colors.black,
        secondary: dark ? const Color(0xFFD0D0D0) : const Color(0xFF303030),
        onSecondary: dark ? Colors.black : Colors.white,
        secondaryContainer: dark
            ? const Color(0xFF292929)
            : const Color(0xFFDEDEDE),
        onSecondaryContainer: dark ? Colors.white : Colors.black,
        tertiary: dark ? const Color(0xFFE6E6E6) : const Color(0xFF424242),
        onTertiary: dark ? Colors.black : Colors.white,
        tertiaryContainer: dark
            ? const Color(0xFF303030)
            : const Color(0xFFD6D6D6),
        onTertiaryContainer: dark ? Colors.white : Colors.black,
        error: dark ? Colors.white : Colors.black,
        onError: dark ? Colors.black : Colors.white,
        errorContainer: dark
            ? const Color(0xFF373737)
            : const Color(0xFFD7D7D7),
        onErrorContainer: dark ? Colors.white : Colors.black,
        surface: dark ? const Color(0xFF050505) : const Color(0xFFFFFFFF),
        onSurface: dark ? const Color(0xFFF5F5F5) : const Color(0xFF101010),
        surfaceContainerLowest: dark ? Colors.black : Colors.white,
        surfaceContainerLow: dark
            ? const Color(0xFF101010)
            : const Color(0xFFF7F7F7),
        surfaceContainer: dark
            ? const Color(0xFF191919)
            : const Color(0xFFEFEFEF),
        surfaceContainerHigh: dark
            ? const Color(0xFF242424)
            : const Color(0xFFE6E6E6),
        surfaceContainerHighest: dark
            ? const Color(0xFF303030)
            : const Color(0xFFDADADA),
        onSurfaceVariant: dark
            ? const Color(0xFFCACACA)
            : const Color(0xFF4F4F4F),
        outline: dark ? const Color(0xFFA0A0A0) : const Color(0xFF666666),
        outlineVariant: dark
            ? const Color(0xFF505050)
            : const Color(0xFFC6C6C6),
        inverseSurface: dark ? Colors.white : Colors.black,
        onInverseSurface: dark ? Colors.black : Colors.white,
        inversePrimary: dark ? Colors.black : Colors.white,
        surfaceTint: Colors.transparent,
        shadow: Colors.black,
        scrim: Colors.black,
      );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        systemNavigationBarColor: scheme.surfaceContainerLow,
        systemNavigationBarIconBrightness: dark
            ? Brightness.light
            : Brightness.dark,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.55)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      indicatorColor: scheme.primaryContainer,
      elevation: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLow,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: scheme.surfaceContainer,
      selectedColor: scheme.primaryContainer,
      side: BorderSide(color: scheme.outlineVariant),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      labelStyle: TextStyle(color: scheme.onSurface),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: scheme.surfaceContainerHighest,
      contentTextStyle: TextStyle(color: scheme.onSurface),
      actionTextColor: scheme.primary,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    ),
  );
}
