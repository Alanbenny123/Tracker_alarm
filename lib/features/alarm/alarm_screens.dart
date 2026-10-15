import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart';

import '../../models/place.dart';
import '../../models/alarm_setup_args.dart';
import '../../models/repeat_schedule.dart';
import '../../models/travel_mode.dart';
import '../../providers/app_providers.dart';
import '../../services/geofence_service.dart';
import '../home/home_screen.dart';
import '../map/map_view.dart';

String _formatEta(Duration duration) {
  if (duration.inHours >= 1) {
    return '${duration.inHours} h ${duration.inMinutes.remainder(60)} min';
  }
  return '${duration.inMinutes < 1 ? 1 : duration.inMinutes} min';
}

String _formatDateTime(BuildContext context, DateTime value) =>
    '${MaterialLocalizations.of(context).formatMediumDate(value)} at ${TimeOfDay.fromDateTime(value).format(context)}';

Future<int?> _pickRepeatDays(BuildContext context, int currentDays) {
  var selectedDays = currentDays;
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    builder:
        (sheetContext) => StatefulBuilder(
          builder:
              (sheetContext, setSheetState) => SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Repeat on selected days',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        children: List.generate(7, (index) {
                          const labels = [
                            'Mon',
                            'Tue',
                            'Wed',
                            'Thu',
                            'Fri',
                            'Sat',
                            'Sun',
                          ];
                          final bit = 1 << index;
                          return FilterChip(
                            label: Text(labels[index]),
                            selected: (selectedDays & bit) != 0,
                            onSelected:
                                (selected) => setSheetState(() {
                                  selectedDays =
                                      selected
                                          ? selectedDays | bit
                                          : selectedDays & ~bit;
                                }),
                          );
                        }),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'The distance alarm rings only on these days. Leave all days unselected to turn repeat off.',
                      ),
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton(
                          onPressed:
                              () => Navigator.pop(sheetContext, selectedDays),
                          child: const Text('Save'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        ),
  );
}

class AlarmSetupScreen extends ConsumerStatefulWidget {
  const AlarmSetupScreen({super.key, required this.place, required this.mode});
  final Place place;
  final TravelMode mode;
  @override
  ConsumerState<AlarmSetupScreen> createState() => _AlarmSetupScreenState();
}

