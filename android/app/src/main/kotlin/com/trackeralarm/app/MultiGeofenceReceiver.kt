package com.trackeralarm.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.location.Location
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingEvent

/** Handles every matching destination without replacing another geofence. */
class MultiGeofenceReceiver : BroadcastReceiver() {
    companion object {
        /** Reject delayed or unverifiable backup events; live GPS can still alert. */
        internal fun verifiedDistance(alarm: MultiAlarmRuntime.Entry, location: Location?, now: Long): Float? {
            if (location == null || !LocationEvidence.usable(location, alarm.radius) ||
                now - location.time !in 0..30_000L ||
                location.time < alarm.monitoringSince ||
                location.time < alarm.cycleDay) return null
            val distance = FloatArray(1).also {
                Location.distanceBetween(location.latitude, location.longitude,
                    alarm.latitude, alarm.longitude, it)
            }[0]
            val tolerance = location.accuracy.coerceIn(50f, 250f)
            return distance.takeIf { it <= alarm.radius + tolerance }
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        val event = GeofencingEvent.fromIntent(intent) ?: return
        if (event.hasError() || event.geofenceTransition != Geofence.GEOFENCE_TRANSITION_ENTER) return
        val location = event.triggeringLocation
        val now = System.currentTimeMillis()
        val live = MultiAlarmRuntime.live(context).associateBy { it.id }
        val candidates = event.triggeringGeofences.orEmpty().mapNotNull { fence ->
            val alarm = live[fence.requestId] ?: return@mapNotNull null
            val distance = verifiedDistance(alarm, location, now) ?: return@mapNotNull null
            alarm.id to distance
        }.sortedBy { it.second }
        candidates.forEach { (id, _) ->
            MultiAlarmRuntime.trigger(context, id, "distance")
        }
    }
}
