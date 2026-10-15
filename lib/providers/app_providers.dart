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

class AlarmProgress {
  const AlarmProgress({
    required this.alarm,
    required this.status,
    required this.timeFired,
    required this.distanceFired,
    required this.triggerReason,
    required this.triggeredAt,
    this.distanceReady = true,
  });

  final DestinationAlarm alarm;
  final String status;
  final bool timeFired;
  final bool distanceFired;
  final String triggerReason;
  final int triggeredAt;
  final bool distanceReady;

  bool get live =>
      status == 'active' || status == 'triggered' || status == 'snoozed';
}

class AlarmController extends ChangeNotifier {
  AlarmController(this._storage, this._geofence, this._location, this._history);

  final StorageService _storage;
  final GeofenceService _geofence;
  final LocationService _location;
  final HistoryController _history;
  List<AlarmProgress> _entries = [];
  String? _selectedId;
  String? error;
  bool busy = false;
  bool restoring = true;
  bool _triggering = false;
  bool _syncing = false;

  List<AlarmProgress> get alarms => List.unmodifiable(_entries);
  AlarmProgress? get selected {
    for (final entry in _entries) {
      if (entry.alarm.id == _selectedId) return entry;
    }
    return _entries.isEmpty ? null : _entries.first;
  }

  DestinationAlarm? get active => selected?.alarm;
  String get status => selected?.status ?? 'inactive';
  bool get timeFired => selected?.timeFired ?? false;
  bool get distanceFired => selected?.distanceFired ?? false;
  String get triggerReason => selected?.triggerReason ?? 'distance';
  bool get hasTriggered => _entries.any((entry) => entry.status == 'triggered');

  void select(String id) {
    if (_selectedId == id || !_entries.any((e) => e.alarm.id == id)) return;
    _selectedId = id;
    notifyListeners();
  }

  AlarmProgress _parse(Map<String, dynamic> state) {
    final alertAt = state['alertAt'] as num?;
    return AlarmProgress(
      alarm: DestinationAlarm(
        id: state['id'] as String,
        place: Place(
          name: state['name'] as String,
          address: state['address'] as String? ?? '',
          latitude: (state['latitude'] as num).toDouble(),
          longitude: (state['longitude'] as num).toDouble(),
        ),
        radius: (state['radius'] as num).toDouble(),
        vibration: state['vibration'] as bool? ?? true,
        sound: state['sound'] as String? ?? 'Default alarm',
        startedAt: DateTime.fromMillisecondsSinceEpoch(
          (state['startedAt'] as num).toInt(),
        ),
        alertAt:
            alertAt == null
                ? null
                : DateTime.fromMillisecondsSinceEpoch(alertAt.toInt()),
        repeatDays: (state['repeatDays'] as num?)?.toInt() ?? 0,
        leadMinutes: (state['leadMinutes'] as num?)?.toInt() ?? 0,
        repeatStartDay:
            state['repeatStartDay'] == null
                ? null
                : DateTime.fromMillisecondsSinceEpoch(
                  (state['repeatStartDay'] as num).toInt(),
                ),
      ),
      status: state['status'] as String? ?? 'active',
      timeFired: state['timeFired'] == true,
      distanceFired: state['distanceFired'] == true,
      triggerReason: state['triggerReason'] as String? ?? 'distance',
      triggeredAt: (state['triggeredAt'] as num?)?.toInt() ?? 0,
      distanceReady: state['distanceReady'] as bool? ?? true,
    );
  }

  Future<void> _applyNativeStates(List<Map<String, dynamic>> states) async {
    final next = <AlarmProgress>[];
    for (final state in states) {
      final entry = _parse(state);
      if (entry.live) {
        next.add(entry);
      } else {
        await _history.add(
          TripRecord(
            alarm: entry.alarm,
            endedAt: DateTime.now(),
            status: entry.status,
          ),
        );
        await _geofence.multiForget(entry.alarm.id);
      }
    }
    final previousSignature = _entries.map(_signature).join('|');
    final nextSignature = next.map(_signature).join('|');
    final oldSelected = _selectedId;
    _entries = next;
    final ringing =
        next.where((entry) => entry.status == 'triggered').toList()
          ..sort((a, b) {
            final order = a.triggeredAt.compareTo(b.triggeredAt);
            return order != 0
                ? order
                : a.alarm.startedAt.compareTo(b.alarm.startedAt);
          });
    if (ringing.isNotEmpty) {
      _selectedId = ringing.first.alarm.id;
    } else if (!next.any((entry) => entry.alarm.id == _selectedId)) {
      _selectedId = next.isEmpty ? null : next.first.alarm.id;
    }
    if (previousSignature != nextSignature ||
        oldSelected != _selectedId ||
        error != null) {
      error = null;
      notifyListeners();
    }
  }

  String _signature(AlarmProgress entry) =>
      '${entry.alarm.id}:${entry.status}:${entry.timeFired}:'
      '${entry.distanceFired}:${entry.distanceReady}:${entry.alarm.alertAt}:'
      '${entry.triggerReason}:${entry.triggeredAt}';

