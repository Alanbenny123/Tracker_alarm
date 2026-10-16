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
                if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
                    // Restore GPS first. Android 15+ forbids media playback FGS
                    // launches from BOOT_COMPLETED; the user resumes a pending alert.
                    MultiAlarmRuntime.checkDue(context, refreshService = false)
                    MultiAlarmRuntime.setPlaybackResumeRequired(context, MultiAlarmRuntime.ringing(context) != null)
                } else MultiAlarmRuntime.checkDue(context)
                MultiAlarmRuntime.ensureGeofences(context)
                MultiAlarmRuntime.refresh(context)
            }
        }
    }
}
