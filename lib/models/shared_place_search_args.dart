import 'place.dart';

/// Reject obviously unrelated geocoder results; this is not proof of an exact pin.
class SharedPlaceSearchArgs {
  const SharedPlaceSearchArgs(this.query);
  final String query;

  bool matches(Place place) {
    final parts = query.toLowerCase().split(',');
    final candidate = '${place.name} ${place.address}'.toLowerCase();
    List<String> words(String value) =>
        value
            .split(RegExp(r'[\s,;:/()\-]+'))
            .where(
              (word) =>
                  word.length >= 3 &&
                  !const {
                    'the',
                    'and',
                    'road',
                    'street',
                    'near',
                  }.contains(word),
            )
            .toList();
    // A detailed shared address must agree with at least one of its location
    // components. A business name by itself may refer to a different branch.
    final context = parts.skip(1).expand(words).toList();
    if (context.isNotEmpty) return context.any(candidate.contains);
    final name = words(parts.first);
    return name.isNotEmpty && name.every(candidate.contains);
  }
}
