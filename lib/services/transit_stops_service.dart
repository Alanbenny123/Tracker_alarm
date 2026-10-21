import 'dart:async';

import 'package:flutter/services.dart';

import '../models/place.dart';
import '../models/travel_mode.dart';

class TransitStopsService {
  TransitStopsService({
    DateTime Function()? clock,
    this.rateLimitRetryDelay = const Duration(milliseconds: 1300),
  }) : _now = clock ?? DateTime.now;

  static const _channel = MethodChannel('tracker_alarm/places');
  static final _cache = <String, (DateTime, List<Place>)>{};
  final DateTime Function() _now;
  final Duration rateLimitRetryDelay;
  Completer<List<Place>>? _pending;
  String? notice;

  void cancel() {
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted) pending.complete([]);
  }

  Future<List<Place>> nearby(
    TravelMode mode,
    double latitude,
    double longitude,
  ) async {
    cancel();
    notice = null;
    if (!mode.usesStops) return [];
    if (!latitude.isFinite ||
        !longitude.isFinite ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      throw const TransitStopsException('Choose a valid map location.');
    }
    final key =
        '${mode.name}:${latitude.toStringAsFixed(4)}:${longitude.toStringAsFixed(4)}';
    final cached = _cache[key];
    if (cached != null &&
        _now().difference(cached.$1) < const Duration(minutes: 10)) {
      return cached.$2;
    }
    final pending = Completer<List<Place>>();
    _pending = pending;
    try {
      final places = await Future.any([
        _fetch(mode, latitude, longitude, pending),
        pending.future,
      ]);
      if (!identical(_pending, pending)) return [];
      _cache[key] = (_now(), List.unmodifiable(places));
      if (_cache.length > 64) _cache.remove(_cache.keys.first);
      return places;
    } on TransitStopsException {
      if (cached != null &&
          _now().difference(cached.$1) < const Duration(hours: 24)) {
        notice =
            'Showing recent saved stops. Search is temporarily unavailable.';
        return cached.$2;
      }
      rethrow;
    } finally {
      if (identical(_pending, pending)) _pending = null;
    }
  }

  Future<List<Place>> _fetch(
    TravelMode mode,
    double latitude,
    double longitude,
    Completer<List<Place>> pending,
  ) async {
    try {
      Future<List<dynamic>?> request() => _channel
          .invokeMethod<List<dynamic>>('nearbyStops', {
            'mode': mode.name,
            'latitude': latitude,
            'longitude': longitude,
          })
          .timeout(const Duration(seconds: 20));
      List<dynamic>? response;
      try {
        response = await request();
      } on PlatformException catch (e) {
        if (e.code != 'rate_limit') rethrow;
        await Future<void>.delayed(rateLimitRetryDelay);
        if (!identical(_pending, pending)) return [];
        response = await request();
      }
      return (response ?? [])
          .map(
            (item) => Place.fromJson({
              ...Map<String, dynamic>.from(item as Map),
              'googleFetchedAt': _now().toIso8601String(),
            }),
          )
          .toList();
    } on PlatformException catch (e) {
      throw TransitStopsException(
        e.message ?? 'Stop search failed. Try again.',
      );
    } on MissingPluginException {
      throw const TransitStopsException(
        'Stop search is available on Android devices.',
      );
    } on TimeoutException {
      throw const TransitStopsException(
        'Stop search timed out. Retry in a moment.',
      );
    }
  }

  void dispose() => cancel();
}

class TransitStopsException implements Exception {
  const TransitStopsException(this.message);
  final String message;
  @override
  String toString() => message;
}
