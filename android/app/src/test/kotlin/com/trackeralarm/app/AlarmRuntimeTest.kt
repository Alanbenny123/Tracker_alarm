package com.trackeralarm.app

import android.Manifest
import android.app.Application
import android.content.Context
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
