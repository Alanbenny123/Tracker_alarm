import 'place.dart';
import 'destination_alarm.dart';
import 'travel_mode.dart';

class AlarmSetupArgs {
  const AlarmSetupArgs({
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
}

class DestinationReselectArgs {
  const DestinationReselectArgs(this.mode);
  final TravelMode mode;
}
