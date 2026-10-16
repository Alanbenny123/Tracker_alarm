package com.trackeralarm.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build

/** Shared Android channels; playback remains owned by the active service. */
object AlarmNotifications {
    const val CHANNEL_TRACKING = "destination_tracking"
    const val CHANNEL_ALARM = "destination_alarm_controls_v2"
    fun notifications(context: Context): NotificationManager {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(NotificationChannel(CHANNEL_TRACKING, "Destination tracking", NotificationManager.IMPORTANCE_LOW))
            val alarm = NotificationChannel(CHANNEL_ALARM, "Destination alarms", NotificationManager.IMPORTANCE_HIGH)
            // A new channel ID is needed: Android keeps old channel sound settings.
            // AlarmSoundPlayer alone owns the selected looping sound and vibration.
            alarm.setSound(null, null)
            alarm.enableVibration(false)
            manager.createNotificationChannel(alarm)
        }
        return manager
    }

}
