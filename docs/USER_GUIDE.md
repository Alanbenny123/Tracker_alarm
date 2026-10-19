# Destination Alarm: user guide

Destination Alarm rings when your phone reaches a chosen distance from a destination. You can set several alarms for the same place or for different places. The alarm monitors saved coordinates, so you do not need to keep the map open while travelling.

## First alarm: step by step

1. Open the app and keep Location turned on.
2. On **Home**, choose **Bus**, **Metro**, **Railway**, or **Other**.
3. Find your destination:
   - **Bus / Metro / Railway:** choose a mapped stop from the list or map. You can search an area, tap a different area on the map, or use **Near me**.
   - **Other:** search for a place or tap the map to place a pin. You can move the pin before confirming.
4. Tap **Confirm destination**. On the setup screen, check the place name and map. Tap **Reselect destination** if it is wrong.
5. Choose the alert distance. The starting distance is **500 m** for Bus and Metro, and **1 km** for Railway and Other. You can use a preset, slider, or manual entry from **100 m to 2 km**. Manual entry has an **m / km** picker; changing the unit keeps the typed number, so check the resulting radius.
6. Optional: open **Repeat** and choose the weekdays on which this distance alarm should run. Leave every day unselected for a one-time alarm. You can also select the alarm sound and vibration.
7. Give the alarm an optional name, such as Morning commute. Complete the phone settings shown on the setup screen: **precise location**, **Location: Allow all the time**, **notifications**, **Alarms & reminders**, **lock-screen alarms**, and **Unrestricted / No restrictions** battery use. If your phone has **Autostart**, allow this app there too.
8. Tap **Start alarm**. The active screen shows straight-line distance, GPS status, radius, and repeat days. Distance is measured directly to the destination; road and railway routes may be longer. Any speed-based estimate uses that same direct distance.

## Finding bus stops and stations

Bus and Metro search within **2.5 km** of the chosen area. Railway searches within **5 km**. These results come from mapped, named OpenStreetMap places. A real stop may be missing if it has not been mapped or named. Searches need internet.

Use the search box to find an area, then select a result. The app loads stops around that area. You can also tap another map area. If a search fails, the error appears by the search box with **Retry search**. Retry repeats the failed place or stop search. If the server remains busy, search another area or use **Other** and choose a map point.

If no places match your search, check the spelling or search a nearby town or landmark. Enter at least three characters. An empty stop list means no named stops for that transport were found within the displayed radius; try another area or use **Other** to select a map point.

### Search cache and busy servers

No server account or API key is needed for the current public stop search. If a server asks the app to slow down, follow the displayed cooldown before retrying. Retry cannot bypass it. A temporary server error gets at most one automatic retry.

Stop results are reused for ten minutes across picker visits. If refreshing fails, the app can show previously loaded results for the **same area and transport**, up to 24 hours old, with a visible cache-age notice. These may be out of date. This cache lives only in memory and disappears when Android ends the app process; it does not download a map. Public services can still be unavailable. You can use **Other** to choose a map point, then start the offline GPS alarm.

## Share a place from Google Maps

In Google Maps, open a place, tap **Share**, and choose **Destination Alarm**. Wait for the loading screen (up to 12 seconds), or tap Cancel. If the link contains coordinates, review the destination in setup. Otherwise, the app automatically searches the full resolved place name and address to obtain coordinates. When one named place matches, it selects that result and centres the map on its pin. Check the name, address, and coordinates, then tap **Confirm destination**. If several places match, choose the correct result first. A general area result is not automatically selected as a business. If no suitable result is found, refine the address or tap the correct map point.

A shortened Google Maps link and place search need internet. Google Maps' downloaded offline maps cannot be imported into this app. Map camera coordinates are not used as destination coordinates. After confirming the destination and starting the alarm, GPS monitoring works offline.

If opening a shared link fails, use **Retry** on the error message. A connection failure will not automatically search only a generic business name. The app can use Google Public DNS over HTTPS as a fallback for Google short-link hostnames; it keeps normal HTTPS checks and does not change your phone’s DNS settings. This needs internet, but no API key or rented server. Shared-address results that clearly disagree with the shared name/address are hidden. Always check the selected pin, because geocoding can still be approximate.

## Repeat and multiple alarms

Repeat runs the distance alarm **only on the weekdays you select**. After it rings on one selected day, it resets for the next selected day. You can edit the days using **Repeat alarm** on the active screen. With Repeat off, the alarm is one-time.

You can have up to **10 active alarms**. On the active screen, tap **Add another alarm for this destination** to make another alarm for the same place. To target a different place, return to Home and choose a new destination. Each alarm has its own distance and repeat settings. Tap **Alarms** in the bottom navigation to see all active alarms, including scheduled repeats. The badge shows how many you have. Tap an alarm to view or end it, or pull down on the list to refresh it.

