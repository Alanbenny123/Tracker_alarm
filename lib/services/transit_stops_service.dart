import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import '../models/place.dart';
import '../models/travel_mode.dart';

class TransitStopsService {
  TransitStopsService({
    HttpClient Function()? clientFactory,
    TransitStopsCache? cache,
  }) : _clientFactory = clientFactory ?? HttpClient.new,
       _cache = cache ?? _sharedCache;

  static final _sharedCache = TransitStopsCache();
  final TransitStopsCache _cache;
  String? notice;

  final HttpClient Function() _clientFactory;
  _StopLookup? _lookup;

  void cancel() {
    final lookup = _lookup;
    _lookup = null;
    if (lookup == null) return;
    if (!lookup.cancelled.isCompleted) lookup.cancelled.complete([]);
    lookup.client.close(force: true);
  }

  static const _endpoint = 'https://overpass-api.de/api/interpreter';

  Future<List<Place>> nearby(
    TravelMode mode,
    double latitude,
    double longitude,
  ) async {
    cancel();
    notice = null;
    if (!latitude.isFinite ||
        !longitude.isFinite ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      throw const TransitStopsException('Choose a valid map location.');
    }
    if (!mode.usesStops) return [];
    final cacheKey =
        '${mode.name}:${latitude.toStringAsFixed(4)}:${longitude.toStringAsFixed(4)}';
    final cached = _cache.read(cacheKey);
    if (cached != null &&
        _cache.now().difference(cached.$1) < const Duration(minutes: 10)) {
      return cached.$2;
    }
    final retryAt = _cache.retryAt;
    if (retryAt != null && retryAt.isAfter(_cache.now())) {
      if (cached != null && cached.$2.isNotEmpty) return _useSaved(cached);
      final seconds = retryAt.difference(_cache.now()).inSeconds + 1;
      throw TransitStopsException(
        'Stop search is cooling down. Retry in $seconds seconds.',
      );
    }
    final lookup = _StopLookup(_clientFactory());
    _lookup = lookup;
    lookup.client.connectionTimeout = const Duration(seconds: 12);
    try {
      final places = await Future.any([
        _search(lookup, mode, latitude, longitude),
        lookup.cancelled.future,
      ]).timeout(const Duration(seconds: 50));
      if (!identical(_lookup, lookup)) return [];
      _cache.save(cacheKey, places);
      return places;
    } on TimeoutException {
      if (!identical(_lookup, lookup)) return [];
      if (cached != null && cached.$2.isNotEmpty) return _useSaved(cached);
      throw const TransitStopsException(
        'Stop search timed out. Retry in a moment.',
      );
    } on TransitStopsException {
      if (!identical(_lookup, lookup)) return [];
      if (cached != null && cached.$2.isNotEmpty) return _useSaved(cached);
      rethrow;
    } finally {
      if (!lookup.cancelled.isCompleted) lookup.cancelled.complete([]);
      lookup.client.close(force: true);
      if (identical(_lookup, lookup)) _lookup = null;
    }
  }

  List<Place> _useSaved((DateTime, List<Place>) cached) {
    final minutes = _cache.now().difference(cached.$1).inMinutes;
    notice =
        'Showing cached stops from $minutes minutes ago. Search is unavailable; stop data may have changed.';
    return cached.$2;
  }

