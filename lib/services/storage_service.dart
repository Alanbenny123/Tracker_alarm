import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/destination_alarm.dart';
import '../models/place.dart';

class StorageService {
  late final SharedPreferencesAsync _prefs = SharedPreferencesAsync();

  Future<List<Place>> savedPlaces() async =>
      _readList('saved_places', Place.fromJson);
  Future<void> setSavedPlaces(List<Place> places) => _prefs.setString(
    'saved_places',
    jsonEncode(places.map((e) => e.toJson()).toList()),
  );
  Future<List<TripRecord>> history() async =>
      _readList('history', TripRecord.fromJson);
  Future<void> setHistory(List<TripRecord> trips) => _prefs.setString(
    'history',
    jsonEncode(trips.map((e) => e.toJson()).toList()),
  );
  Future<String?> getString(String key) => _prefs.getString(key);
  Future<void> setString(String key, String value) =>
      _prefs.setString(key, value);
  Future<bool?> getBool(String key) => _prefs.getBool(key);
  Future<void> setBool(String key, bool value) => _prefs.setBool(key, value);
  Future<double?> getDouble(String key) => _prefs.getDouble(key);
  Future<void> setDouble(String key, double value) =>
      _prefs.setDouble(key, value);

  Future<List<T>> _readList<T>(
    String key,
    T Function(Map<String, dynamic>) decode,
  ) async {
    try {
      final raw = await _prefs.getString(key);
      if (raw == null) return [];
      return (jsonDecode(raw) as List)
          .map((e) => decode(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }
}
