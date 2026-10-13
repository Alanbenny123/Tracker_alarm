import 'package:flutter_test/flutter_test.dart';
import 'package:tracker_alarm/models/destination_alarm.dart';
import 'package:tracker_alarm/models/place.dart';

void main() {
  test(
    'active alarm and trip preserve destination and radius through storage JSON',
    () {
      final alarm = DestinationAlarm(
        id: 'trip-1',
        place: const Place(
          name: 'Bus stand',
          address: 'Kerala',
          latitude: 9.9,
          longitude: 76.7,
        ),
        radius: 500,
        vibration: true,
        sound: 'Bell',
        startedAt: DateTime.utc(2026, 10, 8, 8, 30),
        alertAt: DateTime.utc(2026, 10, 8, 9),
      );
      final copy = DestinationAlarm.fromJson(alarm.toJson());
      expect(copy.place.latitude, 9.9);
      expect(copy.place.longitude, 76.7);
      expect(copy.radius, 500);
      expect(copy.sound, 'Bell');
      expect(copy.alertAt, DateTime.utc(2026, 10, 8, 9));

      final trip = TripRecord(
        alarm: alarm,
        endedAt: DateTime.utc(2026, 10, 8, 9),
        status: 'completed',
      );
      final restored = TripRecord.fromJson(trip.toJson());
      expect(restored.alarm.id, alarm.id);
      expect(restored.status, 'completed');
      expect(restored.endedAt, DateTime.utc(2026, 10, 8, 9));
    },
  );
}
