# Improvement batches

Implemented in batch 1:

1. **Test alarm:** Settings offers a preview using the selected sound and vibration. It waits five seconds, rings for ten seconds, and can be stopped from its notification or alarm screen. It has separate notification IDs and gives real destination alerts priority.
2. **Active alarm details:** the active screen shows the native last GPS timestamp, accuracy, and next repeat day. Unknown readings and paused schedules are labeled explicitly.
3. **Alarm management:** optional names; pause/resume; edit destination, radius, weekdays, sound and vibration while retaining the alarm ID; duplicate into a reviewed setup that creates a new ID. Pausing removes that alarm from GPS, geofences and time scheduling. Resuming skips time reminders missed while paused and uses fresh GPS samples.

Implemented in batch 2:

4. **Straight-line distance:** setup and active monitoring identify direct GPS distance. Speed estimates use the same label; the setup explains that this is not road/rail route length.
5. **Small-screen access:** the ringing screen scrolls while remaining centered when there is room. Repeat, radius-unit, alarm-sound, appearance and snooze sheets scroll with large text, short screens and keyboard insets.
6. **Search/map recovery:** place searches show explicit empty results and minimum-query guidance. Empty transit results identify the transport and search radius, with suggestions. Map tile health follows the rendered tiles; the warning clears after recovery. Retry map reloads tiles while retaining the warning until loading succeeds.

Batch 2 verification: `flutter analyze` reported no issues; all 72 Flutter tests passed. Added coverage includes a 320 × 480 screen with large text, repeat/sound/unit/snooze choices, empty searches, map retry and recovery after panning. No APK was built or installed.

Remaining recommendations, in the original order:

7. Replace duplicate UI polling with native status events.
8. Provide a dependable transit-search backend before wider distribution.
9. Consolidate the legacy single-alarm engine and the multiple-alarm engine.

Each implementation batch stops after three improvements. No APK is built unless explicitly requested. Physical lock-screen and travel tests remain necessary after installation.
