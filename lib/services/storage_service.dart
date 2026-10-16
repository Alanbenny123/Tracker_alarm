import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/destination_alarm.dart';
import '../models/place.dart';

class StorageService extends ChangeNotifier {
  late final SharedPreferencesAsync _prefs = SharedPreferencesAsync();
  static const historyLimit = 100;
  final Map<String, String> _warnings = {};
  List<String> get warnings => List.unmodifiable(_warnings.values);

  Future<List<Place>> savedPlaces() => _readList('saved_places', (json) {
    final place = Place.fromJson(json);
    if (place.id == null || place.id!.trim().isEmpty) {
      throw const FormatException('Missing saved place ID');
    }
    return place;
  });

  void reportFailure(String key, String message) {
    _warnings[key] = message;
    notifyListeners();
  }

  Future<void> setSavedPlaces(List<Place> places) => _writeList(
    'saved_places',
    places.map((place) => place.toJson()).toList(),
  );

  Future<List<TripRecord>> history() async {
    final trips = await _readList('history', TripRecord.fromJson);
    final bounded = boundedHistory(trips);
    if (bounded.length != trips.length) await setHistory(bounded);
    return bounded;
  }

  static List<TripRecord> boundedHistory(Iterable<TripRecord> trips) {
    final sorted =
        trips.toList()..sort((a, b) => b.endedAt.compareTo(a.endedAt));
    final ids = <String>{};
    return sorted
        .where((trip) => ids.add(trip.alarm.id))
        .take(historyLimit)
        .toList();
  }

  Future<void> setHistory(List<TripRecord> trips) => _writeList(
    'history',
    boundedHistory(trips).map((trip) => trip.toJson()).toList(),
  );

  Future<void> clearHistory() => _clearList('history');
  Future<void> clearSavedPlaces() => _clearList('saved_places');

  Future<void> _clearList(String key) async {
    await setString(key, '[]');
    await setString('last_good_$key', '[]');
    await setString('recovery_$key', '');
    _warnings.remove(key);
    notifyListeners();
  }

  Future<void> clearRecoveryCopies() async {
    for (final key in ['history', 'saved_places', 'active_alarm']) {
      await setString('recovery_$key', '');
    }
    for (final key in ['history', 'saved_places', 'active_alarm']) {
      _warnings.remove(key);
    }
    notifyListeners();
  }

  Future<void> preserveDamagedLegacy(String raw) async {
    await setString('recovery_active_alarm', raw);
    await setString('active_alarm', '');
    _warnings['active_alarm'] =
        'An old alarm could not be read. A damaged copy is kept locally; recreate that alarm.';
    notifyListeners();
  }

  Future<String?> getString(String key) => _prefs.getString(key);
  Future<void> setString(String key, String value) =>
      _prefs.setString(key, value);
  Future<bool?> getBool(String key) => _prefs.getBool(key);
  Future<void> setBool(String key, bool value) => _prefs.setBool(key, value);
  Future<double?> getDouble(String key) => _prefs.getDouble(key);
  Future<void> setDouble(String key, double value) =>
      _prefs.setDouble(key, value);

  Future<void> _writeList(String key, List<Map<String, dynamic>> values) async {
    final encoded = jsonEncode(values);
    await setString(key, encoded);
    await setString('last_good_$key', encoded);
  }

  (List<T>, List<Map<String, dynamic>>, bool) _decodeList<T>(
    String raw,
    T Function(Map<String, dynamic>) decode,
  ) {
    final body = jsonDecode(raw);
    if (body is! List) throw const FormatException('Expected a saved list');
    final entries = <T>[];
    final valid = <Map<String, dynamic>>[];
    var damaged = false;
    for (final item in body) {
      try {
        if (item is! Map) throw const FormatException('Invalid saved entry');
        final value = Map<String, dynamic>.from(item);
        entries.add(decode(value));
        valid.add(value);
      } on FormatException {
        damaged = true;
      } on TypeError {
        damaged = true;
      } on ArgumentError {
        damaged = true;
      }
    }
    return (entries, valid, damaged);
  }

  Future<List<T>> _readList<T>(
    String key,
    T Function(Map<String, dynamic>) decode,
  ) async {
    // I/O failures propagate. They must not look like an empty list that is safe
    // to overwrite, or allow an unarchived native alarm to be forgotten.
    final raw = await getString(key);
    if (raw == null || raw.isEmpty) return [];
    (List<T>, List<Map<String, dynamic>>, bool) result;
    try {
      result = _decodeList(raw, decode);
    } on FormatException {
      final backup = await getString('last_good_$key');
      try {
        result = _decodeList(backup ?? '[]', decode);
      } on FormatException {
        result = (<T>[], <Map<String, dynamic>>[], true);
      }
      result = (result.$1, result.$2, true);
    }
    if (result.$3) {
      await setString('recovery_$key', raw);
      await _writeList(key, result.$2);
      final name = key == 'history' ? 'Trip history' : 'Saved places';
      _warnings[key] =
          '$name contained damaged data. ${result.$1.length} valid entries recovered. A damaged copy is kept locally.';
      notifyListeners();
    } else {
      await setString('last_good_$key', jsonEncode(result.$2));
      if ((await getString('recovery_$key'))?.isNotEmpty == true) {
        _warnings[key] =
            '${key == 'history' ? 'Trip history' : 'Saved places'} was repaired. A damaged copy is kept locally.';
        notifyListeners();
      }
    }
    return result.$1;
  }
}
