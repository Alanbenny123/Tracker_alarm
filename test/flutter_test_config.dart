import 'dart:async';

import 'support/fake_maplibre.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  FakeMapLibrePlatform.install();
  await testMain();
}
