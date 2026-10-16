import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../models/place.dart';
import '../../models/repeat_schedule.dart';
import '../../models/travel_mode.dart';
import '../../providers/app_providers.dart';
import '../../services/storage_service.dart';
import '../map/map_view.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key, this.initialIndex = 0});
  final int initialIndex;
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late int index;
  Timer? _statusTimer;
  @override
  void initState() {
    super.initState();
    index = widget.initialIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(locationProvider).refreshAndTrack();
      ref.read(alarmProvider).syncStatus();
    });
    _statusTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => ref.read(alarmProvider).syncStatus(),
    );
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialIndex != widget.initialIndex) {
      index = widget.initialIndex;
    }
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final alarm = ref.watch(alarmProvider);
    ref.listen(locationProvider, (_, next) {
      if (next.position != null) {
        ref.read(alarmProvider).checkVisiblePosition(next.position!);
      }
    });
    if (alarm.hasTriggered) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/triggered');
      });
    }
    if (alarm.restoring) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.notifications_active_outlined, size: 64),
              SizedBox(height: 20),
              Text('Destination Alarm'),
              SizedBox(height: 20),
              CircularProgressIndicator(),
            ],
          ),
        ),
      );
    }
    final pages = [
      const _HomeTab(),
      const _ActiveAlarmsTab(),
      const _SavedTab(),
      const _HistoryTab(),
      const _SettingsTab(),
    ];
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            if (ref.watch(storageProvider).warnings.isNotEmpty ||
                alarm.storageWarning != null)
              MaterialBanner(
                content: const Text(
                  'Some saved data was repaired. Check Settings for details.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => context.go('/?tab=settings'),
                    child: const Text('Details'),
                  ),
                ],
              ),
            if (alarm.error != null)
              MaterialBanner(
                content: Text(alarm.error!),
                actions: [
                  TextButton(
                    onPressed: alarm.syncStatus,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            Expanded(child: pages[index]),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) {
          const tabs = ['home', 'alarms', 'saved', 'history', 'settings'];
          context.go(value == 0 ? '/' : '/?tab=${tabs[value]}');
        },
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Badge.count(
              count: alarm.alarms.length,
              isLabelVisible: alarm.alarms.isNotEmpty,
              child: const Icon(Icons.alarm_outlined),
            ),
            selectedIcon: Badge.count(
              count: alarm.alarms.length,
              isLabelVisible: alarm.alarms.isNotEmpty,
              child: const Icon(Icons.alarm),
            ),
            label: 'Alarms',
            tooltip: 'See active alarms',
          ),
          const NavigationDestination(
            icon: Icon(Icons.bookmark_border),
            selectedIcon: Icon(Icons.bookmark),
            label: 'Saved',
          ),
          const NavigationDestination(
            icon: Icon(Icons.history),
            label: 'History',
          ),
          const NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

class _HomeTab extends ConsumerWidget {
  const _HomeTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = ref.watch(locationProvider);
    final activeAlarms = ref.watch(alarmProvider).alarms;
    final saved = ref.watch(placesProvider).places;
    final history = ref.watch(historyProvider).trips;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Destination Alarm',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Where are you going?',
          style: Theme.of(
            context,
          ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => context.push('/guide'),
            icon: const Icon(Icons.help_outline),
            label: const Text('Guide & tutorial'),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Choose transport',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final mode in TravelMode.values)
              ActionChip(
                avatar: Icon(switch (mode) {
                  TravelMode.bus => Icons.directions_bus,
                  TravelMode.metro => Icons.subway,
                  TravelMode.railway => Icons.train,
                  TravelMode.other => Icons.place_outlined,
                }),
                label: Text(mode.label),
                onPressed: () => context.push('/pick', extra: mode),
              ),
          ],
        ),
        const SizedBox(height: 18),
        TextField(
          readOnly: true,
          onTap: () => context.push('/pick'),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Search destination',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 18),
        if (activeAlarms.isNotEmpty) ...[
          Text(
            'Active alarms (${activeAlarms.length})',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          for (final entry in activeAlarms) _ActiveAlarmCard(entry: entry),
          const SizedBox(height: 12),
        ],
        SizedBox(
          height: 220,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              children: [
                MapView(position: location.position, interactive: false),
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: FilledButton.tonalIcon(
                    onPressed: () => context.push('/pick'),
                    icon: const Icon(Icons.map_outlined),
                    label: const Text('Open map'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (location.error != null)
          _InfoMessage(
            message: location.error!,
            action: 'Try again',
            onPressed: () => ref.read(locationProvider).refreshAndTrack(),
          )
        else
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.my_location),
            title: const Text('Current location'),
            subtitle: Text(
              location.position == null
                  ? 'Finding your location…'
                  : '${location.position!.latitude.toStringAsFixed(5)}, ${location.position!.longitude.toStringAsFixed(5)}',
            ),
          ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () => context.push('/pick'),
          icon: const Icon(Icons.add_location_alt_outlined),
          label: const Text('Set destination'),
        ),
        const SizedBox(height: 24),
        _SectionTitle('Saved places', onTap: () => context.push('/pick')),
        if (saved.isEmpty)
          const Text('Save a place from the destination setup screen.')
        else
          ...saved
              .take(3)
              .map(
                (place) => ListTile(
                  leading: const Icon(Icons.bookmark_outline),
                  title: Text(place.name),
                  subtitle: Text(
                    place.address,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => context.push('/setup', extra: place),
                ),
              ),
        const SizedBox(height: 20),
        const _SectionTitle('Recent trips'),
        if (history.isEmpty)
          const Text('Your completed and cancelled alarms appear here.')
        else
          ...history
              .take(3)
              .map(
                (trip) => ListTile(
                  leading: const Icon(Icons.place_outlined),
                  title: Text(trip.alarm.place.name),
                  subtitle: Text(
                    '${trip.status} · ${trip.endedAt.toLocal().toString().substring(0, 16)}',
                  ),
                ),
              ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {this.onTap});
  final String title;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
      ),
      if (onTap != null)
        TextButton(onPressed: onTap, child: const Text('See all')),
    ],
  );
}

class _InfoMessage extends StatelessWidget {
  const _InfoMessage({
    required this.message,
    required this.action,
    required this.onPressed,
  });
  final String message;
  final String action;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message),
          TextButton(onPressed: onPressed, child: Text(action)),
        ],
      ),
    ),
  );
}

