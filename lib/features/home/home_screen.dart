import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/place.dart';
import '../../models/repeat_schedule.dart';
import '../../models/travel_mode.dart';
import '../../providers/app_providers.dart';
import '../../widgets/scrollable_sheet.dart';
import '../../widgets/location_disclosure.dart';
import '../../widgets/dashboard_panel.dart';
import '../../services/storage_service.dart';
import '../map/map_view.dart';
import '../alarm/alarm_actions.dart';
import '../alarm/test_alarm_button.dart';

const _privacyPolicyUrl =
    'https://github.com/Alanbenny123/Tracker_alarm/blob/main/docs/PRIVACY_POLICY.md';
const _termsOfUseUrl =
    'https://github.com/Alanbenny123/Tracker_alarm/blob/main/docs/TERMS_OF_USE.md';

Future<void> _openLegalPage(BuildContext context, String url) async {
  try {
    if (await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)) {
      return;
    }
  } catch (_) {
    // Show the same recovery instruction for a missing browser or failed link.
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Could not open the page. Check your connection and try again.',
        ),
      ),
    );
  }
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key, this.initialIndex = 0});
  final int initialIndex;
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late int index;
  @override
  void initState() {
    super.initState();
    index = widget.initialIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(locationProvider).refreshAndTrack();
    });
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialIndex != widget.initialIndex) {
      index = widget.initialIndex;
    }
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

  Future<void> _refreshLocation(BuildContext context, WidgetRef ref) async {
    final permission = await Permission.locationWhenInUse.status;
    if (!context.mounted) return;
    if (!permission.isGranted) {
      if (!await showLocationDisclosure(context) || !context.mounted) return;
      final result = await Permission.locationWhenInUse.request();
      if (result.isPermanentlyDenied) await openAppSettings();
      if (!context.mounted) return;
    }
    await ref.read(locationProvider).refreshAndTrack();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = ref.watch(locationProvider);
    final activeAlarms = ref.watch(alarmProvider).alarms;
    final history = ref.watch(historyProvider).trips;
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            scheme.surfaceContainerHigh,
            scheme.surface,
            scheme.surfaceContainerLow,
          ],
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            children: [
              const Icon(Icons.radar, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Destination Alarm',
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                tooltip: 'Guide & tutorial',
                onPressed: () => context.push('/guide'),
                icon: const Icon(Icons.help_outline),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 290,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(26),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  MapView(position: location.position, interactive: false),
                  IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            scheme.surface.withValues(alpha: 0.82),
                            Colors.transparent,
                            scheme.surface.withValues(alpha: 0.95),
                          ],
                          stops: const [0, 0.43, 1],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 18,
                    right: 18,
                    top: 17,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const DashboardLabel('Explore the map'),
                        const SizedBox(height: 5),
                        Text(
                          'Where are you going?',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 16,
                    child: DashboardPanel(
                      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                      accent: scheme.primary,
                      glassOpacity: 0.58,
                      child: Row(
                        children: [
                          Icon(
                            Icons.my_location,
                            color: scheme.primary,
                            size: 19,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const DashboardLabel('Current location'),
                                Text(
                                  location.position == null
                                      ? 'Finding GPS position…'
                                      : '${location.position!.latitude.toStringAsFixed(4)}, ${location.position!.longitude.toStringAsFixed(4)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          IconButton.filledTonal(
                            tooltip: 'Open map',
                            onPressed: () => context.push('/pick'),
                            icon: const Icon(Icons.arrow_outward),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            readOnly: true,
            onTap: () => context.push('/pick'),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search destination',
              suffixIcon: Icon(Icons.arrow_forward),
            ),
          ),
          const SizedBox(height: 20),
          DashboardLabel('Travel mode', color: scheme.tertiary),
          const SizedBox(height: 4),
          Text(
            'Choose transport',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: TravelMode.values.length,
              separatorBuilder: (_, _) => const SizedBox(width: 9),
              itemBuilder: (context, index) {
                final mode = TravelMode.values[index];
                final icon = switch (mode) {
                  TravelMode.bus => Icons.directions_bus,
                  TravelMode.metro => Icons.subway,
                  TravelMode.railway => Icons.train,
                  TravelMode.other => Icons.place_outlined,
                };
                final modeColor = switch (mode) {
                  TravelMode.bus => scheme.secondary,
                  TravelMode.metro => scheme.primary,
                  TravelMode.railway => scheme.tertiary,
                  TravelMode.other => scheme.primary,
                };
                return SizedBox(
                  width: 104,
                  child: Material(
                    color: scheme.surfaceContainerLow,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
                      side: BorderSide(color: scheme.outlineVariant),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(22),
                      onTap: () => context.push('/pick', extra: mode),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Icon(icon, color: modeColor),
                            Text(
                              mode.label,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _OverviewMetric(
                  label: 'Alarms',
                  value: activeAlarms.length.toString(),
                  icon: Icons.notifications_active_outlined,
                  accent: scheme.secondary,
                  onTap: () => context.go('/?tab=alarms'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _OverviewMetric(
                  label: 'Trips',
                  value: history.length.toString(),
                  icon: Icons.route_outlined,
                  accent: scheme.tertiary,
                  onTap: () => context.go('/?tab=history'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (activeAlarms.isNotEmpty) ...[
            Text(
              'Active alarms (${activeAlarms.length})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (final entry in activeAlarms) _ActiveAlarmCard(entry: entry),
            const SizedBox(height: 12),
          ],
          if (location.error != null)
            _InfoMessage(
              message: location.error!,
              action: location.error!.contains('permission')
                  ? 'Enable location'
                  : 'Try again',
              onPressed: () => _refreshLocation(context, ref),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => context.push('/pick'),
            icon: const Icon(Icons.add_location_alt_outlined),
            label: const Text('Set destination'),
          ),
          const SizedBox(height: 24),
          const _SectionTitle('Recent trips'),
          if (history.isEmpty)
            const Text('Your completed and cancelled alarms appear here.')
          else
            ...history
                .take(3)
                .map(
                  (trip) => ListTile(
                    leading: const Icon(Icons.place_outlined),
                    title: Text(trip.alarm.displayName),
                    subtitle: Text(
                      '${trip.status} · ${trip.endedAt.toLocal().toString().substring(0, 16)}',
                    ),
                  ),
                ),
        ],
      ),
    );
  }
}

class _OverviewMetric extends StatelessWidget {
  const _OverviewMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DashboardPanel(
      padding: EdgeInsets.zero,
      accent: accent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: accent, size: 20),
              const SizedBox(height: 9),
              Text(
                value,
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              Text(label, style: Theme.of(context).textTheme.labelMedium),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);
  final String title;
  @override
  Widget build(BuildContext context) => Text(
    title,
    style: Theme.of(context).textTheme.titleLarge
        ?.copyWith(fontWeight: FontWeight.bold),
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
      body: alarms.isEmpty
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
  Widget build(BuildContext context, WidgetRef ref) {
    final needsAttention =
        entry.status != 'paused' &&
        entry.status != 'triggered' &&
        entry.monitoringHealthy == false;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DashboardPanel(
        padding: const EdgeInsets.all(4),
        accent: needsAttention
            ? Theme.of(context).colorScheme.error
            : Theme.of(context).colorScheme.primary,
        child: ListTile(
          leading: Icon(
            entry.status == 'paused'
                ? Icons.pause_circle_outline
                : entry.status == 'snoozed'
                ? Icons.snooze
                : needsAttention
                ? Icons.warning_amber_outlined
                : Icons.notifications_active,
          ),
          title: Text(entry.alarm.displayName),
          isThreeLine: needsAttention && entry.monitoringMessage != null,
          subtitle: Text(
            '${formatDistance(entry.alarm.radius)} · '
            '${entry.alarm.alertAt == null ? 'Distance only' : '${MaterialLocalizations.of(context).formatMediumDate(entry.alarm.alertAt!)} '
                      '${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(entry.alarm.alertAt!))}'} · '
            '${entry.alarm.repeatDays == 0 ? '' : 'Repeats ${repeatDaysLabel(entry.alarm.repeatDays)} · '}'
            '${entry.status == 'triggered'
                ? 'Ringing'
                : entry.status == 'paused'
                ? 'Paused'
                : entry.status == 'snoozed'
                ? 'Snoozed'
                : needsAttention
                ? 'Needs attention'
                : entry.alarm.repeatDays != 0 && !entry.distanceReady
                ? 'Scheduled'
                : 'Monitoring'}'
            '${needsAttention && entry.monitoringMessage != null ? '\n${entry.monitoringMessage}' : ''}',
            maxLines: needsAttention ? 3 : 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: AlarmActions(entry: entry),
          onTap: () {
            ref.read(alarmProvider).select(entry.alarm.id);
            context.push(
              entry.status == 'triggered' ? '/triggered' : '/active',
            );
          },
        ),
      ),
    );
  }
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
            onPressed: () => _confirmClearData(
              context,
              'Clear saved places?',
              'This removes saved places and their local recovery copies. Active alarms are kept.',
              saved.clear,
            ),
          ),
        ],
      ),
      body: saved.error != null
          ? _storageError(saved.error!, saved.reload)
          : places.isEmpty
          ? const Center(child: Text('No saved places yet.'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: places
                  .map(
                    (place) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: DashboardPanel(
                        padding: const EdgeInsets.all(4),
                        child: ListTile(
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
            onPressed: () => _confirmClearData(
              context,
              'Clear trip history?',
              'This removes trip history and its local recovery copies. Active alarms and saved places are kept.',
              ref.read(alarmProvider).clearTripHistory,
            ),
          ),
        ],
      ),
      body: history.error != null
          ? _storageError(history.error!, history.reload)
          : trips.isEmpty
          ? const Center(child: Text('No trips yet.'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: trips
                  .map(
                    (trip) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: DashboardPanel(
                        padding: const EdgeInsets.all(4),
                        child: ListTile(
                          leading: Icon(
                            trip.status == 'completed'
                                ? Icons.check_circle_outline
                                : Icons.cancel_outlined,
                          ),
                          title: Text(trip.alarm.displayName),
                          subtitle: Text(
                            '${trip.endedAt.toLocal().toString().substring(0, 16)} · ${trip.alarm.radius.toInt()} m · ${trip.status}',
                          ),
                          onTap: () =>
                              context.push('/setup', extra: trip.alarm.place),
                        ),
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          const DashboardLabel('Location'),
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
          const SizedBox(height: 20),
          const DashboardLabel('Alarms'),
          const TestAlarmButton(),
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
          const SizedBox(height: 20),
          const DashboardLabel('Map'),
          const ListTile(
            leading: Icon(Icons.map_outlined),
            title: Text('Map type'),
            subtitle: Text('Google Maps · standard 2D map'),
          ),
          const SizedBox(height: 20),
          const DashboardLabel('App'),
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
            onTap: () => showModalBottomSheet<void>(
              context: context,
              builder: (context) => ScrollableSheet(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: ThemeModeSetting.values
                      .map(
                        (mode) => ListTile(
                          title: Text(mode.name),
                          trailing: settings.theme == mode
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
          const SizedBox(height: 20),
          const DashboardLabel('Local data'),
          const ListTile(
            title: Text('Stored on this phone'),
            subtitle: Text(
              'The latest ${StorageService.historyLimit} trips are kept on this phone. Android cloud backup and device transfer are disabled.',
            ),
          ),
          for (final warning in [...storage.warnings, ?nativeWarning])
            ListTile(
              leading: const Icon(Icons.warning_amber_outlined),
              title: Text(warning),
            ),
          ListTile(
            title: const Text('Clear trip history'),
            leading: const Icon(Icons.delete_sweep_outlined),
            onTap: () => _confirmClearData(
              context,
              'Clear trip history?',
              'This removes trip history and its local recovery copies. Active alarms and saved places are kept.',
              ref.read(alarmProvider).clearTripHistory,
            ),
          ),
          ListTile(
            title: const Text('Clear saved places'),
            leading: const Icon(Icons.bookmark_remove_outlined),
            onTap: () => _confirmClearData(
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
            onTap: () => _confirmClearData(context, 'Delete damaged recovery copies?', 'Damaged entries in these copies cannot be recovered after deletion.', () async {
              await storage.clearRecoveryCopies();
              await ref.read(geofenceProvider).clearStorageRecovery();
              await ref.read(alarmProvider).syncStatus();
            }),
          ),
          ListTile(
            title: const Text('Privacy policy'),
            subtitle: const Text('How location and search are used'),
            onTap: () => showDialog<void>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                title: const Text('Privacy policy'),
                content: const SingleChildScrollView(
                  child: Text(
                    'Your active destination, saved places, settings, and up to 100 recent trips are stored on this device. Android cloud backup and device transfer are disabled. You can delete trip history, saved places, and damaged recovery copies in Settings. The app uses location to display your position and monitor the destination alarm. Destination monitoring does not require internet after setup. The app currently has no account, analytics, or app server. Google Maps receives map requests; Google Places receives place search text and the searched area’s coordinates for bus, metro, and railway stop searches. Google may process these requests under its own terms and privacy policy. Shared Google Maps links are opened through Google. If the normal short-link connection fails, Google Public DNS over HTTPS may receive the short-link hostname, not the destination or full shared URL. Map and search requests may reveal the viewed or searched area and your IP address to Google.',
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => _openLegalPage(context, _privacyPolicyUrl),
                    child: const Text('Full policy'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
          ),
          ListTile(
            title: const Text('Terms of use'),
            subtitle: const Text('Alarm limitations and Google service terms'),
            onTap: () => showDialog<void>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                title: const Text('Terms of use'),
                content: const SingleChildScrollView(
                  child: Text(
                    'Destination alarms are approximate. GPS, battery settings, or poor signal can delay or prevent an alert, especially underground. Check your route and surroundings yourself. Maps and place information are provided through Google services and follow Google’s terms and privacy policy.',
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => _openLegalPage(context, _termsOfUseUrl),
                    child: const Text('Full terms'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
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
        builder: (context) => ScrollableSheet(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(title: Text('Alarm sound')),
              ...['Default alarm', 'Bell', 'Digital', 'Beep', 'Wake up'].map(
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

String formatDistance(double distance) => distance >= 1000
    ? '${(distance / 1000).toStringAsFixed(1)} km'
    : '${distance.round()} m';
double? distanceTo(Position? position, Place place) => position == null
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
    builder: (dialogContext) => AlertDialog(
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
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Local data deleted.')));
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
