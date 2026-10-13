import 'package:flutter/services.dart';

import '../models/destination_alarm.dart';

class AlarmRequirements {
  const AlarmRequirements({
    required this.preciseLocation,
    required this.backgroundLocation,
    required this.notifications,
    required this.batteryOptimizationOff,
    this.batteryManuallyConfirmed = false,
  });

  final bool preciseLocation;
  final bool backgroundLocation;
  final bool notifications;
  final bool batteryOptimizationOff;
  final bool batteryManuallyConfirmed;

  bool get batteryReady => batteryOptimizationOff || batteryManuallyConfirmed;

  bool get ready =>
      preciseLocation && backgroundLocation && notifications && batteryReady;

  String get missingMessage {
    if (!preciseLocation) return 'Allow precise location to start an alarm.';
    if (!backgroundLocation) {
      return 'Set location to Allow all the time in Android settings.';
    }
    if (!notifications) return 'Allow notifications to start an alarm.';
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
        batteryOptimizationOff: value['batteryOptimizationOff'] == true,
        batteryManuallyConfirmed: value['batteryManuallyConfirmed'] == true,
      );
}

class GeofenceService {
  static const _channel = MethodChannel('tracker_alarm/geofence');

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

  Future<void> openBatterySettings() =>
      _channel.invokeMethod<void>('openBatterySettings');

  Future<void> openAppBatterySettings() =>
      _channel.invokeMethod<void>('openAppBatterySettings');

  Future<void> confirmBatterySettings() =>
      _channel.invokeMethod<void>('confirmBatterySettings');
}
