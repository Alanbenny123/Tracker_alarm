import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../models/place.dart';
import '../../models/travel_mode.dart';
import '../../providers/app_providers.dart';
import '../../services/places_service.dart';
import '../../services/transit_stops_service.dart';
import 'map_view.dart';

class DestinationPickerScreen extends ConsumerStatefulWidget {
  const DestinationPickerScreen({
    super.key,
    this.initialQuery,
    this.initialMode,
  });
  final String? initialQuery;
  final TravelMode? initialMode;
  @override
  ConsumerState<DestinationPickerScreen> createState() =>
      _DestinationPickerScreenState();
}

class _DestinationPickerScreenState
    extends ConsumerState<DestinationPickerScreen> {
  final searchController = TextEditingController();
  final placesService = PlacesService();
  final stopsService = TransitStopsService();
  late TravelMode mode;
  int searchGeneration = 0;
  int stopGeneration = 0;
  List<Place> results = [];
  List<Place> stops = [];
  Place? selected;
  LatLng? areaCenter;
  String? areaName;
  String? error;
  bool searching = false;
  bool loadingStops = false;

  @override
  void initState() {
    super.initState();
    mode = widget.initialMode ?? TravelMode.car;
    final query = widget.initialQuery;
    if (query != null) {
      searchController.text = query;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) search();
      });
    }
    if (mode.usesStops && query == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadNearby();
      });
    }
  }

  @override
  void dispose() {
    searchController.dispose();
    placesService.dispose();
    stopsService.dispose();
    super.dispose();
  }

  Future<void> search() async {
    if (searching) return;
    final text = searchController.text;
    final generation = ++searchGeneration;
    if (text.trim().length < 3) {
      setState(() {
        results = [];
        searching = false;
        error = null;
      });
      return;
    }
    setState(() {
      searching = true;
      error = null;
    });
    try {
      final found = await placesService.search(text);
      if (mounted) {
        setState(() {
          if (generation == searchGeneration) results = found;
          if (generation == searchGeneration) searching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          if (generation == searchGeneration) error = e.toString();
          if (generation == searchGeneration) searching = false;
        });
      }
    }
  }

  void _changeMode(TravelMode next) {
    if (mode == next) return;
    setState(() {
      mode = next;
      selected = null;
      results = [];
      stops = [];
      areaCenter = null;
      areaName = null;
      error = null;
      searchController.clear();
      searchGeneration++;
      stopGeneration++;
      searching = false;
      loadingStops = false;
    });
    if (next.usesStops) _loadNearby();
  }

  void _loadNearby() {
    final position = ref.read(locationProvider).position;
    if (position == null) {
      setState(
        () => error = 'Waiting for GPS. Search an area, or try nearby again.',
      );
      return;
    }
    _loadStops(LatLng(position.latitude, position.longitude), 'Near me');
  }

  Future<void> _loadStops(LatLng center, String name) async {
    final generation = ++stopGeneration;
    setState(() {
      areaCenter = center;
      areaName = name;
      selected = null;
      stops = [];
      results = [];
      searchGeneration++;
      loadingStops = true;
      searching = false;
      error = null;
    });
    try {
      final found = await stopsService.nearby(
        mode,
        center.latitude,
        center.longitude,
      );
      if (!mounted || generation != stopGeneration) return;
      setState(() {
        stops = found;
        loadingStops = false;
      });
    } catch (e) {
      if (!mounted || generation != stopGeneration) return;
      setState(() {
        error = e.toString();
        loadingStops = false;
      });
    }
  }

  void _selectResult(Place place) {
    FocusScope.of(context).unfocus();
    if (mode.usesStops) {
      _loadStops(LatLng(place.latitude, place.longitude), place.name);
    } else {
      setState(() {
        selected = place;
        results = [];
      });
    }
  }

  void _selectStop(Place place) {
    FocusScope.of(context).unfocus();
    setState(() => selected = place);
  }

  void selectPoint(LatLng point) {
    if (mode.usesStops) {
      _loadStops(point, 'Map point');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      selected = Place(
        name: 'Selected location',
        address:
            '${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}',
        latitude: point.latitude,
        longitude: point.longitude,
      );
      results = [];
    });
  }

  @override
  Widget build(BuildContext context) {
    final position = ref.watch(locationProvider).position;
    final radius = ref.watch(settingsProvider).defaultRadius;
    return Scaffold(
      appBar: AppBar(title: const Text('Choose destination')),
      body: Stack(
        children: [
          MapView(
            position: position,
            destination: selected,
            areaCenter: areaCenter,
            places: stops,
            radius: radius,
            onTap: selectPoint,
            onPlaceTap: _selectStop,
            onDestinationDrag: mode.usesStops ? null : selectPoint,
          ),
          Positioned(
            left: 12,
            right: 12,
            top: 12,
            child: Material(
              color: Theme.of(context).colorScheme.surface,
              elevation: 3,
              borderRadius: BorderRadius.circular(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children:
                            TravelMode.values
                                .map(
                                  (option) => Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 3,
                                    ),
                                    child: ChoiceChip(
                                      label: Text(option.label),
                                      selected: mode == option,
                                      onSelected: (_) => _changeMode(option),
                                    ),
                                  ),
                                )
                                .toList(),
                      ),
                    ),
                  ),
                  TextField(
                    controller: searchController,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => search(),
                    onChanged: (_) {
                      searchGeneration++;
                      setState(() {
                        results = [];
                        error = null;
                        searching = false;
                      });
                    },
                    decoration: InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText:
                          mode.usesStops
                              ? 'Search area for ${mode == TravelMode.bus ? 'bus stops' : 'metro stations'}'
                              : 'Search for a place',
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.all(16),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.arrow_forward),
                        tooltip: 'Search',
                        onPressed: searching ? null : search,
                      ),
                    ),
                  ),
                  if (searching) const LinearProgressIndicator(),
                  if (loadingStops) const LinearProgressIndicator(),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  if (results.isNotEmpty)
                    SizedBox(
                      height: 180,
                      child: ListView.builder(
                        itemCount: results.length,
                        itemBuilder: (context, index) {
                          final place = results[index];
                          return ListTile(
                            title: Text(place.name),
                            subtitle: Text(
                              place.address,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => _selectResult(place),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (mode.usesStops && selected == null && results.isEmpty)
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Card(
                elevation: 3,
                child: SizedBox(
                  height: 225,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${mode == TravelMode.bus ? 'Bus stops' : 'Metro stations'} · ${areaName ?? 'Choose an area'}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            TextButton(
                              onPressed: _loadNearby,
                              child: const Text('Near me'),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child:
                            stops.isEmpty
                                ? Center(
                                  child: Text(
                                    loadingStops
                                        ? 'Finding mapped stops…'
                                        : error != null
                                        ? 'Could not load stops. Try another area or tap Near me.'
                                        : areaCenter == null
                                        ? 'Search an area or tap the map.'
                                        : 'No mapped stops found here. Try another area.',
                                    textAlign: TextAlign.center,
                                  ),
                                )
                                : ListView.builder(
                                  itemCount: stops.length,
                                  itemBuilder: (context, index) {
                                    final stop = stops[index];
                                    return ListTile(
                                      dense: true,
                                      leading: Icon(
                                        mode == TravelMode.bus
                                            ? Icons.directions_bus
                                            : Icons.subway,
                                      ),
                                      title: Text(stop.name),
                                      subtitle: Text(stop.address),
                                      trailing: const Icon(Icons.chevron_right),
                                      onTap: () => _selectStop(stop),
                                    );
                                  },
                                ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (selected != null)
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Card(
                elevation: 3,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Destination',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      Text(
                        selected!.name,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        selected!.address,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${selected!.latitude.toStringAsFixed(6)}, ${selected!.longitude.toStringAsFixed(6)}',
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed:
                            () => context.push('/setup', extra: selected),
                        child: const Text('Confirm destination'),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        mode.usesStops
                            ? 'Tap another stop on the map, or tap the map to search another area.'
                            : 'Tap the map or drag the pin to move it.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
