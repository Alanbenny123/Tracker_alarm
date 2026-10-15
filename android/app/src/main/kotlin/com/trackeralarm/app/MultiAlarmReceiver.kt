package com.trackeralarm.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class MultiAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getStringExtra("id")
        when (intent.action) {
            "tracker_alarm.MULTI_TIME" -> {
                MultiAlarmRuntime.checkDue(context)
                MultiAlarmRuntime.ensureGeofences(context)
            }
            "tracker_alarm.MULTI_DISMISS" -> if (id != null) MultiAlarmRuntime.dismiss(context, id)
            "tracker_alarm.MULTI_END" -> if (id != null) MultiAlarmRuntime.finish(context, id, "completed")
            "tracker_alarm.MULTI_SNOOZE" -> if (id != null) MultiAlarmRuntime.snooze(context, id, 1)
        }
    }
}
