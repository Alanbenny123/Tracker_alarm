import 'package:flutter_test/flutter_test.dart';
import 'package:tracker_alarm/models/travel_mode.dart';
import 'package:tracker_alarm/services/transit_stops_service.dart';

void main() {
  test(
    'parses named bus stops and way centers, removing duplicate platforms',
    () {
      final stops = parseTransitStops({
        'elements': [
          {
            'type': 'node',
            'id': 1,
            'lat': 9.9000,
            'lon': 76.7000,
            'tags': {'name': 'Central Bus Stop'},
          },
          {
            'type': 'way',
            'id': 2,
            'center': {'lat': 9.9002, 'lon': 76.7001},
            'tags': {'name': 'Central Bus Stop'},
          },
          {
            'type': 'node',
            'id': 3,
            'lat': 9.91,
            'lon': 76.71,
            'tags': {'name': 'East Bus Stop'},
          },
          {'type': 'node', 'id': 4, 'lat': 9.92, 'lon': 76.72, 'tags': {}},
        ],
      }, TravelMode.bus);
      expect(stops.length, 2);
      expect(stops.first.name, 'Central Bus Stop');
      expect(stops.first.id, 'osm:node:1');
      expect(stops.last.address, 'Bus stop');
    },
  );

  test('accepts metro station centers and rejects invalid coordinates', () {
    final stations = parseTransitStops({
      'elements': [
        {
          'type': 'way',
          'id': 8,
          'center': {'lat': 10.0, 'lon': 76.0},
          'tags': {'name': 'Central Metro'},
        },
        {
          'type': 'node',
          'id': 9,
          'lat': 100.0,
          'lon': 76.0,
          'tags': {'name': 'Invalid'},
        },
      ],
    }, TravelMode.metro);
    expect(stations.single.name, 'Central Metro');
    expect(stations.single.address, 'Metro station');
    expect(stations.single.latitude, 10.0);
  });

  test('railway stations include halts and exclude metro stations', () {
    final stations = parseTransitStops({
      'elements': [
        {
          'type': 'node',
          'id': 10,
          'lat': 10.1,
          'lon': 76.2,
          'tags': {'name': 'Railway Halt', 'railway': 'halt'},
        },
        {
          'type': 'node',
          'id': 11,
          'lat': 10.2,
          'lon': 76.3,
          'tags': {
            'name': 'Metro Station',
            'railway': 'station',
            'station': 'subway',
          },
        },
      ],
    }, TravelMode.railway);
    expect(stations.single.name, 'Railway Halt');
    expect(stations.single.address, 'Railway station');
    expect(TravelMode.other.usesStops, isFalse);
  });
}
