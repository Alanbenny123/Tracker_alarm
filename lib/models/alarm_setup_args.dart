import 'place.dart';
import 'travel_mode.dart';

class AlarmSetupArgs {
  const AlarmSetupArgs({required this.place, required this.mode});

  final Place place;
  final TravelMode mode;
}

class DestinationReselectArgs {
  const DestinationReselectArgs(this.mode);
  final TravelMode mode;
}
