package com.trackeralarm.app

import android.app.AlarmManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.os.IBinder
import com.google.android.gms.location.LocationServices

/** Read/retire old storage only. No second tracker, scheduler or audio engine. */
object LegacyAlarmMigration {
    private fun prefs(context: Context) = context.getSharedPreferences("destination_monitor", Context.MODE_PRIVATE)
    fun status(context: Context): String = prefs(context).getString("status", "inactive") ?: "inactive"
    fun id(context: Context): String? = prefs(context).getString("id", null)

    private fun coordinate(stored: SharedPreferences, key: String, oldKey: String): Double {
        if (stored.contains(key)) return requireNotNull(stored.getString(key, null)?.toDoubleOrNull())
        require(stored.contains(oldKey))
        return stored.getFloat(oldKey, Float.NaN).toDouble()
    }

    fun problem(context: Context): String? = if (!prefs(context).getBoolean("migrated_to_multi", false) &&
        status(context) in listOf("active", "triggered", "snoozed") && readEntry(context) == null)
        "An older alarm could not be migrated. Its original data is kept; check your alarms and recreate the missing destination."
        else null

    fun readEntry(context: Context): MultiAlarmRuntime.Entry? {
        val stored = prefs(context)
        if (stored.getBoolean("migrated_to_multi", false)) return null
        val status = status(context)
        if (status !in listOf("active", "triggered", "snoozed")) return null
        return try {
            val id = id(context) ?: return null
            val lat = coordinate(stored, "latitude", "lat")
            val lon = coordinate(stored, "longitude", "lng")
            val radius = stored.getFloat("radius", 500f)
            require(id.isNotBlank() && lat.isFinite() && lon.isFinite() && lat in -90.0..90.0 && lon in -180.0..180.0 &&
                radius.isFinite() && radius in 100f..2000f)
            val now = System.currentTimeMillis()
            MultiAlarmRuntime.Entry(
                id, stored.getString("name", null) ?: "Destination", stored.getString("address", null) ?: "",
                lat, lon, radius, stored.getBoolean("vibration", true), stored.getString("sound", null) ?: "Default alarm",
                stored.getLong("startedAt", now).coerceAtLeast(1L), stored.getLong("alertAt", 0L).coerceAtLeast(0L),
                status, stored.getBoolean("timeFired", false), stored.getBoolean("distanceFired", false),
                stored.getString("triggerReason", null) ?: "distance",
                // Older versions did not persist the snooze deadline. Give it a
                // bounded one-minute replacement instead of leaving it silent.
                snoozedUntil = if (status == "snoozed") now + 60_000L else 0L,
                triggeredAt = if (status == "triggered") now else 0L,
            )
        } catch (_: Exception) { null } // Keep unreadable original data untouched.
    }

    fun retire(context: Context) {
        if (!prefs(context).edit().putBoolean("migrated_to_multi", true).commit()) return
        val flags = PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
        val manager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        for ((code, action) in listOf(11 to "tracker_alarm.SNOOZE_END", 12 to "tracker_alarm.TIME_TRIGGER")) {
            PendingIntent.getBroadcast(context, code, Intent(context, AlarmActionReceiver::class.java).setAction(action), flags)?.let {
                manager.cancel(it)
                it.cancel()
            }
        }
        val fenceFlags = PendingIntent.FLAG_NO_CREATE or if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0
        PendingIntent.getBroadcast(context, 10, Intent(context, GeofenceReceiver::class.java), fenceFlags)?.let {
            try { LocationServices.getGeofencingClient(context).removeGeofences(it) } catch (_: Exception) { }
            it.cancel()
        }
        context.stopService(Intent(context, DestinationTrackingService::class.java))
        context.stopService(Intent(context, AlarmPlaybackService::class.java))
        AlarmNotifications.notifications(context).apply { cancel(101); cancel(102) }
    }
}

/** Retained class names route old service intents into the one current engine. */
open class LegacyAlarmService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        MultiAlarmRuntime.migrateLegacy(this)
        MultiAlarmRuntime.refresh(this)
        stopSelf()
        return START_NOT_STICKY
    }
}
