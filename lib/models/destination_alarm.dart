import 'place.dart';

class DestinationAlarm {
  const DestinationAlarm({
    required this.id,
    required this.place,
    required this.radius,
    required this.vibration,
    required this.sound,
    required this.startedAt,
    this.alertAt,
    this.repeatDays = 0,
    this.leadMinutes = 0,
    this.repeatStartDay,
  });

  final String id;
  final Place place;
  final double radius;
  final bool vibration;
  final String sound;
  final DateTime startedAt;
  final DateTime? alertAt;

  /// Monday is bit 0 and Sunday is bit 6. Zero means one-time.
  final int repeatDays;
  final int leadMinutes;
  final DateTime? repeatStartDay;

  Map<String, dynamic> toJson() => {
    'id': id,
    'place': place.toJson(),
    'radius': radius,
    'vibration': vibration,
    'sound': sound,
    'startedAt': startedAt.toIso8601String(),
    'alertAt': alertAt?.toIso8601String(),
    'repeatDays': repeatDays,
    'leadMinutes': leadMinutes,
    'repeatStartDay': repeatStartDay?.toIso8601String(),
  };

  factory DestinationAlarm.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String;
    final radius = (json['radius'] as num).toDouble();
    final days = (json['repeatDays'] as num?)?.toInt() ?? 0;
    if (id.trim().isEmpty ||
        !radius.isFinite ||
        radius <= 0 ||
        days < 0 ||
        days > 127) {
      throw const FormatException('Invalid saved alarm');
    }
    return DestinationAlarm(
      id: id,
      place: Place.fromJson(Map<String, dynamic>.from(json['place'] as Map)),
      radius: radius,
      vibration: json['vibration'] as bool? ?? true,
      sound: json['sound'] as String? ?? 'Default alarm',
      startedAt: DateTime.parse(json['startedAt'] as String),
      alertAt:
          json['alertAt'] == null
              ? null
              : DateTime.parse(json['alertAt'] as String),
      repeatDays: days,
      leadMinutes: (json['leadMinutes'] as num?)?.toInt() ?? 0,
      repeatStartDay:
          json['repeatStartDay'] == null
              ? null
              : DateTime.parse(json['repeatStartDay'] as String),
    );
  }
}

class TripRecord {
  const TripRecord({
    required this.alarm,
    required this.endedAt,
    required this.status,
  });
  final DestinationAlarm alarm;
  final DateTime endedAt;
  final String status;

  Map<String, dynamic> toJson() => {
    'alarm': alarm.toJson(),
    'endedAt': endedAt.toIso8601String(),
    'status': status,
  };
  factory TripRecord.fromJson(Map<String, dynamic> json) {
    if (json['status'] != 'completed' && json['status'] != 'cancelled') {
      throw const FormatException('Invalid saved trip status');
    }
    return TripRecord(
      alarm: DestinationAlarm.fromJson(
        Map<String, dynamic>.from(json['alarm'] as Map),
      ),
      endedAt: DateTime.parse(json['endedAt'] as String),
      status: json['status'] as String,
    );
  }
}
