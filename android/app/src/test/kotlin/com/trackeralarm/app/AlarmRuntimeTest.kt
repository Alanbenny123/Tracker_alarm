package com.trackeralarm.app

import android.Manifest
import android.app.AlarmManager
import android.app.Application
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.media.AudioManager
import android.content.pm.ApplicationInfo
import android.provider.Settings
import org.robolectric.shadows.ShadowSystemClock
import java.time.Duration
import org.xmlpull.v1.XmlPullParser
import android.media.MediaPlayer
import android.os.VibratorManager
import org.robolectric.shadows.ShadowAlarmManager
import org.robolectric.shadows.ShadowMediaPlayer
import android.content.Context
import android.os.Looper
import java.util.Calendar
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import android.content.Intent
import android.location.Location
import android.location.LocationManager
import android.os.PowerManager
import org.json.JSONArray
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode
import org.robolectric.shadows.ShadowPowerManager

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class)
@LooperMode(LooperMode.Mode.PAUSED)
class AlarmRuntimeTest {
    private val app get() = RuntimeEnvironment.getApplication()
    private var base = 0L

    @Before fun reset() {
        AlarmStatusEvents.onCancel(null)
        app.getSharedPreferences("destination_monitor", Context.MODE_PRIVATE).edit().clear().commit()
        ShadowAlarmManager.setCanScheduleExactAlarms(true)
        app.getSharedPreferences("destination_multi_monitor", Context.MODE_PRIVATE).edit().clear().commit()
        MultiAlarmRuntime.refresh(app)
        base = System.currentTimeMillis() - 10_000
        shadowOf(app).grantPermissions(Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.ACCESS_BACKGROUND_LOCATION, Manifest.permission.POST_NOTIFICATIONS)
        val manager = app.getSystemService(Context.LOCATION_SERVICE) as LocationManager
        shadowOf(manager).setProviderEnabled(LocationManager.GPS_PROVIDER, true)
    }

    private fun entry(id: String, longitude: Double = 0.0) = MultiAlarmRuntime.Entry(
        id, id, "", 0.0, longitude, 100f, false, "Beep", base - 1000, 0L)

    private fun save(vararg entries: MultiAlarmRuntime.Entry) {
        val json = JSONArray()
        entries.forEach { json.put(it.json()) }
        app.getSharedPreferences("destination_multi_monitor", Context.MODE_PRIVATE).edit()
            .putString("alarms", json.toString()).commit()
    }

    private fun fix(longitude: Double, offset: Long, accuracy: Float = 5f) = Location("gps").apply {
        latitude = 0.0
        this.longitude = longitude
        time = base + offset
        elapsedRealtimeNanos = (100_000L + offset) * 1_000_000
        this.accuracy = accuracy
        speed = 90f
    }

    private fun legacy(status: String = "active") {
        app.getSharedPreferences("destination_monitor", Context.MODE_PRIVATE).edit()
            .putString("id", "legacy").putString("name", "Old destination")
            .putString("latitude", "9.9").putString("longitude", "76.7")
            .putFloat("radius", 500f).putLong("startedAt", base)
            .putString("status", status).putString("sound", "Bell")
            .putBoolean("vibration", false).putBoolean("distanceFired", status != "active")
            .commit()
    }

    @Test fun legacyMigrationPreservesOthersAndDoesNotResurrectAnArchivedAlarm() {
        save(entry("other"))
        legacy()
        MultiAlarmRuntime.migrateLegacy(app)
        assertEquals(setOf("other", "legacy"), MultiAlarmRuntime.live(app).map { it.id }.toSet())
        val migrated = MultiAlarmRuntime.live(app).first { it.id == "legacy" }
        assertEquals(9.9, migrated.latitude, 0.000001)
        assertEquals("Bell", migrated.sound)
        assertFalse(migrated.vibration)
        assertTrue(app.getSharedPreferences("destination_monitor", Context.MODE_PRIVATE).getBoolean("migrated_to_multi", false))
        MultiAlarmRuntime.migrateLegacy(app)
        assertEquals(2, MultiAlarmRuntime.live(app).size)
        MultiAlarmRuntime.finish(app, "legacy", "completed")
        MultiAlarmRuntime.forget(app, "legacy")
        MultiAlarmRuntime.migrateLegacy(app)
        assertEquals(listOf("other"), MultiAlarmRuntime.live(app).map { it.id })
    }

    @Test fun oldNotificationStopTargetsItsOwnAlarmAndSnoozeMigrationHasADeadline() {
        save(entry("other").apply { status = "triggered"; distanceFired = true; triggeredAt = 1L })
        legacy("triggered")
        AlarmActionReceiver().onReceive(app, Intent("tracker_alarm.STOP"))
        assertEquals("other", MultiAlarmRuntime.ringing(app)?.id)
        assertEquals("completed", MultiAlarmRuntime.states(app).first { it["id"] == "legacy" }["status"])
        // Reset migration storage to exercise an old snoozed installation.
        app.getSharedPreferences("destination_monitor", Context.MODE_PRIVATE).edit().clear().commit()
        save(entry("other"))
        legacy("snoozed")
        val now = System.currentTimeMillis()
        MultiAlarmRuntime.migrateLegacy(app)
        val snoozed = MultiAlarmRuntime.live(app).first { it.id == "legacy" }
        assertEquals("snoozed", snoozed.status)
        assertTrue(snoozed.snoozedUntil in (now + 60_000L)..(System.currentTimeMillis() + 60_000L))
        assertTrue(snoozed.distanceFired)
    }

