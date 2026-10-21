import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gm;
import 'package:latlong2/latlong.dart';

import '../../models/place.dart';
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

  @override
  State<MapView> createState() => _MapViewState();
}

class _MapViewState extends State<MapView> {
  static const _config = MethodChannel('tracker_alarm/google_maps_config');
  gm.GoogleMapController? controller;
  bool? configured;

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _checkConfiguration();
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
    for (final place in widget.places)
      gm.Marker(
        markerId: gm.MarkerId(
          place.id ?? '${place.latitude},${place.longitude}',
        ),
        position: gm.LatLng(place.latitude, place.longitude),
        icon: gm.BitmapDescriptor.defaultMarkerWithHue(
          gm.BitmapDescriptor.hueOrange,
        ),
        infoWindow: gm.InfoWindow(title: place.name),
        onTap: widget.onPlaceTap == null
            ? null
            : () => widget.onPlaceTap!(place),
      ),
    if (widget.position case final position?)
      gm.Marker(
        markerId: const gm.MarkerId('current-location'),
        position: gm.LatLng(position.latitude, position.longitude),
        icon: gm.BitmapDescriptor.defaultMarkerWithHue(
          gm.BitmapDescriptor.hueYellow,
        ),
      ),
    if (widget.destination case final destination?)
      gm.Marker(
        markerId: const gm.MarkerId('destination'),
        position: gm.LatLng(destination.latitude, destination.longitude),
        icon: gm.BitmapDescriptor.defaultMarkerWithHue(
          gm.BitmapDescriptor.hueRed,
        ),
        draggable: widget.onDestinationDrag != null,
        onDragEnd: widget.onDestinationDrag == null
            ? null
            : (point) => widget.onDestinationDrag!(
                LatLng(point.latitude, point.longitude),
              ),
      ),
  };

  @override
  Widget build(BuildContext context) {
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
          style: Theme.of(context).brightness == Brightness.dark
              ? darkMapStyle
              : null,
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
