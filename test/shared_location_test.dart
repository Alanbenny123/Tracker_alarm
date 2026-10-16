import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracker_alarm/services/shared_location_service.dart';

void main() {
  final service = SharedLocationService();

  test('a stalled short link times out and closes its connection', () async {
    final client = _ShareClient();
    final lookup = SharedLocationService(
      clientFactory: () => client,
      lookupTimeout: const Duration(milliseconds: 30),
    );
    await expectLater(
      lookup.parse('https://maps.app.goo.gl/stalled'),
      throwsA(isA<SharedLocationException>()),
    );
    expect(client.closed, isTrue);
  });

  test('cancel completes immediately and ignores a late redirect', () async {
    final client = _ShareClient();
    final lookup = SharedLocationService(clientFactory: () => client);
    final pending = lookup.parse('https://maps.app.goo.gl/cancelled');
    await client.started.future;
    lookup.cancel();
    expect(await pending.timeout(const Duration(seconds: 1)), isNull);
    expect(client.closed, isTrue);
    client.request.complete(_ShareRequest(_ShareResponse()));
    await Future<void>.delayed(Duration.zero);
    expect(lookup.resolvedQuery, isNull);
    expect(await lookup.parse('9.93,76.26'), isNotNull);
  });

  test('redirect coordinates resolve without waiting for the body', () async {
    final response = _ShareResponse();
    final client = _ShareClient()..request.complete(_ShareRequest(response));
    final lookup = SharedLocationService(clientFactory: () => client);
    final place = await lookup.parse('https://maps.app.goo.gl/headers');
    expect(place?.latitude, 9.93);
    expect(response.bodyRead, isFalse);
    expect(client.closed, isTrue);
  });

  test(
    'failed system connection retries with the DNS fallback and preserves the full address',
    () async {
      final normal =
          _ShareClient()
            ..request.completeError(
              const SocketException('Connection timeout'),
            );
      final fallback =
          _ShareClient()
            ..request.complete(
              _ShareRequest(
                _ShareResponse(
                  location:
                      'https://www.google.com/maps/place/Hello+pets,+Mamangalam,+Edappally/data=!1sabc',
                ),
              ),
            );
      final lookup = SharedLocationService(
        clientFactory: () => normal,
        fallbackClientFactory: (host, own) async {
          expect(host, 'maps.app.goo.gl');
          own(fallback);
          return fallback;
        },
      );
      expect(
        await lookup.parse('Hello pets\nhttps://maps.app.goo.gl/place'),
        isNull,
      );
      expect(lookup.resolvedQuery, 'Hello pets, Mamangalam, Edappally');
      expect(normal.closed, isTrue);
      expect(fallback.closed, isTrue);
    },
  );

  test(
    'cancel during fallback closes late clients and never navigates with a late result',
    () async {
      final normal =
          _ShareClient()
            ..request.completeError(
              const SocketException('Connection timeout'),
            );
      final pendingClient = Completer<HttpClient>();
      final started = Completer<void>();
      final lookup = SharedLocationService(
        clientFactory: () => normal,
        fallbackClientFactory: (host, own) {
          started.complete();
          return pendingClient.future;
        },
      );
      final pending = lookup.parse('Hello pets\nhttps://maps.app.goo.gl/place');
      await started.future;
      lookup.cancel();
      expect(await pending, isNull);
      final late = _ShareClient();
      pendingClient.complete(late);
      await Future<void>.delayed(Duration.zero);
      expect(late.closed, isTrue);
      expect(lookup.resolvedQuery, isNull);
    },
  );

  test(
    'a failed fallback is an explicit retryable failure, not a generic worldwide place search',
    () async {
      final normal =
          _ShareClient()
            ..request.completeError(
              const SocketException('Connection timeout'),
            );
      final lookup = SharedLocationService(
        clientFactory: () => normal,
        fallbackClientFactory:
            (_, _) => Future.error(const SocketException('Offline')),
      );
      await expectLater(
        lookup.parse('Hello pets\nhttps://maps.app.goo.gl/place'),
        throwsA(isA<SharedLocationException>()),
      );
      expect(lookup.resolvedQuery, isNull);
    },
  );

  test('reads coordinates and name from a Google Maps place share', () async {
    final place = await service.parse(
      'Central Station\nhttps://www.google.com/maps/place/Central+Station/@9.95,76.28,17z/data=!3d9.931233!4d76.267304',
    );
    expect(place?.name, 'Central Station');
    expect(place?.latitude, 9.931233);
    expect(place?.longitude, 76.267304);
  });

  test(
    'full Maps links without coordinates retain their place search query',
    () async {
      final lookup = SharedLocationService(
        clientFactory: () => throw StateError('No network needed'),
      );
      expect(
        await lookup.parse(
          'https://www.google.com/maps/place/Central+Station/data=!4m2!3m1!1sabc',
        ),
        isNull,
      );
      expect(lookup.resolvedQuery, 'Central Station');
      expect(
        await lookup.parse(
          'https://www.google.com/maps/search/?api=1&query=Central%20Station',
        ),
        isNull,
      );
      expect(lookup.resolvedQuery, 'Central Station');
    },
  );

  test(
    'place names containing literal percent signs are decoded only once',
    () async {
      expect(
        service.queryFromMapsUrl(
          Uri.parse('https://www.google.com/maps/place/50%25+Cafe/data=!1sabc'),
        ),
        '50% Cafe',
      );
      final place = await service.parse(
        'https://www.google.com/maps/place/50%25+Cafe/data=!3d9.93!4d76.26',
      );
      expect(place?.name, '50% Cafe');
    },
  );

  test(
    'a useful redirect is kept without requesting a potentially blocked final page',
    () async {
      final response = _ShareResponse(
        location:
            'https://www.google.com/maps/place/Central+Station/data=!1sabc',
      );
      final request = _ShareRequest(response);
      final client = _ShareClient()..request.complete(request);
      final lookup = SharedLocationService(clientFactory: () => client);
      expect(await lookup.parse('https://maps.app.goo.gl/place'), isNull);
      expect(lookup.resolvedQuery, 'Central Station');
      expect(request.followRedirects, isFalse);
      expect(client.requests, 1);
      expect(response.bodyRead, isFalse);
      expect(client.closed, isTrue);
    },
  );

  test(
    'unrelated redirect hosts are rejected without following them',
    () async {
      final response = _ShareResponse(
        location: 'https://example.com/?q=9.93,76.26',
      );
      final client = _ShareClient()..request.complete(_ShareRequest(response));
      final lookup = SharedLocationService(clientFactory: () => client);
      await expectLater(
        lookup.parse('https://maps.app.goo.gl/untrusted'),
        throwsA(isA<SharedLocationException>()),
      );
      expect(lookup.resolvedQuery, isNull);
      expect(client.requests, 1);
    },
  );

  test('reads destination coordinates from Maps data URL', () async {
    final place = await service.parse(
      'https://www.google.com/maps/place/Station/data=!4m2!3m1!1sabc!3d9.931233!4d76.267304',
    );
    expect(place?.latitude, 9.931233);
    expect(place?.longitude, 76.267304);
  });

  test(
    'the reported Hello pets link searches its full address instead of the generic Android title',
    () async {
      const address =
          'Hello+pets,+Mamangalam,+Edappally,+Ernakulam,+Keralam+682025';
      final response = _ShareResponse(
        location:
            'https://www.google.com/maps/place/$address/data=!4m2!3m1!1s0x3b080db2a0e034ab:0x5fd3c727041dbccf!18m1!1e1?g_st=aw',
      );
      final client = _ShareClient()..request.complete(_ShareRequest(response));
      final lookup = SharedLocationService(clientFactory: () => client);
      const text =
          'Hello pets\nhttps://maps.app.goo.gl/fwc4aVUmk4fWWyfy5?g_st=aw';
      expect(
        await lookup.parse(text),
        isNull,
      ); // No target coordinates to guess.
      expect(
        lookup.fallbackQuery(text),
        'Hello pets, Mamangalam, Edappally, Ernakulam, Keralam 682025',
      );
      expect(client.requests, 1);
      expect(response.bodyRead, isFalse);
    },
  );

  test(
    'named-place camera coordinates do not silently become the destination',
    () async {
      expect(
        await service.parse(
          'https://www.google.com/maps/place/Central+Station/@9.95,76.28,17z',
        ),
        isNull,
      );
      expect(service.resolvedQuery, 'Central Station');
      expect(
        await service.parse('https://www.google.com/maps/@9.95,76.28,17z'),
        isNull,
      );
      expect(
        await service.parse('https://www.google.com/maps?ll=9.95,76.28'),
        isNull,
      );
    },
  );

  test(
    'explicit query destination wins over an earlier viewport or geo origin',
    () async {
      final place = await service.parse(
        'https://www.google.com/maps?ll=9.95,76.28&q=9.93,76.26',
      );
      expect(place?.latitude, 9.93);
      expect(place?.longitude, 76.26);
      final geo = await service.parse('geo:0,0?q=9.93,76.26');
      expect(geo?.latitude, 9.93);
      expect(geo?.longitude, 76.26);
      final pin = await service.parse(
        'https://www.google.com/maps/place/9.93,76.26/@9.95,76.28,17z',
      );
      expect(pin?.latitude, 9.93);
      expect(pin?.longitude, 76.26);
    },
  );

  test('rejects coordinates outside the world', () async {
    expect(await service.parse('999,999'), isNull);
  });

  test('reads encoded Maps query coordinates', () async {
    final place = await service.parse(
      'https://www.google.com/maps/search/?api=1&query=9.931233%2C76.267304',
    );
    expect(place?.latitude, 9.931233);
    expect(place?.longitude, 76.267304);
  });

  test('does not use unrelated address numbers as coordinates', () async {
    expect(
      await service.parse('Shop 12, 34 Main Street\nhttps://example.com/place'),
      isNull,
    );
  });

  test('uses the shared place name as a search fallback', () {
    expect(
      service.searchQuery(
        'Central Station\nMain Road\nhttps://maps.app.goo.gl/abc',
      ),
      'Central Station, Main Road',
    );
  });

  test(
    'uses place and address from a short-link redirect without coordinates',
    () {
      final query = service.queryFromMapsUrl(
        Uri.parse(
          'https://www.google.com/maps/place/I+love+my+pets+(Aquarium+%26+Petshop),+VIP+Panorama+Arcade,+Athani,+Kochi,+Keralam+683585/data=!4m2!3m1!1sabc',
        ),
      );
      expect(query, contains('I love my pets'));
      expect(query, contains('Athani, Kochi'));
    },
  );
}

