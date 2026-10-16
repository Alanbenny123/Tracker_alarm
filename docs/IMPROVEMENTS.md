# Improvement batches

Implemented in batch 1:

1. **Test alarm:** Settings offers a preview using the selected sound and vibration. It waits five seconds, rings for ten seconds, and can be stopped from its notification or alarm screen. It has separate notification IDs and gives real destination alerts priority.
2. **Active alarm details:** the active screen shows the native last GPS timestamp, accuracy, and next repeat day. Unknown readings and paused schedules are labeled explicitly.
3. **Alarm management:** optional names; pause/resume; edit destination, radius, weekdays, sound and vibration while retaining the alarm ID; duplicate into a reviewed setup that creates a new ID. Pausing removes that alarm from GPS, geofences and time scheduling. Resuming skips time reminders missed while paused and uses fresh GPS samples.

Remaining recommendations, in the original order:

4. Label distance as straight-line distance.
5. Make ringing screens and bottom sheets scrollable for small screens and large text.
6. Show no-result messages and recover the map-error banner after successful loading.
7. Replace duplicate UI polling with native status events.
8. Provide a dependable transit-search backend before wider distribution.
9. Consolidate the legacy single-alarm engine and the multiple-alarm engine.

Each implementation batch stops after three improvements. No APK is built unless explicitly requested. Physical lock-screen and travel tests remain necessary after installation.