class _ActiveAlarmsTab extends ConsumerWidget {
  const _ActiveAlarmsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alarms = ref.watch(alarmProvider).alarms;
    return Scaffold(
      appBar: AppBar(
        title: Text('Active alarms (${alarms.length})'),
        actions: [
          IconButton(
            tooltip: 'Add alarm',
            onPressed: () => context.push('/pick'),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body:
          alarms.isEmpty
              ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.alarm_off_outlined, size: 56),
                      const SizedBox(height: 16),
                      const Text('No active alarms'),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () => context.push('/pick'),
                        icon: const Icon(Icons.add),
                        label: const Text('Add alarm'),
                      ),
                    ],
                  ),
                ),
              )
              : RefreshIndicator(
                onRefresh: () => ref.read(alarmProvider).syncStatus(),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  children: [
                    for (final entry in alarms) _ActiveAlarmCard(entry: entry),
                  ],
                ),
              ),
    );
  }
}

class _ActiveAlarmCard extends ConsumerWidget {
  const _ActiveAlarmCard({required this.entry});
  final AlarmProgress entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Card(
    child: ListTile(
      leading: Icon(
        entry.status == 'snoozed' ? Icons.snooze : Icons.notifications_active,
      ),
      title: Text(entry.alarm.place.name),
      subtitle: Text(
        '${formatDistance(entry.alarm.radius)} · '
        '${entry.alarm.alertAt == null ? 'Distance only' : '${MaterialLocalizations.of(context).formatMediumDate(entry.alarm.alertAt!)} '
                '${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(entry.alarm.alertAt!))}'} · '
        '${entry.alarm.repeatDays == 0 ? '' : 'Repeats ${repeatDaysLabel(entry.alarm.repeatDays)} · '}'
        '${entry.status == 'triggered'
            ? 'Ringing'
            : entry.status == 'snoozed'
            ? 'Snoozed'
            : entry.alarm.repeatDays != 0 && !entry.distanceReady
            ? 'Scheduled'
            : entry.monitoringHealthy == false
            ? 'Needs attention'
            : 'Monitoring'}',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        ref.read(alarmProvider).select(entry.alarm.id);
        context.push(entry.status == 'triggered' ? '/triggered' : '/active');
      },
    ),
  );
}

