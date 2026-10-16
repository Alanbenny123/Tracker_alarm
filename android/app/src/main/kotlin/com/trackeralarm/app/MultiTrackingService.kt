package com.trackeralarm.app

import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.util.Log

/** One foreground GPS subscription monitors every active destination. */
class MultiTrackingService : Service() {
    companion object {
        private const val TAG = "MultiTrackingService"
        private const val HEARTBEAT_MS = 30_000L
        private const val WAKE_TIMEOUT_MS = 90_000L
        private var running: MultiTrackingService? = null
        private var startFailure: String? = null

        fun health(context: Context): Map<String, Any> {
            val service = running ?: return mapOf(
                "monitoringMessage" to (startFailure ?: "Background service not running. Reopen the app to restart."),
                "monitoringHealthy" to false, "gpsStatus" to "Not monitoring")
            if (MultiAlarmRuntime.playbackResumeRequired(context)) return mapOf(
                "monitoringMessage" to "Phone restarted. Open the app to resume the pending alert.",
                "monitoringHealthy" to false, "gpsStatus" to "Alert needs attention")
            val distanceActive = MultiAlarmRuntime.live(context).any {
                !it.distanceFired && it.distanceReady(System.currentTimeMillis())
            }
            if (!distanceActive) return mapOf("monitoringMessage" to "Waiting for the next scheduled alert.",
                "monitoringHealthy" to true, "gpsStatus" to "Not needed right now")
            val age = if (service.lastFixElapsed == 0L) Long.MAX_VALUE else
                SystemClock.elapsedRealtime() - service.lastFixElapsed
            val problem = when {
                !service.gpsEnabled() -> "GPS is off. Turn on location services."
                service.interval == 0L -> "GPS subscription failed. Check location permissions."
                age > WAKE_TIMEOUT_MS -> "Waiting for a fresh GPS fix."
                else -> null
            }
            return mapOf(
                "monitoringMessage" to (problem ?: "GPS monitoring active · last fix ${age / 1000} s ago"),
                "monitoringHealthy" to (problem == null),
                "gpsStatus" to if (problem != null) problem else when {
                    service.lastAccuracy <= 20f -> "Excellent"
                    service.lastAccuracy <= 80f -> "Good"
                    else -> "Weak (${service.lastAccuracy.toInt()} m accuracy)"
                })
        }

        fun refreshIfRunning(): Boolean = try {
            running?.syncRuntime() == true
        } catch (e: Exception) {
            Log.e(TAG, "Could not refresh the running tracker", e)
            false
        }
    }

