import 'dart:io';

import 'package:flutter/services.dart';

import '../models/place.dart';

class SharedLocationService {
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
    resolvedQuery = null;
    final direct = _placeFromText(text);
    if (direct != null) return direct;

    final link = RegExp(r'https?://[^\s]+').firstMatch(text)?.group(0);
    if (link == null) return null;
    final uri = Uri.tryParse(link);
    if (uri == null || !_isGoogleShortLink(uri)) return null;

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 8));
      request.followRedirects = true;
      request.maxRedirects = 5;
      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      var resolved = uri;
      for (final redirect in response.redirects) {
        resolved = resolved.resolveUri(redirect.location);
      }
      await response.drain<void>();
      if (!_isGoogleMapsLink(resolved)) return null;
      final place = _placeFromText(resolved.toString());
      if (place == null) resolvedQuery = queryFromMapsUrl(resolved);
      return place;
    } on Exception {
      return null;
    } finally {
      client.close(force: true);
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
