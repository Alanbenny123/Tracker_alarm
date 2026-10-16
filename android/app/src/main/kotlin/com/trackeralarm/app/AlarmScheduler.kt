package com.trackeralarm.app

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build

/** User-visible alerts use alarm-clock scheduling so short snoozes survive Doze. */
object AlarmScheduler {
    fun canScheduleExact(context: Context): Boolean = Build.VERSION.SDK_INT < 31 ||
        (context.getSystemService(Context.ALARM_SERVICE) as AlarmManager).canScheduleExactAlarms()

    fun schedule(context: Context, whenMillis: Long, operation: PendingIntent, audible: Boolean) {
        val manager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        if (canScheduleExact(context)) {
            try {
                if (audible) {
                    val show = PendingIntent.getActivity(context, 49,
                        Intent(context, MainActivity::class.java),
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                    manager.setAlarmClock(AlarmManager.AlarmClockInfo(whenMillis, show), operation)
                } else {
                    // Repeat-day activation is internal work, not a ringing alarm.
                    manager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, whenMillis, operation)
                }
                return
            } catch (_: SecurityException) { /* Permission was revoked. Keep a best-effort backup. */ }
        }
        // Restored alarms still get a backup if access is missing; setup and health
        // explicitly report that timing is unreliable until access is granted.
        manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, whenMillis, operation)
    }
}
