import 'dart:async';

import 'package:flutter/services.dart';

import '../models/place.dart';

class PlacesService {
  PlacesService({
    DateTime Function()? clock,
    this.rateLimitRetryDelay = const Duration(milliseconds: 1300),
  }) : _now = clock ?? DateTime.now;

  static const _channel = MethodChannel('tracker_alarm/places');
  final DateTime Function() _now;
  final Duration rateLimitRetryDelay;
  final Map<String, (DateTime, List<Place>)> _cache = {};
  Completer<List<Place>>? _pending;

  void cancel() {
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted) pending.complete([]);
  }

  Future<List<Place>> search(
    String query, {
    double? latitude,
    double? longitude,
  }) async {
    cancel();
    final text = query.trim();
    if (text.length < 3) return [];
    final hasBias =
        latitude != null &&
        longitude != null &&
        latitude.isFinite &&
        longitude.isFinite &&
        latitude.abs() <= 90 &&
        longitude.abs() <= 180;
    final key =
        '${text.toLowerCase()}:${hasBias ? latitude.toStringAsFixed(2) : ''}:'
        '${hasBias ? longitude.toStringAsFixed(2) : ''}';
    final cached = _cache[key];
    if (cached != null) {
      final age = _now().difference(cached.$1);
      if (age >= Duration.zero && age < const Duration(minutes: 10)) {
        return cached.$2;
      }
      _cache.remove(key);
    }
    final pending = Completer<List<Place>>();
    _pending = pending;
    try {
      // Ignore a replaced native Places callback; it may already be in flight.
      final places = await Future.any([
        _search(
          text,
          pending: pending,
          latitude: hasBias ? latitude : null,
          longitude: hasBias ? longitude : null,
        ),
        pending.future,
      ]);
      if (!identical(_pending, pending)) return [];
      final cachedPlaces = List<Place>.unmodifiable(places);
      _cache[key] = (_now(), cachedPlaces);
      if (_cache.length > 64) _cache.remove(_cache.keys.first);
      return cachedPlaces;
    } finally {
      if (identical(_pending, pending)) _pending = null;
    }
  }

  Future<List<Place>> _search(
    String text, {
    required Completer<List<Place>> pending,
    double? latitude,
    double? longitude,
  }) async {
    try {
      Future<List<dynamic>?> request() => _channel
          .invokeMethod<List<dynamic>>('search', {
            'query': text,
            if (latitude != null && longitude != null) ...{
              'latitude': latitude,
              'longitude': longitude,
            },
          })
          .timeout(const Duration(seconds: 12));
      List<dynamic>? response;
      try {
        response = await request();
      } on PlatformException catch (e) {
        if (e.code != 'rate_limit') rethrow;
        await Future<void>.delayed(rateLimitRetryDelay);
        if (!identical(_pending, pending)) return [];
        response = await request();
      }
      final places = (response ?? [])
          .map(
            (item) => Place.fromJson({
              ...Map<String, dynamic>.from(item as Map),
              'googleFetchedAt': _now().toIso8601String(),
            }),
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
