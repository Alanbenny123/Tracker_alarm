import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracker_alarm/services/offline_pack_store.dart';

const artifactPath = String.fromEnvironment('OFFLINE_PACK_PATH');

void main() {
  test(
    'a built offline pack installs and reads in the app',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'verify-offline-pack-',
      );
      try {
        final store = OfflinePackStore(Directory('${temp.path}/packs'));
        final pack = await store.installZip(File(artifactPath));
        final installed = await store.installed();
        expect(installed.length, 1);
        expect(installed.single.id, pack.id);
        expect(installed.single.placeCount, greaterThan(0));
      } finally {
        await temp.delete(recursive: true);
      }
    },
    skip: artifactPath.isEmpty
        ? 'Pass OFFLINE_PACK_PATH to verify a built pack'
        : null,
  );
}