  Future<List<Place>> _search(
    _StopLookup lookup,
    TravelMode mode,
    double latitude,
    double longitude,
  ) async {
    final radius = mode == TravelMode.railway ? 5000 : 2500;
    final filter = switch (mode) {
      TravelMode.bus =>
        'nwr["highway"="bus_stop"](around:$radius,$latitude,$longitude);'
            'nwr["public_transport"="platform"]["bus"="yes"](around:$radius,$latitude,$longitude);',
      TravelMode.metro =>
        'nwr["railway"="station"]["station"="subway"](around:$radius,$latitude,$longitude);'
            'nwr["railway"="station"]["subway"="yes"](around:$radius,$latitude,$longitude);'
            'nwr["public_transport"="station"]["subway"="yes"](around:$radius,$latitude,$longitude);',
      TravelMode.railway =>
        'nwr["railway"="station"](around:$radius,$latitude,$longitude);'
            'nwr["railway"="halt"](around:$radius,$latitude,$longitude);'
            'nwr["public_transport"="station"]["train"="yes"](around:$radius,$latitude,$longitude);',
      TravelMode.other => '',
    };
    final namedFilter = filter.replaceAll('(around:', '["name"](around:');
    final query = '[out:json][timeout:15];($namedFilter);out center 200;';
    try {
      for (var attempt = 0; attempt < 2; attempt++) {
        if (lookup.cancelled.isCompleted) return [];
        final request = await lookup.client
            .postUrl(Uri.parse(_endpoint))
            .timeout(const Duration(seconds: 12));
        request.headers.contentType = ContentType(
          'application',
          'x-www-form-urlencoded',
          charset: 'utf-8',
        );
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        request.headers.set(
          HttpHeaders.userAgentHeader,
          'DestinationAlarm/1.0 (Android; OSM transit stop lookup)',
        );
        request.write('data=${Uri.encodeQueryComponent(query)}');
        final response = await request.close().timeout(
          const Duration(seconds: 22),
        );
        if (response.statusCode != HttpStatus.ok) {
          final status = response.statusCode;
          if (status == HttpStatus.tooManyRequests ||
              status == HttpStatus.notAcceptable) {
            final retry = response.headers.value(HttpHeaders.retryAfterHeader);
            final seconds = int.tryParse(retry ?? '');
            DateTime? deadline;
            if (seconds != null && seconds >= 0) {
              deadline = _cache.now().add(Duration(seconds: seconds));
            }
            if (deadline == null && retry != null) {
              try {
                deadline = HttpDate.parse(retry);
              } on FormatException {
                /* Use the minimum cooldown. */
              }
            }
            final minimum = _cache.now().add(const Duration(seconds: 30));
            _cache.retryAt =
                deadline != null && deadline.isAfter(minimum)
                    ? deadline
                    : minimum;
          }
          await response.drain<void>().timeout(const Duration(seconds: 3));
          if ((status == HttpStatus.tooManyRequests ||
                  status == HttpStatus.notAcceptable) &&
              _cache.retryAt != null) {
            final seconds =
                _cache.retryAt!.difference(_cache.now()).inSeconds + 1;
            throw TransitStopsException(
              'Stop search is busy. Retry in $seconds seconds.',
            );
          }
          if (attempt == 0 &&
              (status == HttpStatus.badGateway ||
                  status == HttpStatus.serviceUnavailable ||
                  status == HttpStatus.gatewayTimeout)) {
            await Future<void>.delayed(const Duration(seconds: 2));
            continue;
          }
          throw TransitStopsException(_statusMessage(status));
        }
        final bytes = <int>[];
        await for (final chunk in response.timeout(
          const Duration(seconds: 22),
        )) {
          bytes.addAll(chunk);
          if (bytes.length > 2 * 1024 * 1024) {
            throw const TransitStopsException(
              'Too many stops returned. Search a smaller area.',
            );
          }
        }
        final body = jsonDecode(utf8.decode(bytes));
        if (body is! Map ||
            body['elements'] is! List ||
            body['remark'] != null) {
          throw const TransitStopsException(
            'Stop search returned incomplete results. Retry later.',
          );
        }
        final places = parseTransitStops(body, mode);
        places.sort(
          (a, b) => _roughDistanceMetresTo(
            latitude,
            longitude,
            a,
          ).compareTo(_roughDistanceMetresTo(latitude, longitude, b)),
        );
        return places;
      }
      throw const TransitStopsException(
        'Stop search is unavailable. Retry in a moment.',
      );
    } on TransitStopsException {
      rethrow;
    } on TimeoutException {
      throw const TransitStopsException(
        'Stop search timed out. Retry in a moment.',
      );
    } on SocketException {
      throw const TransitStopsException(
        'Connect to the internet to find stops.',
      );
    } on HandshakeException {
      throw const TransitStopsException('Could not connect to stop search.');
    } on HttpException {
      throw const TransitStopsException(
        'Stop search is unavailable. Try again.',
      );
    } on FormatException {
      throw const TransitStopsException(
        'Could not read stop results. Try again.',
      );
    } catch (_) {
      throw const TransitStopsException(
        'Could not load stops. Check your connection and try again.',
      );
    }
  }

