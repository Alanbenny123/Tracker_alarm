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
7. Complete the phone settings shown on the setup screen: **precise location**, **Location: Allow all the time**, **notifications**, and **Unrestricted / No restrictions** battery use. If your phone has **Autostart**, allow this app there too.
8. Tap **Start alarm**. The active screen shows remaining distance, GPS status, radius, and repeat days.

## Finding bus stops and stations

Bus and Metro search within **3 km** of the chosen area. Railway searches within **5 km**. These results come from mapped, named OpenStreetMap places. A real stop may be missing if it has not been mapped or named. Searches need internet.

Use the search box to find an area, then select a result. The app loads stops around that area. You can also tap another map area. If a search fails, the error appears by the search box with **Retry search**. Retry repeats the failed place or stop search. If the server remains busy, search another area or use **Other** and choose a map point.

## Share a place from Google Maps

In Google Maps, open a place, tap **Share**, and choose **Destination Alarm**. Wait for the loading screen, then review the destination in setup. If the link contains no usable coordinates, the app may open place search so you can select the correct result. A shortened Google Maps link needs internet to resolve. Google Maps' downloaded offline maps cannot be imported into this app.

## Repeat and multiple alarms

Repeat runs the distance alarm **only on the weekdays you select**. After it rings on one selected day, it resets for the next selected day. You can edit the days using **Repeat alarm** on the active screen. With Repeat off, the alarm is one-time.

You can have up to **10 active alarms**. On the active screen, tap **Add another alarm for this destination** to make another alarm for the same place. To target a different place, return to Home and choose a new destination. Each alarm has its own distance and repeat settings. Home lists active alarms; tap one to view or end it.

When an alarm rings, use the app or its notification to handle it. **Snooze** pauses the sound for the offered interval; **End trip** or **Stop alarm** ends that alarm. Other active alarms remain in place.

## Locked phone and offline use

The app uses background location monitoring, a foreground service, and an Android geofence backup where available. Keep the required permissions and unrestricted battery setting enabled. Some phones also need their separate Autostart setting. GPS accuracy and device power management can delay an alert, especially at small radii or higher travel speeds. Do not force-stop the app while relying on an alarm.

After the destination is selected and the alarm starts, monitoring the saved coordinates does **not** require internet. Online map tiles, stop searches, many place searches, and shortened Google Maps links do require internet. The app does not include an offline basemap. The active screen shows distance while the online map is hidden.

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
