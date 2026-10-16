import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:tracker_alarm/features/map/map_view.dart';

class _PendingImage extends ImageProvider<_PendingImage> {
  final result = Completer<ImageInfo>();

  @override
  Future<_PendingImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    _PendingImage key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(result.future);
}

class _Tiles extends TileProvider {
  final requests = <_PendingImage>[];

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final image = _PendingImage();
    requests.add(image);
    return image;
  }
}

Future<void> _failPending(WidgetTester tester, _Tiles tiles) async {
  for (final image in tiles.requests.where(
    (image) => !image.result.isCompleted,
  )) {
    image.result.completeError(StateError('Offline'));
  }
  await tester.pumpAndSettle();
}

Future<void> _loadPending(WidgetTester tester, _Tiles tiles) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(Colors.green, BlendMode.src);
  final picture = recorder.endRecording();
  final image = await tester.runAsync(() => picture.toImage(1, 1));
  picture.dispose();
  for (final request in tiles.requests.where(
    (request) => !request.result.isCompleted,
  )) {
    request.result.complete(ImageInfo(image: image!.clone()));
  }
  image!.dispose();
  // flutter_map schedules pruning/rebuilding shortly after its tile fade.
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'failed tiles retry and the warning clears only after successful loading',
    (tester) async {
      final tiles = _Tiles();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MapView(
              tileProvider: tiles,
              areaCenter: const LatLng(10, 76),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tiles.requests, isNotEmpty);
      await _failPending(tester, tiles);
      expect(find.text('Retry map'), findsOneWidget);
      final mapController = MapController.of(
        tester.element(find.byType(TileLayer)),
      );
      final center = mapController.camera.center;
      final zoom = mapController.camera.zoom;
      final count = tiles.requests.length;
      await tester.tap(find.text('Retry map'));
      await tester.pumpAndSettle();
      expect(tiles.requests.length, greaterThan(count));
      expect(mapController.camera.center, center);
      expect(mapController.camera.zoom, zoom);
      expect(find.text('Retry map'), findsOneWidget);
      await _loadPending(tester, tiles);
      expect(find.text('Retry map'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'panning away from failed tiles recovers without a manual retry',
    (tester) async {
      final tiles = _Tiles();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MapView(
              tileProvider: tiles,
              areaCenter: const LatLng(10, 76),
            ),
          ),
        ),
      );
      await tester.pump();
      await _failPending(tester, tiles);
      expect(find.text('Retry map'), findsOneWidget);
      final context = tester.element(find.byType(TileLayer));
      MapController.of(context).move(const LatLng(12, 78), 13);
      await tester.pumpAndSettle();
      await _loadPending(tester, tiles);
      expect(find.text('Retry map'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
