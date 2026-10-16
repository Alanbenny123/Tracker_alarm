import 'package:flutter_test/flutter_test.dart';
import 'package:tracker_alarm/services/maps_dns_fallback.dart';

Map<String, dynamic> answer(
  List<String> addresses, {
  String host = 'maps.app.goo.gl',
}) => {
  'Status': 0,
  'Question': [
    {'name': '$host.', 'type': 1},
  ],
  'Answer':
      addresses.map((ip) => {'name': '$host.', 'type': 1, 'data': ip}).toList(),
};

void main() {
  test(
    'accepts public addresses only for the requested Google short-link hostname',
    () {
      final addresses = MapsDnsFallback.parseAddresses(
        answer(['192.178.173.101']),
        'maps.app.goo.gl',
      );
      expect(addresses.single.address, '192.178.173.101');
      expect(
        () => MapsDnsFallback.parseAddresses(
          answer(['192.178.173.101'], host: 'example.com'),
          'maps.app.goo.gl',
        ),
        throwsFormatException,
      );
      expect(
        () => MapsDnsFallback.parseAddresses(
          answer(['192.178.173.101'], host: 'example.com'),
          'example.com',
        ),
        throwsFormatException,
      );
    },
  );

  test('rejects failed DNS responses and local or invalid addresses', () {
    for (final ip in [
      '127.0.0.1',
      '10.0.0.1',
      '172.16.0.1',
      '192.168.1.1',
      '169.254.1.1',
      '0.0.0.0',
      'invalid',
      '::1',
    ]) {
      expect(
        () => MapsDnsFallback.parseAddresses(answer([ip]), 'maps.app.goo.gl'),
        throwsFormatException,
      );
    }
    expect(
      () => MapsDnsFallback.parseAddresses({
        ...answer(['192.178.173.101']),
        'Status': 2,
      }, 'maps.app.goo.gl'),
      throwsFormatException,
    );
  });
}
