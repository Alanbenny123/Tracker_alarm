import 'package:flutter_test/flutter_test.dart';
import 'package:tracker_alarm/models/place.dart';
import 'package:tracker_alarm/models/shared_place_search_args.dart';

void main() {
  const canada = Place(
    name: '3569',
    address: '3569 Dutch Village Rd, Halifax, NS B3N 0E8, Canada',
    latitude: 44.65,
    longitude: -63.63,
  );
  test('a matching area alone is never selected as the shared business', () {
    const args = SharedPlaceSearchArgs('Hello pets, Mamangalam, Edappally');
    const area = Place(
      name: 'Mamangalam',
      address: 'Edappally, Kerala',
      latitude: 9.98,
      longitude: 76.29,
    );
    expect(args.matches(area), isTrue);
    expect(args.singleNamedMatch([area]), isNull);
    expect(args.singleNamedMatch([]), isNull);
  });

  test('name punctuation does not prevent a unique shared-place match', () {
    const args = SharedPlaceSearchArgs(
      "St. George's Syro-Malabar Church, Kalady",
    );
    const church = Place(
      name: 'St George’s Syro Malabar Church',
      address: 'Kalady, Kerala',
      latitude: 10,
      longitude: 76,
    );
    expect(args.singleNamedMatch([church]), same(church));
  });

  test('a shared business in a different locality is not auto-selected', () {
    const args = SharedPlaceSearchArgs(
      'Hello pets, Mamangalam, Edappally, Ernakulam, Kerala',
    );
    const differentBranch = Place(
      name: 'Hello pets',
      address: 'Kozhikode, Kerala',
      latitude: 11.25,
      longitude: 75.77,
    );
    expect(args.singleNamedMatch([differentBranch]), isNull);
  });
  test(
    'business name fallback does not accept an unrelated numbered address',
    () {
      expect(
        const SharedPlaceSearchArgs('Hello pets').matches(canada),
        isFalse,
      );
      expect(
        const SharedPlaceSearchArgs(
          'Hello pets, Mamangalam, Edappally, Ernakulam, Keralam 682025',
        ).matches(canada),
        isFalse,
      );
    },
  );
  test(
    'address matching supports intentionally shared distant destinations',
    () {
      expect(
        const SharedPlaceSearchArgs(
          'Hello pets, Halifax, Canada',
        ).matches(canada),
        isTrue,
      );
    },
  );
}
