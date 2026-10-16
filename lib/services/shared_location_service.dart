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
    if (uri == null || !_isGoogleShortLink(uri)) return null;

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
      final request = await client.getUrl(uri);
      request.followRedirects = true;
      request.maxRedirects = 5;
      final response = await request.close();
      var resolved = uri;
      for (final redirect in response.redirects) {
        resolved = resolved.resolveUri(redirect.location);
      }
      // Only redirect headers are needed. Do not wait for a Maps HTML body.
      if (!_isGoogleMapsLink(resolved)) return (null, null);
      final place = _placeFromText(resolved.toString());
      return (place, place == null ? queryFromMapsUrl(resolved) : null);
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
    final match = RegExp(r'/place/([^/]+)').firstMatch(uri.path);
    if (match == null) return null;
    final query =
        Uri.decodeComponent(match.group(1)!).replaceAll('+', ' ').trim();
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
            : Uri.decodeComponent(placePath).replaceAll('+', ' ');
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
    final tagged = RegExp('(?:@|[?&](?:q|query|ll|destination)=|geo:)$pair');
    final plain = RegExp('^\\s*$pair\\s*\$');
    final match =
        encoded.firstMatch(text) ??
        tagged.firstMatch(text) ??
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
