import 'package:flutter_test/flutter_test.dart';
import 'package:tracker_alarm/models/destination_alarm.dart';
import 'package:tracker_alarm/models/place.dart';
import 'package:tracker_alarm/models/repeat_schedule.dart';

void main() {
  test('uses the next selected weekday and keeps the chosen clock time', () {
    final start = DateTime(2026, 10, 12, 16); // Monday.
    final now = DateTime(2026, 10, 12, 16, 1);
    final target = nextRepeatTarget(start, 1 << 0, 0, now);
    expect(target, DateTime(2026, 10, 19, 16));
  });

  test('early reminder can ring on the previous calendar day', () {
    final start = DateTime(2026, 10, 13, 0, 5); // Tuesday.
    final now = DateTime(2026, 10, 12, 23, 30);
    final target = nextRepeatTarget(start, 1 << 1, 30, now);
    expect(target, start);
    expect(
      target!.subtract(const Duration(minutes: 30)),
      DateTime(2026, 10, 12, 23, 35),
    );
  });

  test('skips a selected day when its early reminder has passed', () {
    final start = DateTime(2026, 10, 13, 0, 5);
    final now = DateTime(2026, 10, 12, 23, 40);
    expect(
      nextRepeatTarget(start, 1 << 1, 30, now),
      DateTime(2026, 10, 20, 0, 5),
    );
  });

  test('distance-only repeat can start today or the next selected day', () {
    final now = DateTime(2026, 10, 15, 18); // Thursday.
    expect(nextRepeatDay(1 << 3, now), DateTime(2026, 10, 15));
    expect(nextRepeatDay(1 << 4, now), DateTime(2026, 10, 16));
  });

  test('repeat settings survive alarm JSON round trip', () {
    final alarm = DestinationAlarm(
      id: 'weekday',
      place: const Place(
        name: 'Station',
        address: '',
        latitude: 10,
        longitude: 76,
      ),
      radius: 500,
      vibration: true,
      sound: 'Bell',
      startedAt: DateTime(2026, 10, 12),
      alertAt: DateTime(2026, 10, 13, 8),
      repeatDays: (1 << 0) | (1 << 2),
      leadMinutes: 15,
      repeatStartDay: DateTime(2026, 10, 13),
    );
    final restored = DestinationAlarm.fromJson(alarm.toJson());
    expect(restored.repeatDays, alarm.repeatDays);
    expect(restored.leadMinutes, 15);
    expect(restored.alertAt, alarm.alertAt);
    expect(restored.repeatStartDay, alarm.repeatStartDay);
  });
}
