import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:tracker_alarm/features/map/destination_picker_screen.dart';
import 'package:tracker_alarm/features/map/map_view.dart';
import 'package:tracker_alarm/models/place.dart';
import 'package:tracker_alarm/models/travel_mode.dart';
import 'package:tracker_alarm/providers/app_providers.dart';
import 'package:tracker_alarm/services/places_service.dart';
import 'package:tracker_alarm/services/transit_stops_service.dart';

import 'helpers/alarm_fakes.dart';

class _Places extends PlacesService {
  final requests = <Completer<List<Place>>>[];
  @override
  Future<List<Place>> search(
    String query, {
    double? latitude,
    double? longitude,
  }) {
    final pending = Completer<List<Place>>();
    requests.add(pending);
    return pending.future;
  }
}

class _Stops extends TransitStopsService {
  final requests = <Completer<List<Place>>>[];
  final centers = <LatLng>[];
  int cancellations = 0;
  @override
  Future<List<Place>> nearby(
    TravelMode mode,
    double latitude,
    double longitude,
  ) {
    centers.add(LatLng(latitude, longitude));
    final pending = Completer<List<Place>>();
    requests.add(pending);
    return pending.future;
  }

  @override
  void cancel() => cancellations++;
}

void main() {
  testWidgets('stop results show distance from the searched center', (
    tester,
  ) async {
    final places = _Places();
    final stops = _Stops();
    await tester.pumpWidget(_app(places, stops, TravelMode.bus));
    await tester.pump();
    stops.requests.single.complete([stationNearby]);
    await tester.pump();
    expect(find.textContaining('m from search point'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('panning the map searches a new area only after a tap', (
    tester,
  ) async {
    final places = _Places();
    final stops = _Stops();
    await tester.pumpWidget(_app(places, stops, TravelMode.metro));
    await tester.pump();
    expect(stops.centers, [const LatLng(9.9, 76.7)]);
    stops.requests.single.complete([]);
    await tester.pump();

    tester.widget<MapView>(find.byType(MapView)).onCameraMove!(
      const LatLng(10.1, 76.2),
    );
    await tester.pump();
    expect(stops.requests, hasLength(1));
    await tester.tap(find.text('Search this area'));
    await tester.pump();
    expect(stops.centers.last, const LatLng(10.1, 76.2));
    expect(stops.requests, hasLength(2));
    stops.requests.last.complete([stationA]);
    await tester.pump();
    expect(find.text('Station A'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'shared-place search hides the reported unrelated Canada result',
    (tester) async {
      final places = _Places();
      final stops = _Stops();
      await tester.pumpWidget(_app(places, stops, TravelMode.other, true));
      await tester.enterText(
        find.byType(TextField),
        'Hello pets, Mamangalam, Edappally, Ernakulam, Keralam 682025',
      );
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      places.requests.single.complete([
        const Place(
          name: '3569',
          address: '3569 Dutch Village Rd, Halifax, NS B3N 0E8, Canada',
          latitude: 44.65,
          longitude: -63.63,
        ),
        stationA.copyWith(
          name: 'Hello pets',
          address: 'Mamangalam, Edappally, Ernakulam',
        ),
      ]);
      await tester.pump();
      expect(find.text('3569'), findsNothing);
      expect(find.text('Hello pets'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'empty place search explains recovery and clears on a new query',
    (tester) async {
      final places = _Places();
      final stops = _Stops();
      await tester.pumpWidget(_app(places, stops, TravelMode.bus));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Missing town');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      places.requests.single.complete([]);
      await tester.pump();
      expect(
        find.textContaining('No places found for “Missing town”'),
        findsOneWidget,
      );
      expect(find.textContaining('No mapped'), findsNothing);
      // An earlier stop request cannot replace this newer empty result.
      stops.requests.single.complete([stationA]);
      await tester.pump();
      expect(find.text('Station A'), findsNothing);
      await tester.enterText(find.byType(TextField), 'New town');
      await tester.pump();
      expect(find.textContaining('No places found'), findsNothing);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      places.requests.last.complete([stationB]);
      await tester.pump();
      expect(find.text('Station B'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'empty stop searches explain the 5 km search radius',
    (tester) async {
      final places = _Places();
      final stops = _Stops();
      await tester.pumpWidget(_app(places, stops, TravelMode.bus));
      await tester.pump();
      stops.requests.single.complete([]);
      await tester.pump();
      expect(
        find.textContaining('No mapped bus stops found within 5 km'),
        findsOneWidget,
      );
      await tester.tap(find.text('Railway'));
      await tester.pump();
      stops.requests.last.complete([]);
      await tester.pump();
      expect(
        find.textContaining('No mapped railway stations found within 5 km'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('short queries show guidance without making a request', (
    tester,
  ) async {
    final places = _Places();
    final stops = _Stops();
    await tester.pumpWidget(_app(places, stops));
    await tester.enterText(find.byType(TextField), 'ab');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(find.text('Enter at least 3 characters to search.'), findsOneWidget);
    expect(places.requests, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'choosing a map point invalidates a pending shared-place search',
    (tester) async {
      final places = _Places();
      final stops = _Stops();
      await tester.pumpWidget(
        _app(places, stops, TravelMode.other, true, 'Old shop, Kochi'),
      );
      await tester.pump();
      expect(places.requests, hasLength(1));
      tester.widget<MapView>(find.byType(MapView)).onTap!(const LatLng(10, 76));
      await tester.pump();
      places.requests.single.complete([
        stationA.copyWith(name: 'Old shop', address: 'Kochi'),
      ]);
      await tester.pump();
      expect(find.text('Selected location'), findsOneWidget);
      expect(find.text('Old shop'), findsNothing);
      expect(find.text('Confirm destination'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'transport change ignores old stop errors and uses the new stations',
    (tester) async {
      final places = _Places();
      final stops = _Stops();
      await tester.pumpWidget(_app(places, stops, TravelMode.bus));
      await tester.pump();
      expect(stops.requests, hasLength(1));
      await tester.tap(find.text('Metro'));
      await tester.pump();
      expect(stops.requests, hasLength(2));
      stops.requests.first.completeError(Exception('Old bus search failed'));
      await tester.pump();
      expect(find.textContaining('Old bus search failed'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      stops.requests.last.complete([stationB]);
      await tester.pump();
      expect(find.text('Station B'), findsWidgets);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(stops.cancellations, greaterThan(0));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('new area search invalidates pending nearby stops', (
    tester,
  ) async {
    final places = _Places();
    final stops = _Stops();
    await tester.pumpWidget(_app(places, stops, TravelMode.bus));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'new area');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    stops.requests.single.complete([stationA]);
    await tester.pump();
    expect(find.text('Station A'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    places.requests.single.complete([stationB]);
    await tester.pump();
    expect(find.text('Station B'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}

Widget _app(
  _Places places,
  _Stops stops, [
  TravelMode mode = TravelMode.other,
  bool sharedPlace = false,
  String? initialQuery,
]) => ProviderScope(
  overrides: [
    locationProvider.overrideWith(
      (ref) =>
          LocationController(FakeLocation())..position = positionAt(9.9, 76.7),
    ),
  ],
  child: MaterialApp(
    home: DestinationPickerScreen(
      initialMode: mode,
      initialQuery: initialQuery,
      sharedPlace: sharedPlace,
      placesService: places,
      stopsService: stops,
    ),
  ),
);
