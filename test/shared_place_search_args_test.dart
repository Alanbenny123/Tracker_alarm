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
  test('a matching area alone is not the shared business', () {
    const args = SharedPlaceSearchArgs('Hello pets, Mamangalam, Edappally');
    const area = Place(
      name: 'Mamangalam',
      address: 'Edappally, Kerala',
      latitude: 9.98,
      longitude: 76.29,
    );
    expect(args.matches(area), isFalse);
  });
  test('name punctuation does not prevent a shared-place match', () {
    const args = SharedPlaceSearchArgs(
      "St. George's Syro-Malabar Church, Kalady",
    );
    const church = Place(
      name: 'St George’s Syro Malabar Church',
      address: 'Kalady, Kerala',
      latitude: 10,
      longitude: 76,
    );
    expect(args.matches(church), isTrue);
  });
  test('a shared business in a different locality is filtered out', () {
    const args = SharedPlaceSearchArgs(
      'Hello pets, Mamangalam, Edappally, Ernakulam',
    );
    const differentBranch = Place(
      name: 'Hello pets',
      address: 'Kozhikode, Kerala',
      latitude: 11.25,
      longitude: 75.77,
    );
    expect(args.matches(differentBranch), isFalse);
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
      final halifaxBranch = canada.copyWith(name: 'Hello pets');
      expect(
        const SharedPlaceSearchArgs('Hello pets, Halifax, Canada')
            .matches(halifaxBranch),
        isTrue,
      );
    },
  );
}
