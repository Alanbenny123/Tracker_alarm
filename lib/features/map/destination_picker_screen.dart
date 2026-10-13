import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../models/place.dart';
import '../../providers/app_providers.dart';
import '../../services/places_service.dart';
import 'map_view.dart';

class DestinationPickerScreen extends ConsumerStatefulWidget {
  const DestinationPickerScreen({super.key, this.initialQuery});
  final String? initialQuery;
  @override
  ConsumerState<DestinationPickerScreen> createState() =>
      _DestinationPickerScreenState();
}

class _DestinationPickerScreenState
    extends ConsumerState<DestinationPickerScreen> {
  final searchController = TextEditingController();
  final placesService = PlacesService();
  int searchGeneration = 0;
  List<Place> results = [];
  Place? selected;
  String? error;
  bool searching = false;

  @override
  void initState() {
    super.initState();
    final query = widget.initialQuery;
    if (query != null) {
      searchController.text = query;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) search();
      });
    }
  }

  @override
  void dispose() {
    searchController.dispose();
    placesService.dispose();
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
          searching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          if (generation == searchGeneration) error = e.toString();
          searching = false;
        });
      }
    }
  }

  void selectPoint(LatLng point) {
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
            radius: radius,
            onTap: selectPoint,
            onDestinationDrag: selectPoint,
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
                  TextField(
                    controller: searchController,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => search(),
                    onChanged: (_) {
                      searchGeneration++;
                      setState(() {
                        results = [];
                        error = null;
                      });
                    },
                    decoration: InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search for a place',
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
                      height: 280,
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
                            onTap: () {
                              setState(() {
                                selected = place;
                                results = [];
                              });
                              FocusScope.of(context).unfocus();
                            },
                          );
                        },
                      ),
                    ),
                ],
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
                      const Text(
                        'Tap the map or drag the pin to move it.',
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