Changes made from notifications update the open app through native status events. Returning to the app refreshes anything missed while it was in the background. You can still pull down the Alarms list to refresh manually.

When an alarm rings, use the app or its notification to handle it. **Snooze** pauses the sound for the offered interval; **End trip** or **Stop alarm** ends that alarm. Other active alarms remain in place.

## Locked phone and offline use

After restarting the phone, check the app's notification. If it says an alert needs attention, open the app to resume that pending alert. The active screen shows whether the background service is running, whether GPS fixes are fresh, and whether the geofence backup is registered.

The app uses background location monitoring, a foreground service, and an Android geofence backup where available. Keep the required permissions and unrestricted battery setting enabled. Some phones also need their separate Autostart setting. GPS accuracy and device power management can delay an alert, especially at small radii or higher travel speeds. Do not force-stop the app while relying on an alarm.

After the destination is selected and the alarm starts, monitoring the saved coordinates does **not** require internet. The OpenFreeMap vector map, stop searches, many place searches, and shortened Google Maps links do require internet. The app does not include an offline basemap. The active screen shows straight-line distance while the online map is hidden. If the vector map does not load, the map automatically tries a dark backup source without changing the destination or map position. The map labels the backup source. If both sources fail, tap **Retry map** after reconnecting. The warning clears when the visible map tiles recover; alarms continue monitoring without them.

The ringing screen and selection sheets can be scrolled. With a small screen or large text, scroll to reach **Stop this alert**, **Snooze**, the remaining choices, or **Save**.

## Troubleshooting

| Problem | What to try |
| --- | --- |
| Stop or place search failed | Tap **Retry search** beside the error. Check internet, try another area, or choose **Other** and tap the map. |
| **Near me** is waiting for GPS | Turn on phone location services, move where GPS reception is better, or search an area instead. |
| A stop is missing | Map coverage varies. Search or tap a nearby area, or choose **Other** and place a pin. |
| Google Maps share did not find a place | Try sharing a named place while online or copy a coordinate link. Check the destination in setup before starting. |
| Alarm does not ring while locked | Recheck **Allow all the time** location, notifications, **Unrestricted** battery use, and any phone-specific Autostart control. Check GPS status on the active screen. |
| Alarm rings later than expected | GPS accuracy and the selected radius affect timing. Use a larger radius when travelling quickly. |

Saved places are available under **Saved** and ended trips under **History**. You can use either to choose a destination again. The in-app **Guide & tutorial** is available from Home and Settings.

## Test the alarm before travelling

Open **Settings → Test alarm**. Check the displayed sound and vibration setting, then tap **Start test**. The test waits five seconds so you can lock your phone, rings for ten seconds, and stops automatically. **Stop test** is available in its notification and preview screen. Your destination alarms stay saved, and a real destination alert takes priority over the test. Enable alarm notifications and lock-screen alarms when prompted. The preview does not need a GPS fix.

## Name, pause, edit, and duplicate

- Use **Alarm name** in setup or **Rename** in an alarm’s menu to add a label. The destination name and coordinates stay attached to the alarm.
- Use **Pause** in its menu, or **Pause alarm** on the active screen, to suspend that alarm. It stays in your alarm list and persists after restarting the app. Use **Resume** to restart it. Other destinations continue monitoring. Time reminders missed while paused are skipped, and repeat alarms catch up to the current selected day.
- Use **Edit destination and settings** to reselect the destination or change distance, repeat weekdays, sound, vibration, or name. **Save changes** keeps the existing alarm ID. Paused alarms stay paused after editing.
- Use **Duplicate** to open a new setup with the destination, distance, repeat weekdays, sound, vibration, and name filled in. Review and tap **Start alarm** to create a separate alarm. You can cancel setup without creating the copy.
- Handle ringing or snoozed alerts before editing or pausing them.

## GPS and repeat details

Open an alarm to see its last native GPS update, reported accuracy, and next repeat day. A missing reading is shown as unknown. Paused alarms show that repeats and monitoring are suspended.

Manual battery confirmation, for phones whose vendor setting Android cannot verify, expires when you leave the app or after 15 minutes. Reopen battery settings before confirming again.

## Local data

The latest 100 trips are kept locally. **Clear trip history** in History or Settings removes trips and their recovery copies. **Clear saved places** removes bookmarks and their recovery copies. Active alarms are kept. Settings also lets you delete damaged recovery copies after reviewing any repaired data. App data is excluded from Android cloud backup and device transfer; this does not delete backups made by older app versions.

## Updating an older installation

Old destination alarms are moved into the current alarm engine without replacing other destinations. Check **Alarms** after updating. If older saved data cannot be read, Settings shows a warning and preserves the original data; recreate that missing destination. An old snoozed alarm whose expiry was not saved receives a new one-minute snooze. After reboot, open the app if the notification says a pending alert needs attention.
