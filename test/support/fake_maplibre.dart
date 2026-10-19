import 'package:flutter/material.dart';
import 'package:maplibre/maplibre.dart' as ml;
import 'package:maplibre_platform_interface/maplibre_platform_interface.dart';

/// A platform surface for Flutter widget tests. Native map rendering is tested
/// on a device; this surface emits the same creation, style and idle events.
class FakeMapLibrePlatform extends MapLibrePlatform {
  FakeMapLibrePlatform._();

  static final FakeMapLibrePlatform shared = FakeMapLibrePlatform._();
  final states = <FakeMapState>[];
  bool autoIdle = true;

  static void install() {
    MapLibrePlatform.instance = shared;
  }

  void reset() {
    states.clear();
    autoIdle = true;
  }

  @override
  MapLibreMapState createWidgetState() {
    final state = FakeMapState(this);
    states.add(state);
    return state;
  }
}

class FakeMapState extends MapLibreMapState {
  FakeMapState(this.platform);
  final FakeMapLibrePlatform platform;
  final styles = <String>[];

  @override
  void initState() {
    super.initState();
    camera = ml.MapCamera(
      center: widget.options.initCenter ?? ml.Geographic(lon: 0, lat: 0),
      zoom: widget.options.initZoom,
      bearing: 0,
      pitch: 0,
    );
    isInitialized = true;
    styles.add(widget.options.initStyle);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onMapCreated?.call(this);
      emitStyleLoaded();
      if (platform.autoIdle) emitIdle();
    });
  }

  void emitStyleLoaded() {
    widget.onStyleLoaded?.call(_FakeStyleController());
  }

  void emitIdle() {
    widget.onEvent?.call(const ml.MapEventIdle());
  }

  void emitClick(ml.Geographic point) {
    widget.onEvent?.call(
      ml.MapEventClick(point: point, screenPoint: toScreenLocation(point)),
    );
  }

  @override
  Widget buildPlatformWidget(BuildContext context) =>
      const ColoredBox(color: Color(0xFFDBE5DD));

  @override
  Offset toScreenLocation(ml.Geographic point) => const Offset(180, 180);

  @override
  List<Offset> toScreenLocations(List<ml.Geographic> points) =>
      points.map(toScreenLocation).toList();

  @override
  ml.Geographic toLngLat(Offset screenLocation) =>
      camera?.center ?? ml.Geographic(lon: 0, lat: 0);

  @override
  List<ml.Geographic> toLngLats(List<Offset> screenLocations) =>
      screenLocations.map(toLngLat).toList();

  @override
  Future<void> moveCamera({
    ml.Geographic? center,
    double? zoom,
    double? bearing,
    double? pitch,
    EdgeInsets padding = EdgeInsets.zero,
  }) async {
    final old = camera!;
    camera = ml.MapCamera(
      center: center ?? old.center,
      zoom: zoom ?? old.zoom,
      bearing: bearing ?? old.bearing,
      pitch: pitch ?? old.pitch,
    );
    if (mounted) setState(() {});
  }

  @override
  ml.MapCamera getCamera() => camera!;

  @override
  void setStyle(String style) {
    styles.add(style);
    emitStyleLoaded();
    if (platform.autoIdle) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) emitIdle();
      });
    }
  }

  @override
  double getMetersPerPixelAtLatitude(double latitude) => 1;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeStyleController implements ml.StyleController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
