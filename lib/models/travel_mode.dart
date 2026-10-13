enum TravelMode { bus, metro, car, bike }

extension TravelModeLabel on TravelMode {
  String get label => switch (this) {
    TravelMode.bus => 'Bus',
    TravelMode.metro => 'Metro',
    TravelMode.car => 'Car',
    TravelMode.bike => 'Bike',
  };

  bool get usesStops => this == TravelMode.bus || this == TravelMode.metro;
}
