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

Implemented in batch 3:

7. **Native status events:** one lifecycle-managed subscription for all routes replaces screen polling. Android coalesces storage/GPS/health/geofence invalidations. A serialized snapshot queue prevents events arriving during a read from being lost. Reconnecting refreshes missed state; manual refresh remains available.
8. **Server-free transit resilience (scope adjusted by the user):** no hosting, rented server or new account. A bounded memory cache survives picker visits; fresh entries last ten minutes and labeled fallback results expire after 24 hours. Rate limits have a shared cooldown of at least 30 seconds and honor Retry-After. One bounded retry remains for transient server errors. Canceled retries stop, and incomplete responses cannot become successful empty results. **The original recommendation for a dependable hosted backend is not implemented:** the user declined hosting, so public-server outages and capacity remain a limitation before wider distribution.
9. **One alarm engine:** removed the old single-alarm runtime and trackers. Read-only migration plus small old-component bridges preserve installed alarm data and Android callbacks; all scheduling, GPS and destination playback now use the current multiple-alarm engine. Shared channels live in AlarmNotifications. Migration is idempotent, reports invalid old data, preserves flags and prevents completed alarms from resurrecting. Old snoozes lacking a stored deadline receive a one-minute replacement.

Batch 3 verification: `flutter analyze` reported no issues; all 79 Flutter tests and all 29 Android JVM tests passed. Android Kotlin compilation also succeeded. Regression coverage includes event subscription lifecycle and ordering, an idle ringing screen with no polling, cache expiry and cooldowns, incomplete search responses, cancellation during retry, migration without resurrection, old notification targeting, and migration at reboot. No APK was built or installed. Locked-screen travel and installed-version upgrade checks remain physical-device checks.

Each implementation batch stops after three improvements. No APK is built unless explicitly requested. Physical lock-screen and travel tests remain necessary after installation.
