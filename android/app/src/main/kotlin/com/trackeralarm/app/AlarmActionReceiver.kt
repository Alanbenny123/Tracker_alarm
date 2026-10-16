package com.trackeralarm.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Handles old PendingIntents without reviving the retired alarm engine. */
class AlarmActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        MultiAlarmRuntime.migrateLegacy(context)
        val id = LegacyAlarmMigration.id(context) ?: return
        when (intent.action) {
            "tracker_alarm.STOP" -> MultiAlarmRuntime.dismiss(context, id)
            "tracker_alarm.END_TRIP" -> MultiAlarmRuntime.finish(context, id, "completed")
            "tracker_alarm.SNOOZE" -> MultiAlarmRuntime.snooze(context, id, 1)
            "tracker_alarm.TIME_TRIGGER", "tracker_alarm.SNOOZE_END" -> MultiAlarmRuntime.checkDue(context)
        }
    }
}
