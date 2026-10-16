import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../models/place.dart';

class SharedLocationService {
  SharedLocationService({
    HttpClient Function()? clientFactory,
    this.lookupTimeout = const Duration(seconds: 12),
  }) : _clientFactory = clientFactory ?? HttpClient.new;

  final HttpClient Function() _clientFactory;
  final Duration lookupTimeout;
  _ShareLookup? _lookup;

  /// Ends the lookup immediately, including a stalled connection or response.
  void cancel() {
    final lookup = _lookup;
    if (lookup == null) return;
    if (!lookup.cancelled.isCompleted) lookup.cancelled.complete((null, null));
    lookup.client.close(force: true);
    _lookup = null;
  }

  static const channel = MethodChannel('tracker_alarm/share');
  String? resolvedQuery;

  Future<String?> takePendingShare() =>
      channel.invokeMethod<String>('takePendingShare');

  /// Resolved Maps place/address is more specific than Android's shared title.
  String? fallbackQuery(String text) => resolvedQuery ?? searchQuery(text);

  String? searchQuery(String text) {
    final withoutLinks = text.replaceAll(RegExp(r'https?://[^\s]+'), '').trim();
    if (withoutLinks.isEmpty) return null;
    final lines = withoutLinks
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty);
    if (lines.isEmpty) return null;
    return lines.take(2).join(', ');
  }

  Future<Place?> parse(String text) async {
    cancel();
    resolvedQuery = null;
    final direct = _placeFromText(text);
    if (direct != null) return direct;

    final link = RegExp(r'https?://[^\s]+').firstMatch(text)?.group(0);
    if (link == null) return null;
    final uri = Uri.tryParse(link);
    if (uri == null) return null;
    if (_isGoogleMapsLink(uri) && !_isGoogleShortLink(uri)) {
      resolvedQuery = queryFromMapsUrl(uri);
      return null;
    }
    if (!_isGoogleShortLink(uri)) return null;

    final lookup = _ShareLookup(_clientFactory());
    _lookup = lookup;
    lookup.client.connectionTimeout = lookupTimeout;
    try {
      final result = await Future.any([
        _resolve(lookup.client, uri),
        lookup.cancelled.future,
      ]).timeout(lookupTimeout, onTimeout: () => (null, null));
      if (!identical(_lookup, lookup)) return null;
      resolvedQuery = result.$2;
      return result.$1;
    } finally {
      lookup.client.close(force: true);
      if (identical(_lookup, lookup)) _lookup = null;
    }
  }

  Future<(Place?, String?)> _resolve(HttpClient client, Uri uri) async {
    try {
      var current = uri;
      for (var hop = 0; hop <= 5; hop++) {
        // Inspect each Location header before following it. Once a useful Maps
        // destination is known, consent pages and stalled final responses must
        // not discard it or consume the remaining lookup deadline.
        final request = await client.getUrl(current);
        request.followRedirects = false;
        final response = await request.close();
        final location = response.headers.value(HttpHeaders.locationHeader);
        if (response.statusCode < 300 ||
            response.statusCode >= 400 ||
            location == null) {
          return (null, null);
        }
        final next = current.resolve(location);
        if (!_isGoogleMapsLink(next) && !_isGoogleShortLink(next)) {
          return (null, null);
        }
        final place = _placeFromText(next.toString());
        final query = place == null ? queryFromMapsUrl(next) : null;
        if (place != null || query != null) return (place, query);
        current = next;
      }
      return (null, null);
    } on Exception {
      return (null, null);
    }
  }

  bool _isGoogleShortLink(Uri uri) =>
      uri.scheme == 'https' &&
      (uri.host == 'maps.app.goo.gl' ||
          (uri.host == 'goo.gl' && uri.path.startsWith('/maps/')));

  bool _isGoogleMapsLink(Uri uri) =>
      uri.scheme == 'https' &&
      (uri.host == 'maps.google.com' ||
          uri.host == 'www.google.com' ||
          uri.host == 'google.com' ||
          uri.host == 'maps.app.goo.gl');

  String? queryFromMapsUrl(Uri uri) {
    if (!_isGoogleMapsLink(uri)) return null;
    // pathSegments/queryParameters decode percent escapes once.
    final segments = uri.pathSegments;
    final placeIndex = segments.indexOf('place');
    final name =
        placeIndex >= 0 && placeIndex + 1 < segments.length
            ? segments[placeIndex + 1].replaceAll('+', ' ')
            : null;
    final value =
        name ?? uri.queryParameters['query'] ?? uri.queryParameters['q'];
    if (value == null) return null;
    final query = value.trim();
    return query.isEmpty ? null : query;
  }

  Place? _placeFromText(String text) {
    String decoded;
    try {
      decoded = Uri.decodeComponent(text);
    } on FormatException {
      decoded = text;
    }
    final coordinates = _coordinates(decoded);
    if (coordinates == null) return null;
    final link = RegExp(r'https?://[^\s]+').firstMatch(text)?.group(0);
    final prefix =
        link == null ? '' : text.substring(0, text.indexOf(link)).trim();
    final placePath = RegExp(r'/place/([^/@?]+)').firstMatch(decoded)?.group(1);
    final name =
        prefix.isNotEmpty
            ? prefix.split('\n').first.trim()
            : placePath == null
            ? 'Shared location'
            : placePath.replaceAll('+', ' ');
    return Place(
      name: name.isEmpty ? 'Shared location' : name,
      address:
          '${coordinates.$1.toStringAsFixed(6)}, ${coordinates.$2.toStringAsFixed(6)}',
      latitude: coordinates.$1,
      longitude: coordinates.$2,
    );
  }

  (double, double)? _coordinates(String text) {
    const number = r'(-?\d{1,2}(?:\.\d+)?)';
    const longitude = r'(-?\d{1,3}(?:\.\d+)?)';
    final pair = '$number\\s*,\\s*$longitude';
    final encoded = RegExp('!3d$number!4d$longitude');
    // @ and ll describe the camera/viewport, not necessarily the selected pin.
    // Query coordinates and embedded place coordinates are explicit targets.
    final tagged = RegExp('[?&](?:q|query|destination)=$pair');
    final placePath = RegExp(
      '/place/$pair'
      r'(?:/|[?&#]|$)',
    );
    final geo = RegExp(
      '^geo:$pair'
      r'(?:[;?]|$)',
    );
    final plain = RegExp('^\\s*$pair\\s*\$');
    final match =
        encoded.firstMatch(text) ??
        tagged.firstMatch(text) ??
        placePath.firstMatch(text) ??
        geo.firstMatch(text) ??
        plain.firstMatch(text);
    if (match == null) return null;
    final lat = double.tryParse(match.group(1)!);
    final lng = double.tryParse(match.group(2)!);
    if (lat == null || lng == null || lat.abs() > 90 || lng.abs() > 180) {
      return null;
    }
    return (lat, lng);
  }
}

class _ShareLookup {
  _ShareLookup(this.client);

  final HttpClient client;
  final cancelled = Completer<(Place?, String?)>();
}
