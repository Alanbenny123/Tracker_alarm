import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show Provider;
import 'package:flutter_riverpod/legacy.dart';
import 'package:geolocator/geolocator.dart';

import '../models/destination_alarm.dart';
import '../models/place.dart';
import '../models/repeat_schedule.dart';
import '../services/geofence_service.dart';
import '../services/location_service.dart';
import '../services/storage_service.dart';

final storageProvider = ChangeNotifierProvider<StorageService>(
  (ref) => StorageService(),
);
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
    try {
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
    } catch (_) {
      _storage.reportFailure(
        'settings',
        'Could not read app settings. Defaults are shown; stored settings have been kept.',
      );
    }
    notifyListeners();
  }

  Future<void> _save(
    Future<void> Function() write,
    void Function() update,
  ) async {
    try {
      await write();
      update();
      notifyListeners();
    } catch (_) {
      _storage.reportFailure(
        'settings',
        'Could not save app settings. The last displayed settings have been kept. Try again.',
      );
    }
  }

  Future<void> setTheme(ThemeModeSetting value) =>
      _save(() => _storage.setString('theme', value.name), () => theme = value);

  Future<void> setRadius(double value) {
    final radius = value.clamp(100, 2000).toDouble();
    return _save(
      () => _storage.setDouble('default_radius', radius),
      () => defaultRadius = radius,
    );
  }

  Future<void> setSound(String value) =>
      _save(() => _storage.setString('sound', value), () => sound = value);

  Future<void> setVibration(bool value) => _save(
    () => _storage.setBool('vibration', value),
    () => vibration = value,
  );
}

enum ThemeModeSetting { system, light, dark }

class _SerialMutations {
  Future<void> _tail = Future.value();
  Future<void> run(Future<void> Function() action) {
    final next = _tail.then((_) => action());
    _tail = next.catchError((Object _) {});
    return next;
  }
}

class PlacesController extends ChangeNotifier {
  PlacesController(this._storage);
  final StorageService _storage;
  final _mutations = _SerialMutations();
  List<Place> places = [];
  String? error;
  bool _loaded = false;
  Future<void>? _loadFuture;
  Future<void> load() => _loadFuture ??= _load();
  Future<void> reload() {
    _loaded = false;
    _loadFuture = null;
    return load();
  }

  Future<void> _load() async {
    try {
      places = await _storage.savedPlaces();
      _loaded = true;
      error = null;
    } catch (_) {
      error =
          'Could not read saved places. Retry before adding or removing places.';
    }
    notifyListeners();
  }

  Future<void> _save(List<Place> next) async {
    try {
      await _storage.setSavedPlaces(next);
      places = next;
      error = null;
      notifyListeners();
    } catch (_) {
      error = 'Could not save places. Your displayed list has been kept.';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> add(Place place, String name) => _mutations.run(() async {
    await load();
    if (!_loaded) throw StateError(error!);
    await _save([
      ...places,
      place.copyWith(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: name.trim(),
      ),
    ]);
  });

  Future<void> remove(String id) => _mutations.run(() async {
    await load();
    if (!_loaded) throw StateError(error!);
    await _save(places.where((place) => place.id != id).toList());
  });

  Future<void> clear() => _mutations.run(() async {
    await load();
    await _storage.clearSavedPlaces();
    places = [];
    _loaded = true;
    error = null;
    notifyListeners();
  });
}

class HistoryController extends ChangeNotifier {
  HistoryController(this._storage);
  final StorageService _storage;
  final _mutations = _SerialMutations();
  List<TripRecord> trips = [];
  String? error;
  bool _loaded = false;
  Future<void>? _loadFuture;
  Future<void> load() => _loadFuture ??= _load();
  Future<void> reload() {
    _loaded = false;
    _loadFuture = null;
    return load();
  }

  Future<void> _load() async {
    try {
      trips = StorageService.boundedHistory(await _storage.history());
      _loaded = true;
      error = null;
    } catch (_) {
      error =
          'Could not read trip history. Finished alarms will be kept until you retry.';
    }
    notifyListeners();
  }

  Future<void> add(TripRecord trip) => _mutations.run(() async {
    await load();
    if (!_loaded) throw StateError(error!);
    if (trips.any((existing) => existing.alarm.id == trip.alarm.id)) return;
    final next = StorageService.boundedHistory([trip, ...trips]);
    try {
      // Publish only after persistence succeeds; failed archival can be retried
      // without treating an unsaved trip as a duplicate and forgetting it.
      await _storage.setHistory(next);
      trips = next;
      error = null;
      notifyListeners();
    } catch (_) {
      error =
          'Could not save trip history. Finished alarms are kept for retry.';
      notifyListeners();
      rethrow;
    }
  });

  Future<void> clear() => _mutations.run(() async {
    await load();
    await _storage.clearHistory();
    trips = [];
    _loaded = true;
    error = null;
    notifyListeners();
  });
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
    this.monitoringMessage,
    this.monitoringHealthy,
    this.gpsStatus,
    this.geofenceStatus,
    this.lastGpsFixAt,
    this.gpsAccuracy,
    this.nextRepeatAt,
  });