class _SavedTab extends ConsumerWidget {
  const _SavedTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(placesProvider);
    final places = saved.places;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved places'),
        actions: [
          IconButton(
            tooltip: 'Clear saved places',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed:
                () => _confirmClearData(
                  context,
                  'Clear saved places?',
                  'This removes saved places and their local recovery copies. Active alarms are kept.',
                  saved.clear,
                ),
          ),
        ],
      ),
      body:
          saved.error != null
              ? _storageError(saved.error!, saved.reload)
              : places.isEmpty
              ? const Center(child: Text('No saved places yet.'))
              : ListView(
                children:
                    places
                        .map(
                          (place) => ListTile(
                            leading: const Icon(Icons.bookmark),
                            title: Text(place.name),
                            subtitle: Text(place.address),
                            onTap: () => context.push('/setup', extra: place),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline),
                              tooltip: 'Remove',
                              onPressed: () async {
                                try {
                                  await saved.remove(place.id!);
                                } catch (_) {
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Could not remove this place. Try again.',
                                      ),
                                    ),
                                  );
                                }
                              },
                            ),
                          ),
                        )
                        .toList(),
              ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/pick'),
        icon: const Icon(Icons.add),
        label: const Text('Add place'),
      ),
    );
  }
}

class _HistoryTab extends ConsumerWidget {
  const _HistoryTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyProvider);
    final trips = history.trips;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trip history'),
        actions: [
          IconButton(
            tooltip: 'Clear trip history',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed:
                () => _confirmClearData(
                  context,
                  'Clear trip history?',
                  'This removes trip history and its local recovery copies. Active alarms and saved places are kept.',
                  ref.read(alarmProvider).clearTripHistory,
                ),
          ),
        ],
      ),
      body:
          history.error != null
              ? _storageError(history.error!, history.reload)
              : trips.isEmpty
              ? const Center(child: Text('No trips yet.'))
              : ListView(
                children:
                    trips
                        .map(
                          (trip) => ListTile(
                            leading: Icon(
                              trip.status == 'completed'
                                  ? Icons.check_circle_outline
                                  : Icons.cancel_outlined,
                            ),
                            title: Text(trip.alarm.place.name),
                            subtitle: Text(
                              '${trip.endedAt.toLocal().toString().substring(0, 16)} · ${trip.alarm.radius.toInt()} m · ${trip.status}',
                            ),
                            onTap:
                                () => context.push(
                                  '/setup',
                                  extra: trip.alarm.place,
                                ),
                          ),
                        )
                        .toList(),
              ),
    );
  }
}

