import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gm;
import 'package:latlong2/latlong.dart';

import '../../models/place.dart';
import '../../services/offline_pack_store.dart';
import 'dark_map_style.dart';

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
    this.onCameraMove,
    this.interactive = true,
    this.compactPlaceholder = false,
    this.attributionBottomInset = 0,
    this.offlinePack,
  });
  final Position? position;
  final Place? destination;
  final LatLng? areaCenter;
  final List<Place> places;
  final double radius;
  final void Function(LatLng)? onTap;
  final void Function(Place)? onPlaceTap;
  final void Function(LatLng)? onDestinationDrag;
  final ValueChanged<LatLng>? onCameraMove;
  final bool interactive;
  final bool compactPlaceholder;

  /// Moves the SDK's Google logo above any panel drawn over the map.
  final double attributionBottomInset;
  final OfflinePack? offlinePack;

  @override
  State<MapView> createState() => _MapViewState();
}

class _MapViewState extends State<MapView> {
  static const _config = MethodChannel('tracker_alarm/google_maps_config');
  static Future<List<gm.BitmapDescriptor>>? _markerIcons;
  gm.GoogleMapController? controller;
  bool? configured;
  List<gm.BitmapDescriptor>? markerIcons;

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (widget.offlinePack == null) {
      _checkConfiguration();
      _loadMarkerIcons();
    }
  }

  Future<void> _loadMarkerIcons() async {
    try {
      final icons = await (_markerIcons ??= Future.wait([
        _monochromePin(Colors.white),
        _monochromePin(const Color(0xFFB5B5B5)),
        _monochromePin(const Color(0xFFE0E0E0)),
      ]));
      if (mounted) setState(() => markerIcons = icons);
    } catch (_) {
      _markerIcons = null;
    }
  }

  static Future<gm.BitmapDescriptor> _monochromePin(Color fill) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(2);
    final pin = ui.Path()
      ..moveTo(24, 3)
      ..cubicTo(12, 3, 4, 12, 4, 24)
      ..cubicTo(4, 37, 24, 59, 24, 59)
      ..cubicTo(24, 59, 44, 37, 44, 24)
      ..cubicTo(44, 12, 36, 3, 24, 3)
      ..close();
    canvas.drawPath(pin, Paint()..color = Colors.black);
    canvas.drawPath(
      pin,
      Paint()
        ..color = fill
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );
    canvas.drawCircle(Offset(24, 24), 7, Paint()..color = fill);
    final picture = recorder.endRecording();
    final image = await picture.toImage(96, 128);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    if (data == null) throw StateError('Could not draw map marker');
    return gm.BitmapDescriptor.bytes(
      data.buffer.asUint8List(),
      width: 48,
      height: 64,
    );
  }

  Future<void> _checkConfiguration() async {
    try {
      final ready = await _config.invokeMethod<bool>('configured') ?? false;
      if (mounted) setState(() => configured = ready);
    } on MissingPluginException {
      if (mounted) setState(() => configured = false);
    } on PlatformException {
      if (mounted) setState(() => configured = false);
    }
  }

  gm.LatLng get center => _center(widget);
  gm.LatLng _center(MapView view) {
    if (view.destination case final destination?) {
      return gm.LatLng(destination.latitude, destination.longitude);
    }
    if (view.areaCenter case final area?) {
      return gm.LatLng(area.latitude, area.longitude);
    }
    if (view.position case final position?) {
      return gm.LatLng(position.latitude, position.longitude);
    }
    return const gm.LatLng(20, 0);
  }

  @override
  void didUpdateWidget(covariant MapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.offlinePack == null && widget.offlinePack != null) {
      controller?.dispose();
      controller = null;
    }
    if (oldWidget.offlinePack != null && widget.offlinePack == null) {
      _checkConfiguration();
      _loadMarkerIcons();
    }
    if (widget.offlinePack != null) return;
    if (center != _center(oldWidget)) {
      final target = center;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(
            controller?.animateCamera(
                  gm.CameraUpdate.newLatLngZoom(
                    target,
                    widget.destination != null ? 15 : 13,
                  ),
                ) ??
                Future<void>.value(),
          );
        }
      });
    }
  }

  Set<gm.Marker> get markers => {
    if (markerIcons != null) ...{
      for (final place in widget.places)
        gm.Marker(
          markerId: gm.MarkerId(
            place.id ?? '${place.latitude},${place.longitude}',
          ),
          position: gm.LatLng(place.latitude, place.longitude),
          icon: markerIcons![2],
          infoWindow: gm.InfoWindow(title: place.name),
          onTap: widget.onPlaceTap == null
              ? null
              : () => widget.onPlaceTap!(place),
        ),
      if (widget.position case final position?)
        gm.Marker(
          markerId: const gm.MarkerId('current-location'),
          position: gm.LatLng(position.latitude, position.longitude),
          icon: markerIcons![1],
        ),
      if (widget.destination case final destination?)
        gm.Marker(
          markerId: const gm.MarkerId('destination'),
          position: gm.LatLng(destination.latitude, destination.longitude),
          icon: markerIcons![0],
          draggable: widget.onDestinationDrag != null,
          onDragEnd: widget.onDestinationDrag == null
              ? null
              : (point) => widget.onDestinationDrag!(
                  LatLng(point.latitude, point.longitude),
                ),
        ),
    },
  };

  @override
  Widget build(BuildContext context) {
    if (widget.offlinePack case final pack?) {
      return _OfflineMapView(
        key: ValueKey(pack.id),
        pack: pack,
        position: widget.position,
        destination: widget.destination,
        areaCenter: widget.areaCenter,
        places: widget.places,
        radius: widget.radius,
        onTap: widget.onTap,
        onPlaceTap: widget.onPlaceTap,
        onCameraMove: widget.onCameraMove,
        interactive: widget.interactive,
        attributionBottomInset: widget.attributionBottomInset,
      );
    }
    if (configured != true) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (configured == false)
                Icon(
                  Icons.map_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
              const SizedBox(height: 8),
              Text(
                configured == null
                    ? 'Loading map…'
                    : widget.compactPlaceholder
                    ? 'Map setup needed'
                    : 'Map setup needed. Add GOOGLE_MAPS_API_KEY to android/local.properties, then reinstall the app.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    return Stack(
      children: [
        gm.GoogleMap(
          padding: EdgeInsets.only(bottom: widget.attributionBottomInset),
          initialCameraPosition: gm.CameraPosition(
            target: center,
            zoom: widget.destination != null
                ? 15
                : widget.areaCenter != null
                ? 13
                : widget.position != null
                ? 12
                : 2,
          ),
          mapType: gm.MapType.normal,
          style: darkMapStyle,
          buildingsEnabled: false,
          trafficEnabled: false,
          indoorViewEnabled: false,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          rotateGesturesEnabled: widget.interactive,
          scrollGesturesEnabled: widget.interactive,
          zoomGesturesEnabled: widget.interactive,
          tiltGesturesEnabled: false,
          markers: markers,
          circles: widget.destination == null || widget.radius <= 0
              ? const {}
              : {
                  gm.Circle(
                    circleId: const gm.CircleId('alert-radius'),
                    center: center,
                    radius: widget.radius,
                    fillColor: Theme.of(context).colorScheme.primary
                        .withValues(alpha: 0.15),
                    strokeColor: Theme.of(context).colorScheme.primary,
                    strokeWidth: 2,
                  ),
                },
          onMapCreated: (value) => controller = value,
          onCameraMove: widget.onCameraMove == null
              ? null
              : (camera) => widget.onCameraMove!(
                  LatLng(camera.target.latitude, camera.target.longitude),
                ),
          onTap: widget.interactive && widget.onTap != null
              ? (point) =>
                    widget.onTap!(LatLng(point.latitude, point.longitude))
              : null,
        ),
        if (widget.interactive)
          Positioned(
            right: 12,
            top: 12,
            child: Column(
              children: [
                _MapButton(
                  icon: Icons.add,
                  onTap: () => _animate(gm.CameraUpdate.zoomIn()),
                ),
                const SizedBox(height: 6),
                _MapButton(
                  icon: Icons.remove,
                  onTap: () => _animate(gm.CameraUpdate.zoomOut()),
                ),
                if (widget.position case final position?) ...[
                  const SizedBox(height: 6),
                  _MapButton(
                    icon: Icons.my_location,
                    onTap: () => _animate(
                      gm.CameraUpdate.newLatLngZoom(
                        gm.LatLng(position.latitude, position.longitude),
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

  void _animate(gm.CameraUpdate update) {
    final map = controller;
    if (map != null) unawaited(map.animateCamera(update));
  }
}

class _OfflineMapView extends StatefulWidget {
  const _OfflineMapView({
    super.key,
    required this.pack,
    this.position,
    this.destination,
    this.areaCenter,
    required this.places,
    required this.radius,
    this.onTap,
    this.onPlaceTap,
    this.onCameraMove,
    required this.interactive,
    required this.attributionBottomInset,
  });

  final OfflinePack pack;
  final Position? position;
  final Place? destination;
  final LatLng? areaCenter;
  final List<Place> places;
  final double radius;
  final void Function(LatLng)? onTap;
  final void Function(Place)? onPlaceTap;
  final ValueChanged<LatLng>? onCameraMove;
  final bool interactive;
  final double attributionBottomInset;

  @override
  State<_OfflineMapView> createState() => _OfflineMapViewState();
}

class _OfflineMapViewState extends State<_OfflineMapView> {
  final controller = fm.MapController();

  LatLng get center {
    if (widget.destination case final place?) {
      return LatLng(place.latitude, place.longitude);
    }
    if (widget.areaCenter case final point?) return point;
    if (widget.position case final position?) {
      return LatLng(position.latitude, position.longitude);
    }
    return LatLng(
      (widget.pack.south + widget.pack.north) / 2,
      (widget.pack.west + widget.pack.east) / 2,
    );
  }

  @override
  void didUpdateWidget(covariant _OfflineMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (center != _centerOf(oldWidget)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) controller.move(center, controller.camera.zoom);
      });
    }
  }

  LatLng _centerOf(_OfflineMapView view) {
    if (view.destination case final place?) {
      return LatLng(place.latitude, place.longitude);
    }
    if (view.areaCenter case final point?) return point;
    if (view.position case final position?) {
      return LatLng(position.latitude, position.longitude);
    }
    return LatLng(
      (view.pack.south + view.pack.north) / 2,
      (view.pack.west + view.pack.east) / 2,
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final initialZoom = widget.destination != null ? 15.0 : 12.0;
    final zoom = initialZoom.clamp(
      widget.pack.minZoom.toDouble(),
      widget.pack.maxZoom.toDouble(),
    );
    return Stack(
      children: [
        fm.FlutterMap(
          mapController: controller,
          options: fm.MapOptions(
            initialCenter: center,
            initialZoom: zoom,
            minZoom: widget.pack.minZoom.toDouble(),
            maxZoom: widget.pack.maxZoom.toDouble(),
            interactionOptions: fm.InteractionOptions(
              flags: widget.interactive
                  ? fm.InteractiveFlag.all
                  : fm.InteractiveFlag.none,
            ),
            onTap: widget.interactive && widget.onTap != null
                ? (_, point) => widget.onTap!(point)
                : null,
            onPositionChanged: (camera, _) =>
                widget.onCameraMove?.call(camera.center),
          ),
          children: [
            fm.TileLayer(
              urlTemplate: widget.pack.tileTemplate,
              tileProvider: fm.FileTileProvider(),
              minNativeZoom: widget.pack.minZoom,
              maxNativeZoom: widget.pack.tileMaxZoom,
            ),
            if (widget.destination case final destination?)
              fm.CircleLayer(
                circles: [
                  fm.CircleMarker(
                    point: LatLng(destination.latitude, destination.longitude),
                    radius: widget.radius,
                    useRadiusInMeter: true,
                    color: color.withValues(alpha: 0.15),
                    borderColor: color,
                    borderStrokeWidth: 2,
                  ),
                ],
              ),
            fm.MarkerLayer(
              markers: [
                for (final place in widget.places)
                  fm.Marker(
                    point: LatLng(place.latitude, place.longitude),
                    width: 42,
                    height: 42,
                    child: IconButton(
                      tooltip: place.name,
                      onPressed: widget.onPlaceTap == null
                          ? null
                          : () => widget.onPlaceTap!(place),
                      icon: const Icon(Icons.place),
                    ),
                  ),
                if (widget.position case final position?)
                  fm.Marker(
                    point: LatLng(position.latitude, position.longitude),
                    width: 36,
                    height: 36,
                    child: const Icon(Icons.my_location, color: Colors.blue),
                  ),
                if (widget.destination case final destination?)
                  fm.Marker(
                    point: LatLng(destination.latitude, destination.longitude),
                    width: 42,
                    height: 42,
                    child: Icon(Icons.location_on, color: color, size: 36),
                  ),
              ],
            ),
          ],
        ),
        Positioned(
          left: 8,
          bottom: widget.attributionBottomInset + 8,
          child: ColoredBox(
            color: Theme.of(context).colorScheme.surface
                .withValues(alpha: 0.85),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text(
                '© OpenStreetMap contributors · ODbL',
                style: TextStyle(fontSize: 10),
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
                _MapButton(
                  icon: Icons.add,
                  onTap: () => controller.move(
                    controller.camera.center,
                    controller.camera.zoom + 1,
                  ),
                ),
                const SizedBox(height: 6),
                _MapButton(
                  icon: Icons.remove,
                  onTap: () => controller.move(
                    controller.camera.center,
                    controller.camera.zoom - 1,
                  ),
                ),
                if (widget.position case final position?) ...[
                  const SizedBox(height: 6),
                  _MapButton(
                    icon: Icons.my_location,
                    onTap: () => controller.move(
                      LatLng(position.latitude, position.longitude),
                      controller.camera.zoom,
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