    @Test fun legacyBootMigrationRestoresGpsWithoutStartingPendingPlayback() {
        legacy("triggered")
        AlarmRestoreReceiver().onReceive(app, Intent(Intent.ACTION_BOOT_COMPLETED))
        assertEquals("legacy", MultiAlarmRuntime.ringing(app)?.id)
        assertTrue(MultiAlarmRuntime.playbackResumeRequired(app))
        val controller = Robolectric.buildService(MultiTrackingService::class.java).create().startCommand(0, 1)
        assertEquals(MultiAlarmRuntime.TRACKING_ID, shadowOf(controller.get()).lastForegroundNotificationId)
        controller.destroy()
    }

    @Test fun invalidLegacyCoordinatesStayPreservedWithoutPoisoningCurrentAlarms() {
        save(entry("kept"))
        legacy()
        val stored = app.getSharedPreferences("destination_monitor", Context.MODE_PRIVATE)
        stored.edit().putString("latitude", "NaN").commit()
        MultiAlarmRuntime.migrateLegacy(app)
        assertEquals(listOf("kept"), MultiAlarmRuntime.live(app).map { it.id })
        assertFalse(stored.getBoolean("migrated_to_multi", false))
        assertEquals("NaN", stored.getString("latitude", null))
        assertNotNull(MultiAlarmRuntime.storageWarning(app))
        stored.edit().putString("latitude", "invalid").commit()
        MultiAlarmRuntime.migrateLegacy(app)
        assertEquals(listOf("kept"), MultiAlarmRuntime.live(app).map { it.id })
    }

