enum TravelMode { bus, metro, railway, other }

extension TravelModeLabel on TravelMode {
  String get label => switch (this) {
    TravelMode.bus => 'Bus',
    TravelMode.metro => 'Metro',
    TravelMode.railway => 'Railway',
    TravelMode.other => 'Other',
  };

  bool get usesStops => this != TravelMode.other;

  String get placeName => switch (this) {
    TravelMode.bus => 'bus stops',
    TravelMode.metro => 'metro stations',
    TravelMode.railway => 'railway stations',
    TravelMode.other => 'places',
  };
}
