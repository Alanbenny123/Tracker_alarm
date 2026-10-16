import 'dart:async';
import 'package:tracker_alarm/services/storage_service.dart';

class RawMemoryStorage extends StorageService {
  final values = <String, String>{};
  String? failReadKey;
  bool failWrites = false;
  Completer<void>? historyWriteGate;
  @override
  Future<String?> getString(String key) async {
    if (key == failReadKey) throw StateError('Read failed');
    return values[key];
  }

  @override
  Future<void> setString(String key, String value) async {
    if (key == 'history' && historyWriteGate != null) {
      await historyWriteGate!.future;
    }
    if (failWrites) throw StateError('Write failed');
    values[key] = value;
  }

  @override
  Future<bool?> getBool(String key) async => null;
  @override
  Future<double?> getDouble(String key) async => null;
}
