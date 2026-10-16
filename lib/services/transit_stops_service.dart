import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import '../models/place.dart';
import '../models/travel_mode.dart';

class TransitStopsService {
  TransitStopsService({HttpClient Function()? clientFactory})
    : _clientFactory = clientFactory ?? HttpClient.new;

  final HttpClient Function() _clientFactory;
  _StopLookup? _lookup;

  void cancel() {
    final lookup = _lookup;
    _lookup = null;
    if (lookup == null) return;
    if (!lookup.cancelled.isCompleted) lookup.cancelled.complete([]);
    lookup.client.close(force: true);
  }

  final Map<String, (DateTime, List<Place>)> _cache = {};
  static const _endpoint = 'https://overpass-api.de/api/interpreter';

  Future<List<Place>> nearby(
    TravelMode mode,
    double latitude,
    double longitude,
  ) async {
    cancel();
    if (!mode.usesStops) return [];
    final cacheKey =
        '${mode.name}:${(latitude * 1000).round()}:${(longitude * 1000).round()}';
    final cached = _cache[cacheKey];
    if (cached != null &&
        DateTime.now().difference(cached.$1) < const Duration(minutes: 10)) {
      return cached.$2;
    }
    final lookup = _StopLookup(_clientFactory());
    _lookup = lookup;
    lookup.client.connectionTimeout = const Duration(seconds: 12);
    try {
      final places = await Future.any([
        _search(lookup.client, mode, latitude, longitude),
        lookup.cancelled.future,
      ]).timeout(const Duration(seconds: 50));
      if (!identical(_lookup, lookup)) return [];
      _cache[cacheKey] = (DateTime.now(), places);
      return places;
    } on TimeoutException {
      throw const TransitStopsException(
        'Stop search timed out. Retry in a moment.',
      );
    } finally {
      lookup.client.close(force: true);
      if (identical(_lookup, lookup)) _lookup = null;
    }
  }

  Future<List<Place>> _search(
    HttpClient client,
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
    final query = '[out:json][timeout:15];($filter);out center 200;';
    try {
      for (var attempt = 0; attempt < 2; attempt++) {
        final request = await client
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
          await response.drain<void>().timeout(const Duration(seconds: 3));
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
        final places = parseTransitStops(jsonDecode(utf8.decode(bytes)), mode);
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
    _cache.clear();
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
  HttpStatus.badRequest || HttpStatus.notAcceptable =>
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
