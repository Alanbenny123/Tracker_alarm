import 'package:flutter/material.dart';

import '../providers/app_providers.dart';

/// One subscription shared by every route; Android monitors while UI is paused.
class AlarmStatusListener extends StatefulWidget {
  const AlarmStatusListener({
    super.key,
    required this.controller,
    required this.child,
  });
  final AlarmController controller;
  final Widget child;

  @override
  State<AlarmStatusListener> createState() => _AlarmStatusListenerState();
}

class _AlarmStatusListenerState extends State<AlarmStatusListener>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    if (state == null ||
        state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive) {
      widget.controller.startStatusUpdates();
    }
  }

  @override
  void didUpdateWidget(covariant AlarmStatusListener oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.stopStatusUpdates();
      didChangeAppLifecycleState(
        WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed,
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.controller.startStatusUpdates();
    } else if (state != AppLifecycleState.inactive) {
      widget.controller.stopStatusUpdates();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.stopStatusUpdates();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