  final DestinationAlarm alarm;
  final String status;
  final bool timeFired;
  final bool distanceFired;
  final String triggerReason;
  final int triggeredAt;
  final bool distanceReady;
  final String? monitoringMessage;
  final bool? monitoringHealthy;
  final String? gpsStatus;
  final String? geofenceStatus;
  final DateTime? lastGpsFixAt;
  final double? gpsAccuracy;
  final DateTime? nextRepeatAt;

  bool get live =>
      status == 'active' ||
      status == 'triggered' ||
      status == 'snoozed' ||
      status == 'paused';
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
  Future<void>? _syncFuture;
  String? storageWarning;

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
        label: state['label'] as String? ?? '',
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
      monitoringMessage: state['monitoringMessage'] as String?,
      monitoringHealthy: state['monitoringHealthy'] as bool?,
      gpsStatus: state['gpsStatus'] as String?,
      geofenceStatus: state['geofenceStatus'] as String?,
      lastGpsFixAt:
          state['lastGpsFixAt'] == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(
                (state['lastGpsFixAt'] as num).toInt(),
              ),
      gpsAccuracy: (state['gpsAccuracy'] as num?)?.toDouble(),
      nextRepeatAt:
          state['nextRepeatAt'] == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(
                (state['nextRepeatAt'] as num).toInt(),
              ),
    );
  }

  Future<void> _applyNativeStates(List<Map<String, dynamic>> states) async {
    final parsed = states.map(_parse).toList();
    final next = parsed.where((entry) => entry.live).toList();
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
    for (final entry in parsed.where((entry) => !entry.live)) {
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

  String _signature(AlarmProgress entry) =>
      '${entry.alarm.id}:${entry.status}:${entry.timeFired}:'
      '${entry.distanceFired}:${entry.distanceReady}:${entry.alarm.alertAt}:'
      '${entry.triggerReason}:${entry.triggeredAt}:${entry.monitoringMessage}:'
      '${entry.monitoringHealthy}:${entry.gpsStatus}:${entry.geofenceStatus}:'
      '${entry.lastGpsFixAt}:${entry.gpsAccuracy}:${entry.nextRepeatAt}:'
      '${entry.alarm.label}:${entry.alarm.place.toJson()}:${entry.alarm.radius}:${entry.alarm.sound}:${entry.alarm.vibration}:${entry.alarm.repeatDays}';

  Future<void> restore() async {
    try {
      final legacyRaw = await _storage.getString('active_alarm');
      final states = await _geofence.multiStates();
      await _applyNativeStates(states);
      if (legacyRaw != null && legacyRaw.isNotEmpty) {
        DestinationAlarm? legacy;
        try {
          legacy = DestinationAlarm.fromJson(
            Map<String, dynamic>.from(jsonDecode(legacyRaw) as Map),
          );
        } on FormatException {
          await _storage.preserveDamagedLegacy(legacyRaw);
        } on TypeError {
          await _storage.preserveDamagedLegacy(legacyRaw);
        }
        if (legacy != null) {
          if (!states.any((state) => state['id'] == legacy!.id)) {
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
      }
      storageWarning = await _geofence.storageWarning();
      if (_entries.isNotEmpty) await _geofence.multiEnsure();
    } catch (e) {
      error = 'Could not restore destination alarms: $e';
    }
    restoring = false;
    notifyListeners();
  }

  Future<void> syncStatus() =>
      _syncFuture ??= _syncStatus().whenComplete(() {
        _syncFuture = null;
      });

  Future<void> _syncStatus() async {
    try {
      await _applyNativeStates(await _geofence.multiStates());
      final warning = await _geofence.storageWarning();
      if (warning != storageWarning) {
        storageWarning = warning;
        notifyListeners();
      }
    } catch (e) {
      final nextError = e.toString();
      if (error != nextError) {
        error = nextError;
        notifyListeners();
      }
    }
  }

  Future<void> clearTripHistory() async {
    await syncStatus();
    await _geofence.clearFinished();
    await _history.clear();
    await _geofence.clearStorageRecovery();
    storageWarning = null;
    notifyListeners();
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
    String label = '',
  ]) async {
    if (busy) throw StateError('An alarm change is already in progress.');
    busy = true;
    error = null;
    notifyListeners();
    var registered = false;
    try {
      final requirements = await _geofence.requirements();
      if (!requirements.ready) {
        throw LocationException(requirements.missingMessage);
      }
      final now = DateTime.now();
      final firstRepeatDay =
          repeatDays == 0 || alertAt != null
              ? repeatStartDay
              : repeatStartDay ?? nextRepeatDay(repeatDays, now);
      final target =
          firstRepeatDay ?? alertAt?.add(Duration(minutes: leadMinutes));
      final repeatDistanceReady =
          repeatDays == 0 ||
          (target != null &&
              target.year == now.year &&
              target.month == now.month &&
              target.day == now.day);
      // Future repeat days need saved coordinates and permissions, not a GPS fix
      // at creation time. The native tracker acquires GPS on the selected day.
      final position = repeatDistanceReady ? await _location.current() : null;
      final alarm = DestinationAlarm(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        place: place,
        label: label.trim(),
        radius: radius,
        vibration: vibration,
        sound: sound,
        startedAt: DateTime.now(),
        alertAt: alertAt,
        repeatDays: repeatDays,
        leadMinutes: leadMinutes,
        repeatStartDay: firstRepeatDay,
      );
      await _geofence.multiRegister(alarm);
      registered = true;
      _selectedId = alarm.id;
      if (position != null &&
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

  Future<void> _manage(Future<void> Function() action) async {
    if (busy) throw StateError('An alarm change is already in progress.');
    busy = true;
    error = null;
    notifyListeners();
    try {
      await action();
      await _applyNativeStates(await _geofence.multiStates());
    } catch (e) {
      error = e.toString();
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> renameAlarm(String id, String label) =>
      _manage(() => _geofence.renameAlarm(id, label.trim()));

  Future<void> pauseAlarm(String id, bool paused) => _manage(() async {
    if (!paused) {
      final requirements = await _geofence.requirements();
      if (!requirements.ready) {
        throw LocationException(requirements.missingMessage);
      }
    }
    await _geofence.pauseAlarm(id, paused);
  });

  Future<void> updateAlarm(
    String id,
    Place place,
    double radius,
    bool vibration,
    String sound,
    int days,
    String label,
  ) => _manage(() async {
    final latest = await _geofence.multiStates();
    await _applyNativeStates(latest);
    final current = _entries.where((entry) => entry.alarm.id == id).firstOrNull;
    if (current == null ||
        (current.status != 'active' && current.status != 'paused')) {
      throw StateError('Stop the ringing alert before editing this alarm.');
    }
    if (current.status != 'paused') {
      final requirements = await _geofence.requirements();
      if (!requirements.ready) {
        throw LocationException(requirements.missingMessage);
      }
    }
    await _geofence.updateAlarm(
      id,
      place,
      radius,
      vibration,
      sound,
      days,
      label.trim(),
    );
    _selectedId = id;
  });

  Future<void> cancel([String? id]) => _finish('cancelled', id);
  Future<void> stop([String? id]) => _finish('completed', id);

  Future<void> setRepeatDays(String id, int days) async {
    busy = true;
    notifyListeners();
    try {
      await _geofence.multiUpdateRepeat(id, days);
      await _applyNativeStates(await _geofence.multiStates());
    } catch (e) {
      error = e.toString();
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

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
                  entry.status != 'paused' &&
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
