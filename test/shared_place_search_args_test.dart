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
