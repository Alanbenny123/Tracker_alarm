import 'place.dart';

/// Filter shared-link search hints; the user still chooses the exact pin.
class SharedPlaceSearchArgs {
  const SharedPlaceSearchArgs(this.query);
  final String query;

  static List<String> _words(String value) => value
      .toLowerCase()
      .split(RegExp(r"[\s,;:/().'’&+\-]+"))
      .where(
        (word) =>
            word.length >= 3 &&
            !const {'the', 'and', 'road', 'street', 'near'}.contains(word),
      )
      .toList();

  bool matches(Place place) {
    final parts = query.split(',');
    final candidate = _words('${place.name} ${place.address}').toSet();
    final name = _words(parts.first);
    if (name.isEmpty || !name.every(candidate.contains)) return false;
    final locality = parts.skip(1).expand(_words).toList();
    return locality.isEmpty || locality.any(candidate.contains);
  }
}
