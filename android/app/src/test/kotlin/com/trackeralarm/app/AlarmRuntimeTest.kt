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

    @Test fun fastCrossingRingsBothDestinationsInTravelOrder() {
        save(entry("second", 0.0015), entry("first", -0.0015))
        MultiAlarmRuntime.checkLocation(app, fix(-0.004, 0))
        val interval = MultiAlarmRuntime.checkLocation(app, fix(0.004, 10_000))
        assertEquals(2, MultiAlarmRuntime.live(app).count { it.status == "triggered" })
        assertEquals("first", MultiAlarmRuntime.ringing(app)?.id)
        assertTrue(interval <= 1000)
    }

    @Test fun inaccurateOrOldSegmentsDoNotInferCrossings() {
        assertNull(DestinationCrossing.fraction(fix(-0.0015, 0, 500f), fix(0.0015, 5000), 0.0, 0.0, 100f))
        assertNull(DestinationCrossing.fraction(fix(-0.0015, 0), fix(0.0015, 20_000), 0.0, 0.0, 100f))
        assertNull(DestinationCrossing.fraction(fix(-0.0015, 0), fix(-0.0012, 5000), 0.0, 0.0, 100f))
    }

    @Test fun notificationDismissKeepsTheOtherAlarmRinging() {
        save(entry("first").apply { status = "triggered"; distanceFired = true; triggeredAt = 1 },
            entry("second").apply { status = "triggered"; distanceFired = true; triggeredAt = 2 })
        MultiAlarmReceiver().onReceive(app, Intent("tracker_alarm.MULTI_DISMISS").putExtra("id", "first"))
        assertEquals("second", MultiAlarmRuntime.ringing(app)?.id)
        assertEquals("completed", MultiAlarmRuntime.states(app).first { it["id"] == "first" }["status"])
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
        val channel = AlarmRuntime.notifications(app).getNotificationChannel(AlarmRuntime.CHANNEL_ALARM)
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
        val manager = AlarmRuntime.notifications(app)
        assertTrue(AlarmReadiness.notificationsReady(app))
        manager.createNotificationChannel(NotificationChannel(AlarmRuntime.CHANNEL_ALARM, "Alarms", NotificationManager.IMPORTANCE_NONE))
        assertFalse(AlarmReadiness.notificationsReady(app))
        val settings = AlarmReadiness.notificationSettings(app)
        assertEquals(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS, settings.action)
        assertEquals(AlarmRuntime.CHANNEL_ALARM, settings.getStringExtra(Settings.EXTRA_CHANNEL_ID))
    }

    @Test fun readinessChecksTrackingChannelAndWarnsAboutMutedAudio() {
        val manager = AlarmRuntime.notifications(app)
        manager.createNotificationChannel(NotificationChannel(AlarmRuntime.CHANNEL_TRACKING, "Tracking", NotificationManager.IMPORTANCE_NONE))
        assertEquals(AlarmRuntime.CHANNEL_TRACKING, AlarmReadiness.blockedChannel(app))
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