class _AlarmSetupScreenState extends ConsumerState<AlarmSetupScreen>
    with WidgetsBindingObserver {
  AlarmRequirements? requirements;
  bool checkingRequirements = true;
  String? requirementsError;
  int requirementsCheck = 0;
  bool batterySettingsOpened = false;
  late Place selectedPlace;
  late TravelMode selectedMode;
  late double radius;
  late final TextEditingController radiusController;
  String radiusUnit = 'm';
  String? radiusError;
  int repeatDays = 0;
  late bool vibration;
  late String sound;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final settings = ref.read(settingsProvider);
    selectedPlace = widget.place;
    selectedMode = widget.mode;
    radius = selectedMode.defaultAlertRadius;
    radiusController = TextEditingController(text: radius.toInt().toString());
    vibration = settings.vibration;
    sound = settings.sound;
    _refreshRequirements();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    radiusController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshRequirements();
  }

  Future<void> _refreshRequirements() async {
    if (!mounted) return;
    final check = ++requirementsCheck;
    setState(() => checkingRequirements = true);
    try {
      final next = await ref.read(geofenceProvider).requirements();
      if (!mounted || check != requirementsCheck) return;
      setState(() {
        requirements = next;
        requirementsError = null;
        checkingRequirements = false;
      });
    } catch (_) {
      if (!mounted || check != requirementsCheck) return;
      setState(() {
        requirements = null;
        requirementsError = 'Could not check Android permissions. Tap Recheck.';
        checkingRequirements = false;
      });
    }
  }

  Future<void> _enableLocation() async {
    if (requirements?.preciseLocation != true) {
      await Permission.locationWhenInUse.request();
      if (!mounted) return;
      final next = await ref.read(geofenceProvider).requirements();
      if (!next.preciseLocation) await openAppSettings();
    } else {
      await openAppSettings();
    }
    await _refreshRequirements();
  }

  Future<void> _enableNotifications() async {
    await Permission.notification.request();
    if (!mounted) return;
    final next = await ref.read(geofenceProvider).requirements();
    if (!next.notifications) await openAppSettings();
    await _refreshRequirements();
  }

  Future<void> _enableBattery() async {
    final geofence = ref.read(geofenceProvider);
    try {
      await geofence.openBatterySettings();
    } catch (_) {
      await geofence.openAppBatterySettings();
    }
    if (mounted) setState(() => batterySettingsOpened = true);
    await _refreshRequirements();
  }

  Future<void> _openAppBatterySettings() async {
    await ref.read(geofenceProvider).openAppBatterySettings();
    if (mounted) setState(() => batterySettingsOpened = true);
    await _refreshRequirements();
  }

  Future<void> _confirmBatterySettings() async {
    await ref.read(geofenceProvider).confirmBatterySettings();
    await _refreshRequirements();
  }

  void setRadius(double value) {
    setState(() {
      radius = value;
      radiusController.text = _radiusInput(value);
      radiusError = null;
    });
  }

  String _radiusInput(double metres) {
    if (radiusUnit == 'm') return metres.toInt().toString();
    return (metres / 1000)
        .toStringAsFixed(3)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  void setTypedRadius(String value) {
    final entered =
        radiusUnit == 'm'
            ? int.tryParse(value)?.toDouble()
            : double.tryParse(value);
    final meters =
        entered == null ? null : entered * (radiusUnit == 'km' ? 1000 : 1);
    setState(() {
      if (meters == null || meters < 100 || meters > 2000) {
        radiusError =
            radiusUnit == 'km' ? 'Enter 0.1 to 2 km' : 'Enter 100 to 2000 m';
      } else {
        radius = meters;
        radiusError = null;
      }
    });
  }

  void setRadiusUnit(String unit) {
    setState(() {
      radiusUnit = unit;
    });
    setTypedRadius(radiusController.text);
  }

  Future<void> pickRadiusUnit() async {
    final unit = await showModalBottomSheet<String>(
      context: context,
      builder:
          (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(title: Text('Distance unit')),
                ListTile(
                  title: const Text('Metres (m)'),
                  trailing: radiusUnit == 'm' ? const Icon(Icons.check) : null,
                  onTap: () => Navigator.pop(context, 'm'),
                ),
                ListTile(
                  title: const Text('Kilometres (km)'),
                  trailing: radiusUnit == 'km' ? const Icon(Icons.check) : null,
                  onTap: () => Navigator.pop(context, 'km'),
                ),
              ],
            ),
          ),
    );
    if (unit != null && mounted) setRadiusUnit(unit);
  }

  Future<void> _reselectDestination() async {
    final selection = await context.push<AlarmSetupArgs>(
      '/pick',
      extra: DestinationReselectArgs(selectedMode),
    );
    if (!mounted || selection == null) return;
    setState(() {
      selectedPlace = selection.place;
      selectedMode = selection.mode;
      radius = selectedMode.defaultAlertRadius;
      radiusController.text = _radiusInput(radius);
      radiusError = null;
    });
  }

  Future<void> _editRepeat() async {
    final days = await _pickRepeatDays(context, repeatDays);
    if (mounted && days != null) setState(() => repeatDays = days);
  }

  @override
  Widget build(BuildContext context) {
    final position = ref.watch(locationProvider).position;
    final alarm = ref.watch(alarmProvider);
    final distance = distanceTo(position, selectedPlace);
    final eta =
        distance != null && position != null && position.speed > 1
            ? Duration(seconds: (distance / position.speed).round())
            : null;
    final saved = ref
        .watch(placesProvider)
        .places
        .any(
          (p) =>
              p.latitude == selectedPlace.latitude &&
              p.longitude == selectedPlace.longitude,
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Destination alarm')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SizedBox(
            height: 230,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: MapView(
                position: position,
                destination: selectedPlace,
                radius: radius,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            selectedPlace.name,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          Text(selectedPlace.address),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _reselectDestination,
              icon: const Icon(Icons.edit_location_alt_outlined),
              label: const Text('Reselect destination'),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            distance == null
                ? 'Finding current distance…'
                : '${formatDistance(distance)} away',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (eta != null)
            Text('Estimated travel time at current speed: ${_formatEta(eta)}'),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed:
                  saved
                      ? null
                      : () async {
                        final name = await _askName(
                          context,
                          selectedPlace.name,
                        );
                        if (name != null && name.trim().isNotEmpty) {
                          await ref
                              .read(placesProvider)
                              .add(selectedPlace, name);
                        }
                      },
              icon: Icon(saved ? Icons.bookmark : Icons.bookmark_add_outlined),
              label: Text(saved ? 'Saved place' : 'Save this place'),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Alert me when I am nearby',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children:
                [100.0, 250.0, 500.0, 1000.0, 2000.0]
                    .map(
                      (value) => ChoiceChip(
                        label: Text(formatDistance(value)),
                        selected: radius == value,
                        onSelected: (_) => setRadius(value),
                      ),
                    )
                    .toList(),
          ),
          Slider(
            min: 100,
            max: 2000,
            value: radius.clamp(100, 2000),
            label: formatDistance(radius),
            onChanged: (value) => setRadius(value.roundToDouble()),
          ),
          TextField(
            controller: radiusController,
            keyboardType: TextInputType.numberWithOptions(
              decimal: radiusUnit == 'km',
            ),
            inputFormatters: [
              TextInputFormatter.withFunction((oldValue, newValue) {
                final pattern =
                    radiusUnit == 'km'
                        ? RegExp(r'^\d{0,1}(\.\d{0,3})?$')
                        : RegExp(r'^\d{0,4}$');
                return pattern.hasMatch(newValue.text) ? newValue : oldValue;
              }),
            ],
            decoration: InputDecoration(
              labelText: 'Enter alert distance manually',
              suffixIcon: TextButton(
                onPressed: pickRadiusUnit,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(radiusUnit),
                    const Icon(Icons.arrow_drop_down),
                  ],
                ),
              ),
              helperText: radiusUnit == 'km' ? '0.1–2 km' : '100–2000 m',
              errorText: radiusError,
              border: const OutlineInputBorder(),
            ),
            onChanged: setTypedRadius,
          ),
          const SizedBox(height: 8),
          const Text('GPS accuracy can affect when the alarm rings.'),
          const SizedBox(height: 8),
          Center(child: Text('${radius.toInt()} m radius')),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.repeat),
            title: const Text('Repeat'),
            subtitle: Text(
              repeatDays == 0 ? 'Off' : repeatDaysLabel(repeatDays),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _editRepeat,
          ),
          const SizedBox(height: 10),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.music_note_outlined),
            title: const Text('Alarm sound'),
            subtitle: Text(sound),
            trailing: const Icon(Icons.chevron_right),
            onTap:
                () => showModalBottomSheet<void>(
                  context: context,
                  builder:
                      (context) => SafeArea(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children:
                              [
                                    'Default alarm',
                                    'Bell',
                                    'Digital',
                                    'Beep',
                                    'Wake up',
                                  ]
                                  .map(
                                    (value) => ListTile(
                                      title: Text(value),
                                      onTap: () {
                                        setState(() => sound = value);
                                        Navigator.pop(context);
                                      },
                                    ),
                                  )
                                  .toList(),
                        ),
                      ),
                ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Vibration'),
            value: vibration,
            onChanged: (value) => setState(() => vibration = value),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Text(
                      'Required for an alarm',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                      'Complete these Android settings so alerts can work with the screen locked.',
                    ),
                  ),
                  if (checkingRequirements)
                    const Center(child: CircularProgressIndicator())
                  else if (requirements == null)
                    ListTile(
                      title: Text(
                        requirementsError ?? 'Could not check permissions',
                      ),
                      trailing: TextButton(
                        onPressed: _refreshRequirements,
                        child: const Text('Recheck'),
                      ),
                    )
                  else ...[
                    _requirementTile(
                      title: 'Precise location',
                      subtitle: 'Allow precise location while using the app',
                      done: requirements!.preciseLocation,
                      onTap: _enableLocation,
                    ),
                    _requirementTile(
                      title: 'Location: Allow all the time',
                      subtitle:
                          'Needed to track your destination in the background',
                      done: requirements!.backgroundLocation,
                      onTap: _enableLocation,
                    ),
                    _requirementTile(
                      title: 'Notifications',
                      subtitle: 'Allow alarm notifications',
                      done: requirements!.notifications,
                      onTap: _enableNotifications,
                    ),
                    _requirementTile(
                      title: 'Battery: Unrestricted',
                      subtitle:
                          requirements!.batteryManuallyConfirmed &&
                                  !requirements!.batteryOptimizationOff
                              ? 'Confirmed by you for this phone'
                              : 'Choose Unrestricted / No restrictions',
                      done: requirements!.batteryReady,
                      onTap: _enableBattery,
                    ),
                    if (!requirements!.batteryReady)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: TextButton(
                          onPressed: _openAppBatterySettings,
                          child: const Text('Open this app’s battery settings'),
                        ),
                      ),
                    if (!requirements!.batteryReady && batterySettingsOpened)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: OutlinedButton.icon(
                          onPressed: _confirmBatterySettings,
                          icon: const Icon(Icons.check),
                          label: const Text(
                            'I set Unrestricted / No restrictions',
                          ),
                        ),
                      ),
                    if (!requirements!.batteryReady && batterySettingsOpened)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Text(
                          'Use this confirmation only if your phone does not report its battery setting to Android.',
                        ),
                      ),
                  ],
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Text(
                      'Also set this app to No restrictions and enable Autostart if your phone offers those settings.',
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed:
                          checkingRequirements ? null : _refreshRequirements,
                      child: const Text('Recheck'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (alarm.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    alarm.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: openAppSettings,
                    icon: const Icon(Icons.settings_outlined),
                    label: const Text('Open app settings'),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          if (alarm.alarms.length >= 10)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text('Maximum 10 active alarms. End one to add another.'),
            ),
          FilledButton.icon(
            onPressed:
                alarm.busy ||
                        alarm.alarms.length >= 10 ||
                        radiusError != null ||
                        checkingRequirements ||
                        requirements?.ready != true
                    ? null
                    : () async {
                      try {
                        await ref
                            .read(alarmProvider)
                            .start(
                              selectedPlace,
                              radius,
                              vibration,
                              sound,
                              null,
                              repeatDays,
                            );
                        if (context.mounted) {
                          context.go(
                            ref.read(alarmProvider).status == 'triggered'
                                ? '/triggered'
                                : '/active',
                          );
                        }
                      } catch (_) {
                        await _refreshRequirements();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Could not start alarm. Check the message above and your permissions.',
                              ),
                            ),
                          );
                        }
                      }
                    },
            icon: const Icon(Icons.notifications_active_outlined),
            label: Text(
              alarm.busy
                  ? 'Starting…'
                  : alarm.alarms.length >= 10
                  ? 'Maximum 10 alarms active'
                  : requirements?.ready == true
                  ? 'Start alarm'
                  : 'Complete required settings to start',
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _requirementTile({
    required String title,
    required String subtitle,
    required bool done,
    required Future<void> Function() onTap,
  }) => ListTile(
    leading: Icon(
      done ? Icons.check_circle : Icons.radio_button_unchecked,
      color: done ? Colors.green : null,
    ),
    title: Text(title),
    subtitle: Text(subtitle),
    trailing: done ? null : const Icon(Icons.chevron_right),
    onTap: done ? null : onTap,
  );

  Future<String?> _askName(BuildContext context, String current) async {
    final controller = TextEditingController(text: current);
    final result = await showDialog<String>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Save place'),
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Place name'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, controller.text),
                child: const Text('Save'),
              ),
            ],
          ),
    );
    controller.dispose();
    return result;
  }
}

