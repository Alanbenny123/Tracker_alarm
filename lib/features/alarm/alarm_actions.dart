import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/alarm_setup_args.dart';
import '../../models/travel_mode.dart';
import '../../providers/app_providers.dart';

class AlarmActions extends ConsumerWidget {
  const AlarmActions({super.key, required this.entry});
  final AlarmProgress entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(alarmProvider);
    final editable = entry.status == 'active' || entry.status == 'paused';
    return PopupMenuButton<String>(
      tooltip: 'Manage ${entry.alarm.displayName}',
      enabled: !controller.busy,
      onSelected: (action) async {
        if (action == 'edit' || action == 'duplicate') {
          context.push(
            '/setup',
            extra: AlarmSetupArgs(
              place: entry.alarm.place,
              mode: TravelMode.other,
              initialAlarm: entry.alarm,
              editing: action == 'edit',
              duplicating: action == 'duplicate',
            ),
          );
          return;
        }
        try {
          if (action == 'rename') {
            final label = await showDialog<String>(
              context: context,
              builder:
                  (_) => _RenameAlarmDialog(
                    label: entry.alarm.label,
                    destination: entry.alarm.place.name,
                  ),
            );
            if (label != null && context.mounted) {
              await controller.renameAlarm(entry.alarm.id, label);
            }
          } else if (action == 'pause') {
            final paused = entry.status != 'paused';
            await controller.pauseAlarm(entry.alarm.id, paused);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    paused
                        ? 'Alarm paused. Resume it when you want alerts again.'
                        : 'Alarm resumed.',
                  ),
                ),
              );
            }
          }
        } catch (_) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  controller.error ?? 'Could not change this alarm. Try again.',
                ),
              ),
            );
          }
        }
      },
      itemBuilder:
          (_) => [
            const PopupMenuItem(value: 'rename', child: Text('Rename')),
            if (editable)
              const PopupMenuItem(
                value: 'edit',
                child: Text('Edit destination and settings'),
              ),
            PopupMenuItem(
              value: 'duplicate',
              enabled: controller.alarms.length < 10,
              child: const Text('Duplicate'),
            ),
            if (editable)
              PopupMenuItem(
                value: 'pause',
                child: Text(entry.status == 'paused' ? 'Resume' : 'Pause'),
              ),
          ],
    );
  }
}

class _RenameAlarmDialog extends StatefulWidget {
  const _RenameAlarmDialog({required this.label, required this.destination});
  final String label;
  final String destination;
  @override
  State<_RenameAlarmDialog> createState() => _RenameAlarmDialogState();
}

class _RenameAlarmDialogState extends State<_RenameAlarmDialog> {
  late final controller = TextEditingController(text: widget.label);
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Name this alarm'),
    content: TextField(
      controller: controller,
      autofocus: true,
      maxLength: 80,
      decoration: InputDecoration(
        hintText: widget.destination,
        helperText: 'Leave blank to use the destination name',
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, controller.text.trim()),
        child: const Text('Save'),
      ),
    ],
  );
}
