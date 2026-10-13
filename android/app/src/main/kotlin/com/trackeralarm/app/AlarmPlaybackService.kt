package com.trackeralarm.app

import android.app.Service
import android.content.Intent
import android.os.IBinder

/** Fallback when Android wakes the app with a geofence or time event. */
class AlarmPlaybackService : Service() {
    companion object {
        var isRunning = false
            private set
    }

    private val sound by lazy { AlarmSoundPlayer(this) }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        isRunning = true
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (AlarmRuntime.prefs(this).getString("status", "inactive") != "triggered") {
            stopSelf()
            return START_NOT_STICKY
        }
        startForeground(AlarmRuntime.ALARM_ID, AlarmRuntime.alarmNotification(this))
        stopService(Intent(this, DestinationTrackingService::class.java))
        sound.start()
        return START_STICKY
    }

    override fun onDestroy() {
        isRunning = false
        sound.stop()
        super.onDestroy()
    }
}
