import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';

import '../models/place.dart';
import '../models/travel_mode.dart';

const defaultOfflinePackCatalogUrl =
    'https://raw.githubusercontent.com/Alanbenny123/offline_maps/main/offline-packs/catalog.json';

@immutable
class OfflinePackListing {
  const OfflinePackListing({
    required this.id,
    required this.name,
    required this.url,
  });

  final String id;
  final String name;
  final Uri url;

  static List<OfflinePackListing> parseCatalog(Object? data) {
    if (data is! Map<String, dynamic> ||
        data['schema'] != 1 ||
        data['packs'] is! List) {
      throw const FormatException('Invalid offline map catalog');
    }
    final entries = data['packs'] as List;
    if (entries.length > 500) {
      throw const FormatException('Offline map catalog is too large');
    }
    final seen = <String>{};
    return entries.map((item) {
      if (item is! Map<String, dynamic> ||
          item['id'] is! String ||
          item['name'] is! String ||
          item['url'] is! String) {
        throw const FormatException('Invalid offline map listing');
      }
      final id = item['id'] as String;
      final name = item['name'] as String;
      final url = Uri.tryParse(item['url'] as String);
      if (!RegExp(r'^[a-z0-9][a-z0-9_-]{1,63}$').hasMatch(id) ||
          !seen.add(id) ||
          name.trim().isEmpty ||
          url == null ||
          url.scheme != 'https' ||
          url.host.isEmpty) {
        throw const FormatException('Invalid offline map listing');
      }
      return OfflinePackListing(id: id, name: name.trim(), url: url);
    }).toList();
  }
}

/// A versioned archive of OpenStreetMap-derived data. Google content must
/// never be put in these packs. The expected ZIP layout is:
/// pack.json, places.json, tiles/{z}/{x}/{y}.png.
@immutable
class OfflinePack {
  const OfflinePack({
    required this.id,
    required this.name,
    required this.directory,
    required this.south,
    required this.west,
    required this.north,
    required this.east,
    required this.minZoom,
    required this.maxZoom,
    required this.tileMaxZoom,
    required this.placeCount,
    this.coverage = const [],
  });

  final String id;
  final String name;
  final Directory directory;
  final double south;
  final double west;
  final double north;
  final double east;
  final int minZoom;
  final int maxZoom;
  final int tileMaxZoom;
  final int placeCount;
  final List<OfflineCoveragePolygon> coverage;

  bool contains(double latitude, double longitude) {
    if (latitude < south ||
        latitude > north ||
        longitude < west ||
        longitude > east) {
      return false;
    }
    return coverage.isEmpty ||
        coverage.any((polygon) => polygon.contains(latitude, longitude));
  }

  String get tileTemplate => '${directory.path}/tiles/{z}/{x}/{y}.png';

  static OfflinePack fromJson(Map<String, dynamic> json, Directory directory) {
    final id = json['id'];
    final name = json['name'];
    final bounds = json['bounds'];
    final minZoom = json['minZoom'];
    final maxZoom = json['maxZoom'];
    final tileMaxZoom = json['tileMaxZoom'] ?? maxZoom;
    final placeCount = json['placeCount'];
    if (json['schema'] != 1 ||
        id is! String ||
        !RegExp(r'^[a-z0-9][a-z0-9_-]{1,63}$').hasMatch(id) ||
        name is! String ||
        name.trim().isEmpty ||
        bounds is! Map ||
        minZoom is! int ||
        maxZoom is! int ||
        minZoom < 0 ||
        maxZoom > 18 ||
        minZoom > maxZoom ||
        tileMaxZoom is! int ||
        tileMaxZoom < minZoom ||
        tileMaxZoom > maxZoom ||
        placeCount is! int ||
        placeCount < 0 ||
        placeCount > 2000000) {
      throw const FormatException('Invalid offline pack metadata');
    }
    double coordinate(String key) {
      final value = bounds[key];
      if (value is! num || !value.toDouble().isFinite) {
        throw const FormatException('Invalid offline pack bounds');
      }
      return value.toDouble();
    }

    final south = coordinate('south');
    final north = coordinate('north');
    final west = coordinate('west');
    final east = coordinate('east');
    if (south < -90 ||
        north > 90 ||
        west < -180 ||
        east > 180 ||
        south >= north ||
        west >= east) {
      throw const FormatException('Invalid offline pack bounds');
    }
    return OfflinePack(
      id: id,
      name: name.trim(),
      directory: directory,
      south: south,
      west: west,
      north: north,
      east: east,
      minZoom: minZoom,
      maxZoom: maxZoom,
      tileMaxZoom: tileMaxZoom,
      placeCount: placeCount,
      coverage: OfflineCoveragePolygon.parseCoverage(json['coverage']),
    );
  }
}

