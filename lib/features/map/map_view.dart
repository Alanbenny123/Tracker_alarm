import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:maplibre/maplibre.dart' as ml;

import '../../models/place.dart';

enum MapLoadNotice {
  retryingPrimary,
  loadingBackup,
  backupFailed,
  usingBackup;

  String get message => switch (this) {
    retryingPrimary => 'Trying map again… GPS alarms still work.',
    loadingBackup => 'Trying backup map… GPS alarms still work.',
    backupFailed => 'Both map sources could not load. GPS alarms still work.',
    usingBackup => 'Using backup map (dark style)',
  };

  bool get canRetry => this != usingBackup;
}

class MapView extends StatefulWidget {
  const MapView({
    super.key,
    this.position,
    this.destination,
    this.areaCenter,
    this.places = const [],
    this.radius = 500,
    this.onTap,
    this.onPlaceTap,
    this.onDestinationDrag,
    this.interactive = true,
    this.showLoadNotice = true,
    this.onLoadNoticeChanged,
  });

  final Position? position;
  final Place? destination;
  final LatLng? areaCenter;
  final List<Place> places;
  final double radius;
  final void Function(LatLng)? onTap;
  final void Function(Place)? onPlaceTap;
  final void Function(LatLng)? onDestinationDrag;
  final bool interactive;
  final bool showLoadNotice;
  final void Function(MapLoadNotice?, VoidCallback retry)? onLoadNoticeChanged;

  @override
  State<MapView> createState() => _MapViewState();
}

class _MapViewState extends State<MapView> {
  static const primaryStyle = 'https://tiles.openfreemap.org/styles/liberty';
  static const backupTiles =
      'https://basemap.queeniemella.cc/tiles/countries/{z}/{x}/{y}.png';
  static final backupStyle = jsonEncode({
    'version': 8,
    'sources': {
      'backup': {
        'type': 'raster',
        'tiles': [backupTiles],
        'tileSize': 256,
        'maxzoom': 19,
        'attribution': '© queeniemella · © OpenStreetMap contributors',
      },
    },
    'layers': [
      {'id': 'backup', 'type': 'raster', 'source': 'backup'},
    ],
  });

  ml.MapController? controller;
  Timer? loadTimer;
  bool styleReady = false;
  bool mapReady = false;
  bool tilesUnavailable = false;
  bool backupFailed = false;
  bool draggingPin = false;
  int sourceIndex = 0;

  MapLoadNotice? get loadNotice {
    if (tilesUnavailable) {
      if (sourceIndex == 0) return MapLoadNotice.retryingPrimary;
      return backupFailed
          ? MapLoadNotice.backupFailed
          : MapLoadNotice.loadingBackup;
    }
    if (sourceIndex == 1 && mapReady) return MapLoadNotice.usingBackup;
    return null;
  }

  void reportLoadNotice() =>
      widget.onLoadNoticeChanged?.call(loadNotice, retryMap);

  @override
  void dispose() {
    loadTimer?.cancel();
    super.dispose();
  }

  void startLoadTimer() {
    loadTimer?.cancel();
    loadTimer = Timer(const Duration(seconds: 10), () {
      if (!mounted || mapReady) return;
      if (sourceIndex == 0) {
        switchToBackup();
      } else {
        setState(() {
          tilesUnavailable = true;
          backupFailed = true;
        });
        reportLoadNotice();
      }
    });
  }

  void switchToBackup() {
    if (sourceIndex != 0) return;
    setState(() {
      sourceIndex = 1;
      styleReady = false;
      mapReady = false;
      tilesUnavailable = true;
      backupFailed = false;
    });
    controller?.setStyle(backupStyle);
    startLoadTimer();
    reportLoadNotice();
  }

  void retryMap() {
    setState(() {
      sourceIndex = 0;
      styleReady = false;
      mapReady = false;
      tilesUnavailable = true;
      backupFailed = false;
    });
    controller?.setStyle(primaryStyle);
    startLoadTimer();
    reportLoadNotice();
  }

  void onMapCreated(ml.MapController value) {
    controller = value;
    startLoadTimer();
  }

