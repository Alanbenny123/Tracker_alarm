import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/app_providers.dart';

class TestAlarmButton extends ConsumerWidget {
  const TestAlarmButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListTile(
    leading: const Icon(Icons.volume_up_outlined),
    title: const Text('Test alarm'),
    subtitle: const Text('Check sound, vibration, and the lock-screen alert'),
    onTap: () async {
      final settings = ref.read(settingsProvider);
      final start = await showDialog<bool>(
        context: context,
        builder:
            (dialogContext) => AlertDialog(
              title: const Text('Test alarm'),
              content: Text(
                'Sound: ${settings.sound}\nVibration: ${settings.vibration ? 'On' : 'Off'}\n\nThe test rings in 5 seconds and stops after 10 seconds. Lock your phone after starting to check its alarm screen.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Start test'),
                ),
              ],
            ),
      );
      if (start != true || !context.mounted) return;
      try {
        final service = ref.read(geofenceProvider);
        final requirements = await service.requirements();
        if (!requirements.notifications || !requirements.fullScreenAlarms) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Allow alarm notifications and lock-screen alarms in Android settings before testing.',
              ),
            ),
          );
          return;
        }
        await service.startTestAlarm(settings.sound, settings.vibration);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 16),
            content: const Text(
              'Test alarm in 5 seconds. Lock your phone to check its alert.',
            ),
            action: SnackBarAction(
              label: 'Stop test',
              onPressed: () async {
                try {
                  await service.stopTestAlarm();
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Use Stop test in the notification. The test ends automatically.',
                        ),
                      ),
                    );
                  }
                }
              },
            ),
          ),
        );
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Could not start the test. Stop any ringing alert and recheck phone settings.',
              ),
            ),
          );
        }
      }
    },
  );
}
