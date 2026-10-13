package com.trackeralarm.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class AlarmActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            "tracker_alarm.STOP" -> {
                val pending = goAsync()
                AlarmRuntime.dismissCurrent(context, done = { pending.finish() })
            }
            "tracker_alarm.END_TRIP" -> {
                val pending = goAsync()
                AlarmRuntime.finish(context, "completed", done = { pending.finish() })
            }
            "tracker_alarm.SNOOZE" -> AlarmRuntime.snooze(context, 1)
            "tracker_alarm.TIME_TRIGGER" -> AlarmRuntime.trigger(context, "time")
            "tracker_alarm.SNOOZE_END" -> {
                val pending = goAsync()
                AlarmRuntime.snoozeExpired(context) { pending.finish() }
            }
        }
    }
}