  Future<void> restore() async {
    try {
      final legacyRaw = await _storage.getString('active_alarm');
      final states = await _geofence.multiStates();
      if (legacyRaw != null && legacyRaw.isNotEmpty) {
        final legacy = DestinationAlarm.fromJson(
          Map<String, dynamic>.from(jsonDecode(legacyRaw) as Map),
        );
        if (!states.any((state) => state['id'] == legacy.id)) {
          final legacyStatus = await _geofence.status();
          if (legacyStatus == 'completed' || legacyStatus == 'cancelled') {
            await _history.add(
              TripRecord(
                alarm: legacy,
                endedAt: DateTime.now(),
                status: legacyStatus,
              ),
            );
          }
        }
        await _storage.setString('active_alarm', '');
      }
      await _applyNativeStates(states);
      if (_entries.isNotEmpty) await _geofence.multiEnsure();
    } catch (e) {
      error = 'Could not restore destination alarms: $e';
    }
    restoring = false;
    notifyListeners();
  }

  Future<void> syncStatus() async {
    if (_syncing) return;
    _syncing = true;
    try {
      await _applyNativeStates(await _geofence.multiStates());
    } catch (e) {
      final nextError = e.toString();
      if (error != nextError) {
        error = nextError;
        notifyListeners();
      }
    } finally {
      _syncing = false;
    }
  }

  Future<void> start(
    Place place,
    double radius,
    bool vibration,
    String sound, [
    DateTime? alertAt,
    int repeatDays = 0,
    int leadMinutes = 0,
    DateTime? repeatStartDay,
  ]) async {
    busy = true;
    error = null;
    notifyListeners();
    var registered = false;
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
        repeatDays: repeatDays,
        leadMinutes: leadMinutes,
        repeatStartDay: repeatStartDay,
      );
      await _geofence.multiRegister(alarm);
      registered = true;
      _selectedId = alarm.id;
      final target =
          repeatStartDay ?? alertAt?.add(Duration(minutes: leadMinutes));
      final now = DateTime.now();
      final repeatDistanceReady =
          repeatDays == 0 ||
          (target != null &&
              target.year == now.year &&
              target.month == now.month &&
              target.day == now.day);
      if (repeatDistanceReady &&
          position.accuracy <= radius &&
          _location.distance(position, place.latitude, place.longitude) <=
              radius) {
        await _geofence.multiTrigger(alarm.id);
      }
      await _applyNativeStates(await _geofence.multiStates());
    } catch (e) {
      if (registered) {
        try {
          await _applyNativeStates(await _geofence.multiStates());
        } catch (_) {
          // The native alarm remains saved; the next status sync can recover it.
        }
      }
      error = e.toString();
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> cancel([String? id]) => _finish('cancelled', id);
  Future<void> stop([String? id]) => _finish('completed', id);

  Future<void> _finish(String result, String? targetId) async {
    final id = targetId ?? active?.id;
    if (id == null || !_entries.any((entry) => entry.alarm.id == id)) return;
    busy = true;
    notifyListeners();
    try {
      await _geofence.multiFinish(id, result);
      await _applyNativeStates(await _geofence.multiStates());
    } catch (e) {
      error = e.toString();
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> dismissCurrent([String? targetId]) async {
    final id = targetId ?? active?.id;
    if (id == null ||
        !_entries.any(
          (entry) => entry.alarm.id == id && entry.status == 'triggered',
        )) {
      return;
    }
    busy = true;
    notifyListeners();
    try {
      await _geofence.multiDismiss(id);
      await _applyNativeStates(await _geofence.multiStates());
    } catch (e) {
      error = e.toString();
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> snooze(int minutes, [String? targetId]) async {
    final id = targetId ?? active?.id;
    if (id == null ||
        !_entries.any(
          (entry) => entry.alarm.id == id && entry.status == 'triggered',
        )) {
      return;
    }
    try {
      await _geofence.multiSnooze(id, minutes);
      await _applyNativeStates(await _geofence.multiStates());
    } catch (e) {
      error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> checkVisiblePosition(Position position) async {
    if (_triggering) return;
    final reached =
        _entries
            .where(
              (entry) =>
                  entry.live &&
                  entry.distanceReady &&
                  !entry.distanceFired &&
                  position.accuracy <= entry.alarm.radius &&
                  _location.distance(
                        position,
                        entry.alarm.place.latitude,
                        entry.alarm.place.longitude,
                      ) <=
                      entry.alarm.radius,
            )
            .toList()
          ..sort(
            (a, b) => _location
                .distance(
                  position,
                  a.alarm.place.latitude,
                  a.alarm.place.longitude,
                )
                .compareTo(
                  _location.distance(
                    position,
                    b.alarm.place.latitude,
                    b.alarm.place.longitude,
                  ),
                ),
          );
    if (reached.isEmpty) return;
    _triggering = true;
    try {
      for (final entry in reached) {
        await _geofence.multiTrigger(entry.alarm.id);
      }
      await _applyNativeStates(await _geofence.multiStates());
    } catch (e) {
      error = e.toString();
      notifyListeners();
    } finally {
      _triggering = false;
    }
  }
}
