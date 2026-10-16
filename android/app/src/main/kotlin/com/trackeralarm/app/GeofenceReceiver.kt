package com.trackeralarm.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Old geofence callbacks follow the same validation as current callbacks. */
class GeofenceReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        MultiAlarmRuntime.migrateLegacy(context)
        MultiGeofenceReceiver().onReceive(context, intent)
    }
}
