import 'package:flutter_test/flutter_test.dart';
import 'package:tracker_alarm/services/shared_location_service.dart';

void main() {
  final service = SharedLocationService();

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
