import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show Provider;
import 'package:flutter_riverpod/legacy.dart';
import 'package:geolocator/geolocator.dart';

import '../models/destination_alarm.dart';
import '../models/place.dart';
import '../services/geofence_service.dart';
import '../services/location_service.dart';
import '../services/storage_service.dart';

final storageProvider = Provider<StorageService>((ref) => StorageService());
final geofenceProvider = Provider<GeofenceService>((ref) => GeofenceService());
final locationServiceProvider = Provider<LocationService>(
  (ref) => LocationService(),
);

final settingsProvider = ChangeNotifierProvider<SettingsController>(
  (ref) => SettingsController(ref.read(storageProvider))..load(),
);
final placesProvider = ChangeNotifierProvider<PlacesController>(
  (ref) => PlacesController(ref.read(storageProvider))..load(),
);
final historyProvider = ChangeNotifierProvider<HistoryController>(
  (ref) => HistoryController(ref.read(storageProvider))..load(),
);
final locationProvider = ChangeNotifierProvider<LocationController>(
  (ref) => LocationController(ref.read(locationServiceProvider)),
);
final alarmProvider = ChangeNotifierProvider<AlarmController>(
  (ref) => AlarmController(
    ref.read(storageProvider),
    ref.read(geofenceProvider),
    ref.read(locationServiceProvider),
    ref.read(historyProvider),
  )..restore(),
);

class SettingsController extends ChangeNotifier {
  SettingsController(this._storage);
  final StorageService _storage;
  ThemeModeSetting theme = ThemeModeSetting.system;
  double defaultRadius = 500;
  String sound = 'Default alarm';
  bool vibration = true;

  Future<void> load() async {
    final storedTheme = await _storage.getString('theme');
    theme = ThemeModeSetting.values.firstWhere(
      (e) => e.name == storedTheme,
      orElse: () => ThemeModeSetting.system,
    );
    defaultRadius =
        (await _storage.getDouble('default_radius') ?? 500)
            .clamp(100, 2000)
            .toDouble();
    sound = await _storage.getString('sound') ?? 'Default alarm';
    vibration = await _storage.getBool('vibration') ?? true;
    notifyListeners();
  }

  Future<void> setTheme(ThemeModeSetting value) async {
    theme = value;
    notifyListeners();
    await _storage.setString('theme', value.name);
  }

  Future<void> setRadius(double value) async {
    defaultRadius = value.clamp(100, 2000).toDouble();
    notifyListeners();
    await _storage.setDouble('default_radius', defaultRadius);
  }

  Future<void> setSound(String value) async {
    sound = value;
    notifyListeners();
    await _storage.setString('sound', value);
  }

  Future<void> setVibration(bool value) async {
    vibration = value;
    notifyListeners();
    await _storage.setBool('vibration', value);
  }
}

enum ThemeModeSetting { system, light, dark }

class PlacesController extends ChangeNotifier {
  PlacesController(this._storage);
  final StorageService _storage;
  List<Place> places = [];
  Future<void>? _loadFuture;
  Future<void> load() => _loadFuture ??= _load();
  Future<void> _load() async {
    places = await _storage.savedPlaces();
    notifyListeners();
  }

  Future<void> add(Place place, String name) async {
    await load();
    places = [
      ...places,
      place.copyWith(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: name.trim(),
      ),
    ];
    notifyListeners();
    await _storage.setSavedPlaces(places);
  }

  Future<void> remove(String id) async {
    await load();
    places = places.where((e) => e.id != id).toList();
    notifyListeners();
    await _storage.setSavedPlaces(places);
  }
}

class HistoryController extends ChangeNotifier {
  HistoryController(this._storage);
  final StorageService _storage;
  List<TripRecord> trips = [];
  Future<void>? _loadFuture;
  Future<void> load() => _loadFuture ??= _load();
  Future<void> _load() async {
    trips = await _storage.history();
    notifyListeners();
  }

  Future<void> add(TripRecord trip) async {
    await load();
    if (trips.any((existing) => existing.alarm.id == trip.alarm.id)) return;
    trips = [trip, ...trips];
    notifyListeners();
    await _storage.setHistory(trips);
  }
}

