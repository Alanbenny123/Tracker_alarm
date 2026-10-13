package com.trackeralarm.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingEvent

class GeofenceReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val event = GeofencingEvent.fromIntent(intent) ?: return
        if (event.hasError() || event.geofenceTransition != Geofence.GEOFENCE_TRANSITION_ENTER) return
        val id = AlarmRuntime.prefs(context).getString("id", null)
        if (event.triggeringGeofences?.any { it.requestId == id } == true) AlarmRuntime.trigger(context)
    }
}
