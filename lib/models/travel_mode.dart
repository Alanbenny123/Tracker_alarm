enum TravelMode { bus, metro, railway, other }

extension TravelModeLabel on TravelMode {
  double get defaultAlertRadius => switch (this) {
    TravelMode.bus || TravelMode.metro => 500,
    TravelMode.railway || TravelMode.other => 1000,
  };

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