class _ShareClient implements HttpClient {
  int requests = 0;
  final request = Completer<HttpClientRequest>();
  final started = Completer<void>();
  bool closed = false;
  @override
  Duration? connectionTimeout;
  @override
  Future<HttpClientRequest> getUrl(Uri url) {
    requests++;
    started.complete();
    return request.future;
  }

  @override
  void close({bool force = false}) => closed = force;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ShareRequest implements HttpClientRequest {
  _ShareRequest(this.response);
  final HttpClientResponse response;
  @override
  bool followRedirects = false;
  @override
  int maxRedirects = 0;
  @override
  Future<HttpClientResponse> close() async => response;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ShareResponse implements HttpClientResponse {
  _ShareResponse({this.location = 'https://www.google.com/maps?q=9.93,76.26'});
  final String location;
  @override
  int get statusCode => 302;
  @override
  HttpHeaders get headers => _Headers(location);
  bool bodyRead = false;
  @override
  List<RedirectInfo> get redirects => [_ShareRedirect()];
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    bodyRead = true;
    return const Stream<List<int>>.empty().listen(onData);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Headers implements HttpHeaders {
  _Headers(this.location);
  final String location;
  @override
  String? value(String name) =>
      name == HttpHeaders.locationHeader ? location : null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ShareRedirect implements RedirectInfo {
  @override
  Uri get location => Uri.parse('https://www.google.com/maps?q=9.93,76.26');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