class _SettingsTab extends ConsumerWidget {
  const _SettingsTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final storage = ref.watch(storageProvider);
    final nativeWarning = ref.watch(alarmProvider).storageWarning;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const ListTile(
            title: Text(
              'LOCATION',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.location_on_outlined),
            title: const Text('Location permission'),
            subtitle: const Text('Needed to show your position'),
            onTap: () => ref.read(locationProvider).refreshAndTrack(),
          ),
          ListTile(
            leading: const Icon(Icons.location_history),
            title: const Text('Background location'),
            subtitle: const Text(
              'Needed while travelling with the screen locked',
            ),
            onTap: openAppSettings,
          ),
          ListTile(
            leading: const Icon(Icons.battery_saver_outlined),
            title: const Text('Battery restrictions'),
            subtitle: const Text(
              'Set to Unrestricted and allow Autostart if your phone offers it',
            ),
            onTap: openAppSettings,
          ),
          const Divider(),
          const ListTile(
            title: Text(
              'ALARMS',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          const ListTile(
            title: Text('Starting alert radius'),
            subtitle: Text('Bus and Metro: 500 m · Railway and Other: 1 km'),
          ),
          ListTile(
            title: const Text('Alarm sound'),
            subtitle: Text(settings.sound),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _pickSound(context, settings),
          ),
          SwitchListTile(
            title: const Text('Vibration'),
            value: settings.vibration,
            onChanged: settings.setVibration,
          ),
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('Notifications'),
            subtitle: const Text('Allow destination alerts in system settings'),
            onTap: () => ref.read(geofenceProvider).openNotificationSettings(),
          ),
          ListTile(
            title: const Text('Lock-screen alarms'),
            leading: const Icon(Icons.lock_clock_outlined),
            onTap: () => ref.read(geofenceProvider).openFullScreenSettings(),
          ),
          const Divider(),
          const ListTile(
            title: Text('MAP', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          const ListTile(
            leading: Icon(Icons.map_outlined),
            title: Text('Map type'),
            subtitle: Text('OpenStreetMap standard'),
          ),
          const Divider(),
          const ListTile(
            title: Text('APP', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          ListTile(
            leading: const Icon(Icons.menu_book_outlined),
            title: const Text('Guide & tutorial'),
            subtitle: const Text('How to set alarms and solve common problems'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/guide'),
          ),
          ListTile(
            title: const Text('Appearance'),
            subtitle: Text(settings.theme.name),
            trailing: const Icon(Icons.chevron_right),
            onTap:
                () => showModalBottomSheet<void>(
                  context: context,
                  builder:
                      (context) => SafeArea(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children:
                              ThemeModeSetting.values
                                  .map(
                                    (mode) => ListTile(
                                      title: Text(mode.name),
                                      trailing:
                                          settings.theme == mode
                                              ? const Icon(Icons.check)
                                              : null,
                                      onTap: () {
                                        settings.setTheme(mode);
                                        Navigator.pop(context);
                                      },
                                    ),
                                  )
                                  .toList(),
                        ),
                      ),
                ),
          ),
          const Divider(),
          const ListTile(
            title: Text(
              'LOCAL DATA',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              'The latest ${StorageService.historyLimit} trips are kept on this phone. Android cloud backup and device transfer are disabled.',
            ),
          ),
          for (final warning in [
            ...storage.warnings,
            if (nativeWarning != null) nativeWarning,
          ])
            ListTile(
              leading: const Icon(Icons.warning_amber_outlined),
              title: Text(warning),
            ),
          ListTile(
            title: const Text('Clear trip history'),
            leading: const Icon(Icons.delete_sweep_outlined),
            onTap:
                () => _confirmClearData(
                  context,
                  'Clear trip history?',
                  'This removes trip history and its local recovery copies. Active alarms and saved places are kept.',
                  ref.read(alarmProvider).clearTripHistory,
                ),
          ),
          ListTile(
            title: const Text('Clear saved places'),
            leading: const Icon(Icons.bookmark_remove_outlined),
            onTap:
                () => _confirmClearData(
                  context,
                  'Clear saved places?',
                  'This removes saved places and their local recovery copies. Active alarms are kept.',
                  ref.read(placesProvider).clear,
                ),
          ),
          ListTile(
            title: const Text('Delete damaged recovery copies'),
            subtitle: const Text(
              'Removes damaged data kept after a repair; current alarms, history, and saved places stay.',
            ),
            onTap:
                () => _confirmClearData(
                  context,
                  'Delete damaged recovery copies?',
                  'Damaged entries in these copies cannot be recovered after deletion.',
                  () async {
                    await storage.clearRecoveryCopies();
                    await ref.read(geofenceProvider).clearStorageRecovery();
                    await ref.read(alarmProvider).syncStatus();
                  },
                ),
          ),
          ListTile(
            title: const Text('Privacy policy'),
            subtitle: const Text('How location and search are used'),
            onTap:
                () => showDialog<void>(
                  context: context,
                  builder:
                      (context) => AlertDialog(
                        title: const Text('Privacy policy'),
                        content: const SingleChildScrollView(
                          child: Text(
                            'Your active destination, saved places, settings, and up to 100 recent trips are stored on this device. Android cloud backup and device transfer are disabled. You can delete trip history, saved places, and damaged recovery copies in Settings. The app uses location to display your position and monitor the destination alarm. Destination monitoring does not require internet after setup. The app currently has no account, analytics, or app server. Place queries may be processed by your device geocoding provider. Bus, metro, and railway stop searches send the searched area’s coordinates to the public Overpass API. Map tile requests go to OpenStreetMap and may reveal the viewed area and your IP address.',
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Close'),
                          ),
                        ],
                      ),
                ),
          ),
          const ListTile(
            title: Text('About'),
            subtitle: Text('Destination Alarm 1.0'),
          ),
        ],
      ),
    );
  }

  void _pickSound(BuildContext context, SettingsController settings) =>
      showModalBottomSheet<void>(
        context: context,
        builder:
            (context) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const ListTile(title: Text('Alarm sound')),
                  ...[
                    'Default alarm',
                    'Bell',
                    'Digital',
                    'Beep',
                    'Wake up',
                  ].map(
                    (value) => ListTile(
                      title: Text(value),
                      onTap: () {
                        settings.setSound(value);
                        Navigator.pop(context);
                      },
                    ),
                  ),
                ],
              ),
            ),
      );
}

String formatDistance(double distance) =>
    distance >= 1000
        ? '${(distance / 1000).toStringAsFixed(1)} km'
        : '${distance.round()} m';
double? distanceTo(Position? position, Place place) =>
    position == null
        ? null
        : Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          place.latitude,
          place.longitude,
        );

Widget _storageError(String message, Future<void> Function() retry) => Center(
  child: Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(message, textAlign: TextAlign.center),
        TextButton(onPressed: retry, child: const Text('Retry')),
      ],
    ),
  ),
);

Future<void> _confirmClearData(
  BuildContext context,
  String title,
  String message,
  Future<void> Function() clear,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder:
        (dialogContext) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete'),
            ),
          ],
        ),
  );
  if (confirmed != true) return;
  try {
    await clear();
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Local data deleted.')));
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not delete all data. Please retry.'),
        ),
      );
    }
  }
}
