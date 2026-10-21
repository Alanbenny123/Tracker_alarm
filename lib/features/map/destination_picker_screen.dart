import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../models/alarm_setup_args.dart';
import '../../models/place.dart';
import '../../models/shared_place_search_args.dart';
import '../../models/travel_mode.dart';
import '../../providers/app_providers.dart';
import '../../widgets/dashboard_panel.dart';
import '../../services/places_service.dart';
import '../../services/transit_stops_service.dart';
import 'map_view.dart';

enum _SearchErrorSource { place, stops, nearby }

class DestinationPickerScreen extends ConsumerStatefulWidget {
  const DestinationPickerScreen({
    super.key,
    this.initialQuery,
    this.initialMode,
    this.returnSelection = false,
    this.placesService,
    this.stopsService,
    this.sharedPlace = false,
  });
  final String? initialQuery;
  final TravelMode? initialMode;
  final bool returnSelection;
  final PlacesService? placesService;
  final TransitStopsService? stopsService;
  final bool sharedPlace;
  @override
  ConsumerState<DestinationPickerScreen> createState() =>
      _DestinationPickerScreenState();
}

class _DestinationPickerScreenState
    extends ConsumerState<DestinationPickerScreen> {
  final searchController = TextEditingController();
  late final PlacesService placesService;
  late final TransitStopsService stopsService;
  late TravelMode mode;
  int searchGeneration = 0;
  List<Place> results = [];
  List<Place> stops = [];
  Place? selected;
  LatLng? areaCenter;
  LatLng? cameraCenter;
  String? areaName;
  String? error;
  _SearchErrorSource? errorSource;
  bool searching = false;
  bool sharedResultSelected = false;
  bool loadingStops = false;
  String? emptyPlaceQuery;
  bool stopsLoaded = false;
  String? queryHint;
  String? transitNotice;

  @override
  void initState() {
    super.initState();
    placesService = widget.placesService ?? PlacesService();
    stopsService = widget.stopsService ?? TransitStopsService();
    mode = widget.initialMode ?? TravelMode.other;
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

  // One generation covers both geocoding and stop lookup, since either can
  // replace the same list, map pins, selection, and error message.
  void _cancelLookups() {
    searchGeneration++;
    placesService.cancel();
    stopsService.cancel();
    searching = false;
    sharedResultSelected = false;
    loadingStops = false;
    emptyPlaceQuery = null;
    stopsLoaded = false;
    queryHint = null;
    transitNotice = null;
  }

  void _queryChanged(String _) {
    setState(() {
      _cancelLookups();
      results = [];
      stops = [];
      selected = null;
      error = null;
      errorSource = null;
    });
  }

  Future<void> search() async {
    final text = searchController.text.trim();
    _cancelLookups();
    final generation = searchGeneration;
    setState(() {
      results = [];
      stops = [];
      selected = null;
      searching = text.length >= 3;
      queryHint = text.length < 3
          ? 'Enter at least 3 characters to search.'
          : null;
      error = null;
      errorSource = null;
    });
    if (text.length < 3) return;
    try {
      final position = ref.read(locationProvider).position;
      final received = await placesService.search(
        text,
        latitude: position?.latitude,
        longitude: position?.longitude,
      );
      final found = widget.sharedPlace
          ? received.where(SharedPlaceSearchArgs(text).matches).toList()
          : received;
      if (!mounted || generation != searchGeneration) return;
      setState(() {
        // A shared link without coordinates supplies a search hint, not an
        // exact pin. Let the user choose the result before confirming it.
        results = found;
        searching = false;
        emptyPlaceQuery = found.isEmpty ? text : null;
      });
    } catch (e) {
      if (!mounted || generation != searchGeneration) return;
      setState(() {
        error = e.toString();
        errorSource = _SearchErrorSource.place;
        searching = false;
      });
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
      cameraCenter = null;
      areaName = null;
      error = null;
      errorSource = null;
      searchController.clear();
      _cancelLookups();
    });
    if (next.usesStops) _loadNearby();
  }

  void _loadNearby() {
    final position = ref.read(locationProvider).position;
    if (position == null) {
      setState(() {
        _cancelLookups();
        results = [];
        stops = [];
        selected = null;
        error = 'Waiting for GPS. Search an area, or try nearby again.';
        errorSource = _SearchErrorSource.nearby;
      });
      return;
    }
    _loadStops(LatLng(position.latitude, position.longitude), 'Near me');
  }

  void _searchMapArea() {
    final center = cameraCenter ?? areaCenter;
    if (center == null) {
      _loadNearby();
      return;
    }
    _loadStops(center, 'Map area');
  }

  Future<void> _loadStops(LatLng center, String name) async {
    _cancelLookups();
    final generation = searchGeneration;
    setState(() {
      areaCenter = center;
      areaName = name;
      selected = null;
      stops = [];
      results = [];
      loadingStops = true;
      searching = false;
      error = null;
      errorSource = null;
    });
    try {
      final found = await stopsService.nearby(
        mode,
        center.latitude,
        center.longitude,
      );
      if (!mounted || generation != searchGeneration) return;
      setState(() {
        stops = found;
        loadingStops = false;
        stopsLoaded = true;
        transitNotice =
            stopsService.notice ??
            (found.length >= 20
                ? 'Showing the 20 closest results. Search a smaller area or search for a stop by name to find others.'
                : null);
      });
    } catch (e) {
      if (!mounted || generation != searchGeneration) return;
      setState(() {
        error = e.toString();
        errorSource = _SearchErrorSource.stops;
        loadingStops = false;
      });
    }
  }

  void _retrySearch() {
    switch (errorSource) {
      case _SearchErrorSource.place:
        search();
        return;
      case _SearchErrorSource.stops:
        final center = areaCenter;
        if (center != null) _loadStops(center, areaName ?? 'Map point');
        return;
      case _SearchErrorSource.nearby:
        _loadNearby();
        return;
      case null:
        break;
    }
  }

  void _selectResult(Place place) {
    FocusScope.of(context).unfocus();
    if (mode.usesStops) {
      _loadStops(LatLng(place.latitude, place.longitude), place.name);
    } else {
      setState(() {
        _cancelLookups();
        selected = place;
        sharedResultSelected = widget.sharedPlace;
        results = [];
        error = null;
        errorSource = null;
      });
    }
  }

  void _selectStop(Place place) {
    FocusScope.of(context).unfocus();
    setState(() {
      _cancelLookups();
      selected = place;
      results = [];
      error = null;
      errorSource = null;
    });
  }

  String _stopSubtitle(Place stop) {
    final center = areaCenter;
    if (center == null) return stop.address;
    final metres = const Distance()(
      center,
      LatLng(stop.latitude, stop.longitude),
    );
    final distance = metres < 1000
        ? '${metres.round()} m'
        : '${(metres / 1000).toStringAsFixed(1)} km';
    return '$distance from search point${stop.address.isEmpty ? '' : ' · ${stop.address}'}';
  }

  void selectPoint(LatLng point) {
    if (mode.usesStops) {
      _loadStops(point, 'Map point');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _cancelLookups();
      error = null;
      errorSource = null;
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
    final radius = mode.defaultAlertRadius;
    final showStopsPanel =
        mode.usesStops &&
        selected == null &&
        results.isEmpty &&
        !searching &&
        emptyPlaceQuery == null &&
        errorSource != _SearchErrorSource.place &&
        queryHint == null;
    return Scaffold(
      appBar: AppBar(title: const Text('Choose destination')),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                MapView(
                  position: position,
                  destination: selected,
                  areaCenter: areaCenter,
                  places: stops,
                  radius: radius,
                  attributionBottomInset: selected != null || showStopsPanel
                      ? 290
                      : 0,
                  onTap: selectPoint,
                  onPlaceTap: _selectStop,
                  onDestinationDrag: mode.usesStops ? null : selectPoint,
                  onCameraMove: (center) => cameraCenter = center,
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  top: 12,
                  child: Material(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: DashboardLabel('Find a destination'),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: TravelMode.values
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
                          onChanged: _queryChanged,
                          decoration: InputDecoration(
                            prefixIcon: Icon(Icons.search),
                            hintText: mode.usesStops
                                ? 'Search area for ${mode.placeName}'
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
                        if (searching) ...[
                          if (widget.sharedPlace)
                            const Padding(
                              padding: EdgeInsets.all(12),
                              child: Text(
                                'Finding the shared place…',
                                semanticsLabel:
                                    'Finding coordinates for the shared place',
                              ),
                            ),
                          const LinearProgressIndicator(),
                        ],
                        if (loadingStops) const LinearProgressIndicator(),
                        if (transitNotice != null)
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(transitNotice!),
                          ),
                        if (queryHint != null || emptyPlaceQuery != null)
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              queryHint ??
                                  (widget.sharedPlace
                                      ? 'No matching shared place found for “$emptyPlaceQuery”. Refine the address or choose the correct point on the map.'
                                      : 'No places found for “$emptyPlaceQuery”. Check the spelling or search a nearby town or landmark.'),
                            ),
                          ),
                        if (error != null)
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  error!,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                FilledButton.tonalIcon(
                                  onPressed: errorSource == null
                                      ? null
                                      : _retrySearch,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Retry search'),
                                ),
                              ],
                            ),
                          ),
                        if (results.isNotEmpty && widget.sharedPlace)
                          const Padding(
                            padding: EdgeInsets.all(12),
                            child: Text(
                              'Select the matching place to view its coordinates.',
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
                if (showStopsPanel)
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: DashboardPanel(
                      child: SizedBox(
                        height: 245,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${mode.placeName} · ${areaName ?? 'Choose an area'}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: _loadNearby,
                                    child: const Text('Near me'),
                                  ),
                                ],
                              ),
                            ),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: loadingStops ? null : _searchMapArea,
                                icon: const Icon(Icons.travel_explore),
                                label: const Text('Search this area'),
                              ),
                            ),
                            Expanded(
                              child: stops.isEmpty
                                  ? SingleChildScrollView(
                                      padding: const EdgeInsets.all(12),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            loadingStops
                                                ? 'Finding mapped stops…'
                                                : error != null
                                                ? 'Could not load stops in this area.'
                                                : !stopsLoaded
                                                ? 'Search an area or tap the map.'
                                                : 'No mapped ${mode.placeName.toLowerCase()} found within 5 km. Search another area or tap a different point on the map.',
                                            textAlign: TextAlign.center,
                                          ),
                                        ],
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
                                                : mode == TravelMode.metro
                                                ? Icons.subway
                                                : Icons.train,
                                          ),
                                          title: Text(stop.name),
                                          subtitle: Text(_stopSubtitle(stop)),
                                          trailing: const Icon(
                                            Icons.chevron_right,
                                          ),
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
                    child: DashboardPanel(
                      accent: Theme.of(context).colorScheme.primary,
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
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
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
                            onPressed: () {
                              final selection = AlarmSetupArgs(
                                place: selected!,
                                mode: mode,
                              );
                              if (widget.returnSelection) {
                                context.pop(selection);
                              } else {
                                context.push('/setup', extra: selection);
                              }
                            },
                            child: const Text('Confirm destination'),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            sharedResultSelected
                                ? 'Found from the shared place. Check the pin before confirming. You can drag it to adjust the location.'
                                : mode.usesStops
                                ? 'Tap another stop on the map, or tap the map to search another area.'
                                : 'Tap the map or drag the pin to move it.',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