@immutable
class OfflineCoveragePolygon {
  const OfflineCoveragePolygon(this.rings);

  final List<List<LatLng>> rings;

  bool contains(double latitude, double longitude) {
    if (rings.isEmpty || !_inRing(rings.first, latitude, longitude)) {
      return false;
    }
    for (final hole in rings.skip(1)) {
      if (_inRing(hole, latitude, longitude)) return false;
    }
    return true;
  }

  static bool _inRing(List<LatLng> ring, double latitude, double longitude) {
    var inside = false;
    for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      final a = ring[i];
      final b = ring[j];
      if ((a.latitude > latitude) != (b.latitude > latitude) &&
          longitude <
              (b.longitude - a.longitude) *
                      (latitude - a.latitude) /
                      (b.latitude - a.latitude) +
                  a.longitude) {
        inside = !inside;
      }
    }
    return inside;
  }

  static List<OfflineCoveragePolygon> parseCoverage(Object? raw) {
    if (raw == null) return const [];
    if (raw is! Map || raw['type'] is! String || raw['coordinates'] is! List) {
      throw const FormatException('Invalid offline pack coverage');
    }
    final type = raw['type'] as String;
    final coordinates = raw['coordinates'] as List;
    final polygons = type == 'Polygon'
        ? [coordinates]
        : type == 'MultiPolygon'
        ? coordinates
        : throw const FormatException('Invalid offline pack coverage');
    if (polygons.isEmpty || polygons.length > 1000) {
      throw const FormatException('Invalid offline pack coverage');
    }
    var vertices = 0;
    return polygons
        .map((polygon) {
          if (polygon is! List || polygon.isEmpty || polygon.length > 1000) {
            throw const FormatException('Invalid offline pack coverage');
          }
          return OfflineCoveragePolygon(
            polygon
                .map((ring) {
                  if (ring is! List || ring.length < 4) {
                    throw const FormatException(
                      'Invalid offline pack coverage',
                    );
                  }
                  vertices += ring.length;
                  if (vertices > 100000) {
                    throw const FormatException(
                      'Offline pack coverage is too large',
                    );
                  }
                  return ring
                      .map((coordinate) {
                        if (coordinate is! List ||
                            coordinate.length < 2 ||
                            coordinate[0] is! num ||
                            coordinate[1] is! num) {
                          throw const FormatException(
                            'Invalid offline pack coverage',
                          );
                        }
                        final longitude = (coordinate[0] as num).toDouble();
                        final latitude = (coordinate[1] as num).toDouble();
                        if (!longitude.isFinite ||
                            !latitude.isFinite ||
                            longitude < -180 ||
                            longitude > 180 ||
                            latitude < -90 ||
                            latitude > 90) {
                          throw const FormatException(
                            'Invalid offline pack coverage',
                          );
                        }
                        return LatLng(latitude, longitude);
                      })
                      .toList(growable: false);
                })
                .toList(growable: false),
          );
        })
        .toList(growable: false);
  }
}

class OfflinePackStore {
  OfflinePackStore(this.root);

  final Directory root;
  final Map<String, Future<List<_OfflineEntry>>> _placeCache = {};

  static Future<OfflinePackStore> open() async {
    final support = await getApplicationSupportDirectory();
    return OfflinePackStore(Directory('${support.path}/offline_packs'));
  }