class ActiveAlarmScreen extends ConsumerStatefulWidget {
  const ActiveAlarmScreen({super.key});
  @override
  ConsumerState<ActiveAlarmScreen> createState() => _ActiveAlarmScreenState();
}

class _ActiveAlarmScreenState extends ConsumerState<ActiveAlarmScreen>
    with WidgetsBindingObserver {
  Timer? timer;
  bool showMap = false;

  Future<void> _editRepeat(String id, int currentDays) async {
    final days = await _pickRepeatDays(context, currentDays);
    if (days == null || days == currentDays || !mounted) return;
    try {
      await ref.read(alarmProvider).setRepeatDays(id, days);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not update repeat days. Try again.'),
          ),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(locationProvider).refreshAndTrack();
      ref.read(alarmProvider).syncStatus();
    });
    _startStatusTimer();
  }

  void _startStatusTimer() {
    timer ??= Timer.periodic(
      const Duration(seconds: 5),
      (_) => ref.read(alarmProvider).syncStatus(),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(alarmProvider).syncStatus();
      _startStatusTimer();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      timer?.cancel();
      timer = null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(locationProvider, (_, next) {
      final position = next.position;
      if (position != null) {
        ref.read(alarmProvider).checkVisiblePosition(position);
      }
    });
    final alarmState = ref.watch(alarmProvider);
    final alarm = alarmState.active;
    if (alarm == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Alarm')),
        body: Center(
          child: FilledButton(
            onPressed: () => context.go('/'),
            child: const Text('Go home'),
          ),
        ),
      );
    }
    if (alarmState.status == 'triggered') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/triggered');
      });
    }
    final position = ref.watch(locationProvider).position;
    final distance = distanceTo(position, alarm.place);
    final eta =
        distance != null && position != null && position.speed > 1
            ? Duration(seconds: (distance / position.speed).round())
            : null;
    final accuracy = position?.accuracy;
    final quality =
        accuracy == null
            ? 'Waiting for GPS'
            : accuracy <= 20
            ? 'Excellent'
            : accuracy <= 80
            ? 'Good'
            : 'Weak';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Alarm active'),
        actions: [
          IconButton(
            tooltip: 'All alarms',
            onPressed: () => context.go('/'),
            icon: const Icon(Icons.list),
          ),
          IconButton(
            tooltip: 'Add alarm',
            onPressed: () => context.push('/pick'),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: Icon(
              Icons.location_pin,
              color: Theme.of(context).colorScheme.primary,
              size: 60,
            ),
          ),
          Center(
            child: Text(
              alarm.place.name,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 18),
          Center(
            child: Text(
              distance == null ? '—' : formatDistance(distance),
              style: Theme.of(
                context,
              ).textTheme.displayMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          const Center(child: Text('REMAINING')),
          if (eta != null)
            Center(child: Text('About ${_formatEta(eta)} at current speed')),
          Center(
            child: Text(
              distance == null
                  ? 'Waiting for GPS'
                  : distance <= alarm.radius
                  ? 'Inside alert zone'
                  : distance <= 1000
                  ? 'Approaching destination'
                  : 'On the way',
            ),
          ),
          const SizedBox(height: 20),
          if (showMap)
            SizedBox(
              height: 330,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: MapView(
                  position: position,
                  destination: alarm.place,
                  radius: alarm.radius,
                ),
              ),
            )
          else
            Card(
              child: ListTile(
                leading: const Icon(Icons.offline_bolt_outlined),
                title: const Text('Offline monitoring'),
                subtitle: Text(
                  'GPS checks your distance to ${alarm.place.latitude.toStringAsFixed(5)}, '
                  '${alarm.place.longitude.toStringAsFixed(5)}. The alarm does not need map tiles.',
                ),
              ),
            ),
          TextButton.icon(
            onPressed: () => setState(() => showMap = !showMap),
            icon: Icon(showMap ? Icons.expand_less : Icons.map_outlined),
            label: Text(showMap ? 'Hide map' : 'Show online map'),
          ),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.gps_fixed),
                  title: const Text('GPS status'),
                  subtitle: Text(quality),
                ),
                ListTile(
                  leading: const Icon(Icons.radio_button_checked),
                  title: const Text('Alert radius'),
                  subtitle: Text(
                    '${formatDistance(alarm.radius)} · ${alarmState.distanceFired
                        ? 'Rang'
                        : alarmState.selected?.distanceReady == false
                        ? 'Waiting for repeat day'
                        : 'Waiting'}',
                  ),
                ),
                if (alarm.alertAt != null)
                  ListTile(
                    leading: const Icon(Icons.schedule),
                    title: const Text('Time alarm'),
                    subtitle: Text(
                      '${_formatDateTime(context, alarm.alertAt!)} · ${alarmState.timeFired ? 'Rang' : 'Waiting'}',
                    ),
                  ),
                ListTile(
                  leading: const Icon(Icons.shield_outlined),
                  title: const Text('Background monitoring'),
                  subtitle: Text(
                    alarmState.status == 'snoozed'
                        ? 'Snoozed'
                        : alarm.repeatDays != 0 &&
                            alarmState.selected?.distanceReady == false
                        ? 'Next selected day scheduled; GPS checks less often until then'
                        : 'GPS monitoring active; geofence backup where available',
                  ),
                ),
              ],
            ),
          ),
          if (alarmState.error != null)
            Text(
              alarmState.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const SizedBox(height: 20),
          Card(
            child: ListTile(
              leading: const Icon(Icons.repeat),
              title: const Text('Repeat alarm'),
              subtitle: Text(
                alarm.repeatDays == 0
                    ? 'Off · choose days'
                    : repeatDaysLabel(alarm.repeatDays),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap:
                  alarmState.busy || alarmState.selected?.status != 'active'
                      ? null
                      : () => _editRepeat(alarm.id, alarm.repeatDays),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: () => context.push('/setup', extra: alarm.place),
            icon: const Icon(Icons.add_alert_outlined),
            label: const Text('Add another alarm for this destination'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed:
                alarmState.busy
                    ? null
                    : () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder:
                            (context) => AlertDialog(
                              title: Text(
                                alarm.repeatDays == 0
                                    ? 'End this trip?'
                                    : 'Stop this repeating alarm?',
                              ),
                              content: Text(alarm.place.name),
                              actions: [
                                TextButton(
                                  onPressed:
                                      () => Navigator.pop(context, false),
                                  child: const Text('No'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: Text(
                                    alarm.repeatDays == 0
                                        ? 'End trip'
                                        : 'Stop alarm',
                                  ),
                                ),
                              ],
                            ),
                      );
                      if (confirmed == true) {
                        try {
                          await ref.read(alarmProvider).cancel(alarm.id);
                          if (context.mounted) {
                            final current = ref.read(alarmProvider);
                            context.go(
                              current.hasTriggered
                                  ? '/triggered'
                                  : current.active == null
                                  ? '/'
                                  : '/active',
                            );
                          }
                        } catch (_) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Could not cancel alarm. Try again.',
                                ),
                              ),
                            );
                          }
                        }
                      }
                    },
            icon: const Icon(Icons.cancel_outlined),
            label: Text(
              alarm.repeatDays == 0 ? 'End trip' : 'Stop repeating alarm',
            ),
          ),
        ],
      ),
    );
  }
}

