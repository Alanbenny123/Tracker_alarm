import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:tracker_alarm/models/travel_mode.dart';
import 'package:tracker_alarm/services/offline_pack_store.dart';

void main() {
  late Directory root;
  late OfflinePackStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('tracker-offline-test-');
    store = OfflinePackStore(Directory('${root.path}/packs'));
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<File> makeArchive({
    String id = 'test-region',
    String? extraFile,
    int placeCount = 3,
    bool withDirectories = false,
    bool corruptTile = false,
  }) async {
    final archive = Archive()
      ..addFile(
        ArchiveFile.string(
          'pack.json',
          jsonEncode({
            'schema': 1,
            'id': id,
            'name': 'Test region',
            'bounds': {'south': 9.8, 'west': 76.2, 'north': 10.2, 'east': 76.5},
            'minZoom': 10,
            'maxZoom': 15,
            'placeCount': placeCount,
          }),
        ),
      )
      ..addFile(
        ArchiveFile.string(
          'places.json',
          jsonEncode([
            {
              'id': 'n1',
              'name': 'Edappally Metro',
              'address': 'Kochi',
              'latitude': 10.025,
              'longitude': 76.309,
              'type': 'metro',
            },
            {
              'id': 'n2',
              'name': 'Palarivattom Metro',
              'address': 'Kochi',
              'latitude': 10.0,
              'longitude': 76.304,
              'type': 'metro',
            },
            {
              'id': 'n3',
              'name': 'Edappally Bus Stop',
              'address': 'Kochi',
              'latitude': 10.025,
              'longitude': 76.309,
              'type': 'bus',
            },
          ]),
        ),
      )
      ..addFile(
        ArchiveFile(
          'tiles/10/729/483.png',
          corruptTile ? 3 : 68,
          corruptTile
              ? [1, 2, 3]
              : base64Decode(
                  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/lV8AAAAASUVORK5CYII=',
                ),
        ),
      );
    if (withDirectories) {
      archive
        ..addFile(ArchiveFile.directory('tiles/'))
        ..addFile(ArchiveFile.directory('tiles/10/'))
        ..addFile(ArchiveFile.directory('tiles/10/729/'));
    }
    if (extraFile != null) {
      archive.addFile(ArchiveFile.string(extraFile, 'bad'));
    }
    final file = File('${root.path}/$id.zip');
    await file.writeAsBytes(ZipEncoder().encode(archive));
    return file;
  }

  test('installs and searches a pack without Google requests', () async {
    final pack = await store.installZip(await makeArchive());
    expect(pack.id, 'test-region');
    expect(pack.contains(10.025, 76.309), true);
    expect((await store.installed()).single.id, 'test-region');
    final results = await store.search([pack], 'edappally');
    expect(results.map((place) => place.name), contains('Edappally Metro'));
    expect(results.first.googleFetchedAt, isNull);
    final metro = await store.nearby(
      [pack],
      TravelMode.metro,
      const LatLng(10.025, 76.309),
      radiusMetres: 5000,
    );
    expect(
      metro.map((place) => place.name),
      containsAll(['Edappally Metro', 'Palarivattom Metro']),
    );
    expect(
      metro.map((place) => place.name),
      isNot(contains('Edappally Bus Stop')),
    );
    await store.delete(pack);
    expect(await store.installed(), isEmpty);
  });

  test('rejects traversal and leaves no installed pack', () async {
    expect(
      store.installZip(await makeArchive(extraFile: '../escape.txt')),
      throwsFormatException,
    );
    expect(await store.installed(), isEmpty);
    expect(await File('${root.path}/escape.txt').exists(), false);
  });

  test('accepts standard ZIP directory entries', () async {
    final pack = await store.installZip(
      await makeArchive(withDirectories: true),
    );
    expect(pack.name, 'Test region');
  });

  test('keeps multiple downloaded regions independently', () async {
    final first = await store.installZip(await makeArchive(id: 'kerala'));
    final second = await store.installZip(await makeArchive(id: 'tamil-nadu'));
    expect(
      (await store.installed()).map((pack) => pack.id),
      containsAll(['kerala', 'tamil-nadu']),
    );
    await store.delete(first);
    expect((await store.installed()).single.id, second.id);
  });

  test('rejects inconsistent place count', () async {
    expect(
      store.installZip(await makeArchive(placeCount: 4)),
      throwsFormatException,
    );
    expect(await store.installed(), isEmpty);
  });

  test('rejects damaged map tiles', () async {
    expect(
      store.installZip(await makeArchive(corruptTile: true)),
      throwsFormatException,
    );
    expect(await store.installed(), isEmpty);
  });

  test('a damaged update keeps the installed pack', () async {
    final original = await store.installZip(await makeArchive());
    expect(
      store.installZip(await makeArchive(corruptTile: true)),
      throwsFormatException,
    );
    expect((await store.installed()).single.id, original.id);
    expect(
      (await store.search(await store.installed(), 'edappally')),
      isNotEmpty,
    );
  });

  test('requires HTTPS for downloads', () async {
    expect(
      store.download(Uri.parse('http://example.com/pack.zip')),
      throwsFormatException,
    );
  });

  test('catalog accepts multiple HTTPS region downloads', () {
    final catalog = OfflinePackListing.parseCatalog({
      'schema': 1,
      'packs': [
        {
          'id': 'kerala',
          'name': 'Kerala',
          'url': 'https://example.com/kerala.zip',
        },
        {
          'id': 'tamil-nadu',
          'name': 'Tamil Nadu',
          'url': 'https://example.com/tn.zip',
        },
      ],
    });
    expect(catalog.map((entry) => entry.name), ['Kerala', 'Tamil Nadu']);
    expect(
      () => OfflinePackListing.parseCatalog({
        'schema': 1,
        'packs': [
          {'id': 'kerala', 'name': 'Kerala', 'url': 'http://example.com/a.zip'},
        ],
      }),
      throwsFormatException,
    );
  });

  test('state coverage excludes another location inside its bounding box', () {
    final pack = OfflinePack.fromJson({
      'schema': 1,
      'id': 'sample-state',
      'name': 'Sample State',
      'bounds': {'south': 9, 'west': 76, 'north': 12, 'east': 79},
      'minZoom': 7,
      'maxZoom': 14,
      'tileMaxZoom': 12,
      'placeCount': 1,
      'coverage': {
        'type': 'Polygon',
        'coordinates': [
          [
            [76, 9],
            [77, 9],
            [77, 10],
            [76, 10],
            [76, 9],
          ],
          [
            [76.3, 9.3],
            [76.7, 9.3],
            [76.7, 9.7],
            [76.3, 9.7],
            [76.3, 9.3],
          ],
        ],
      },
    }, root);
    expect(pack.tileMaxZoom, 12);
    expect(pack.contains(9.1, 76.1), true);
    expect(pack.contains(9.5, 76.5), false);
    expect(pack.contains(11, 78), false);
  });
}