class LocationController extends ChangeNotifier {
  LocationController(this._service);
  final LocationService _service;
  Position? position;
  String? error;
  bool loading = false;
  StreamSubscription<Position>? _subscription;
  Future<void>? _refreshFuture;
  bool _trackingRequested = false;

  Future<void> refresh() =>
      _refreshFuture ??= _refresh().whenComplete(() {
        _refreshFuture = null;
      });

  Future<void> _refresh() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      position = await _service.current();
    } catch (e) {
      position = null;
      error = e.toString();
    }
    loading = false;
    notifyListeners();
  }

  Future<void> refreshAndTrack() async {
    _trackingRequested = true;
    await refresh();
    if (_trackingRequested && position != null) startVisibleUpdates();
  }

  void startVisibleUpdates() {
    _subscription ??= _service.visibleUpdates().listen(
      (value) {
        position = value;
        error = null;
        notifyListeners();
      },
      onError: (Object e) {
        error = e.toString();
        _subscription?.cancel();
        _subscription = null;
        notifyListeners();
      },
    );
  }

  void stopVisibleUpdates() {
    _trackingRequested = false;
    _subscription?.cancel();
    _subscription = null;
  }

  @override
  void dispose() {
    stopVisibleUpdates();
    super.dispose();
  }
}

class AlarmController extends ChangeNotifier {
  AlarmController(this._storage, this._geofence, this._location, this._history);
  final StorageService _storage;
  final GeofenceService _geofence;
  final LocationService _location;
  final HistoryController _history;
  DestinationAlarm? active;
  String status = 'inactive';
  String? error;
  bool busy = false;
  bool restoring = true;
  bool _triggering = false;
  bool _syncing = false;
  bool timeFired = false;
  bool distanceFired = false;
  String triggerReason = 'distance';

  bool _readProgress(Map<String, dynamic>? native) {
    if (native == null) return false;
    final nextTime = native['timeFired'] == true;
    final nextDistance = native['distanceFired'] == true;
    final nextReason = native['triggerReason'] as String? ?? 'distance';
    final changed =
        nextTime != timeFired ||
        nextDistance != distanceFired ||
        nextReason != triggerReason;
    timeFired = nextTime;
    distanceFired = nextDistance;
    triggerReason = nextReason;
    return changed;
  }