class AlarmTriggeredScreen extends ConsumerWidget {
  const AlarmTriggeredScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alarmState = ref.watch(alarmProvider);
    final alarm = alarmState.active;
    final waitingAlerts =
        alarmState.alarms
            .where(
              (entry) =>
                  entry.status == 'triggered' && entry.alarm.id != alarm?.id,
            )
            .toList()
          ..sort((a, b) => a.triggeredAt.compareTo(b.triggeredAt));
    if (alarm == null) {
      return Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: () => context.go('/'),
            child: const Text('Go home'),
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              Icon(
                Icons.notifications_active,
                size: 96,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 28),
              Text(
                'ALARM',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                alarm.place.name,
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(switch (alarmState.triggerReason) {
                'time' => 'The selected time has been reached.',
                'both' =>
                  'The selected time and distance have both been reached.',
                _ => 'You have reached the selected distance.',
              }, textAlign: TextAlign.center),
              if (waitingAlerts.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Next: ${waitingAlerts.first.alarm.place.name}'
                  '${waitingAlerts.length > 1 ? ' (+${waitingAlerts.length - 1} more)' : ''}',
                  textAlign: TextAlign.center,
                ),
              ],
              const Spacer(),
              FilledButton.icon(
                onPressed:
                    alarmState.busy
                        ? null
                        : () async {
                          try {
                            await ref
                                .read(alarmProvider)
                                .dismissCurrent(alarm.id);
                            if (context.mounted) {
                              final current = ref.read(alarmProvider);
                              context.go(
                                current.hasTriggered
                                    ? '/triggered'
                                    : current.active == null
                                    ? '/'
                                    : '/active',
                              );
                            }
                          } catch (_) {}
                        },
                icon: const Icon(Icons.stop),
                label: const Text('Stop this alert'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed:
                    () => showModalBottomSheet<void>(
                      context: context,
                      builder:
                          (sheetContext) => SafeArea(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const ListTile(title: Text('Snooze for')),
                                ...[1, 2, 5].map(
                                  (minutes) => ListTile(
                                    title: Text(
                                      '$minutes ${minutes == 1 ? 'minute' : 'minutes'}',
                                    ),
                                    onTap: () async {
                                      Navigator.pop(sheetContext);
                                      try {
                                        await ref
                                            .read(alarmProvider)
                                            .snooze(minutes, alarm.id);
                                        if (context.mounted) {
                                          context.go(
                                            ref.read(alarmProvider).hasTriggered
                                                ? '/triggered'
                                                : '/active',
                                          );
                                        }
                                      } catch (_) {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Could not snooze alarm.',
                                              ),
                                            ),
                                          );
                                        }
                                      }
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                    ),
                icon: const Icon(Icons.snooze),
                label: const Text('Snooze'),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed:
                    alarmState.busy
                        ? null
                        : () async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder:
                                (dialogContext) => AlertDialog(
                                  title: Text(
                                    alarm.repeatDays == 0
                                        ? 'End trip?'
                                        : 'Stop repeating alarm?',
                                  ),
                                  content: Text(
                                    alarm.repeatDays == 0
                                        ? 'This cancels both the time and distance alerts.'
                                        : 'This cancels future repeats and the current alert.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed:
                                          () => Navigator.pop(
                                            dialogContext,
                                            false,
                                          ),
                                      child: const Text('Keep trip'),
                                    ),
                                    FilledButton(
                                      onPressed:
                                          () => Navigator.pop(
                                            dialogContext,
                                            true,
                                          ),
                                      child: const Text('End trip'),
                                    ),
                                  ],
                                ),
                          );
                          if (confirmed != true) return;
                          try {
                            await ref.read(alarmProvider).stop(alarm.id);
                            if (context.mounted) {
                              final current = ref.read(alarmProvider);
                              context.go(
                                current.hasTriggered
                                    ? '/triggered'
                                    : current.active == null
                                    ? '/'
                                    : '/active',
                              );
                            }
                          } catch (_) {}
                        },
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('End trip'),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