    private val locationManager by lazy { getSystemService(Context.LOCATION_SERVICE) as LocationManager }
    private val sound by lazy { AlarmSoundPlayer(this) }
    private val handler = Handler(Looper.getMainLooper())
    private val monitoringWakeLock by lazy {
        (getSystemService(Context.POWER_SERVICE) as PowerManager)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "$packageName:destination-monitor")
            .apply { setReferenceCounted(false) }
    }
    private var interval = 0L
    private var ringingId: String? = null
    private var lastFixElapsed = 0L
    private var lastAccuracy = Float.MAX_VALUE
    private var lastRequestElapsed = 0L
    private val heartbeat = object : Runnable {
        override fun run() {
            MultiAlarmRuntime.checkDue(this@MultiTrackingService)
            if (!syncRuntime()) return
            // Recover a stalled GPS subscription without relying on Flutter or unlocking.
            if (interval != 0L && gpsEnabled() &&
                SystemClock.elapsedRealtime() - maxOf(lastFixElapsed, lastRequestElapsed) >= WAKE_TIMEOUT_MS) {
                requestUpdates(5_000L)
            }
            handler.postDelayed(this, HEARTBEAT_MS)
        }
    }
    private val listener = object : LocationListener {
        override fun onLocationChanged(location: Location) {
            if (System.currentTimeMillis() - location.time in 0..30_000L) {
                lastFixElapsed = SystemClock.elapsedRealtime()
                lastAccuracy = if (location.hasAccuracy()) location.accuracy else Float.MAX_VALUE
            }
            val wanted = MultiAlarmRuntime.checkLocation(this@MultiTrackingService, location)
            if (wanted <= 30_000L && wanted != interval) requestUpdates(wanted)
            syncRuntime()
        }
        override fun onProviderDisabled(provider: String) {
            if (provider == LocationManager.GPS_PROVIDER) {
                syncRuntime()
            }
        }
        override fun onProviderEnabled(provider: String) {
            if (provider == LocationManager.GPS_PROVIDER) {
                stopUpdates()
                syncRuntime()
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        running = this
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return try {
            startFailure = null
            startMonitoring()
        } catch (e: Exception) {
            startFailure = "Background monitoring could not start. Check location permissions and battery settings."
            Log.e(TAG, "Could not start monitoring", e)
            stopUpdates()
            releaseWakeLock()
            sound.stop()
            running = null
            stopSelf()
            START_NOT_STICKY
        }
    }

    private fun startMonitoring(): Int {
        if (!syncRuntime()) return START_NOT_STICKY
        MultiAlarmRuntime.checkDue(this)
        if (!syncRuntime()) return START_NOT_STICKY
        handler.removeCallbacks(heartbeat)
        handler.postDelayed(heartbeat, HEARTBEAT_MS)
        return START_STICKY
    }

    private fun syncRuntime(): Boolean {
        val live = MultiAlarmRuntime.live(this)
        if (live.isEmpty()) {
            stopUpdates()
            releaseWakeLock()
            stopSelf()
            return false
        }
        val ringing = MultiAlarmRuntime.ringing(this)
        if (ringing != null && !MultiAlarmRuntime.playbackResumeRequired(this)) {
            val notification = MultiAlarmRuntime.alarmNotification(this, ringing)
            if (Build.VERSION.SDK_INT >= 29) {
                startForeground(MultiAlarmRuntime.ALARM_ID, notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION or ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
            } else startForeground(MultiAlarmRuntime.ALARM_ID, notification)
            AlarmRuntime.notifications(this).cancel(MultiAlarmRuntime.TRACKING_ID)
            if (ringingId != ringing.id) {
                sound.stop()
                sound.start(ringing.sound, ringing.vibration)
                ringingId = ringing.id
            }
        } else {
            val notification = MultiAlarmRuntime.trackingNotification(this, live.size,
                health(this)["monitoringMessage"] as String)
            if (Build.VERSION.SDK_INT >= 29) {
                startForeground(MultiAlarmRuntime.TRACKING_ID, notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION)
            } else startForeground(MultiAlarmRuntime.TRACKING_ID, notification)
            AlarmRuntime.notifications(this).cancel(MultiAlarmRuntime.ALARM_ID)
            if (ringingId != null) {
                sound.stop()
                ringingId = null
            }
        }
        val distanceActive = live.any {
            !it.distanceFired && it.distanceReady(System.currentTimeMillis())
        }
        if (distanceActive) {
            if (interval == 0L) requestUpdates(5_000L)
        } else stopUpdates()
        if (distanceActive && interval != 0L && gpsEnabled()) {
            // Renew a bounded CPU lock only while a destination needs GPS today.
            // Future repeat days and time-only waiting do not keep the CPU awake.
            monitoringWakeLock.acquire(WAKE_TIMEOUT_MS)
        } else releaseWakeLock()
        return true
    }

    private fun gpsEnabled(): Boolean = try {
        locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)
    } catch (e: Exception) {
        Log.w(TAG, "Could not read GPS state", e)
        false
    }

    @Suppress("DEPRECATION")
    private fun requestUpdates(wanted: Long) {
        stopUpdates()
        try {
            locationManager.requestLocationUpdates(LocationManager.GPS_PROVIDER,
                wanted, 0f, listener, Looper.getMainLooper())
            interval = wanted
            lastRequestElapsed = SystemClock.elapsedRealtime()
        } catch (e: Exception) {
            Log.e(TAG, "Could not subscribe to background GPS", e)
            releaseWakeLock()
            AlarmRuntime.notifications(this).notify(MultiAlarmRuntime.TRACKING_ID,
                MultiAlarmRuntime.trackingNotification(this, MultiAlarmRuntime.live(this).size))
        }
    }

    private fun stopUpdates() {
        if (interval != 0L) {
            try { locationManager.removeUpdates(listener) } catch (_: Exception) { }
        }
        interval = 0L
    }

    private fun releaseWakeLock() {
        if (monitoringWakeLock.isHeld) monitoringWakeLock.release()
    }

    override fun onDestroy() {
        if (running === this) running = null
        handler.removeCallbacks(heartbeat)
        stopUpdates()
        releaseWakeLock()
        sound.stop()
        super.onDestroy()
    }
}
