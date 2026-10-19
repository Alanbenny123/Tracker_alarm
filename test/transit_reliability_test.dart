import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracker_alarm/models/travel_mode.dart';
import 'package:tracker_alarm/services/transit_stops_service.dart';

const _good =
    '{"elements":[{"type":"node","id":1,"lat":10,"lon":76,"tags":{"name":"Town stop"}}]}';

class _Headers implements HttpHeaders {
  _Headers([this.retryAfter]);
  final String? retryAfter;
  @override
  ContentType? contentType;
  @override
  String? value(String name) =>
      name == HttpHeaders.retryAfterHeader ? retryAfter : null;
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(this.statusCode, [this.body = _good, String? retryAfter])
    : headers = _Headers(retryAfter);
  final String body;
  @override
  final int statusCode;
  @override
  final HttpHeaders headers;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream.value(utf8.encode(body)).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Request implements HttpClientRequest {
  _Request(this.response, this.onQuery);
  final _Response response;
  final void Function(String) onQuery;
  @override
  final headers = _Headers();
  @override
  void write(Object? object) => onQuery(object.toString());
  @override
  Future<HttpClientResponse> close() async => response;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Client implements HttpClient {
  _Client(this.responses);
  final List<_Response> responses;
  final queries = <String>[];
  final urls = <Uri>[];
  int requests = 0;
  bool closed = false;
  @override
  Duration? connectionTimeout;
  @override
  Future<HttpClientRequest> postUrl(Uri url) async {
    urls.add(url);
    return _Request(responses[requests++], queries.add);
  }

  @override
  void close({bool force = false}) => closed = true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _OfflineClient extends _Client {
  _OfflineClient() : super([]);
  @override
  Future<HttpClientRequest> postUrl(Uri url) =>
      Future.error(const SocketException('Offline'));
}

class _TimeoutClient extends _Client {
  _TimeoutClient() : super([]);
  @override
  Future<HttpClientRequest> postUrl(Uri url) {
    urls.add(url);
    return Future.error(TimeoutException('Connection timed out'));
  }
}

void main() {
  test(
    'picker visits reuse cache; stale offline results are labeled and expire',
    () async {
      var now = DateTime.utc(2026, 10, 16);
      final cache = TransitStopsCache(clock: () => now);
      final client = _Client([_Response(200)]);
      final first = TransitStopsService(
        cache: cache,
        clientFactory: () => client,
      );
      expect(
        (await first.nearby(TravelMode.bus, 10, 76)).single.name,
        'Town stop',
      );
      expect(
        Uri.decodeQueryComponent(client.queries.single),
        contains('["name"](around:2500'),
      );
      first.dispose();
      var networkCalls = 0;
      final second = TransitStopsService(
        cache: cache,
        clientFactory: () {
          networkCalls++;
          throw const SocketException('Offline');
        },
      );
      expect(
        (await second.nearby(TravelMode.bus, 10, 76)).single.name,
        'Town stop',
      );
      expect(networkCalls, 0);
      // A transport or area change never reuses a different destination's stops.
      final failedClient = _OfflineClient();
      final offline = TransitStopsService(
        cache: cache,
        clientFactory: () => failedClient,
      );
      now = now.add(const Duration(minutes: 15));
      expect(
        (await offline.nearby(TravelMode.bus, 10, 76)).single.name,
        'Town stop',
      );
      expect(offline.notice, contains('15 minutes ago'));
      expect(offline.notice, contains('may have changed'));
      now = now.add(const Duration(hours: 24));
      final expired = TransitStopsService(
        cache: cache,
        clientFactory: () => _Client([_Response(400)]),
      );
      await expectLater(
        expired.nearby(TravelMode.bus, 10, 76),
        throwsA(isA<TransitStopsException>()),
      );
      expect(expired.notice, isNull);
      second.dispose();
      offline.dispose();
      expired.dispose();
    },
  );

  test(
    '429 respects Retry-After across picker visits and transport changes',
    () async {
      var now = DateTime.utc(2026, 10, 16);
      final cache = TransitStopsCache(clock: () => now);
      final client = _Client([_Response(429, '{}', '90')]);
      final service = TransitStopsService(
        cache: cache,
        clientFactory: () => client,
      );
      await expectLater(
        service.nearby(TravelMode.bus, 10, 76),
        throwsA(isA<TransitStopsException>()),
      );
      expect(client.requests, 1);
      expect(cache.retryAt, now.add(const Duration(seconds: 90)));
      var newClients = 0;
      final next = TransitStopsService(
        cache: cache,
        clientFactory: () {
          newClients++;
          return _Client([_Response(200)]);
        },
      );
      await expectLater(
        next.nearby(TravelMode.metro, 10, 76),
        throwsA(predicate((e) => e.toString().contains('cooling down'))),
      );
      expect(newClients, 0);
      now = now.add(const Duration(seconds: 91));
      expect(
        (await next.nearby(TravelMode.metro, 10, 76)).single.name,
        'Town stop',
      );
      expect(newClients, 1);
      service.dispose();
      next.dispose();
    },
  );

  test(
    'partial Overpass responses are not cached as empty successful results',
    () async {
      final cache = TransitStopsCache();
      final bad = TransitStopsService(
        cache: cache,
        clientFactory:
            () => _Client([
              _Response(
                200,
                '{"elements":[],"remark":"runtime error: timed out"}',
              ),
            ]),
      );
      await expectLater(
        bad.nearby(TravelMode.railway, 10, 76),
        throwsA(predicate((e) => e.toString().contains('incomplete'))),
      );
      var requests = 0;
      final good = TransitStopsService(
        cache: cache,
        clientFactory: () {
          requests++;
          return _Client([_Response(200)]);
        },
      );
      expect(
        (await good.nearby(TravelMode.railway, 10, 76)).single.name,
        'Town stop',
      );
      expect(requests, 1);
      bad.dispose();
      good.dispose();
    },
  );

  test(
    'transient failure tries a different server and cancellation stops retry',
    () async {
      final first = _Client([_Response(503)]);
      final second = _Client([_Response(200)]);
      var created = 0;
      final service = TransitStopsService(
        cache: TransitStopsCache(),
        clientFactory: () => created++ == 0 ? first : second,
      );
      final result = service.nearby(TravelMode.bus, 10, 76);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(first.requests, 1);
      await Future<void>.delayed(const Duration(milliseconds: 2100));
      expect((await result).single.name, 'Town stop');
      expect(first.urls.single.host, 'overpass-api.de');
      expect(second.urls.single.host, 'overpass.private.coffee');
      expect(second.requests, 1);
      expect(first.closed, isTrue);
      service.dispose();
      final cancelled = _Client([_Response(503)]);
      var cancelledClients = 0;
      final other = TransitStopsService(
        cache: TransitStopsCache(),
        clientFactory: () {
          cancelledClients++;
          return cancelled;
        },
      );
      final pending = other.nearby(TravelMode.metro, 10, 76);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      other.cancel();
      expect(await pending, isEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 2100));
      expect(cancelled.requests, 1);
      expect(cancelledClients, 1);
      expect(cancelled.closed, isTrue);
      other.dispose();
    },
  );

  test('connection timeout falls back to another server', () async {
    final first = _TimeoutClient();
    final second = _Client([_Response(200)]);
    var created = 0;
    final service = TransitStopsService(
      cache: TransitStopsCache(),
      clientFactory: () => created++ == 0 ? first : second,
    );
    expect(
      (await service.nearby(TravelMode.bus, 10, 76)).single.name,
      'Town stop',
    );
    expect(first.closed, isTrue);
    expect(second.urls.single.host, 'overpass.private.coffee');
    service.dispose();
  });

  test('both connection timeouts show the timeout message', () async {
    final clients = <_TimeoutClient>[];
    final service = TransitStopsService(
      cache: TransitStopsCache(),
      clientFactory: () {
        final client = _TimeoutClient();
        clients.add(client);
        return client;
      },
    );
    await expectLater(
      service.nearby(TravelMode.bus, 10, 76),
      throwsA(predicate((e) => e.toString().contains('timed out'))),
    );
    expect(clients.length, 2);
    expect(clients.every((client) => client.closed), isTrue);
    service.dispose();
  });
}
