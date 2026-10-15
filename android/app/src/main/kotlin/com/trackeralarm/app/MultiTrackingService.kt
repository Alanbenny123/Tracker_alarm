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

/** One foreground GPS subscription monitors every active destination. */
class MultiTrackingService : Service() {
    private val locationManager by lazy { getSystemService(Context.LOCATION_SERVICE) as LocationManager }
    private val sound by lazy { AlarmSoundPlayer(this) }
    private var interval = 0L
    private var ringingId: String? = null
    private val listener = object : LocationListener {
        override fun onLocationChanged(location: Location) {
            val wanted = MultiAlarmRuntime.checkLocation(this@MultiTrackingService, location)
            updateForeground()
            if (wanted != interval) requestUpdates(wanted)
        }
        override fun onProviderDisabled(provider: String) {
            if (provider == LocationManager.GPS_PROVIDER) {
                AlarmRuntime.notifications(this@MultiTrackingService).notify(
                    MultiAlarmRuntime.TRACKING_ID,
                    MultiAlarmRuntime.trackingNotification(this@MultiTrackingService, MultiAlarmRuntime.live(this@MultiTrackingService).size))
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (!updateForeground()) {
            stopSelf()
            return START_NOT_STICKY
        }
        val distanceActive = MultiAlarmRuntime.live(this).any {
            !it.distanceFired && it.distanceReady(System.currentTimeMillis())
        }
        if (interval == 0L || (distanceActive && interval > 30_000L)) {
            requestUpdates(if (distanceActive) 30_000L else 30 * 60_000L)
        }
        MultiAlarmRuntime.checkDue(this)
        updateForeground()
        return START_STICKY
    }

    private fun updateForeground(): Boolean {
        val live = MultiAlarmRuntime.live(this)
        if (live.isEmpty()) return false
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
        return true
    }

    @Suppress("DEPRECATION")
    private fun requestUpdates(wanted: Long) {
        try {
            if (interval != 0L) locationManager.removeUpdates(listener)
            locationManager.requestLocationUpdates(LocationManager.GPS_PROVIDER,
                wanted, 0f, listener, Looper.getMainLooper())
            interval = wanted
        } catch (_: Exception) {
            interval = 0L
            AlarmRuntime.notifications(this).notify(MultiAlarmRuntime.TRACKING_ID,
                MultiAlarmRuntime.trackingNotification(this, MultiAlarmRuntime.live(this).size))
        }
    }

    override fun onDestroy() {
        if (interval != 0L) {
            try { locationManager.removeUpdates(listener) } catch (_: Exception) { }
        }
        sound.stop()
        super.onDestroy()
    }
}
