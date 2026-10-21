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
          detail: 'Search an area or place, choose a stop from the list or map, then tap Confirm destination.',
        ),
        const _GuideStep(
          number: '3',
          title: 'Set your alert',
          detail: 'Check the destination, choose a distance, and optionally choose repeat weekdays, sound, and vibration.',
        ),
        const _GuideStep(
          number: '4',
          title: 'Complete phone settings',
          detail: 'Allow precise location all the time, notifications, Alarms & reminders, lock-screen alarms, and unrestricted battery use when the setup screen asks.',
        ),
        const _GuideStep(
          number: '5',
          title: 'Start the alarm',
          detail: 'Tap Start alarm. Keep location services on while travelling; the active screen shows distance and GPS status.',
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
            'Bus, Metro, and Railway show mapped stops or stations within 5 km of your current position, a searched area, or a point you tap on the map. Move the map and tap Search this area to look around its center. Only mapped, named stops can appear.',
            'Search an area, then choose a stop from the list or its map pin. The stop list shows straight-line distance from the searched point. Changing the query or transport cancels the previous search. For Other, search a place or tap the map to set an exact point. You can move the pin before confirming.',
            'On the setup screen, use Reselect destination to choose a different place before starting the alarm.',
          ],
        ),
        const _GuideSection(
          icon: Icons.share_location_outlined,
          title: 'Sharing from Google Maps',
          points: [
            'In Google Maps, open a place, tap Share, and choose Destination Alarm. Wait while the shared link is read (up to 12 seconds), or tap Cancel. Then check the place on the setup screen.',
            'If opening a link fails, tap Retry. The app can retry Google short links with an HTTPS DNS fallback; your phone’s DNS settings are not changed. It does not automatically search a generic business name after a connection failure.',
            'If a shared link has no coordinates, the app searches its full place name and address. Select the correct result, check its map pin and coordinates, then tap Confirm destination. If none match, refine the address or tap the correct map point. Link resolution and place search need internet.',
            'If you share a second place while the first link is still opening, the latest share takes priority.',
            'Google Maps offline downloads cannot be imported into this app.',
          ],
        ),
        const _GuideSection(
          icon: Icons.notifications_active_outlined,
          title: 'Distance, repeat, and multiple alarms',
          points: [
            'The starting alert distance is 500 m for Bus and Metro, and 1 km for Railway and Other. Choose a preset, move the slider, or enter 100–2000 m manually. The manual field lets you choose m or km; changing the unit does not change your typed number.',
            'The displayed distance is straight-line GPS distance. Roads and railway routes can be longer. Speed-based estimates also use this direct distance.',
            'Repeat is optional. Select the weekdays when the distance alarm should run. With no days selected, it is a one-time alarm. You can edit repeat days on the active alarm screen. If the first selected day is later, you can save the alarm without waiting for a GPS fix; keep the required permissions enabled for that day.',
            'Use the alarm menu to Rename, Edit destination and settings, Duplicate, or Pause/Resume. Duplicate opens setup for review before creating a separate alarm. Paused alarms stay saved and do not ring until resumed; missed time reminders are skipped.',
            'The active screen shows the last native GPS update, accuracy, and next repeat day. Its distance is marked last known when the visible GPS position gets old. A repeating alarm waiting for a selected day says so even if you are near the destination.',
            'The Alarms list shows Needs attention and the reported problem even while a repeat is scheduled for another day.',
            'If GPS coordinates or accuracy cannot support an alarm’s radius, that alarm waits for a usable fix and shows the reason. Poor reception can delay a distance alert.',
            'You can keep up to ten alarms active, including several for one destination or different destinations. Use Add another alarm on the active screen or start from Home. Each alarm has its own radius and repeat days.',
          ],
        ),
        const _GuideSection(
          icon: Icons.lock_outline,
          title: 'Working while the phone is locked',
          points: [
            'The setup screen checks precise location, Location: Allow all the time, notifications (including the alarm and tracking channels), Alarms & reminders, lock-screen alarms, and Unrestricted or No restrictions battery use. Complete these settings before starting an alarm.',
            'Manual battery confirmation expires when you leave the app or after 15 minutes. Recheck No restrictions before confirming again. Zero alarm volume or Do Not Disturb may silence the alert; setup shows warnings for these settings.',
            'Keep phone location services on. If your phone has an Autostart control, allow this app there too. Some phones may still delay background GPS; choose a larger distance when travelling quickly.',
            'Underground metro tunnels can weaken or block GPS. Set the alarm and a suitable radius before entering a tunnel; an alert may be delayed until the phone gets another position.',
            'When the alarm rings, open its notification or the app to snooze or stop it. Alarms & reminders access lets short snoozes ring while the phone is idle. Force-stopping the app stops background monitoring.',
          ],
        ),
        const _GuideSection(
          icon: Icons.volume_up_outlined,
          title: 'Test the alarm',
          points: [
            'Open Settings → Test alarm to preview the selected sound, vibration, and lock-screen notification. Tap Start test, then lock your phone during the five-second countdown.',
            'The preview rings for ten seconds and stops automatically. Stop test is available in its notification and alarm screen. Real destination alerts take priority.',
            'Allow alarm notifications and lock-screen alarms for the preview. It does not need GPS or register a destination.',
          ],
        ),
        const _GuideSection(
          icon: Icons.delete_outline,
          title: 'Local data and privacy',
          points: [
            'The latest 100 trips are kept locally. Use Clear trip history in History or Settings to delete trips and their recovery copies. Active alarms and saved places are kept.',
            'Saved places can be removed individually or cleared in Settings. Android cloud backup and device transfer are disabled for app data.',
            'If saved data is damaged, valid entries are recovered and Settings shows a warning. Check your alarms and recreate any missing ones. Delete damaged recovery copies in Settings when you no longer need them.',
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
            'If a stop or place search fails, tap Retry search beside the error. Check your connection, then try another area or a point on the map if needed. If you search again too quickly, the app waits briefly and retries that request once. Google Places coverage varies.',
            'Searches run when requested, with a short pause between requests. Place results refresh after ten minutes; recently loaded stops are reused across visits, and recent cached stops may be shown if refreshing fails. This does not download map tiles.',
            'If no places match, check spelling or search a nearby town or landmark. Enter at least three characters. An empty stop list means no mapped, named stops were found in that search radius.',
            'Google Maps needs an internet connection to display map data. GPS alarm monitoring continues without the map.',
            'On small screens or with large text, scroll the ringing screen and selection sheets to reach the remaining actions and choices.',
            'If Near me waits for GPS, turn on location services or search an area instead. The GPS status on the active screen shows when reception is weak.',
            'If the phone stays silent while locked, recheck background location, notifications, Alarms & reminders, lock-screen alarms, and unrestricted battery use. A small alert radius or poor GPS reception can delay an alarm.',
            'If the last GPS fix is less accurate than your selected alert radius, setup warns you. Consider a larger radius for an earlier warning, especially while moving quickly.',
            'Background GPS and the geofence backup skip old or unverifiable positions. Poor reception may delay the alert until a usable fix arrives.',
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
              children: [
                const Text('•  '),
                Expanded(child: Text(point)),
              ],
            ),
          ),
      ],
    ),
  );
}
