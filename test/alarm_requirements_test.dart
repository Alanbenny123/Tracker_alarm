import 'package:flutter_test/flutter_test.dart';
import 'package:tracker_alarm/services/geofence_service.dart';

void main() {
  test('exact alarm access is verified and required before starting', () {
    final settings = <String, dynamic>{
      'preciseLocation': true,
      'backgroundLocation': true,
      'notifications': true,
      'batteryOptimizationOff': true,
    };
    expect(AlarmRequirements.fromMap(settings).ready, isFalse);
    expect(
      AlarmRequirements.fromMap(settings).missingMessage,
      contains('Alarms & reminders'),
    );
    settings['exactAlarms'] = true;
    expect(AlarmRequirements.fromMap(settings).ready, isTrue);
  });
}
