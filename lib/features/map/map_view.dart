import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../models/place.dart';

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

  @override
  State<MapView> createState() => _MapViewState();
}

class _MapViewState extends State<MapView> {
  final MapController controller = MapController();
  bool tilesUnavailable = false;
  bool draggingPin = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
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
          controller.move(
            LatLng(destination.latitude, destination.longitude),
            15,
          );
        }
      });
    } else if (destination == null &&
        widget.areaCenter != null &&
        (oldWidget.areaCenter != widget.areaCenter ||
            oldWidget.destination != null)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) controller.move(widget.areaCenter!, 13);
      });
    } else if (destination == null &&
        widget.areaCenter == null &&
        oldWidget.position == null &&
        widget.position != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          controller.move(
            LatLng(widget.position!.latitude, widget.position!.longitude),
            14,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final center =
        widget.destination == null
            ? (widget.areaCenter ??
                (widget.position == null
                    ? const LatLng(20, 0)
                    : LatLng(
                      widget.position!.latitude,
                      widget.position!.longitude,
                    )))
            : LatLng(
              widget.destination!.latitude,
              widget.destination!.longitude,
            );
    return Stack(
      children: [
        FlutterMap(
          mapController: controller,
          options: MapOptions(
            initialCenter: center,
            initialZoom:
                widget.destination == null
                    ? (widget.areaCenter != null
                        ? 13
                        : widget.position == null
                        ? 2
                        : 12)
                    : 15,
            interactionOptions: InteractionOptions(
              flags:
                  widget.interactive
                      ? InteractiveFlag.all
                      : InteractiveFlag.none,
            ),
            onTap:
                widget.onTap == null
                    ? null
                    : (_, point) => widget.onTap!(point),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.trackeralarm.app',
              maxZoom: 19,
              errorTileCallback: (_, _, _) {
                if (!tilesUnavailable) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) setState(() => tilesUnavailable = true);
                  });
                }
              },
            ),
            if (widget.destination != null)
              CircleLayer(
                circles: [
                  CircleMarker(
                    point: center,
                    radius: widget.radius,
                    useRadiusInMeter: true,
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.16),
                    borderColor: Theme.of(context).colorScheme.primary,
                    borderStrokeWidth: 2,
                  ),
                ],
              ),
            MarkerLayer(
              markers: [
                for (final place in widget.places)
                  Marker(
                    point: LatLng(place.latitude, place.longitude),
                    width: 42,
                    height: 42,
                    child: Semantics(
                      label: place.name,
                      button: true,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap:
                            widget.onPlaceTap == null
                                ? null
                                : () => widget.onPlaceTap!(place),
                        child: Icon(
                          Icons.place,
                          color:
                              widget.destination?.id == place.id
                                  ? Theme.of(context).colorScheme.primary
                                  : const Color(0xFFAA4A35),
                          size: 33,
                        ),
                      ),
                    ),
                  ),
                if (widget.position != null)
                  Marker(
                    point: LatLng(
                      widget.position!.latitude,
                      widget.position!.longitude,
                    ),
                    width: 42,
                    height: 42,
                    child: const Icon(
                      Icons.my_location,
                      color: Color(0xFF137EC1),
                      size: 32,
                    ),
                  ),
                if (widget.destination != null)
                  Marker(
                    point: center,
                    width: 50,
                    height: 50,
                    child: GestureDetector(
                      onPanStart:
                          widget.onDestinationDrag == null
                              ? null
                              : (_) => draggingPin = true,
                      onPanEnd:
                          widget.onDestinationDrag == null
                              ? null
                              : (_) => draggingPin = false,
                      onPanCancel:
                          widget.onDestinationDrag == null
                              ? null
                              : () => draggingPin = false,
                      onPanUpdate:
                          widget.onDestinationDrag == null
                              ? null
                              : (details) {
                                final camera = controller.camera;
                                final point = LatLng(
                                  widget.destination!.latitude,
                                  widget.destination!.longitude,
                                );
                                final screen = camera.latLngToScreenOffset(
                                  point,
                                );
                                widget.onDestinationDrag!(
                                  camera.screenOffsetToLatLng(
                                    screen + details.delta,
                                  ),
                                );
                              },
                      child: const Icon(
                        Icons.location_pin,
                        color: Color(0xFFE15C48),
                        size: 44,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
        Positioned(
          left: 6,
          bottom: 4,
          child: ColoredBox(
            color: Theme.of(
              context,
            ).colorScheme.surface.withValues(alpha: 0.85),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                '© OpenStreetMap contributors',
                style: TextStyle(fontSize: 10),
              ),
            ),
          ),
        ),
        if (tilesUnavailable)
          Positioned(
            left: 8,
            right: 8,
            top: 8,
            child: Material(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Text('Map unavailable. GPS alarm will continue.'),
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
                  onTap:
                      () => controller.move(
                        controller.camera.center,
                        controller.camera.zoom + 1,
                      ),
                ),
                const SizedBox(height: 6),
                _MapButton(
                  icon: Icons.remove,
                  onTap:
                      () => controller.move(
                        controller.camera.center,
                        controller.camera.zoom - 1,
                      ),
                ),
                if (widget.position != null) ...[
                  const SizedBox(height: 6),
                  _MapButton(
                    icon: Icons.my_location,
                    onTap:
                        () => controller.move(
                          LatLng(
                            widget.position!.latitude,
                            widget.position!.longitude,
                          ),
                          15,
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
