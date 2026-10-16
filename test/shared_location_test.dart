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
    expect(await lookup.parse('https://maps.app.goo.gl/stalled'), isNull);
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

  test('reads coordinates and name from a Google Maps place share', () async {
    final place = await service.parse(
      'Central Station\nhttps://www.google.com/maps/place/Central+Station/@9.931233,76.267304,17z',
    );
    expect(place?.name, 'Central Station');
    expect(place?.latitude, 9.931233);
    expect(place?.longitude, 76.267304);
  });

  test('reads destination coordinates from Maps data URL', () async {
    final place = await service.parse(
      'https://www.google.com/maps/place/Station/data=!4m2!3m1!1sabc!3d9.931233!4d76.267304',
    );
    expect(place?.latitude, 9.931233);
    expect(place?.longitude, 76.267304);
  });

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
  final request = Completer<HttpClientRequest>();
  final started = Completer<void>();
  bool closed = false;
  @override
  Duration? connectionTimeout;
  @override
  Future<HttpClientRequest> getUrl(Uri url) {
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

class _ShareRedirect implements RedirectInfo {
  @override
  Uri get location => Uri.parse('https://www.google.com/maps?q=9.93,76.26');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
