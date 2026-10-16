import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracker_alarm/providers/app_providers.dart';

import 'helpers/alarm_fakes.dart';

class _Native extends FakeNative {
  _Native() {
    events = StreamController<void>.broadcast(
      sync: true,
      onListen: () => listeners++,
      onCancel: () => listeners--,
    );
  }
  late final StreamController<void> events;
  int listeners = 0;
  int reads = 0;
  Completer<List<Map<String, dynamic>>>? blocked;
  @override
  Stream<void> get statusChanges => events.stream;
  @override
  Future<List<Map<String, dynamic>>> multiStates() {
    reads++;
    final pending = blocked;
    blocked = null;
    return pending?.future ?? super.multiStates();
  }
}

Future<AlarmController> _controller(_Native native) async {
  final store = MemoryStorage();
  final controller = AlarmController(
    store,
    native,
    FakeLocation(),
    HistoryController(store),
  );
  await controller.restore();
  await controller.start(stationA, 500, true, 'Bell');
  return controller;
}

void main() {
  test('one subscription updates all alarms and stops cleanly', () async {
    final native = _Native();
    final controller = await _controller(native);
    controller.startStatusUpdates();
    controller.startStatusUpdates();
    await controller.syncStatus();
    expect(native.listeners, 1);
    await native.multiTrigger(controller.active!.id);
    native.events.add(null);
    await controller.syncStatus();
    expect(controller.hasTriggered, isTrue);
    controller.stopStatusUpdates();
    await Future<void>.delayed(Duration.zero);
    expect(native.listeners, 0);
    final reads = native.reads;
    native.events.add(null);
    await Future<void>.delayed(Duration.zero);
    expect(native.reads, reads);
    controller.dispose();
    await native.events.close();
  });

  test(
    'an event arriving during a snapshot read queues the newer state',
    () async {
      final native = _Native();
      final controller = await _controller(native);
      controller.startStatusUpdates();
      await controller.syncStatus();
      final old = await native.multiStates();
      final block = Completer<List<Map<String, dynamic>>>();
      native.blocked = block;
      final reads = native.reads;
      final pending = controller.syncStatus();
      await native.multiTrigger(controller.active!.id);
      native.events.add(null);
      block.complete(old);
      await pending;
      expect(controller.hasTriggered, isTrue);
      expect(native.reads - reads, 2);
      controller.dispose();
      await native.events.close();
    },
  );

  test(
    'reattaching refreshes missed events and dispose ignores a late snapshot',
    () async {
      final native = _Native();
      final controller = await _controller(native);
      controller.startStatusUpdates();
      await controller.syncStatus();
      controller.stopStatusUpdates();
      await native.multiTrigger(controller.active!.id);
      controller.startStatusUpdates();
      await controller.syncStatus();
      expect(controller.hasTriggered, isTrue);
      final block = Completer<List<Map<String, dynamic>>>();
      native.blocked = block;
      final pending = controller.syncStatus();
      controller.dispose();
      block.complete([]);
      await pending;
      await Future<void>.delayed(Duration.zero);
      expect(native.listeners, 0);
      await native.events.close();
    },
  );
}
