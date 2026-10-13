package com.trackeralarm.app

import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.IBinder
import android.os.Looper

/** Checks the destination while the screen is off; the geofence remains a backup. */
class DestinationTrackingService : Service() {
    companion object {
        private var running: DestinationTrackingService? = null

        fun ringIfRunning(): Boolean = running?.ring() == true
        fun snoozeIfRunning(): Boolean = running?.resumeMonitoring() == true
        fun latestLocation(): Location? = running?.lastLocation?.let { Location(it) }
    }

    private val locationManager by lazy { getSystemService(Context.LOCATION_SERVICE) as LocationManager }
    private val sound by lazy { AlarmSoundPlayer(this) }
    private var trackingInterval = 0L
    private var ringing = false
    private var lastLocation: Location? = null
    private val listener = object : LocationListener {
        override fun onLocationChanged(location: Location) = checkLocation(location)
        override fun onProviderDisabled(provider: String) {
            if (provider == LocationManager.GPS_PROVIDER)
                AlarmRuntime.showTracking(this@DestinationTrackingService, "Turn on GPS to monitor your destination.")
        }
        override fun onProviderEnabled(provider: String) {
            if (provider == LocationManager.GPS_PROVIDER && trackingInterval == 0L) requestUpdates(30_000L)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        running = this
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val status = AlarmRuntime.prefs(this).getString("status", "inactive")
        if (status == "triggered") {
            if (AlarmPlaybackService.isRunning) {
                stopSelf()
                return START_NOT_STICKY
            }
            if (ring()) return START_STICKY
            stopSelf()
            return START_NOT_STICKY
        }
        if (status != "active" && status != "snoozed") {
            stopSelf()
            return START_NOT_STICKY
        }
        if (!resumeMonitoring()) {
            stopSelf()
            return START_NOT_STICKY
        }
        return START_STICKY
    }

    private fun ring(): Boolean {
        if (ringing) {
            AlarmRuntime.notifications(this).notify(AlarmRuntime.ALARM_ID, AlarmRuntime.alarmNotification(this))
            return true
        }
        if (AlarmRuntime.prefs(this).getString("status", "inactive") != "triggered") return false
        try {
            val notification = AlarmRuntime.alarmNotification(this)
            if (Build.VERSION.SDK_INT >= 29) {
                startForeground(AlarmRuntime.ALARM_ID, notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION or ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
            } else startForeground(AlarmRuntime.ALARM_ID, notification)
            AlarmRuntime.notifications(this).cancel(AlarmRuntime.TRACKING_ID)
            ringing = true
            sound.start()
            return true
        } catch (_: Exception) {
            return false
        }
    }

    private fun resumeMonitoring(): Boolean {
        val status = AlarmRuntime.prefs(this).getString("status", "inactive")
        if (status != "active" && status != "snoozed") return false
        try {
            val name = AlarmRuntime.prefs(this).getString("name", "destination")
            val message = if (status == "snoozed") "Alarm snoozed" else "Monitoring $name"
            val notification = AlarmRuntime.trackingNotification(this, message)
            if (Build.VERSION.SDK_INT >= 29) {
                startForeground(AlarmRuntime.TRACKING_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION)
            } else startForeground(AlarmRuntime.TRACKING_ID, notification)
            if (ringing) {
                sound.stop()
                ringing = false
                AlarmRuntime.notifications(this).cancel(AlarmRuntime.ALARM_ID)
            }
            if (trackingInterval == 0L) requestUpdates(30_000L)
            return true
        } catch (_: Exception) {
            return false
        }
    }

    @Suppress("DEPRECATION")
    private fun requestUpdates(interval: Long) {
        try {
            if (trackingInterval != 0L) locationManager.removeUpdates(listener)
            trackingInterval = interval
            locationManager.requestLocationUpdates(
                LocationManager.GPS_PROVIDER, interval, 0f, listener, Looper.getMainLooper(),
            )
            if (!locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)) {
                AlarmRuntime.showTracking(this, "Turn on GPS to monitor your destination.")
            }
        } catch (_: Exception) {
            trackingInterval = 0L
            AlarmRuntime.showTracking(this, "GPS unavailable. Check location and app permissions.")
        }
    }

    private fun checkLocation(location: Location) {
        lastLocation = Location(location)
        val status = AlarmRuntime.prefs(this).getString("status", "inactive")
        if (status == "inactive" || status == "cancelled" || status == "completed") {
            stopSelf()
            return
        }
        if (status == "triggered") {
            if (AlarmPlaybackService.isRunning) {
                stopSelf()
                return
            }
            if (!ringing) ring()
        }
        if (status != "active" && status != "triggered") return
        val alertAt = AlarmRuntime.prefs(this).getLong("alertAt", 0L)
        if (alertAt > 0L && !AlarmRuntime.prefs(this).getBoolean("timeFired", false) && System.currentTimeMillis() >= alertAt) {
            AlarmRuntime.trigger(this, "time")
        }
        if (System.currentTimeMillis() - location.time > 30_000L) return
        val distance = AlarmRuntime.distanceToDestination(this, location)
        val radius = AlarmRuntime.prefs(this).getFloat("radius", 500f)
        if (distance <= radius && !AlarmRuntime.prefs(this).getBoolean("distanceFired", false)) {
            AlarmRuntime.trigger(this)
            return
        }
        // Save battery while far away, then check more frequently on approach.
        val wantedInterval = when {
            distance <= 1_000f + radius -> 5_000L
            distance <= 5_000f + radius -> 10_000L
            else -> 30_000L
        }
        if (wantedInterval != trackingInterval) requestUpdates(wantedInterval)
    }

    override fun onDestroy() {
        if (running === this) running = null
        if (trackingInterval != 0L) {
            try { locationManager.removeUpdates(listener) } catch (_: Exception) { }
        }
        sound.stop()
        super.onDestroy()
    }
}
