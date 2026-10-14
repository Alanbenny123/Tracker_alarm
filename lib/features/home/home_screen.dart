import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../models/place.dart';
import '../../models/travel_mode.dart';
import '../../providers/app_providers.dart';
import '../map/map_view.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int index = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(locationProvider).refreshAndTrack();
    });
  }

  @override
  Widget build(BuildContext context) {
    final alarm = ref.watch(alarmProvider);
    ref.listen(alarmProvider, (previous, next) {
      if (next.active != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            context.go(next.status == 'triggered' ? '/triggered' : '/active');
          }
        });
      }
    });
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
      const _SavedTab(),
      const _HistoryTab(),
      const _SettingsTab(),
    ];
    return Scaffold(
      body: SafeArea(child: pages[index]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.bookmark_border),
            selectedIcon: Icon(Icons.bookmark),
            label: 'Saved',
          ),
          NavigationDestination(icon: Icon(Icons.history), label: 'History'),
          NavigationDestination(
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
    final active = ref.watch(alarmProvider).active;
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
        if (active != null)
          Card(
            child: ListTile(
              leading: const Icon(Icons.notifications_active),
              title: Text(active.place.name),
              subtitle: const Text('Destination alarm active'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/active'),
            ),
          ),
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

class _SavedTab extends ConsumerWidget {
  const _SavedTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final places = ref.watch(placesProvider).places;
    return Scaffold(
      appBar: AppBar(title: const Text('Saved places')),
      body:
          places.isEmpty
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
                              onPressed:
                                  () => ref
                                      .read(placesProvider)
                                      .remove(place.id!),
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
    final trips = ref.watch(historyProvider).trips;
    return Scaffold(
      appBar: AppBar(title: const Text('Trip history')),
      body:
          trips.isEmpty
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
          ListTile(
            title: const Text('Default radius'),
            subtitle: Text('${settings.defaultRadius.toInt()} m'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _pickRadius(context, settings),
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
            onTap: openAppSettings,
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
                            'Your active destination, saved places, settings, and trip history are stored on this device. The app uses location to display your position and monitor the destination alarm. Destination monitoring does not require internet after setup. The app currently has no account, analytics, or app server. Place queries may be processed by your device geocoding provider. Bus, metro, and railway stop searches send the searched area’s coordinates to the public Overpass API. Map tile requests go to OpenStreetMap and may reveal the viewed area and your IP address.',
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

  void _pickRadius(BuildContext context, SettingsController settings) =>
      showModalBottomSheet<void>(
        context: context,
        builder:
            (context) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const ListTile(title: Text('Default radius')),
                  ...[100.0, 250.0, 500.0, 1000.0, 2000.0].map(
                    (value) => ListTile(
                      title: Text('${value.toInt()} m'),
                      onTap: () {
                        settings.setRadius(value);
                        Navigator.pop(context);
                      },
                    ),
                  ),
                ],
              ),
            ),
      );
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