  void dispose() {
    cancel();
  }
}

/// Bounded process-memory cache shared across picker visits. Nothing is uploaded
/// or written to disk, and expired results cannot be used indefinitely offline.
class TransitStopsCache {
  TransitStopsCache({DateTime Function()? clock}) : now = clock ?? DateTime.now;
  final DateTime Function() now;
  final _entries = <String, (DateTime, List<Place>)>{};
  DateTime? retryAt;

  (DateTime, List<Place>)? read(String key) {
    _entries.removeWhere(
      (_, value) => now().difference(value.$1) >= const Duration(hours: 24),
    );
    return _entries[key];
  }

  void save(String key, List<Place> places) {
    _entries.remove(key);
    _entries[key] = (now(), List<Place>.unmodifiable(places));
    while (_entries.length > 64) {
      _entries.remove(_entries.keys.first);
    }
  }
}

class _StopLookup {
  _StopLookup(this.client);
  final HttpClient client;
  final cancelled = Completer<List<Place>>();
}

String _statusMessage(int status) => switch (status) {
  HttpStatus.tooManyRequests =>
    'Too many stop searches right now. Wait a minute, then retry.',
  HttpStatus.badGateway ||
  HttpStatus.serviceUnavailable ||
  HttpStatus.gatewayTimeout => 'Stop search server is busy. Retry in a moment.',
  HttpStatus.notAcceptable =>
    'Stop search asked us to wait. Retry after 30 seconds.',
  HttpStatus.badRequest =>
    'Stop search request was rejected. Please update the app.',
  _ => 'Stop search is unavailable (HTTP $status). Retry later.',
};

class TransitStopsException implements Exception {
  const TransitStopsException(this.message);
  final String message;
  @override
  String toString() => message;
}

List<Place> parseTransitStops(Object? body, TravelMode mode) {
  if (body is! Map || body['elements'] is! List) return [];
  final places = <Place>[];
  for (final item in body['elements'] as List) {
    if (item is! Map || item['tags'] is! Map) continue;
    final tags = item['tags'] as Map;
    if (mode == TravelMode.railway &&
        (tags['subway'] == 'yes' ||
            tags['light_rail'] == 'yes' ||
            tags['station'] == 'subway' ||
            tags['station'] == 'light_rail')) {
      continue;
    }
    final name =
        tags['name'] is String ? (tags['name'] as String).trim() : null;
    if (name == null || name.isEmpty) continue;
    final center = item['center'];
    final lat = item['lat'] ?? (center is Map ? center['lat'] : null);
    final lon = item['lon'] ?? (center is Map ? center['lon'] : null);
    if (lat is! num || lon is! num) continue;
    if (lat < -90 || lat > 90 || lon < -180 || lon > 180) continue;
    final place = Place(
      id: 'osm:${item['type']}:${item['id']}',
      name: name,
      address: switch (mode) {
        TravelMode.bus => 'Bus stop',
        TravelMode.metro => 'Metro station',
        TravelMode.railway => 'Railway station',
        TravelMode.other => 'Place',
      },
      latitude: lat.toDouble(),
      longitude: lon.toDouble(),
    );
    // Platforms and stations can be mapped several times at the same place.
    final duplicate = places.any(
      (other) =>
          other.name.toLowerCase() == name.toLowerCase() &&
          _roughDistanceMetres(other, place) <
              (mode == TravelMode.bus ? 80 : 350),
    );
    if (!duplicate) places.add(place);
  }
  return places;
}

double _roughDistanceMetres(Place a, Place b) {
  final north = (a.latitude - b.latitude) * 111000;
  final east =
      (a.longitude - b.longitude) *
      111000 *
      _cosLatitude((a.latitude + b.latitude) / 2);
  return math.sqrt(north * north + east * east);
}

double _roughDistanceMetresTo(double lat, double lon, Place place) =>
    _roughDistanceMetres(
      Place(name: '', address: '', latitude: lat, longitude: lon),
      place,
    );

// This estimate is only used for de-duplicating very close OSM objects.
double _cosLatitude(double degrees) => math.cos(degrees * 0.017453292519943295);