  void onMapEvent(ml.MapEvent event) {
    switch (event) {
      case ml.MapEventClick():
        if (widget.interactive && widget.onTap != null) {
          widget.onTap!(LatLng(event.point.lat, event.point.lon));
        }
      case ml.MapEventIdle():
        if (!styleReady || mapReady) return;
        loadTimer?.cancel();
        setState(() {
          mapReady = true;
          tilesUnavailable = false;
          backupFailed = false;
        });
        reportLoadNotice();
      default:
        break;
    }
  }

  Future<void> moveCamera(ml.Geographic point, double zoom) async {
    final map = controller;
    if (map == null) return;
    try {
      await map.moveCamera(center: point, zoom: zoom);
    } catch (_) {
      // The native view can finish disposing during a camera update.
    }
  }

  @override
  void didUpdateWidget(covariant MapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final destination = widget.destination;
    if (!draggingPin &&
        destination != null &&
        (oldWidget.destination?.latitude != destination.latitude ||
            oldWidget.destination?.longitude != destination.longitude)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(
            moveCamera(point(destination.latitude, destination.longitude), 15),
          );
        }
      });
    } else if (destination == null &&
        widget.areaCenter != null &&
        (oldWidget.areaCenter != widget.areaCenter ||
            oldWidget.destination != null)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(
            moveCamera(
              point(widget.areaCenter!.latitude, widget.areaCenter!.longitude),
              13,
            ),
          );
        }
      });
    } else if (destination == null &&
        widget.areaCenter == null &&
        oldWidget.position == null &&
        widget.position != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(
            moveCamera(
              point(widget.position!.latitude, widget.position!.longitude),
              14,
            ),
          );
        }
      });
    }
  }

  ml.Geographic get center {
    if (widget.destination case final destination?) {
      return point(destination.latitude, destination.longitude);
    }
    if (widget.areaCenter case final area?) {
      return point(area.latitude, area.longitude);
    }
    if (widget.position case final position?) {
      return point(position.latitude, position.longitude);
    }
    return point(20, 0);
  }

  double get initialZoom => widget.destination != null
      ? 15
      : widget.areaCenter != null
      ? 13
      : widget.position != null
      ? 12
      : 2;

  void zoom(double delta) {
    final camera = controller?.camera;
    if (camera != null) {
      unawaited(moveCamera(camera.center, (camera.zoom + delta).clamp(0, 19)));
    }
  }

  void dragPin(DragUpdateDetails details) {
    final map = controller;
    final destination = widget.destination;
    if (map == null ||
        destination == null ||
        widget.onDestinationDrag == null) {
      return;
    }
    final screen = map.toScreenLocation(
      point(destination.latitude, destination.longitude),
    );
    final next = map.toLngLat(screen + details.delta);
    widget.onDestinationDrag!(LatLng(next.lat, next.lon));
  }

  List<ml.Layer> radiusLayer(Color color) {
    if (widget.destination == null || widget.radius <= 0) return const [];
    final ring = <double>[];
    final latitude = center.lat * math.pi / 180;
    final longitude = center.lon * math.pi / 180;
    final angle = widget.radius / 6371000;
    for (var i = 0; i <= 64; i++) {
      final bearing = 2 * math.pi * i / 64;
      final lat = math.asin(
        math.sin(latitude) * math.cos(angle) +
            math.cos(latitude) * math.sin(angle) * math.cos(bearing),
      );
      final lon =
          longitude +
          math.atan2(
            math.sin(bearing) * math.sin(angle) * math.cos(latitude),
            math.cos(angle) - math.sin(latitude) * math.sin(lat),
          );
      ring.addAll([lon * 180 / math.pi, lat * 180 / math.pi]);
    }
    return [
      ml.PolygonLayer(
        polygons: [
          ml.Feature<ml.Polygon>(
            geometry: ml.Polygon([ring.positions(ml.Coords.xy)]),
          ),
        ],
        color: color.withValues(alpha: 0.16),
        outlineColor: color,
      ),
    ];
  }

  List<ml.Marker> markers(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return [
      for (final place in widget.places)
        ml.Marker(
          point: point(place.latitude, place.longitude),
          size: const Size(42, 42),
          alignment: Alignment.bottomCenter,
          child: Semantics(
            label: place.name,
            button: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onPlaceTap == null
                  ? null
                  : () => widget.onPlaceTap!(place),
              child: Icon(
                Icons.place,
                color: widget.destination?.id == place.id
                    ? primary
                    : const Color(0xFFAA4A35),
                size: 33,
              ),
            ),
          ),
        ),
      if (widget.position case final position?)
        ml.Marker(
          point: point(position.latitude, position.longitude),
          size: const Size(42, 42),
          child: const IgnorePointer(
            child: Icon(Icons.my_location, color: Color(0xFF137EC1), size: 32),
          ),
        ),
      if (widget.destination != null)
        ml.Marker(
          point: center,
          size: const Size(50, 50),
          alignment: Alignment.bottomCenter,
          child: GestureDetector(
            onPanStart: widget.onDestinationDrag == null
                ? null
                : (_) => draggingPin = true,
            onPanEnd: widget.onDestinationDrag == null
                ? null
                : (_) => draggingPin = false,
            onPanCancel: widget.onDestinationDrag == null
                ? null
                : () => draggingPin = false,
            onPanUpdate: widget.onDestinationDrag == null ? null : dragPin,
            child: const Icon(
              Icons.location_pin,
              color: Color(0xFFE15C48),
              size: 44,
            ),
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Stack(
      children: [
        ml.MapLibreMap(
          options: ml.MapOptions(
            initStyle: primaryStyle,
            initCenter: center,
            initZoom: initialZoom,
            maxZoom: 19,
            gestures: widget.interactive
                ? const ml.MapGestures.all()
                : const ml.MapGestures.none(),
          ),
          onMapCreated: onMapCreated,
          onStyleLoaded: (_) => styleReady = true,
          onEvent: onMapEvent,
          layers: radiusLayer(primary),
          children: [
            ml.WidgetLayer(markers: markers(context), allowInteraction: true),
          ],
        ),
        Positioned(
          left: 6,
          bottom: 4,
          child: ColoredBox(
            color: Theme.of(context).colorScheme.surface
                .withValues(alpha: 0.85),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                sourceIndex == 0
                    ? '© OpenFreeMap · © OpenMapTiles · © OpenStreetMap contributors'
                    : '© queeniemella · © OpenStreetMap contributors',
                style: const TextStyle(fontSize: 10),
              ),
            ),
          ),
        ),
        if (widget.showLoadNotice && sourceIndex == 1 && mapReady)
          Positioned(
            left: 8,
            right: widget.interactive ? 76 : 8,
            top: 8,
            child: _MapNotice(MapLoadNotice.usingBackup.message),
          ),
        if (widget.showLoadNotice && tilesUnavailable)
          Positioned(
            left: 8,
            right: widget.interactive ? 76 : 8,
            top: 8,
            child: Material(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(loadNotice!.message),
                    TextButton.icon(
                      onPressed: retryMap,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry map'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (widget.interactive)
          Positioned(
            right: 12,
            top: 12,
            child: Column(
              children: [
                _MapButton(icon: Icons.add, onTap: () => zoom(1)),
                const SizedBox(height: 6),
                _MapButton(icon: Icons.remove, onTap: () => zoom(-1)),
                if (widget.position case final position?) ...[
                  const SizedBox(height: 6),
                  _MapButton(
                    icon: Icons.my_location,
                    onTap: () => unawaited(
                      moveCamera(
                        point(position.latitude, position.longitude),
                        15,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

ml.Geographic point(double latitude, double longitude) =>
    ml.Geographic(lon: longitude, lat: latitude);

class _MapNotice extends StatelessWidget {
  const _MapNotice(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
    borderRadius: BorderRadius.circular(8),
    child: Padding(padding: const EdgeInsets.all(8), child: Text(message)),
  );
}

class _MapButton extends StatelessWidget {
  const _MapButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    elevation: 2,
    borderRadius: BorderRadius.circular(12),
    child: IconButton(onPressed: onTap, icon: Icon(icon)),
  );
}
