import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker_alarm/models/travel_mode.dart';
import 'package:tracker_alarm/services/places_service.dart';
import 'package:tracker_alarm/services/transit_stops_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('tracker_alarm/places');

  test('text search retries one local rate-limit rejection', () async {
    var attempts = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          attempts++;
          if (attempts == 1) {
            throw PlatformException(code: 'rate_limit');
          }
          return [_place('Nearby shop')];
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final service = PlacesService(rateLimitRetryDelay: Duration.zero);
    expect((await service.search('Nearby shop')).single.name, 'Nearby shop');
    expect(attempts, 2);
    service.dispose();
  });

  test('stop search retries one local rate-limit rejection', () async {
    var attempts = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          attempts++;
          if (attempts == 1) {
            throw PlatformException(code: 'rate_limit');
          }
          return [_place('Bus stop')];
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final service = TransitStopsService(rateLimitRetryDelay: Duration.zero);
    expect(
      (await service.nearby(TravelMode.bus, 11.1234, 77.1234)).single.name,
      'Bus stop',
    );
    expect(attempts, 2);
    service.dispose();
  });

  test('canceling a throttled stop search prevents its retry', () async {
    var attempts = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          attempts++;
          throw PlatformException(code: 'rate_limit');
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final service = TransitStopsService(
      rateLimitRetryDelay: const Duration(milliseconds: 30),
    );
    final search = service.nearby(TravelMode.metro, 11.5678, 77.5678);
    await Future<void>.delayed(Duration.zero);
    expect(attempts, 1);
    service.cancel();
    expect(await search, isEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 45));
    expect(attempts, 1);
    service.dispose();
  });

  test('replaced text search ignores late results', () async {
    final requests = <String, Completer<List<dynamic>>>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) {
          final pending = Completer<List<dynamic>>();
          requests[call.arguments['query'] as String] = pending;
          return pending.future;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final service = PlacesService();
    final old = service.search('old area');
    await Future<void>.delayed(Duration.zero);
    final latest = service.search('new area');
    await Future<void>.delayed(Duration.zero);
    expect(await old, isEmpty);
    requests['new area']!.complete([_place('New area')]);
    expect((await latest).single.name, 'New area');
    requests['old area']!.complete([_place('Old area')]);
    service.dispose();
  });

  test('text searches bias toward GPS and keep separate area caches', () async {
    final arguments = <Map<dynamic, dynamic>>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          arguments.add(call.arguments as Map<dynamic, dynamic>);
          return [_place('Matched place')];
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final service = PlacesService();
    await service.search('Station', latitude: 9.9, longitude: 76.7);
    await service.search('Station', latitude: 9.9, longitude: 76.7);
    await service.search('Station', latitude: 10.1, longitude: 76.9);
    expect(arguments, hasLength(2));
    expect(arguments.first, {
      'query': 'Station',
      'latitude': 9.9,
      'longitude': 76.7,
    });
    expect(arguments.last['latitude'], 10.1);
    service.dispose();
  });

  test(
    'replaced stop search ignores late results and caches the new area',
    () async {
      final requests = <Completer<List<dynamic>>>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) {
            expect(call.method, 'nearbyStops');
            final pending = Completer<List<dynamic>>();
            requests.add(pending);
            return pending.future;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final service = TransitStopsService();
      final old = service.nearby(TravelMode.bus, 9.9, 76.7);
      await Future<void>.delayed(Duration.zero);
      final latest = service.nearby(TravelMode.metro, 9.91, 76.71);
      await Future<void>.delayed(Duration.zero);
      expect(await old, isEmpty);
      requests.last.complete([_place('New station')]);
      expect((await latest).single.name, 'New station');
      requests.first.complete([_place('Old stop')]);
      expect(
        (await service.nearby(TravelMode.metro, 9.91, 76.71)).single.name,
        'New station',
      );
      expect(requests, hasLength(2));
      service.dispose();
    },
  );
}

Map<String, dynamic> _place(String name) => {
  'name': name,
  'address': '',
  'latitude': 9.9,
  'longitude': 76.7,
};
