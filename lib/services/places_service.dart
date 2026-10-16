import 'dart:async';
import 'package:flutter/services.dart';
import '../models/place.dart';

class PlacesService {
  static const _channel = MethodChannel('tracker_alarm/places');
  final Map<String, List<Place>> _cache = {};
  Completer<List<Place>>? _pending;

  void cancel() {
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted) pending.complete([]);
  }

  Future<List<Place>> search(String query) async {
    cancel();
    final text = query.trim();
    if (text.length < 3) return [];
    final key = text.toLowerCase();
    if (_cache.containsKey(key)) return _cache[key]!;
    final pending = Completer<List<Place>>();
    _pending = pending;
    try {
      // Android Geocoder has no cancel API. Ignore its eventual callback after
      // replacement/disposal, and complete the Dart lookup immediately.
      final places = await Future.any([_search(text), pending.future]);
      if (!identical(_pending, pending)) return [];
      _cache[key] = places;
      return places;
    } finally {
      if (identical(_pending, pending)) _pending = null;
    }
  }

  Future<List<Place>> _search(String text) async {
    try {
      final response = await _channel
          .invokeMethod<List<dynamic>>('search', {'query': text})
          .timeout(const Duration(seconds: 12));
      final places =
          (response ?? [])
              .map(
                (item) =>
                    Place.fromJson(Map<String, dynamic>.from(item as Map)),
              )
              .toList();
      return places;
    } on PlatformException catch (e) {
      throw Exception(
        e.message ?? 'Place search is unavailable on this device.',
      );
    } on MissingPluginException {
      throw Exception('Place search is available on Android devices.');
    } on TimeoutException {
      throw Exception(
        'Place search timed out. Check your connection or tap the map.',
      );
    }
  }

  void dispose() {
    cancel();
    _cache.clear();
  }
}
