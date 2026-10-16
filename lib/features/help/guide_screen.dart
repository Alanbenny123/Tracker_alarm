import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class GuideScreen extends StatelessWidget {
  const GuideScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Guide & tutorial')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Set a destination alarm',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text(
          'Follow these steps for your first trip. Open the topics below whenever you need more detail.',
        ),
        const SizedBox(height: 16),
        const _GuideStep(
          number: '1',
          title: 'Choose transport',
          detail: 'Pick Bus, Metro, Railway, or Other on Home.',
        ),
        const _GuideStep(
          number: '2',
          title: 'Choose a destination',
          detail:
              'Search an area or place, choose a stop from the list or map, then tap Confirm destination.',
        ),
        const _GuideStep(
          number: '3',
          title: 'Set your alert',
          detail:
              'Check the destination, choose a distance, and optionally choose repeat weekdays, sound, and vibration.',
        ),
        const _GuideStep(
          number: '4',
          title: 'Complete phone settings',
          detail:
              'Allow precise location all the time, notifications, Alarms & reminders, and unrestricted battery use when the setup screen asks.',
        ),
        const _GuideStep(
          number: '5',
          title: 'Start the alarm',
          detail:
              'Tap Start alarm. Keep location services on while travelling; the active screen shows distance and GPS status.',
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => context.push('/pick'),
          icon: const Icon(Icons.add_location_alt_outlined),
          label: const Text('Choose a destination'),
        ),
        const SizedBox(height: 20),
        Text('Detailed guide', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const _GuideSection(
          icon: Icons.travel_explore,
          title: 'Finding a destination',
          points: [
            'Bus and Metro show mapped stops or stations within 2.5 km of your current position, a searched area, or a point you tap on the map. Railway searches within 5 km. Only mapped, named stops can appear.',
            'Search an area, then choose a stop from the list or its map pin. For Other, search a place or tap the map to set an exact point. You can move the pin before confirming.',
            'On the setup screen, use Reselect destination to choose a different place before starting the alarm.',
          ],
        ),
        const _GuideSection(
          icon: Icons.share_location_outlined,
          title: 'Sharing from Google Maps',
          points: [
            'In Google Maps, open a place, tap Share, and choose Destination Alarm. Wait while the shared link is read (up to 12 seconds), or tap Cancel. Then check the place on the setup screen.',
            'If a shared link does not contain coordinates, the app may open a place search so you can select the right result. Short Google Maps links need internet to resolve.',
            'Google Maps offline downloads cannot be imported into this app.',
          ],
        ),
        const _GuideSection(
          icon: Icons.notifications_active_outlined,
          title: 'Distance, repeat, and multiple alarms',
          points: [
            'The starting alert distance is 500 m for Bus and Metro, and 1 km for Railway and Other. Choose a preset, move the slider, or enter 100–2000 m manually. The manual field lets you choose m or km; changing the unit does not change your typed number.',
            'Repeat is optional. Select the weekdays when the distance alarm should run. With no days selected, it is a one-time alarm. You can edit repeat days on the active alarm screen.',
            'You can keep up to ten alarms active, including several for one destination or different destinations. Use Add another alarm on the active screen or start from Home. Each alarm has its own radius and repeat days.',
          ],
        ),
        const _GuideSection(
          icon: Icons.lock_outline,
          title: 'Working while the phone is locked',
          points: [
            'The setup screen checks precise location, Location: Allow all the time, notifications, Alarms & reminders, and Unrestricted or No restrictions battery use. Complete these settings before starting an alarm.',
            'Keep phone location services on. If your phone has an Autostart control, allow this app there too. Some phones may still delay background GPS; choose a larger distance when travelling quickly.',
            'When the alarm rings, open its notification or the app to snooze or stop it. Alarms & reminders access lets short snoozes ring while the phone is idle. Force-stopping the app stops background monitoring.',
          ],
        ),
        const _GuideSection(
          icon: Icons.wifi_off_outlined,
          title: 'What works offline',
          points: [
            'After you have selected a destination and started an alarm, GPS checks the saved coordinates without map tiles or internet.',
            'Map tiles, bus/metro/railway stop searches, and many place searches need internet. A Google Maps short link also needs internet to resolve.',
            'The online map is hidden on the active alarm screen by default. You can still see the remaining distance there while offline.',
          ],
        ),
        const _GuideSection(
          icon: Icons.refresh_outlined,
          title: 'If search or an alarm has a problem',
          points: [
            'If a stop or place search fails, tap Retry search beside the error. Check your connection, then try another area or a point on the map if needed. Public stop data and server availability vary.',
            'If Near me waits for GPS, turn on location services or search an area instead. The GPS status on the active screen shows when reception is weak.',
            'If the phone stays silent while locked, recheck background location, notifications, Alarms & reminders, and unrestricted battery use. A small alert radius or poor GPS reception can delay an alarm.',
          ],
        ),
        const _GuideSection(
          icon: Icons.bookmark_outline,
          title: 'Saved places and history',
          points: [
            'Use Save this place on the setup screen to keep a destination for later. Find it under Saved on Home.',
            'Use History to review ended trips and choose a past destination again. Tap Alarms in the bottom navigation to see all active alarms, including scheduled repeats. Tap an alarm to see its status or end it.',
          ],
        ),
        const SizedBox(height: 16),
        FilledButton.tonalIcon(
          onPressed: () => context.push('/pick'),
          icon: const Icon(Icons.map_outlined),
          label: const Text('Start a new alarm'),
        ),
        const SizedBox(height: 24),
      ],
    ),
  );
}

class _GuideStep extends StatelessWidget {
  const _GuideStep({
    required this.number,
    required this.title,
    required this.detail,
  });

  final String number;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(radius: 16, child: Text(number)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(detail),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _GuideSection extends StatelessWidget {
  const _GuideSection({
    required this.icon,
    required this.title,
    required this.points,
  });

  final IconData icon;
  final String title;
  final List<String> points;

  @override
  Widget build(BuildContext context) => Card(
    child: ExpansionTile(
      leading: Icon(icon),
      title: Text(title),
      children: [
        for (final point in points)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [const Text('•  '), Expanded(child: Text(point))],
            ),
          ),
      ],
    ),
  );
}
