package com.trackeralarm.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.location.Location
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingEvent

/** Handles every matching destination without replacing another geofence. */
class MultiGeofenceReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val event = GeofencingEvent.fromIntent(intent) ?: return
        if (event.hasError() || event.geofenceTransition != Geofence.GEOFENCE_TRANSITION_ENTER) return
        val location = event.triggeringLocation
        val live = MultiAlarmRuntime.live(context).associateBy { it.id }
        val candidates = event.triggeringGeofences.orEmpty().mapNotNull { fence ->
            val alarm = live[fence.requestId] ?: return@mapNotNull null
            val distance = if (location == null) 0f else FloatArray(1).also {
                Location.distanceBetween(location.latitude, location.longitude,
                    alarm.latitude, alarm.longitude, it)
            }[0]
            val tolerance = if (location != null && location.hasAccuracy())
                location.accuracy.coerceIn(50f, 250f) else 100f
            if (location != null && distance > alarm.radius + tolerance) null
            else alarm.id to distance
        }.sortedBy { it.second }
        candidates.forEach { (id, _) ->
            MultiAlarmRuntime.trigger(context, id, "distance")
        }
    }
}
