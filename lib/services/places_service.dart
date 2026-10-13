import 'dart:async';
import 'package:flutter/services.dart';
import '../models/place.dart';

class PlacesService {
  static const _channel = MethodChannel('tracker_alarm/places');
  final Map<String, List<Place>> _cache = {};

  Future<List<Place>> search(String query) async {
    final text = query.trim();
    if (text.length < 3) return [];
    final key = text.toLowerCase();
    if (_cache.containsKey(key)) return _cache[key]!;
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
      _cache[key] = places;
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

  void dispose() => _cache.clear();
}
