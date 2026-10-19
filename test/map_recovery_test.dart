import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:maplibre/maplibre.dart' as ml;
import 'package:tracker_alarm/features/map/map_view.dart';
import 'package:tracker_alarm/models/place.dart';

import 'support/fake_maplibre.dart';

const destination = Place(
  name: 'Destination',
  address: '10, 76',
  latitude: 10,
  longitude: 76,
);

Future<void> showMap(WidgetTester tester, MapView view) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: view)));
  await tester.pump();
}

void main() {
  setUp(FakeMapLibrePlatform.shared.reset);

  testWidgets('MapLibre uses the keyless vector style and a distance area', (
    tester,
  ) async {
    await showMap(tester, const MapView(destination: destination, radius: 500));
    final map = tester.widget<ml.MapLibreMap>(find.byType(ml.MapLibreMap));
    expect(
      map.options.initStyle,
      'https://tiles.openfreemap.org/styles/liberty',
    );
    expect(map.layers.single, isA<ml.PolygonLayer>());
    final camera = FakeMapLibrePlatform.shared.states.single.camera!;
    expect(camera.center.lat, 10);
    expect(camera.center.lon, 76);
    expect(camera.zoom, 15);
    expect(find.textContaining('© OpenFreeMap'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'stalled primary map changes style without moving the destination',
    (tester) async {
      FakeMapLibrePlatform.shared.autoIdle = false;
      await showMap(tester, const MapView(destination: destination));
      final native = FakeMapLibrePlatform.shared.states.single;
      final camera = native.camera;
      await tester.pump(const Duration(seconds: 10));
      await tester.pump();
      expect(native.styles.last, contains('basemap.queeniemella.cc'));
      expect(native.camera, camera);
      expect(find.textContaining('Trying backup map'), findsOneWidget);
      native.emitIdle();
      await tester.pump();
      expect(find.text('Using backup map (dark style)'), findsOneWidget);
      expect(find.text('Retry map'), findsNothing);
      expect(
        tester.widget<MapView>(find.byType(MapView)).destination,
        destination,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('backup timeout offers retry of the vector map', (tester) async {
    FakeMapLibrePlatform.shared.autoIdle = false;
    await showMap(tester, const MapView(areaCenter: LatLng(10, 76)));
    final native = FakeMapLibrePlatform.shared.states.single;
    await tester.pump(const Duration(seconds: 10));
    await tester.pump(const Duration(seconds: 10));
    await tester.pump();
    expect(find.text('Retry map'), findsOneWidget);
    expect(
      find.textContaining('Both map sources could not load'),
      findsOneWidget,
    );
    final camera = native.camera;
    await tester.tap(find.text('Retry map'));
    await tester.pump();
    expect(native.styles.last, 'https://tiles.openfreemap.org/styles/liberty');
    expect(native.camera, camera);
    native.emitIdle();
    await tester.pump();
    expect(find.text('Retry map'), findsNothing);
    expect(find.text('Using backup map (dark style)'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('map and place taps keep their destination selection callbacks', (
    tester,
  ) async {
    LatLng? tapped;
    Place? selected;
    const stop = Place(
      name: 'Stop',
      address: 'Bus stop',
      latitude: 10,
      longitude: 76,
    );
    await showMap(
      tester,
      MapView(
        areaCenter: const LatLng(10, 76),
        places: const [stop],
        onTap: (value) => tapped = value,
        onPlaceTap: (value) => selected = value,
      ),
    );
    FakeMapLibrePlatform.shared.states.single.emitClick(
      ml.Geographic(lon: 76.2, lat: 10.1),
    );
    expect(tapped, const LatLng(10.1, 76.2));
    await tester.tap(find.byIcon(Icons.place));
    expect(selected, stop);
    await tester.pumpWidget(const SizedBox());
  });
}
