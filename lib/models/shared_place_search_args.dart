import 'place.dart';

/// Reject obviously unrelated geocoder results; this is not proof of an exact pin.
class SharedPlaceSearchArgs {
  const SharedPlaceSearchArgs(this.query);
  final String query;

  static List<String> _words(String value) =>
      value
          .toLowerCase()
          .split(RegExp(r"[\s,;:/().'’&+\-]+"))
          .where(
            (word) =>
                word.length >= 3 &&
                !const {'the', 'and', 'road', 'street', 'near'}.contains(word),
          )
          .toList();

  /// Auto-select only one named match. A locality-only result is not a pin for
  /// the shared business, even when its address passes the regional filter.
  Place? singleNamedMatch(Iterable<Place> places) {
    final parts = query.split(',');
    final name = _words(parts.first);
    // Prefer the building/locality nearest the name. Matching only a state or
    // country later in a detailed address can select a different branch.
    final locality = parts.skip(1).take(2).expand(_words).toList();
    if (name.isEmpty) return null;
    final candidates =
        places.where((place) {
          final words = _words('${place.name} ${place.address}').toSet();
          return matches(place) &&
              name.every(words.contains) &&
              (locality.isEmpty || locality.any(words.contains));
        }).toList();
    return candidates.length == 1 ? candidates.single : null;
  }

  bool matches(Place place) {
    final parts = query.toLowerCase().split(',');
    final candidate = '${place.name} ${place.address}'.toLowerCase();
    // A detailed shared address must agree with at least one of its location
    // components. A business name by itself may refer to a different branch.
    final context = parts.skip(1).expand(_words).toList();
    if (context.isNotEmpty) return context.any(candidate.contains);
    final name = _words(parts.first);
    return name.isNotEmpty && name.every(candidate.contains);
  }
}