  Future<List<OfflinePackListing>> catalog(Uri url) async {
    if (url.scheme != 'https') {
      throw const FormatException('Offline map catalog must use HTTPS');
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.getUrl(url);
      request.headers.set(HttpHeaders.userAgentHeader, 'DestinationAlarm/1.0');
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Catalog unavailable (${response.statusCode})',
          uri: url,
        );
      }
      const maximumBytes = 256 * 1024;
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 15))) {
        bytes.addAll(chunk);
        if (bytes.length > maximumBytes) {
          throw const FormatException('Offline map catalog is too large');
        }
      }
      return OfflinePackListing.parseCatalog(jsonDecode(utf8.decode(bytes)));
    } finally {
      client.close(force: true);
    }
  }

  Future<List<OfflinePack>> installed() async {
    if (!await root.exists()) return [];
    final packs = <OfflinePack>[];
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory || entity.path.split('/').last.startsWith('.')) {
        continue;
      }
      try {
        final pack = await _readPack(entity);
        if (entity.path.split('/').last == pack.id) packs.add(pack);
      } on FileSystemException {
        // Incomplete or damaged packs must not appear as available.
      } on FormatException {
        // A damaged pack is ignored until a fresh copy is installed.
      }
    }
    packs.sort((a, b) => a.name.compareTo(b.name));
    return packs;
  }

  Future<OfflinePack> _readPack(Directory directory) async {
    final metadata = jsonDecode(
      await File('${directory.path}/pack.json').readAsString(),
    );
    if (metadata is! Map<String, dynamic>) {
      throw const FormatException('Invalid offline pack metadata');
    }
    final pack = OfflinePack.fromJson(metadata, directory);
    if (!await File('${directory.path}/places.json').exists() ||
        !await Directory('${directory.path}/tiles').exists()) {
      throw const FormatException('Offline pack is incomplete');
    }
    return pack;
  }

  /// Downloads one prepared pack. The archive URL should be hosted as a static
  /// file; no app server or Google Maps API is needed for the download.
  Future<OfflinePack> download(
    Uri url, {
    void Function(int received, int? total)? onProgress,
  }) async {
    if (url.scheme != 'https') {
      throw const FormatException('Offline pack links must use HTTPS');
    }
    await root.create(recursive: true);
    final temp = File(
      '${root.path}/.download-${DateTime.now().microsecondsSinceEpoch}.zip',
    );
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      final request = await client.getUrl(url);
      request.headers.set(HttpHeaders.userAgentHeader, 'DestinationAlarm/1.0');
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Pack download failed (${response.statusCode})',
          uri: url,
        );
      }
      const maxArchiveBytes = 750 * 1024 * 1024;
      final total = response.contentLength < 0 ? null : response.contentLength;
      if (total != null && total > maxArchiveBytes) {
        throw const FormatException('Offline pack is too large');
      }
      final sink = temp.openWrite();
      var received = 0;
      try {
        await for (final chunk in response) {
          received += chunk.length;
          if (received > maxArchiveBytes) {
            throw const FormatException('Offline pack is too large');
          }
          sink.add(chunk);
          onProgress?.call(received, total);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      return await installZip(temp);
    } finally {
      client.close(force: true);
      if (await temp.exists()) await temp.delete();
    }
  }

  /// Also used by tests and by future import flows. Rejects links, traversal,
  /// oversized content, and duplicates before writing any pack files.
  Future<OfflinePack> installZip(File archiveFile) async {
    await root.create(recursive: true);
    final input = InputFileStream(archiveFile.path);
    late final Archive archive;
    try {
      archive = ZipDecoder().decodeStream(input);
      if (archive.length > 300000) {
        throw const FormatException('Offline pack has too many files');
      }
      var totalBytes = 0;
      final names = <String>{};
      var tileCount = 0;
      for (final file in archive) {
        final name = file.name;
        final directoryName = name.endsWith('/')
            ? name.substring(0, name.length - 1)
            : name;
        final validDirectory =
            !file.isFile &&
            RegExp(r'^tiles(?:/[0-9]{1,2}(?:/[0-9]+)?)?$')
                .hasMatch(directoryName);
        final validFile =
            file.isFile &&
            (name == 'pack.json' ||
                name == 'places.json' ||
                RegExp(r'^tiles/[0-9]{1,2}/[0-9]+/[0-9]+\.png$')
                    .hasMatch(name));
        if (file.isSymbolicLink ||
            !names.add(name) ||
            name.length > 200 ||
            name.startsWith('/') ||
            name.contains('\\') ||
            directoryName
                .split('/')
                .any((part) => part.isEmpty || part == '..') ||
            !(validDirectory || validFile)) {
          throw const FormatException('Invalid offline pack archive');
        }
        if (name.endsWith('.png')) tileCount++;
        totalBytes += file.size;
        if (file.size > 100 * 1024 * 1024 || totalBytes > 1024 * 1024 * 1024) {
          throw const FormatException('Offline pack is too large');
        }
      }
      if (!names.contains('pack.json') ||
          !names.contains('places.json') ||
          tileCount == 0) {
        throw const FormatException('Offline pack is incomplete');
      }
      final staging = await root.createTemp('.install-');
      try {
        for (final file in archive) {
          if (!file.isFile) continue;
          final destination = File('${staging.path}/${file.name}');
          await destination.parent.create(recursive: true);
          final bytes = file.content;
          if (file.name.endsWith('.png') &&
              (bytes.length < 8 ||
                  bytes[0] != 137 ||
                  bytes[1] != 80 ||
                  bytes[2] != 78 ||
                  bytes[3] != 71 ||
                  bytes[4] != 13 ||
                  bytes[5] != 10 ||
                  bytes[6] != 26 ||
                  bytes[7] != 10)) {
            throw const FormatException('Invalid offline map tile');
          }
          await destination.writeAsBytes(bytes, flush: false);
        }
        final pack = await _readPack(staging);
        final places = await _readPlaces(pack);
        if (places.length != pack.placeCount) {
          throw const FormatException(
            'Offline pack place count does not match',
          );
        }
        final target = Directory('${root.path}/${pack.id}');
        final backup = Directory('${root.path}/.old-${pack.id}');
        if (await backup.exists()) await backup.delete(recursive: true);
        if (await target.exists()) await target.rename(backup.path);
        try {
          await staging.rename(target.path);
        } catch (_) {
          if (await backup.exists()) await backup.rename(target.path);
          rethrow;
        }
        if (await backup.exists()) await backup.delete(recursive: true);
        _placeCache.remove(target.path);
        return await _readPack(target);
      } finally {
        _placeCache.remove(staging.path);
        if (await staging.exists()) await staging.delete(recursive: true);
      }
    } finally {
      input.close();
    }
  }

  Future<void> delete(OfflinePack pack) async {
    if (pack.directory.parent.path != root.path ||
        pack.directory.path.split('/').last != pack.id) {
      throw ArgumentError('Pack is outside the offline map directory');
    }
    if (await pack.directory.exists()) {
      await pack.directory.delete(recursive: true);
    }
    _placeCache.remove(pack.directory.path);
  }

  Future<List<_OfflineEntry>> _readPlaces(OfflinePack pack) {
    if (!_placeCache.containsKey(pack.directory.path)) {
      // Keep one region in memory. Users may install many state packs.
      _placeCache.clear();
    }
    return _placeCache.putIfAbsent(
      pack.directory.path,
      () => _decodePlaces(pack),
    );
  }

  Future<List<_OfflineEntry>> _decodePlaces(OfflinePack pack) async {
    final file = File('${pack.directory.path}/places.json');
    if (await file.length() > 100 * 1024 * 1024) {
      throw const FormatException('Offline place list is too large');
    }
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! List || decoded.length > 2000000) {
      throw const FormatException('Invalid offline place list');
    }
    return decoded.map((item) => _OfflineEntry.fromJson(item, pack)).toList();
  }

  Future<List<Place>> search(
    List<OfflinePack> packs,
    String query, {
    LatLng? near,
    int limit = 30,
  }) async {
    final needle = query.trim().toLowerCase();
    if (needle.length < 3) return [];
    final found = <_OfflineEntry>[];
    for (final pack in packs) {
      for (final entry in await _readPlaces(pack)) {
        if (entry.place.name.toLowerCase().contains(needle) ||
            entry.place.address.toLowerCase().contains(needle)) {
          found.add(entry);
        }
      }
    }
    if (near != null) {
      found.sort(
        (a, b) =>
            const Distance()(
              near,
              LatLng(a.place.latitude, a.place.longitude),
            ).compareTo(
              const Distance()(
                near,
                LatLng(b.place.latitude, b.place.longitude),
              ),
            ),
      );
    }
    return found.take(limit).map((entry) => entry.place).toList();
  }

  Future<List<Place>> nearby(
    List<OfflinePack> packs,
    TravelMode mode,
    LatLng center, {
    double radiusMetres = 5000,
    int limit = 30,
  }) async {
    final found = <_OfflineEntry>[];
    for (final pack in packs) {
      if (!pack.contains(center.latitude, center.longitude)) continue;
      for (final entry in await _readPlaces(pack)) {
        if (entry.mode == mode &&
            const Distance()(
                  center,
                  LatLng(entry.place.latitude, entry.place.longitude),
                ) <=
                radiusMetres) {
          found.add(entry);
        }
      }
    }
    found.sort(
      (a, b) =>
          const Distance()(
            center,
            LatLng(a.place.latitude, a.place.longitude),
          ).compareTo(
            const Distance()(
              center,
              LatLng(b.place.latitude, b.place.longitude),
            ),
          ),
    );
    return found.take(limit).map((entry) => entry.place).toList();
  }
}

