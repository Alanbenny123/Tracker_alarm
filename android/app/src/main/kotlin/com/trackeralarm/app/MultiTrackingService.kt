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
            lastFixElapsed = SystemClock.elapsedRealtime()
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
        if (ringing != null) {
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
            val notification = MultiAlarmRuntime.trackingNotification(this, live.size)
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
