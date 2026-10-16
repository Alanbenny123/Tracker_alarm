import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracker_alarm/models/travel_mode.dart';
import 'package:tracker_alarm/services/places_service.dart';
import 'package:tracker_alarm/services/transit_stops_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'replaced geocoder callbacks cannot update the cache or block a new search',
    () async {
      const channel = MethodChannel('tracker_alarm/places');
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
      await Future<void>.delayed(Duration.zero);
      final oldAgain = service.search('old area');
      await Future<void>.delayed(Duration.zero);
      expect(
        requests['old area']!.isCompleted,
        isFalse,
      ); // No stale cached result.
      service.dispose();
      expect(await oldAgain, isEmpty);
      requests['old area']!.completeError(PlatformException(code: 'late'));
      await Future<void>.delayed(Duration.zero);
    },
  );

  test(
    'replaced stop lookup closes its connection and ignores late failures',
    () async {
      final clients = [_StopClient(), _StopClient(), _StopClient()];
      var created = 0;
      final service = TransitStopsService(
        clientFactory: () => clients[created++],
      );
      final old = service.nearby(TravelMode.bus, 9.9, 76.7);
      await clients[0].started.future;
      final latest = service.nearby(TravelMode.metro, 9.91, 76.71);
      await clients[1].started.future;
      expect(await old, isEmpty);
      expect(clients[0].closed, isTrue);
      clients[0].pending.completeError(const SocketException('Late failure'));
      clients[1].pending.complete(_StopRequest());
      expect((await latest).single.name, 'New station');
      expect(clients[1].closed, isTrue);
      expect(
        (await service.nearby(TravelMode.metro, 9.91, 76.71)).single.name,
        'New station',
      );
      expect(created, 2);
      final pending = service.nearby(TravelMode.bus, 9.9, 76.7);
      await clients[2].started.future;
      service.dispose();
      expect(await pending, isEmpty);
      expect(clients[2].closed, isTrue);
      clients[2].pending.completeError(const SocketException('Disposed'));
      await Future<void>.delayed(Duration.zero);
    },
  );
}

Map<String, dynamic> _place(String name) => {
  'name': name,
  'address': '',
  'latitude': 9.9,
  'longitude': 76.7,
};

class _StopClient implements HttpClient {
  final pending = Completer<HttpClientRequest>();
  final started = Completer<void>();
  bool closed = false;
  @override
  Duration? connectionTimeout;
  @override
  Future<HttpClientRequest> postUrl(Uri url) {
    started.complete();
    return pending.future;
  }

  @override
  void close({bool force = false}) => closed = force;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StopHeaders implements HttpHeaders {
  @override
  ContentType? contentType;
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StopRequest implements HttpClientRequest {
  @override
  final headers = _StopHeaders();
  @override
  void write(Object? object) {}
  @override
  Future<HttpClientResponse> close() async => _StopResponse();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StopResponse extends Stream<List<int>> implements HttpClientResponse {
  @override
  int get statusCode => HttpStatus.ok;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream.value(
    utf8.encode(
      jsonEncode({
        'elements': [
          {
            'type': 'node',
            'id': 1,
            'lat': 9.91,
            'lon': 76.71,
            'tags': {'name': 'New station'},
          },
        ],
      }),
    ),
  ).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
