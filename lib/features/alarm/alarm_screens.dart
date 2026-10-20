import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart';

import '../../models/place.dart';
import '../../models/alarm_setup_args.dart';
import '../../models/destination_alarm.dart';
import '../../models/repeat_schedule.dart';
import '../../models/travel_mode.dart';
import '../../providers/app_providers.dart';
import '../../widgets/scrollable_sheet.dart';
import '../../widgets/location_disclosure.dart';
import '../../widgets/dashboard_panel.dart';
import '../../services/geofence_service.dart';
import '../home/home_screen.dart';
import '../map/map_view.dart';
import 'alarm_actions.dart';

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
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, setSheetState) => ScrollableSheet(
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
                    onSelected: (selected) => setSheetState(() {
                      selectedDays = selected
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
                  onPressed: () => Navigator.pop(sheetContext, selectedDays),
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
  const AlarmSetupScreen({
    super.key,
    required this.place,
    required this.mode,
    this.initialAlarm,
    this.editing = false,
    this.duplicating = false,
  });
  final Place place;
  final TravelMode mode;
  final DestinationAlarm? initialAlarm;
  final bool editing;
  final bool duplicating;
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
  late final TextEditingController labelController;
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
    radius = widget.initialAlarm?.radius ?? selectedMode.defaultAlertRadius;
    repeatDays = widget.initialAlarm?.repeatDays ?? 0;
    labelController = TextEditingController(
      text: widget.initialAlarm?.label ?? '',
    );
    radiusController = TextEditingController(text: radius.toInt().toString());
    vibration = widget.initialAlarm?.vibration ?? settings.vibration;
    sound = widget.initialAlarm?.sound ?? settings.sound;
    _refreshRequirements();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    radiusController.dispose();
    labelController.dispose();
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
    if (!await showLocationDisclosure(context) || !mounted) return;
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
    if (!next.notifications) {
      await ref.read(geofenceProvider).openNotificationSettings();
    }
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
    try {
      await ref.read(geofenceProvider).confirmBatterySettings();
    } catch (_) {
      if (!mounted) return;
      setState(() => batterySettingsOpened = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Open battery settings again, then confirm No restrictions.',
          ),
        ),
      );
    }
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
    final entered = radiusUnit == 'm'
        ? int.tryParse(value)?.toDouble()
        : double.tryParse(value);
    final meters = entered == null
        ? null
        : entered * (radiusUnit == 'km' ? 1000 : 1);
    setState(() {
      if (meters == null || meters < 100 || meters > 2000) {
        radiusError = radiusUnit == 'km'
            ? 'Enter 0.1 to 2 km'
            : 'Enter 100 to 2000 m';
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
      builder: (context) => ScrollableSheet(
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
    final eta = distance != null && position != null && position.speed > 1
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
      appBar: AppBar(
        title: Text(
          widget.editing
              ? 'Edit alarm'
              : widget.duplicating
              ? 'Duplicate alarm'
              : 'Destination alarm',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const DashboardLabel('Your destination'),
          const SizedBox(height: 10),
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
          const SizedBox(height: 12),
          DashboardPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        selectedPlace.name,
                        style: Theme.of(context).textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    Icon(
                      Icons.place,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(selectedPlace.address),
                const SizedBox(height: 12),
                Text(
                  distance == null
                      ? 'Finding straight-line distance…'
                      : '${formatDistance(distance)} away in a straight line',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Text(
                  'Distance is measured directly to the destination, not along roads or tracks.',
                ),
                if (eta != null)
                  Text(
                    'Straight-line estimate at current speed: ${_formatEta(eta)}',
                  ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: _reselectDestination,
                      icon: const Icon(Icons.edit_location_alt_outlined),
                      label: const Text('Reselect destination'),
                    ),
                    TextButton.icon(
                      onPressed: saved
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
                      icon: Icon(
                        saved ? Icons.bookmark : Icons.bookmark_add_outlined,
                      ),
                      label: Text(saved ? 'Saved place' : 'Save this place'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: labelController,
            maxLength: 80,
            decoration: const InputDecoration(
              labelText: 'Alarm name (optional)',
              hintText: 'For example, Morning commute',
            ),
          ),
          const DashboardLabel('Alert settings'),
          const SizedBox(height: 8),
          DashboardPanel(
            accent: Theme.of(context).colorScheme.primary,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Alert me when I am nearby',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [100.0, 250.0, 500.0, 1000.0, 2000.0]
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
                      final pattern = radiusUnit == 'km'
                          ? RegExp(r'^\d{0,1}(\.\d{0,3})?$')
                          : RegExp(r'^\d{0,4}$');
                      return pattern.hasMatch(newValue.text)
                          ? newValue
                          : oldValue;
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
                if (position != null &&
                    position.accuracy.isFinite &&
                    position.accuracy > radius)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.gps_not_fixed),
                      title: const Text(
                        'GPS accuracy is wider than this radius',
                      ),
                      subtitle: Text(
                        'The last GPS fix was accurate to about ±${position.accuracy.round()} m '
                        'for a ${radius.round()} m alert radius. Consider a larger '
                        'radius if you need an earlier warning.',
                      ),
                    ),
                  ),
                if (selectedMode == TravelMode.metro)
                  const Card(
                    child: ListTile(
                      leading: Icon(Icons.gps_off_outlined),
                      title: Text('Metro GPS warning'),
                      subtitle: Text(
                        'GPS can be weak or unavailable underground. Choose a '
                        'station and an alert distance before entering a tunnel; '
                        'the alarm may ring late if there is no GPS fix.',
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Center(child: Text('${radius.toInt()} m radius')),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const DashboardLabel('Schedule & sound'),
          const SizedBox(height: 8),
          DashboardPanel(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Column(
              children: [
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
                  onTap: () => showModalBottomSheet<void>(
                    context: context,
                    builder: (context) => ScrollableSheet(
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
              ],
            ),
          ),
          const SizedBox(height: 18),
          const DashboardLabel('Before you start'),
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
                      subtitle: 'Needed to track your destination when the app is closed or not in use',
                      done: requirements!.backgroundLocation,
                      onTap: _enableLocation,
                    ),
                    _requirementTile(
                      title: 'Notifications',
                      subtitle:
                          'Allow notifications and high-priority alarm alerts',
                      done: requirements!.notifications,
                      onTap: _enableNotifications,
                    ),
                    _requirementTile(
                      title: 'Alarms & reminders',
                      subtitle: 'Allow reliable snooze and scheduled alarms',
                      done: requirements!.exactAlarms,
                      onTap: () async {
                        try {
                          await ref
                              .read(geofenceProvider)
                              .openExactAlarmSettings();
                        } catch (_) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Open Android settings → Apps → Special app access → Alarms & reminders.',
                              ),
                            ),
                          );
                        }
                        await _refreshRequirements();
                      },
                    ),
                    _requirementTile(
                      title: 'Lock-screen alarms',
                      subtitle: 'Allow alarms to open over the lock screen',
                      done: requirements!.fullScreenAlarms,
                      onTap: () async {
                        try {
                          await ref
                              .read(geofenceProvider)
                              .openFullScreenSettings();
                        } catch (_) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Open Android settings → Special app access → Full-screen notifications.',
                              ),
                            ),
                          );
                        }
                        await _refreshRequirements();
                      },
                    ),
                    for (final warning in requirements!.warnings)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(warning),
                      ),
                    _requirementTile(
                      title: 'Battery: Unrestricted',
                      subtitle:
                          requirements!.batteryManuallyConfirmed &&
                              !requirements!.batteryOptimizationOff
                          ? 'Confirmed for this foreground session (up to 15 minutes)'
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
                          'Use this confirmation only if your phone does not report its battery setting to Android. It expires after leaving the app or after 15 minutes.',
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
                      onPressed: checkingRequirements
                          ? null
                          : _refreshRequirements,
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
          if ((alarm.alarms.length >= 10 && !widget.editing))
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text('Maximum 10 active alarms. End one to add another.'),
            ),
          FilledButton.icon(
            onPressed:
                alarm.busy ||
                    (alarm.alarms.length >= 10 && !widget.editing) ||
                    radiusError != null ||
                    checkingRequirements ||
                    (requirements?.ready != true &&
                        !(widget.editing &&
                            alarm.alarms.any(
                              (entry) =>
                                  entry.alarm.id == widget.initialAlarm?.id &&
                                  entry.status == 'paused',
                            )))
                ? null
                : () async {
                    try {
                      final controller = ref.read(alarmProvider);
                      if (widget.editing) {
                        await controller.updateAlarm(
                          widget.initialAlarm!.id,
                          selectedPlace,
                          radius,
                          vibration,
                          sound,
                          repeatDays,
                          labelController.text,
                        );
                      } else {
                        // Duplicating copies the displayed distance/repeat/sound settings;
                        // review and Start create a new, independent alarm ID.
                        await controller.start(
                          selectedPlace,
                          radius,
                          vibration,
                          sound,
                          null,
                          repeatDays,
                          0,
                          null,
                          labelController.text,
                        );
                      }
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
                  ? (widget.editing ? 'Saving…' : 'Starting…')
                  : (alarm.alarms.length >= 10 && !widget.editing)
                  ? 'Maximum 10 alarms active'
                  : requirements?.ready == true ||
                        (widget.editing &&
                            alarm.alarms.any(
                              (entry) =>
                                  entry.alarm.id == widget.initialAlarm?.id &&
                                  entry.status == 'paused',
                            ))
                  ? (widget.editing ? 'Save changes' : 'Start alarm')
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
      color: done ? Theme.of(context).colorScheme.primary : null,
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
      builder: (context) => AlertDialog(
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
  const ActiveAlarmScreen({super.key, this.now});
  final DateTime Function()? now;
  @override
  ConsumerState<ActiveAlarmScreen> createState() => _ActiveAlarmScreenState();
}

class _ActiveAlarmScreenState extends ConsumerState<ActiveAlarmScreen> {
  bool showMap = false;
  Timer? _displayRefresh;

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
    _displayRefresh = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(locationProvider).refreshAndTrack();
    });
  }

  @override
  void dispose() {
    _displayRefresh?.cancel();
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
    final now = widget.now?.call() ?? DateTime.now();
    final freshPosition =
        position != null &&
        !position.timestamp.isBefore(
          now.subtract(const Duration(seconds: 45)),
        ) &&
        !position.timestamp.isAfter(now.add(const Duration(seconds: 10)));
    final distance = freshPosition ? distanceTo(position, alarm.place) : null;
    final lastKnownDistance = freshPosition
        ? null
        : distanceTo(position, alarm.place);
    final eta = distance != null && position != null && position.speed > 1
        ? Duration(seconds: (distance / position.speed).round())
        : null;
    final accuracy = freshPosition ? position.accuracy : null;
    final quality = accuracy == null
        ? 'Waiting for GPS'
        : accuracy <= 20
        ? 'Excellent'
        : accuracy <= 80
        ? 'Good'
        : 'Weak';
    return Scaffold(
      appBar: AppBar(
        title: Text(
          alarmState.status == 'paused' ? 'Alarm paused' : 'Alarm active',
        ),
        actions: [
          AlarmActions(entry: alarmState.selected!),
          IconButton(
            tooltip: 'All alarms',
            onPressed: () => context.go('/?tab=alarms'),
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
          DashboardPanel(
            accent: Theme.of(context).colorScheme.primary,
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const DashboardLabel('Live trip'),
                    const Spacer(),
                    Icon(
                      Icons.radar,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  alarm.displayName,
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 14),
                Text(
                  distance == null ? '—' : formatDistance(distance),
                  style: Theme.of(context).textTheme.displayMedium?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const DashboardLabel('Straight-line distance'),
                if (lastKnownDistance != null) ...[
                  const SizedBox(height: 6),
                  Text('Last known: ${formatDistance(lastKnownDistance)}'),
                ],
                if (eta != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Straight-line estimate: ${_formatEta(eta)} at current speed',
                  ),
                ],
                const SizedBox(height: 16),
                Divider(color: Theme.of(context).colorScheme.outlineVariant),
                Row(
                  children: [
                    Icon(
                      Icons.adjust,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        alarmState.status == 'paused'
                            ? 'Paused · resume to monitor this destination'
                            : alarmState.selected?.monitoringHealthy == false
                            ? alarmState.selected?.monitoringMessage ??
                                  'Waiting for reliable GPS monitoring'
                            : alarm.repeatDays != 0 &&
                                  alarmState.selected?.distanceReady == false
                            ? 'Waiting for the next selected repeat day'
                            : distance == null
                            ? 'Waiting for a fresh GPS position'
                            : distance <= alarm.radius
                            ? 'Inside alert zone'
                            : distance <= 1000
                            ? 'Approaching destination'
                            : 'On the way',
                      ),
                    ),
                  ],
                ),
              ],
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
                  'GPS checks your straight-line distance to ${alarm.place.latitude.toStringAsFixed(5)}, '
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
                  subtitle: Text(
                    alarmState.status == 'paused'
                        ? 'Monitoring paused for this alarm'
                        : alarmState.selected?.gpsStatus ?? quality,
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.update),
                  title: const Text('Last GPS update'),
                  subtitle: Text(
                    alarmState.selected?.lastGpsFixAt == null
                        ? 'No GPS fix available'
                        : '${_formatDateTime(context, alarmState.selected!.lastGpsFixAt!)} · ${now.difference(alarmState.selected!.lastGpsFixAt!).inSeconds.clamp(0, 999999)} s ago',
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.my_location),
                  title: const Text('GPS accuracy'),
                  subtitle: Text(
                    alarmState.selected?.gpsAccuracy == null
                        ? 'Unknown until a GPS fix arrives'
                        : '±${alarmState.selected!.gpsAccuracy!.toStringAsFixed(0)} m',
                  ),
                ),
                if (alarm.repeatDays != 0)
                  ListTile(
                    leading: const Icon(Icons.event_repeat),
                    title: const Text('Next repeat day'),
                    subtitle: Text(
                      alarmState.status == 'paused'
                          ? 'Paused · resume to enable repeats'
                          : alarmState.selected?.nextRepeatAt == null
                          ? 'Checking schedule…'
                          : MaterialLocalizations.of(context).formatFullDate(
                              alarmState.selected!.nextRepeatAt!,
                            ),
                    ),
                  ),
                ListTile(
                  leading: const Icon(Icons.radio_button_checked),
                  title: const Text('Alert radius'),
                  subtitle: Text(
                    '${formatDistance(alarm.radius)} · ${alarmState.status == 'paused'
                        ? 'Paused'
                        : alarmState.distanceFired
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
                    alarmState.status == 'paused'
                        ? 'Paused · this alarm will not ring until resumed'
                        : alarmState.status == 'snoozed'
                        ? 'Snoozed'
                        : alarm.repeatDays != 0 &&
                              alarmState.selected?.distanceReady == false
                        ? 'Waiting for the next selected day'
                        : '${alarmState.selected?.monitoringMessage ?? 'Checking background monitoring…'}'
                              '\nGeofence backup: ${alarmState.selected?.geofenceStatus ?? 'Not confirmed'}',
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
                  alarmState.busy ||
                      (alarmState.selected?.status != 'active' &&
                          alarmState.selected?.status != 'paused')
                  ? null
                  : () => _editRepeat(alarm.id, alarm.repeatDays),
            ),
          ),
          if (alarmState.status == 'active' || alarmState.status == 'paused')
            OutlinedButton.icon(
              onPressed: alarmState.busy
                  ? null
                  : () async {
                      try {
                        await alarmState.pauseAlarm(
                          alarm.id,
                          alarmState.status != 'paused',
                        );
                      } catch (_) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              alarmState.error ??
                                  'Could not change pause setting.',
                            ),
                          ),
                        );
                      }
                    },
              icon: Icon(
                alarmState.status == 'paused' ? Icons.play_arrow : Icons.pause,
              ),
              label: Text(
                alarmState.status == 'paused' ? 'Resume alarm' : 'Pause alarm',
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
            onPressed: alarmState.busy
                ? null
                : () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text(
                          alarm.repeatDays == 0
                              ? 'End this trip?'
                              : 'Stop this repeating alarm?',
                        ),
                        content: Text(alarm.displayName),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('No'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: Text(
                              alarm.repeatDays == 0 ? 'End trip' : 'Stop alarm',
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

class AlarmTriggeredScreen extends ConsumerStatefulWidget {
  const AlarmTriggeredScreen({super.key});

  @override
  ConsumerState<AlarmTriggeredScreen> createState() =>
      _AlarmTriggeredScreenState();
}

class _AlarmTriggeredScreenState extends ConsumerState<AlarmTriggeredScreen> {
  bool _redirecting = false;

  @override
  Widget build(BuildContext context) {
    final alarmState = ref.watch(alarmProvider);
    final ringing =
        alarmState.alarms.where((entry) => entry.status == 'triggered').toList()
          ..sort((a, b) {
            final order = a.triggeredAt.compareTo(b.triggeredAt);
            return order != 0
                ? order
                : a.alarm.startedAt.compareTo(b.alarm.startedAt);
          });
    if (ringing.isEmpty) {
      if (!_redirecting && !alarmState.restoring) {
        _redirecting = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final current = ref.read(alarmProvider);
          if (current.hasTriggered) {
            setState(() => _redirecting = false);
            return;
          }
          context.go(current.active == null ? '/' : '/active');
        });
      }
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final currentAlert = ringing.first;
    final alarm = currentAlert.alarm;
    final waitingAlerts = ringing.skip(1).toList();
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 28),
                    Container(
                      width: 134,
                      height: 134,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Theme.of(context).colorScheme.tertiaryContainer,
                        border: Border.all(
                          color: Theme.of(context).colorScheme.tertiary,
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        Icons.notifications_active,
                        size: 74,
                        color: Theme.of(context).colorScheme.tertiary,
                      ),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      'ALARM',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: Theme.of(context).colorScheme.tertiary,
                            letterSpacing: 2,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      alarm.displayName,
                      style: Theme.of(context).textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(switch (currentAlert.triggerReason) {
                      'time' => 'The selected time has been reached.',
                      'both' => 'The selected time and distance have both been reached.',
                      _ => 'You have reached the selected distance.',
                    }, textAlign: TextAlign.center),
                    if (alarmState.error != null) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'Could not refresh alarm status. Retrying…',
                        textAlign: TextAlign.center,
                      ),
                    ],
                    if (waitingAlerts.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Next: ${waitingAlerts.first.alarm.displayName}'
                        '${waitingAlerts.length > 1 ? ' (+${waitingAlerts.length - 1} more)' : ''}',
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 28),
                    FilledButton.icon(
                      onPressed: alarmState.busy
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
                      onPressed: alarmState.busy
                          ? null
                          : () => showModalBottomSheet<void>(
                              context: context,
                              builder: (sheetContext) => ScrollableSheet(
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
                                                ref
                                                        .read(alarmProvider)
                                                        .hasTriggered
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
                      onPressed: alarmState.busy
                          ? null
                          : () async {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (dialogContext) => AlertDialog(
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
                                      onPressed: () =>
                                          Navigator.pop(dialogContext, false),
                                      child: const Text('Keep trip'),
                                    ),
                                    FilledButton(
                                      onPressed: () =>
                                          Navigator.pop(dialogContext, true),
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
          ),
        ),
      ),
    );
  }
}