  Future<void> restore() async {
    try {
      final raw = await _storage.getString('active_alarm');
      if (raw != null && raw.isNotEmpty) {
        active = DestinationAlarm.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map),
        );
      }
      status = await _geofence.status();
      if (active == null &&
          (status == 'active' ||
              status == 'snoozed' ||
              status == 'triggered')) {
        final native = await _geofence.state();
        if (native != null) {
          active = DestinationAlarm(
            id: native['id'] as String,
            place: Place(
              name: native['name'] as String,
              address: native['address'] as String,
              latitude: (native['latitude'] as num).toDouble(),
              longitude: (native['longitude'] as num).toDouble(),
            ),
            radius: (native['radius'] as num).toDouble(),
            vibration: native['vibration'] as bool,
            sound: native['sound'] as String,
            startedAt: DateTime.fromMillisecondsSinceEpoch(
              (native['startedAt'] as num).toInt(),
            ),
            alertAt:
                native['alertAt'] == null
                    ? null
                    : DateTime.fromMillisecondsSinceEpoch(
                      (native['alertAt'] as num).toInt(),
                    ),
          );
          await _storage.setString(
            'active_alarm',
            jsonEncode(active!.toJson()),
          );
        }
      }
      if (active != null && (status == 'completed' || status == 'cancelled')) {
        await _archiveNativeFinish(status);
      }
      if (active != null && status == 'inactive') {
        await _geofence.register(active!);
        status = 'active';
      } else if (active != null &&
          (status == 'active' || status == 'snoozed')) {
        await _geofence.ensure();
      } else if (active != null && status == 'triggered') {
        await _geofence.resumeTriggered();
      }
      if (active != null) _readProgress(await _geofence.state());
    } catch (e) {
      error = 'Could not restore the active alarm: $e';
    }
    restoring = false;
    notifyListeners();
  }

  Future<void> syncStatus() async {
    if (active == null || _syncing) return;
    final currentAlarm = active;
    _syncing = true;
    try {
      final nextStatus = await _geofence.status();
      if (active != currentAlarm) return;
      final native = await _geofence.state();
      if (active != currentAlarm) return;
      final progressChanged = _readProgress(native);
      final changed = nextStatus != status || error != null || progressChanged;
      status = nextStatus;
      if (status == 'completed' || status == 'cancelled') {
        await _archiveNativeFinish(status);
        notifyListeners();
      } else if (changed) {
        error = null;
        notifyListeners();
      }
    } catch (e) {
      if (active != currentAlarm) return;
      final nextError = e.toString();
      if (error != nextError) {
        error = nextError;
        notifyListeners();
      }
    } finally {
      _syncing = false;
    }
  }

  Future<void> _archiveNativeFinish(String result) async {
    final alarm = active;
    if (alarm == null) return;
    await _history.add(
      TripRecord(alarm: alarm, endedAt: DateTime.now(), status: result),
    );
    await _storage.setString('active_alarm', '');
    active = null;
    status = 'inactive';
  }

  Future<void> start(
    Place place,
    double radius,
    bool vibration,
    String sound, [
    DateTime? alertAt,
  ]) async {
    if (active != null) {
      throw StateError(
        'Cancel the current destination alarm before starting another.',
      );
    }
    busy = true;
    error = null;
    notifyListeners();
    try {
      final requirements = await _geofence.requirements();
      if (!requirements.ready) {
        throw LocationException(requirements.missingMessage);
      }
      final position = await _location.current();
      final alarm = DestinationAlarm(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        place: place,
        radius: radius,
        vibration: vibration,
        sound: sound,
        startedAt: DateTime.now(),
        alertAt: alertAt,
      );
      await _geofence.register(alarm);
      await _storage.setString('active_alarm', jsonEncode(alarm.toJson()));
      active = alarm;
      status = 'active';
      timeFired = false;
      distanceFired = false;
      triggerReason = 'distance';
      if (_location.distance(position, place.latitude, place.longitude) <=
          radius) {
        await _geofence.trigger();
        status = await _geofence.status();
        _readProgress(await _geofence.state());
      }
    } catch (e) {
      error = e.toString();
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> cancel() => _finish('cancelled');
  Future<void> stop() => _finish('completed');

  Future<void> dismissCurrent() async {
    if (active == null || status != 'triggered') return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      await _geofence.dismissCurrent();
      status = await _geofence.status();
      if (status == 'completed') {
        await _archiveNativeFinish('completed');
      } else {
        _readProgress(await _geofence.state());
      }
    } catch (e) {
      error = e.toString();
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> _finish(String result) async {
    final alarm = active;
    if (alarm == null) return;
    busy = true;
    notifyListeners();
    try {
      if (result == 'completed') {
        await _geofence.stop();
      } else {
        await _geofence.cancel();
      }
      await _history.add(
        TripRecord(alarm: alarm, endedAt: DateTime.now(), status: result),
      );
      await _storage.setString('active_alarm', '');
      active = null;
      status = 'inactive';
      error = null;
    } catch (e) {
      error = e.toString();
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> snooze(int minutes) async {
    try {
      await _geofence.snooze(minutes);
      status = 'snoozed';
      notifyListeners();
    } catch (e) {
      error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> checkVisiblePosition(Position position) async {
    final alarm = active;
    if (alarm == null ||
        distanceFired ||
        (status != 'active' && status != 'triggered') ||
        _triggering) {
      return;
    }
    if (_location.distance(
          position,
          alarm.place.latitude,
          alarm.place.longitude,
        ) >
        alarm.radius) {
      return;
    }
    _triggering = true;
    try {
      await _geofence.trigger();
      status = await _geofence.status();
      _readProgress(await _geofence.state());
      notifyListeners();
    } catch (e) {
      error = e.toString();
      notifyListeners();
    } finally {
      _triggering = false;
    }
  }
}