    @Test fun nativeEventsCoalesceWritesAndCancelWithoutLeavingCallbacks() {
        save(entry("event"))
        var events = 0
        val sink = object : EventChannel.EventSink {
            override fun success(event: Any?) { events++ }
            override fun error(code: String, message: String?, details: Any?) { fail(message) }
            override fun endOfStream() { }
        }
        try {
            AlarmStatusEvents.onListen(null, sink)
            assertEquals(1, events)
            MultiAlarmRuntime.rename(app, "event", "One", Result())
            MultiAlarmRuntime.rename(app, "event", "Two", Result())
            MultiAlarmRuntime.rename(app, "event", "Three", Result())
            assertEquals(1, events)
            shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(200))
            assertEquals(2, events)
            assertEquals("Three", MultiAlarmRuntime.states(app).single()["label"])
            AlarmStatusEvents.changed()
            AlarmStatusEvents.onCancel(null)
            shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(1))
            assertEquals(2, events)
        } finally { AlarmStatusEvents.onCancel(null) }
    }

    @Test fun fastCrossingRingsBothDestinationsInTravelOrder() {
        save(entry("second", 0.0015), entry("first", -0.0015))
        MultiAlarmRuntime.checkLocation(app, fix(-0.004, 0))
        val interval = MultiAlarmRuntime.checkLocation(app, fix(0.004, 10_000))
        assertEquals(2, MultiAlarmRuntime.live(app).count { it.status == "triggered" })
        assertEquals("first", MultiAlarmRuntime.ringing(app)?.id)
        assertTrue(interval <= 1000)
    }

    @Test fun visibleGpsOnlyTriggersTheDestinationActuallyReached() {
        save(entry("Aluva", 0.03), entry("Ambattukavu", 0.02), entry("Edappally", 0.01))
        val now = System.currentTimeMillis()
        MultiAlarmRuntime.triggerAt(app, "Aluva", 0.0, 0.01, 10.0, now)
        MultiAlarmRuntime.triggerAt(app, "Ambattukavu", 0.0, 0.01, 10.0, now)
        MultiAlarmRuntime.triggerAt(app, "Edappally", 0.0, 0.01, 10.0, now)
        assertEquals("Edappally", MultiAlarmRuntime.ringing(app)?.id)
        assertEquals(listOf("Edappally"), MultiAlarmRuntime.live(app)
            .filter { it.status == "triggered" }.map { it.id })
    }

    @Test fun backgroundGpsRingsEdappallyBeforeEarlierCreatedFarawayAlarms() {
        save(entry("Aluva", 0.03), entry("Ambattukavu", 0.02), entry("Edappally", 0.01))
        MultiAlarmRuntime.checkLocation(app, fix(0.0, 0))
        MultiAlarmRuntime.checkLocation(app, fix(0.01, 10_000))
        assertEquals("Edappally", MultiAlarmRuntime.ringing(app)?.id)
        assertEquals(listOf("Edappally"), MultiAlarmRuntime.live(app)
            .filter { it.status == "triggered" }.map { it.id })
    }

    @Test fun gpsServiceChecksEveryDestinationWithoutNetworkProvider() {
        save(entry("Aluva", 0.03), entry("Ambattukavu", 0.02), entry("Edappally", 0.01))
        val manager = app.getSystemService(Context.LOCATION_SERVICE) as LocationManager
        shadowOf(manager).setProviderEnabled(LocationManager.NETWORK_PROVIDER, false)
        val controller = Robolectric.buildService(MultiTrackingService::class.java)
            .create().startCommand(0, 1)
        try {
            shadowOf(manager).simulateLocation(fix(0.0, 0))
            shadowOf(Looper.getMainLooper()).idle()
            shadowOf(manager).simulateLocation(fix(0.01, 10_000))
            shadowOf(Looper.getMainLooper()).idle()
            assertEquals("Edappally", MultiAlarmRuntime.ringing(app)?.id)
            assertEquals(listOf("Edappally"), MultiAlarmRuntime.live(app)
                .filter { it.status == "triggered" }.map { it.id })
        } finally { controller.destroy() }
    }

    @Test fun anOlderPreciseFixCanProveArrivalWithoutReversingTravelHistory() {
        save(entry("older", 0.02), entry("next", 0.01))
        MultiAlarmRuntime.checkLocation(app, fix(0.0, 8_000))
        MultiAlarmRuntime.checkLocation(app, fix(0.02, 5_000))
        assertEquals("older", MultiAlarmRuntime.ringing(app)?.id)
        MultiAlarmRuntime.checkLocation(app, fix(0.01, 9_000))
        assertEquals(setOf("older", "next"), MultiAlarmRuntime.live(app)
            .filter { it.status == "triggered" }.map { it.id }.toSet())
    }

    @Test fun inaccurateOrOldSegmentsDoNotInferCrossings() {
        assertNull(DestinationCrossing.fraction(fix(-0.0015, 0, 500f), fix(0.0015, 5000), 0.0, 0.0, 100f))
        assertNull(DestinationCrossing.fraction(fix(-0.0015, 0), fix(0.0015, 20_000), 0.0, 0.0, 100f))
        assertNull(DestinationCrossing.fraction(fix(-0.0015, 0), fix(-0.0012, 5000), 0.0, 0.0, 100f))
    }

    @Test fun aGpsFixWithoutAccuracyCannotRingButAVerifiedFixCan() {
        save(entry("verify"))
        val unverified = Location("gps").apply {
            latitude = 0.0
            longitude = 0.0
            time = System.currentTimeMillis()
        }
        MultiAlarmRuntime.checkLocation(app, unverified)
        assertEquals("active", MultiAlarmRuntime.live(app).single().status)
        MultiAlarmRuntime.checkLocation(app, fix(0.0, 10_000))
        assertEquals("triggered", MultiAlarmRuntime.live(app).single().status)
    }

    @Test fun invalidGpsEvidenceCannotTriggerAnAlarmOrAProjectedCrossing() {
        save(entry("invalid"))
        val invalidAccuracy = fix(0.0, 10_000, Float.NaN)
        assertFalse(LocationEvidence.usable(invalidAccuracy, 100f))
        MultiAlarmRuntime.checkLocation(app, invalidAccuracy)
        assertEquals("active", MultiAlarmRuntime.live(app).single().status)
        assertNull(MultiGeofenceReceiver.verifiedDistance(
            MultiAlarmRuntime.live(app).single(), invalidAccuracy, System.currentTimeMillis()))
        assertNull(DestinationCrossing.fraction(fix(-0.002, 0), invalidAccuracy,
            0.0, 0.0, 100f))
        val invalidCoordinates = fix(0.0, 10_000).apply { longitude = Double.NaN }
        MultiAlarmRuntime.checkLocation(app, invalidCoordinates)
        assertEquals("active", MultiAlarmRuntime.live(app).single().status)
    }

    @Test @Config(sdk = [33]) fun monitoringStatusWaitsForAccuracyUsableByEachAlarm() {
        save(entry("tight"), entry("wide").copy(radius = 500f))
        val controller = Robolectric.buildService(MultiTrackingService::class.java)
            .create().startCommand(0, 1)
        val manager = app.getSystemService(Context.LOCATION_SERVICE) as LocationManager
        try {
            val noAccuracy = Location("gps").apply {
                latitude = 0.0; longitude = 0.0; time = System.currentTimeMillis()
            }
            shadowOf(manager).simulateLocation(noAccuracy)
            shadowOf(Looper.getMainLooper()).idle()
            val noAccuracyHealth = MultiTrackingService.health(app, MultiAlarmRuntime.live(app).first())
            assertTrue(noAccuracyHealth.toString(),
                noAccuracyHealth["monitoringMessage"].toString().contains("accuracy"))
            shadowOf(manager).simulateLocation(fix(0.01, 10_000, 300f))
            shadowOf(Looper.getMainLooper()).idle()
            val entries = MultiAlarmRuntime.live(app).associateBy { it.id }
            assertEquals(false, MultiTrackingService.health(app, entries.getValue("tight"))["monitoringHealthy"])
            assertEquals(true, MultiTrackingService.health(app, entries.getValue("wide"))["monitoringHealthy"])
            shadowOf(manager).simulateLocation(fix(0.01, 10_000, 10f))
            shadowOf(Looper.getMainLooper()).idle()
            assertEquals(true, MultiTrackingService.health(app, entries.getValue("tight"))["monitoringHealthy"])
        } finally { controller.destroy() }
    }

    @Test fun geofenceBackupRejectsOldMissingOrInaccurateLocations() {
        val alarm = entry("backup")
        val now = base + 10_000
        assertNotNull(MultiGeofenceReceiver.verifiedDistance(alarm, fix(0.0, 9_000), now))
        assertNull(MultiGeofenceReceiver.verifiedDistance(alarm,
            fix(0.0015, 9_000), now)) // 167 m away is outside this alarm's 100 m radius.
        assertNull(MultiGeofenceReceiver.verifiedDistance(alarm, null, now))
        assertNull(MultiGeofenceReceiver.verifiedDistance(alarm, Location("gps").apply {
            latitude = 0.0
            longitude = 0.0
            time = now
        }, now))
        assertNull(MultiGeofenceReceiver.verifiedDistance(alarm, fix(0.0, 9_000, 500f), now))
        assertNull(MultiGeofenceReceiver.verifiedDistance(
            alarm.copy(monitoringSince = base - 100_000), fix(0.0, -40_000), now))
        assertNull(MultiGeofenceReceiver.verifiedDistance(
            alarm.copy(monitoringSince = base + 9_500), fix(0.0, 9_000), now))
    }

    @Test fun notificationDismissKeepsTheOtherAlarmRinging() {
        save(entry("first").apply { status = "triggered"; distanceFired = true; triggeredAt = 1 },
            entry("second").apply { status = "triggered"; distanceFired = true; triggeredAt = 2 })
        MultiAlarmReceiver().onReceive(app, Intent("tracker_alarm.MULTI_DISMISS").putExtra("id", "first"))
        assertEquals("second", MultiAlarmRuntime.ringing(app)?.id)
        assertEquals("completed", MultiAlarmRuntime.states(app).first { it["id"] == "first" }["status"])
    }

    @Test fun aLaterDestinationCanSoundWhileAnEarlierAlertIsUndismissed() {
        save(entry("Aluva").apply { status = "triggered"; distanceFired = true; triggeredAt = 1_000 },
            entry("Edappally").apply { status = "triggered"; distanceFired = true; triggeredAt = 61_000 })
        assertEquals("Edappally", MultiAlarmRuntime.ringing(app)?.id)
        MultiAlarmRuntime.dismiss(app, "Edappally")
        assertEquals("Aluva", MultiAlarmRuntime.ringing(app)?.id)
    }

    @Test fun monitoringWakeLockIsReleasedWhenServiceEnds() {
        save(entry("trip", 0.02))
        val controller = Robolectric.buildService(MultiTrackingService::class.java).create()
        controller.startCommand(0, 1)
        val lock: PowerManager.WakeLock = ShadowPowerManager.getLatestWakeLock()
        assertTrue(lock.isHeld)
        controller.destroy()
        assertFalse(lock.isHeld)
        assertEquals(false, MultiTrackingService.health(app)["monitoringHealthy"])
    }

    @Test fun rebootRestoresPendingAlertWithoutStartingPlayback() {
        save(entry("pending").apply { status = "triggered"; distanceFired = true })
        AlarmRestoreReceiver().onReceive(app, Intent(Intent.ACTION_BOOT_COMPLETED))
        assertTrue(MultiAlarmRuntime.playbackResumeRequired(app))
        val controller = Robolectric.buildService(MultiTrackingService::class.java).create().startCommand(0, 1)
        assertEquals(MultiAlarmRuntime.TRACKING_ID, shadowOf(controller.get()).lastForegroundNotificationId)
        controller.destroy()
    }

    @Test fun shortSnoozeUsesExactAlarmClockAndExpiresIntoRinging() {
        save(entry("snooze").apply { status = "triggered"; distanceFired = true })
        MultiAlarmRuntime.snooze(app, "snooze", 1)
        val manager = app.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val stored = MultiAlarmRuntime.live(app).single()
        val scheduled = shadowOf(manager).scheduledAlarms.single()
        assertEquals(stored.snoozedUntil, scheduled.triggerAtMs)
        assertEquals(0L, scheduled.windowLengthMs)
        assertNotNull(scheduled.alarmClockInfo)
        assertEquals(stored.snoozedUntil, manager.nextAlarmClock.triggerTime)
        // Deliver the real receiver after the persisted snooze deadline.
        save(stored.apply { snoozedUntil = System.currentTimeMillis() - 1 })
        MultiAlarmReceiver().onReceive(app, shadowOf(scheduled.operation).savedIntent)
        assertEquals("triggered", MultiAlarmRuntime.ringing(app)?.status)
    }

    @Test fun grantingExactAccessReplacesRestoredInexactSchedule() {
        ShadowAlarmManager.setCanScheduleExactAlarms(false)
        save(entry("waiting").apply { alertAt = System.currentTimeMillis() + 60_000 })
        MultiAlarmRuntime.refresh(app)
        val manager = app.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        assertTrue(shadowOf(manager).scheduledAlarms.single().windowLengthMs != 0L)
        ShadowAlarmManager.setCanScheduleExactAlarms(true)
        AlarmRestoreReceiver().onReceive(app,
            Intent(AlarmManager.ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED))
        val scheduled = shadowOf(manager).scheduledAlarms.single()
        assertEquals(0L, scheduled.windowLengthMs)
        assertNotNull(scheduled.alarmClockInfo)
    }

    @Test fun alarmNotificationNeverAddsASecondSoundOrVibration() {
        val notification = MultiAlarmRuntime.alarmNotification(app, entry("quiet"))
        val channel = AlarmNotifications.notifications(app).getNotificationChannel(AlarmNotifications.CHANNEL_ALARM)
        assertNull(channel.sound)
        assertFalse(channel.shouldVibrate())
        assertNull(notification.sound)
        assertNull(notification.vibrate)
        assertTrue(notification.flags and Notification.FLAG_ONLY_ALERT_ONCE != 0)
    }

    @Test fun playbackFollowsVibrationChoiceAndCleansUpBeforeNextAlarm() {
        ShadowMediaPlayer.setMediaInfoProvider { ShadowMediaPlayer.MediaInfo(1000, 0) }
        val players = mutableListOf<MediaPlayer>()
        ShadowMediaPlayer.setCreateListener { player, _ -> players.add(player) }
        val vibrator = (app.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
        val sound = AlarmSoundPlayer(app)
        sound.start("Bell", false)
        assertTrue(players.last().isPlaying)
        assertTrue(players.last().isLooping)
        assertFalse(shadowOf(vibrator).isVibrating)
        sound.stop()
        sound.start("Digital", true)
        assertTrue(players.last().isPlaying)
        assertTrue(shadowOf(vibrator).isVibrating)
        sound.stop()
        assertFalse(shadowOf(vibrator).isVibrating)
    }

    @Test fun readinessDetectsBlockedAlarmAndTrackingChannels() {
        val manager = AlarmNotifications.notifications(app)
        assertTrue(AlarmReadiness.notificationsReady(app))
        manager.createNotificationChannel(NotificationChannel(AlarmNotifications.CHANNEL_ALARM, "Alarms", NotificationManager.IMPORTANCE_NONE))
        assertFalse(AlarmReadiness.notificationsReady(app))
        val settings = AlarmReadiness.notificationSettings(app)
        assertEquals(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS, settings.action)
        assertEquals(AlarmNotifications.CHANNEL_ALARM, settings.getStringExtra(Settings.EXTRA_CHANNEL_ID))
    }

    @Test fun readinessChecksTrackingChannelAndWarnsAboutMutedAudio() {
        val manager = AlarmNotifications.notifications(app)
        manager.createNotificationChannel(NotificationChannel(AlarmNotifications.CHANNEL_TRACKING, "Tracking", NotificationManager.IMPORTANCE_NONE))
        assertEquals(AlarmNotifications.CHANNEL_TRACKING, AlarmReadiness.blockedChannel(app))
        val audio = app.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        audio.setStreamVolume(AudioManager.STREAM_ALARM, 0, 0)
        val values = AlarmReadiness.values(app, false)
        assertEquals(false, values["notifications"])
        assertEquals(manager.canUseFullScreenIntent(), values["fullScreenAlarms"])
        assertTrue((values["warnings"] as List<*>).any { it.toString().contains("volume is zero") })
    }

    @Test fun batteryConfirmationExpiresAndIsInvalidatedOnLeavingTheApp() {
        val confirmation = BatteryConfirmation()
        assertFalse(confirmation.valid())
        confirmation.confirm()
        assertTrue(confirmation.valid())
        ShadowSystemClock.advanceBy(Duration.ofMinutes(16))
        assertFalse(confirmation.valid())
        confirmation.confirm()
        confirmation.invalidate()
        assertFalse(confirmation.valid())
        assertFalse(BatteryConfirmation().valid())
    }

    @Test fun damagedNativeEntryDoesNotEraseOtherDestinations() {
        val valid = entry("kept").json()
        val invalid = entry("invalid").json().put("latitude", 100.0)
        val raw = JSONArray().put(valid).put(invalid).put("broken").toString()
        app.getSharedPreferences("destination_multi_monitor", Context.MODE_PRIVATE).edit().putString("alarms", raw).commit()
        assertEquals(listOf("kept"), MultiAlarmRuntime.live(app).map { it.id })
        val stored = app.getSharedPreferences("destination_multi_monitor", Context.MODE_PRIVATE)
        assertEquals(raw, stored.getString("recovery_alarms", null))
        assertNotNull(MultiAlarmRuntime.storageWarning(app))
        assertEquals(1, JSONArray(stored.getString("alarms", "[]")).length())
    }

    @Test fun corruptNativeJsonRestoresTheLastGoodSnapshotAndRecoveryCanBeDeleted() {
        save(entry("kept"))
        MultiAlarmRuntime.live(app)
        val stored = app.getSharedPreferences("destination_multi_monitor", Context.MODE_PRIVATE)
        stored.edit().putString("alarms", "broken JSON").commit()
        assertEquals("kept", MultiAlarmRuntime.live(app).single().id)
        assertNotNull(MultiAlarmRuntime.storageWarning(app))
        assertTrue(MultiAlarmRuntime.clearStorageRecovery(app))
        assertNull(stored.getString("recovery_alarms", null))
        assertNull(MultiAlarmRuntime.storageWarning(app))
        assertEquals("kept", MultiAlarmRuntime.live(app).single().id)
    }

    @Test fun clearingFinishedNativeRecordsPreservesAllActiveDestinations() {
        save(entry("live"), entry("ringing").apply { status = "triggered" },
            entry("done").apply { status = "completed" })
        assertTrue(MultiAlarmRuntime.clearFinished(app))
        assertEquals(setOf("live", "ringing"), MultiAlarmRuntime.live(app).map { it.id }.toSet())
        val stored = app.getSharedPreferences("destination_multi_monitor", Context.MODE_PRIVATE)
        assertFalse(stored.getString("last_good_alarms", "")!!.contains("done"))
    }

    @Test fun sensitiveDataIsExcludedFromCloudBackupAndDeviceTransfer() {
        assertEquals(0, app.applicationInfo.flags and ApplicationInfo.FLAG_ALLOW_BACKUP)
        val expected = setOf("root", "file", "database", "sharedpref", "external",
            "device_root", "device_file", "device_database", "device_sharedpref")
        val parser = app.resources.getXml(R.xml.data_extraction_rules)
        val domains = mutableMapOf<String, MutableSet<String>>()
        var section = ""
        while (parser.eventType != XmlPullParser.END_DOCUMENT) {
            if (parser.eventType == XmlPullParser.START_TAG) {
                if (parser.name == "cloud-backup" || parser.name == "device-transfer") section = parser.name
                if (parser.name == "exclude") {
                    assertEquals(".", parser.getAttributeValue(null, "path"))
                    domains.getOrPut(section) { mutableSetOf() }.add(parser.getAttributeValue(null, "domain"))
                }
            }
            parser.next()
        }
        parser.close()
        assertEquals(expected, domains["cloud-backup"])
        assertEquals(expected, domains["device-transfer"])
    }

    private class Result : MethodChannel.Result {
        var error: String? = null
        var success = false
        override fun success(value: Any?) { success = true }
        override fun error(code: String, message: String?, details: Any?) { error = code }
        override fun notImplemented() { error = "missing" }
    }

    @Test fun pauseIsPersistedAndBlocksTimeGpsAndLateGeofenceTriggers() {
        save(entry("paused").apply { alertAt = System.currentTimeMillis() + 60_000 })
        MultiAlarmRuntime.refresh(app)
        val result = Result()
        MultiAlarmRuntime.pause(app, "paused", true, result)
        assertTrue(result.success)
        assertTrue(MultiAlarmRuntime.live(app).isEmpty())
        assertEquals("paused", MultiAlarmRuntime.states(app).single()["status"])
        MultiAlarmRuntime.trigger(app, "paused", "distance")
        MultiAlarmRuntime.checkLocation(app, fix(0.0, 10_000))
        ShadowSystemClock.advanceBy(Duration.ofMinutes(2))
        MultiAlarmRuntime.checkDue(app)
        assertNull(MultiAlarmRuntime.ringing(app))
        val manager = app.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        assertTrue(shadowOf(manager).scheduledAlarms.isEmpty())
        assertTrue(MultiAlarmRuntime.clearFinished(app))
        assertEquals("paused", MultiAlarmRuntime.states(app).single()["status"])
    }

    @Test fun pausingOneAlarmDoesNotPauseAnotherAndResumeRejectsOldCrossings() {
        save(entry("paused").apply { paused = true }, entry("other", 0.02))
        MultiAlarmRuntime.checkLocation(app, fix(-0.004, 0))
        ShadowSystemClock.advanceBy(Duration.ofSeconds(1))
        val resume = Result()
        MultiAlarmRuntime.pause(app, "paused", false, resume)
        assertTrue(resume.success)
        val current = fix(0.004, 10_000).apply { time = System.currentTimeMillis() }
        MultiAlarmRuntime.checkLocation(app, current)
        assertNull(MultiAlarmRuntime.ringing(app))
        MultiAlarmRuntime.checkLocation(app, Location(current).apply { longitude = 0.0 })
        assertEquals("paused", MultiAlarmRuntime.ringing(app)?.id)
        assertEquals("active", MultiAlarmRuntime.states(app).first { it["id"] == "other" }["status"])
    }

    @Test fun editKeepsIdentityOtherAlarmsAndPausedState() {
        save(entry("edited").apply { paused = true }, entry("other", 0.02))
        val result = Result()
        MultiAlarmRuntime.update(app, mapOf("id" to "edited", "name" to "New stop", "address" to "Town",
            "latitude" to 1.0, "longitude" to 2.0, "radius" to 750.0,
            "sound" to "Digital", "vibration" to false, "repeatDays" to 0, "label" to "Commute"), result)
        assertTrue(result.success)
        val states = MultiAlarmRuntime.states(app)
        assertEquals(2, states.size)
        val edited = states.first { it["id"] == "edited" }
        assertEquals("paused", edited["status"])
        assertEquals("Commute", edited["label"])
        assertEquals("New stop", edited["name"])
        assertEquals(750.0, edited["radius"])
        assertEquals("Digital", edited["sound"])
        assertEquals(0.02, states.first { it["id"] == "other" }["longitude"])
        val invalid = Result()
        MultiAlarmRuntime.update(app, mapOf("id" to "edited", "name" to "Bad", "latitude" to 100.0,
            "longitude" to 0.0, "radius" to 750.0, "repeatDays" to 0), invalid)
        assertEquals("arguments", invalid.error)
        assertEquals("New stop", MultiAlarmRuntime.states(app).first { it["id"] == "edited" }["name"])
    }

    @Test fun renameChangesTheAlertLabelWithoutChangingTheDestination() {
        save(entry("named").apply { status = "triggered"; distanceFired = true })
        val result = Result()
        MultiAlarmRuntime.rename(app, "named", "Morning commute", result)
        assertTrue(result.success)
        val alarm = MultiAlarmRuntime.ringing(app)!!
        assertEquals("Morning commute", alarm.displayName)
        assertEquals("named", alarm.name)
        assertEquals("Morning commute", MultiAlarmRuntime.alarmNotification(app, alarm).extras.getString(Notification.EXTRA_TEXT))
        val pause = Result()
        MultiAlarmRuntime.pause(app, "named", true, pause)
        assertEquals("state", pause.error)
    }

    @Test fun nextRepeatDayAndNativeGpsDetailsAreReported() {
        val day = Calendar.getInstance().apply {
            add(Calendar.DAY_OF_MONTH, 1); set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
        }
        val weekday = (day.get(Calendar.DAY_OF_WEEK) + 5) % 7
        save(entry("later").copy(repeatDays = 1 shl weekday, cycleDay = day.timeInMillis))
        assertEquals(day.timeInMillis, MultiAlarmRuntime.states(app).single()["nextRepeatAt"])
        save(entry("tracking", 0.02))
        val controller = Robolectric.buildService(MultiTrackingService::class.java).create().startCommand(0, 1)
        val manager = app.getSystemService(Context.LOCATION_SERVICE) as LocationManager
        val position = fix(0.0, 10_000, 12f)
        shadowOf(manager).simulateLocation(position)
        shadowOf(Looper.getMainLooper()).idle()
        val health = MultiTrackingService.health(app)
        assertEquals(position.time, health["lastGpsFixAt"])
        assertEquals(12.0, health["gpsAccuracy"])
        controller.destroy()
    }

    @Test fun completedRepeatCycleIsArchivedSeparatelyFromNextCycle() {
        val day = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0); set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
        }
        val weekday = (day.get(Calendar.DAY_OF_WEEK) + 5) % 7
        save(entry("commute").copy(status = "triggered", distanceFired = true,
            repeatDays = 1 shl weekday, cycleDay = day.timeInMillis,
            cycleDate = day.get(Calendar.YEAR) * 10000 +
                (day.get(Calendar.MONTH) + 1) * 100 + day.get(Calendar.DAY_OF_MONTH)))
        MultiAlarmRuntime.dismiss(app, "commute")
        val states = MultiAlarmRuntime.states(app)
        assertEquals(2, states.size)
        assertTrue(states.any { it["id"] == "commute" && it["status"] == "active" })
        val cycle = states.single { (it["id"] as String).contains(":cycle:") }
        assertEquals("completed", cycle["status"])
        assertTrue((cycle["endedAt"] as Long) > 0L)
    }

    @Test fun expiredGoogleCoordinatesAreRemovedBeforeAnotherAlarmCanRing() {
        save(entry("expired").copy(sourceExpiresAt = System.currentTimeMillis() - 1L),
            entry("current", 0.02))
        val states = MultiAlarmRuntime.states(app)
        val expired = states.single { it["id"] == "expired" }
        assertEquals("cancelled", expired["status"])
        assertEquals(0.0, expired["latitude"])
        assertEquals(0.0, expired["longitude"])
        assertEquals(0L, expired["sourceExpiresAt"])
        assertEquals(true, expired["locationRedacted"])
        val expiryNotice = AlarmNotifications.notifications(app).activeNotifications
            .firstOrNull { it.id == 203 }?.notification
        assertNotNull(expiryNotice?.contentIntent)
        assertTrue(states.any { it["id"] == "current" && it["status"] == "active" })
    }

    @Test fun legacyAlarmWithoutSourceMarkerGetsConservativeExpiry() {
        val old = entry("legacy", 20.0).json()
        old.remove("sourceExpiresAt")
        val stored = app.getSharedPreferences("destination_multi_monitor", Context.MODE_PRIVATE)
        stored.edit().putString("alarms", JSONArray().put(old).toString()).commit()
        val state = MultiAlarmRuntime.states(app).single()
        assertTrue((state["sourceExpiresAt"] as Long) > System.currentTimeMillis())
        assertTrue(stored.getString("alarms", "")!!.contains("sourceExpiresAt"))

        old.put("startedAt", System.currentTimeMillis() - 31L * 24 * 60 * 60 * 1000)
        stored.edit().putString("alarms", JSONArray().put(old).toString()).commit()
        val expired = MultiAlarmRuntime.states(app).single()
        assertEquals("cancelled", expired["status"])
        assertEquals(0.0, expired["longitude"])
    }

    @Test fun completedLegacyAlarmLosesUnknownSourceCoordinates() {
        val old = entry("legacy-done", 20.0).json()
        old.remove("sourceExpiresAt")
        old.put("status", "completed")
        val stored = app.getSharedPreferences("destination_multi_monitor", Context.MODE_PRIVATE)
        stored.edit().putString("alarms", JSONArray().put(old).toString()).commit()
        val state = MultiAlarmRuntime.states(app).single()
        assertEquals(0.0, state["longitude"])
        assertEquals(0L, state["sourceExpiresAt"])
        assertFalse(stored.getString("alarms", "")!!.contains("\"longitude\":20"))
    }

    @Test fun completedGoogleAlarmDoesNotKeepPlacesCoordinatesInHistory() {
        save(entry("finished").copy(latitude = 10.0, longitude = 20.0,
            sourceExpiresAt = System.currentTimeMillis() + 86_400_000L))
        MultiAlarmRuntime.finish(app, "finished", "completed")
        val finished = MultiAlarmRuntime.states(app).single()
        assertEquals(0.0, finished["latitude"])
        assertEquals(0.0, finished["longitude"])
        assertEquals(0L, finished["sourceExpiresAt"])
        assertEquals(true, finished["locationRedacted"])
    }

    @Test fun testAlarmIsIsolatedAndStopsAutomaticallyWithWakeLockCleanup() {
        ShadowMediaPlayer.setMediaInfoProvider { ShadowMediaPlayer.MediaInfo(1000, 0) }
        save(entry("untouched", 0.02))
        val before = app.getSharedPreferences("destination_multi_monitor", Context.MODE_PRIVATE).getString("alarms", null)
        val controller = Robolectric.buildService(TestAlarmService::class.java, Intent().putExtra("sound", "Bell").putExtra("vibration", false)).create()
            .startCommand(0, 1)
        val lock = ShadowPowerManager.getLatestWakeLock()
        assertTrue(lock.isHeld)
        assertFalse(TestAlarmService.isRinging())
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(5))
        assertTrue(TestAlarmService.isRinging())
        val notification = shadowOf(controller.get()).lastForegroundNotification
        assertEquals(TestAlarmActivity::class.java.name,
            shadowOf(notification.fullScreenIntent).savedIntent.component?.className)
        assertEquals(TestAlarmService.NOTIFICATION_ID, shadowOf(controller.get()).lastForegroundNotificationId)
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(10))
        assertFalse(TestAlarmService.isRinging())
        assertFalse(lock.isHeld)
        assertEquals(before, app.getSharedPreferences("destination_multi_monitor", Context.MODE_PRIVATE).getString("alarms", null))
        controller.destroy()
    }

    @Test fun realDestinationAlertStopsTheTestWithoutLosingItsOwnNotification() {
        ShadowMediaPlayer.setMediaInfoProvider { ShadowMediaPlayer.MediaInfo(1000, 0) }
        save(entry("real", 0.02))
        val test = Robolectric.buildService(TestAlarmService::class.java, Intent().putExtra("sound", "Bell")).create()
            .startCommand(0, 1)
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(5))
        assertTrue(TestAlarmService.isRinging())
        save(entry("real").apply { status = "triggered"; distanceFired = true })
        val tracking = Robolectric.buildService(MultiTrackingService::class.java).create().startCommand(0, 1)
        assertFalse(TestAlarmService.isRinging())
        assertEquals(MultiAlarmRuntime.ALARM_ID, shadowOf(tracking.get()).lastForegroundNotificationId)
        tracking.destroy(); test.destroy()
    }

    @Test fun lockScreenActivityHasNoAppNavigationAndRejectsMissingAlarm() {
        val inactive = Robolectric.buildActivity(LockedAlarmActivity::class.java).create()
        assertTrue(inactive.get().isFinishing)
        inactive.destroy()
        save(entry("locked").apply { status = "triggered"; distanceFired = true })
        val notification = MultiAlarmRuntime.alarmNotification(app, MultiAlarmRuntime.ringing(app)!!)
        assertEquals(LockedAlarmActivity::class.java.name,
            shadowOf(notification.fullScreenIntent).savedIntent.component?.className)
        val controller = Robolectric.buildActivity(LockedAlarmActivity::class.java).create().start().resume()
        val info = app.packageManager.getActivityInfo(controller.get().componentName, 0)
        assertFalse(info.exported)
        assertFalse(controller.get().isFinishing)
        controller.pause().stop().destroy()
    }
}
