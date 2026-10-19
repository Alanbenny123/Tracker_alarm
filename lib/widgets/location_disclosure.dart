import 'package:flutter/material.dart';

/// Show this before opening Android's location permission prompt or settings.
Future<bool> showLocationDisclosure(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Allow location for destination alarms?'),
        content: const Text(
          'Destination Alarm uses your location to show nearby places and '
          'measure your distance to a destination. While an alarm is active, '
          'it also collects location when the app is closed or not in use, '
          'so it can alert you when you get close. A monitoring notification '
          'stays visible, and you can stop the alarm at any time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    ) ??
    false;