class _OfflineEntry {
  const _OfflineEntry(this.place, this.mode);
  final Place place;
  final TravelMode mode;

  static _OfflineEntry fromJson(Object? json, OfflinePack pack) {
    if (json is! Map<String, dynamic>) {
      throw const FormatException('Invalid offline place');
    }
    final name = json['name'];
    final address = json['address'];
    final latitude = json['latitude'];
    final longitude = json['longitude'];
    final type = json['type'];
    if (name is! String ||
        name.trim().isEmpty ||
        address is! String ||
        latitude is! num ||
        longitude is! num ||
        type is! String) {
      throw const FormatException('Invalid offline place');
    }
    final lat = latitude.toDouble();
    final lon = longitude.toDouble();
    if (!lat.isFinite || !lon.isFinite || !pack.contains(lat, lon)) {
      throw const FormatException('Offline place outside pack');
    }
    final mode = TravelMode.values
        .where((value) => value.name == type)
        .firstOrNull;
    if (mode == null) throw const FormatException('Invalid offline place type');
    return _OfflineEntry(
      Place(
        id: 'osm:${pack.id}:${json['id'] ?? '$lat,$lon'}',
        name: name.trim(),
        address: address,
        latitude: lat,
        longitude: lon,
      ),
      mode,
    );
  }
}
