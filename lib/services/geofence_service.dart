import 'package:flutter/services.dart';

import '../models/destination_alarm.dart';

class AlarmRequirements {
  const AlarmRequirements({
    required this.preciseLocation,
    required this.backgroundLocation,
    required this.notifications,
    required this.batteryOptimizationOff,
    this.batteryManuallyConfirmed = false,
    this.exactAlarms = false,
    this.fullScreenAlarms = false,
    this.warnings = const [],
  });

  final bool preciseLocation;
  final bool backgroundLocation;
  final bool notifications;
  final bool exactAlarms;
  final bool fullScreenAlarms;
  final List<String> warnings;
  final bool batteryOptimizationOff;
  final bool batteryManuallyConfirmed;

  bool get batteryReady => batteryOptimizationOff || batteryManuallyConfirmed;

  bool get ready =>
      preciseLocation &&
      backgroundLocation &&
      notifications &&
      exactAlarms &&
      fullScreenAlarms &&
      batteryReady;

  String get missingMessage {
    if (!preciseLocation) return 'Allow precise location to start an alarm.';
    if (!backgroundLocation) {
      return 'Set location to Allow all the time in Android settings.';
    }
    if (!notifications) {
      return 'Allow notifications and high-priority alarm alerts in Android settings.';
    }
    if (!exactAlarms) {
      return 'Allow Alarms & reminders for reliable snooze and repeat alarms.';
    }
    if (!fullScreenAlarms) {
      return 'Allow lock-screen alarms in Android settings.';
    }
    if (!batteryReady) {
      return 'Set battery use to Unrestricted or No restrictions before starting.';
    }
    return '';
  }

  factory AlarmRequirements.fromMap(Map<dynamic, dynamic> value) =>
      AlarmRequirements(
        preciseLocation: value['preciseLocation'] == true,
        backgroundLocation: value['backgroundLocation'] == true,
        notifications: value['notifications'] == true,
        exactAlarms: value['exactAlarms'] == true,
        fullScreenAlarms: value['fullScreenAlarms'] == true,
        warnings:
            (value['warnings'] as List? ?? []).whereType<String>().toList(),
        batteryOptimizationOff: value['batteryOptimizationOff'] == true,
        batteryManuallyConfirmed: value['batteryManuallyConfirmed'] == true,
      );
}

class GeofenceService {
  static const _channel = MethodChannel('tracker_alarm/geofence');

  Future<List<Map<String, dynamic>>> multiStates() async {
    final states =
        await _channel.invokeListMethod<dynamic>('multiStates') ?? [];
    return states
        .map((value) => Map<String, dynamic>.from(value as Map))
        .toList();
  }

  Future<void> multiRegister(DestinationAlarm alarm) =>
      _channel.invokeMethod<void>('multiRegister', {
        'id': alarm.id,
        'name': alarm.place.name,
        'address': alarm.place.address,
        'latitude': alarm.place.latitude,
        'longitude': alarm.place.longitude,
        'radius': alarm.radius,
        'vibration': alarm.vibration,
        'sound': alarm.sound,
        'startedAt': alarm.startedAt.millisecondsSinceEpoch,
        'alertAt': alarm.alertAt?.millisecondsSinceEpoch,
        'repeatDays': alarm.repeatDays,
        'leadMinutes': alarm.leadMinutes,
        'repeatStartDay': alarm.repeatStartDay?.millisecondsSinceEpoch,
      });

  Future<void> clearFinished() =>
      _channel.invokeMethod<void>('multiClearFinished');

  Future<String?> storageWarning() =>
      _channel.invokeMethod<String>('multiStorageWarning');
  Future<void> clearStorageRecovery() =>
      _channel.invokeMethod<void>('multiClearStorageRecovery');

  Future<void> multiEnsure() => _channel.invokeMethod<void>('multiEnsure');
  Future<void> multiUpdateRepeat(String id, int days) => _channel
      .invokeMethod<void>('multiUpdateRepeat', {'id': id, 'days': days});
  Future<void> multiFinish(String id, String status) =>
      _channel.invokeMethod<void>('multiFinish', {'id': id, 'status': status});
  Future<void> multiForget(String id) =>
      _channel.invokeMethod<void>('multiForget', {'id': id});
  Future<void> multiDismiss(String id) =>
      _channel.invokeMethod<void>('multiDismiss', {'id': id});
  Future<void> multiSnooze(String id, int minutes) => _channel
      .invokeMethod<void>('multiSnooze', {'id': id, 'minutes': minutes});
  Future<void> multiTrigger(String id) =>
      _channel.invokeMethod<void>('multiTrigger', {'id': id});

  Future<void> register(DestinationAlarm alarm) =>
      _channel.invokeMethod<void>('register', {
        'id': alarm.id,
        'name': alarm.place.name,
        'address': alarm.place.address,
        'latitude': alarm.place.latitude,
        'longitude': alarm.place.longitude,
        'radius': alarm.radius,
        'vibration': alarm.vibration,
        'sound': alarm.sound,
        'startedAt': alarm.startedAt.millisecondsSinceEpoch,
        'alertAt': alarm.alertAt?.millisecondsSinceEpoch,
      });

  Future<void> cancel() => _channel.invokeMethod<void>('cancel');
  Future<void> ensure() => _channel.invokeMethod<void>('ensure');
  Future<void> resumeTriggered() =>
      _channel.invokeMethod<void>('resumeTriggered');
  Future<void> stop() => _channel.invokeMethod<void>('stop');
  Future<void> dismissCurrent() =>
      _channel.invokeMethod<void>('dismissCurrent');
  Future<void> trigger() => _channel.invokeMethod<void>('trigger');
  Future<void> snooze(int minutes) =>
      _channel.invokeMethod<void>('snooze', {'minutes': minutes});
  Future<String> status() async =>
      await _channel.invokeMethod<String>('status') ?? 'inactive';
  Future<Map<String, dynamic>?> state() async {
    final value = await _channel.invokeMethod<Map<dynamic, dynamic>>('state');
    return value == null ? null : Map<String, dynamic>.from(value);
  }

  Future<AlarmRequirements> requirements() async {
    final value = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'requirements',
    );
    if (value == null) throw StateError('Could not check alarm requirements.');
    return AlarmRequirements.fromMap(value);
  }

  Future<void> openNotificationSettings() =>
      _channel.invokeMethod<void>('openNotificationSettings');

  Future<void> openFullScreenSettings() =>
      _channel.invokeMethod<void>('openFullScreenSettings');

  Future<void> openExactAlarmSettings() =>
      _channel.invokeMethod<void>('openExactAlarmSettings');

  Future<void> openBatterySettings() =>
      _channel.invokeMethod<void>('openBatterySettings');

  Future<void> openAppBatterySettings() =>
      _channel.invokeMethod<void>('openAppBatterySettings');

  Future<void> confirmBatterySettings() =>
      _channel.invokeMethod<void>('confirmBatterySettings');
}
