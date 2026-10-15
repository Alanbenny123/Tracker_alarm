package com.trackeralarm.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Restores time scheduling and geofence backups after a restart or clock change. */
class AlarmRestoreReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED -> {
                MultiAlarmRuntime.realignClock(context)
                MultiAlarmRuntime.checkDue(context)
                MultiAlarmRuntime.ensureGeofences(context)
                MultiAlarmRuntime.refresh(context)
            }
        }
    }
}
