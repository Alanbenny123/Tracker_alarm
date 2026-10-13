package com.trackeralarm.app

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.location.Location
import android.location.LocationManager
import android.os.Build
import android.os.SystemClock
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingRequest
import com.google.android.gms.location.LocationServices
import io.flutter.plugin.common.MethodChannel

object AlarmRuntime {
    const val TRACKING_ID = 101
    const val ALARM_ID = 102
    const val CHANNEL_TRACKING = "destination_tracking"
    const val CHANNEL_ALARM = "destination_alarm"

    fun prefs(context: Context): SharedPreferences = context.getSharedPreferences("destination_monitor", Context.MODE_PRIVATE)

    private fun coordinate(stored: SharedPreferences, key: String, oldKey: String): Double =
        stored.getString(key, null)?.toDoubleOrNull() ?: stored.getFloat(oldKey, 0f).toDouble()

    fun state(context: Context): Map<String, Any>? {
        val stored = prefs(context)
        val id = stored.getString("id", null) ?: return null
        val state = mutableMapOf<String, Any>(
            "id" to id,
            "name" to (stored.getString("name", null) ?: "Destination"),
            "address" to (stored.getString("address", null) ?: ""),
            "latitude" to coordinate(stored, "latitude", "lat"),
            "longitude" to coordinate(stored, "longitude", "lng"),
            "radius" to stored.getFloat("radius", 500f).toDouble(),
            "vibration" to stored.getBoolean("vibration", true),
            "sound" to (stored.getString("sound", null) ?: "Default alarm"),
            "startedAt" to stored.getLong("startedAt", System.currentTimeMillis()),
        )
        val alertAt = stored.getLong("alertAt", 0L)
        if (alertAt > 0L) state["alertAt"] = alertAt
        return state
    }

    private fun geofenceIntent(context: Context): PendingIntent {
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0
        return PendingIntent.getBroadcast(context, 10, Intent(context, GeofenceReceiver::class.java), flags)
    }

    private fun snoozeIntent(context: Context): PendingIntent = PendingIntent.getBroadcast(
        context, 11, Intent(context, AlarmActionReceiver::class.java).setAction("tracker_alarm.SNOOZE_END"),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    private fun timeIntent(context: Context): PendingIntent = PendingIntent.getBroadcast(
        context, 12, Intent(context, AlarmActionReceiver::class.java).setAction("tracker_alarm.TIME_TRIGGER"),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    private fun scheduleTime(context: Context) {
        val whenMillis = prefs(context).getLong("alertAt", 0L)
        if (whenMillis <= System.currentTimeMillis()) return
        val manager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, whenMillis, timeIntent(context))
    }

    private fun cancelTime(context: Context) {
        val manager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        manager.cancel(timeIntent(context))
    }

    fun register(context: Context, args: Map<String, Any>, result: MethodChannel.Result) {
        val id = args["id"] as? String
        val name = args["name"] as? String
        val lat = (args["latitude"] as? Number)?.toDouble()
        val lng = (args["longitude"] as? Number)?.toDouble()
        val radius = (args["radius"] as? Number)?.toFloat()
        if (id.isNullOrBlank() || name.isNullOrBlank() || lat == null || lng == null ||
            !lat.isFinite() || !lng.isFinite() || lat !in -90.0..90.0 || lng !in -180.0..180.0 ||
            radius == null || !radius.isFinite() || radius < 100f || radius > 2000f) {
            result.error("arguments", "Invalid geofence destination or radius", null); return
        }
        val geofence = Geofence.Builder()
            .setRequestId(id)
            .setCircularRegion(lat, lng, radius)
            .setTransitionTypes(Geofence.GEOFENCE_TRANSITION_ENTER)
            .setExpirationDuration(Geofence.NEVER_EXPIRE)
            .build()
        val request = GeofencingRequest.Builder()
            .setInitialTrigger(GeofencingRequest.INITIAL_TRIGGER_ENTER)
            .addGeofence(geofence).build()
        val saved = prefs(context).edit()
            .putString("id", id).putString("name", name)
            .putString("address", args["address"] as? String ?: "")
            .putString("latitude", lat.toString()).putString("longitude", lng.toString())
            .putFloat("radius", radius)
            .putBoolean("vibration", args["vibration"] as? Boolean ?: true)
            .putString("sound", args["sound"] as? String ?: "Default alarm")
            .putLong("startedAt", (args["startedAt"] as? Number)?.toLong() ?: System.currentTimeMillis())
            .putLong("alertAt", (args["alertAt"] as? Number)?.toLong() ?: 0L)
            .putString("status", "active").commit()
        if (!saved) {
            result.error("storage", "Could not save the destination alarm", null)
            return
        }
        try {
            startTracking(context)
        } catch (e: Exception) {
            prefs(context).edit().putString("status", "inactive").commit()
            result.error("tracking", "Could not start background GPS monitoring: ${e.message}", null)
            return
        }
        try {
            cancelTime(context)
            scheduleTime(context)
        } catch (_: Exception) {
            // The GPS monitor also checks the selected time.
        }
        result.success(null)

        // Google Play geofencing is only a backup. Starting GPS monitoring does
        // not wait for it, so the alarm can be armed without internet.
        try {
            val client = LocationServices.getGeofencingClient(context)
            client.removeGeofences(geofenceIntent(context)).addOnCompleteListener {
                if (prefs(context).getString("id", null) != id ||
                    prefs(context).getString("status", "inactive") != "active") return@addOnCompleteListener
                try {
                    client.addGeofences(request, geofenceIntent(context))
                        .addOnFailureListener {
                            if (prefs(context).getString("id", null) == id &&
                                prefs(context).getString("status", "inactive") == "active")
                                showTracking(context, "GPS monitoring active; geofence backup unavailable.")
                        }
                } catch (_: Exception) {
                    showTracking(context, "GPS monitoring active; geofence backup unavailable.")
                }
            }
        } catch (_: Exception) {
            showTracking(context, "GPS monitoring active; geofence backup unavailable.")
        }
    }

    fun ensure(context: Context, result: MethodChannel.Result) {
        val stored = prefs(context)
        val id = stored.getString("id", null)
        if (id == null) { result.error("restore", "No saved native geofence", null); return }
        val geofence = Geofence.Builder()
            .setRequestId(id)
            .setCircularRegion(coordinate(stored, "latitude", "lat"), coordinate(stored, "longitude", "lng"), stored.getFloat("radius", 500f))
            .setTransitionTypes(Geofence.GEOFENCE_TRANSITION_ENTER)
            .setExpirationDuration(Geofence.NEVER_EXPIRE).build()
        val request = GeofencingRequest.Builder().setInitialTrigger(GeofencingRequest.INITIAL_TRIGGER_ENTER).addGeofence(geofence).build()
        try {
            if (stored.getString("status", "inactive") == "active" ||
                stored.getString("status", "inactive") == "snoozed") startTracking(context)
        } catch (e: Exception) {
            result.error("tracking", "Could not resume background GPS monitoring: ${e.message}", null)
            return
        }
        try { scheduleTime(context) } catch (_: Exception) { }
        result.success(null)
        try {
            LocationServices.getGeofencingClient(context).addGeofences(request, geofenceIntent(context))
                .addOnFailureListener {
                    if (stored.getString("status", "inactive") == "active" ||
                        stored.getString("status", "inactive") == "snoozed")
                        showTracking(context, "GPS monitoring active; geofence backup unavailable.")
                }
        } catch (_: Exception) {
            if (stored.getString("status", "inactive") == "active" ||
                stored.getString("status", "inactive") == "snoozed")
                showTracking(context, "GPS monitoring active; geofence backup unavailable.")
        }
    }

    fun resumeTriggered(context: Context) {
        if (prefs(context).getString("status", "inactive") != "triggered") return
        if (DestinationTrackingService.ringIfRunning()) return
        val service = Intent(context, AlarmPlaybackService::class.java)
        try {
            if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(service) else context.startService(service)
        } catch (_: Exception) { notifications(context).notify(ALARM_ID, alarmNotification(context)) }
    }

    fun finish(context: Context, status: String, result: MethodChannel.Result? = null, done: (() -> Unit)? = null) {
        if (!prefs(context).edit().putString("status", status).commit()) {
            result?.error("storage", "Could not save the stopped alarm state", null)
            done?.invoke()
            return
        }
        cancelSnooze(context)
        cancelTime(context)
        context.stopService(Intent(context, AlarmPlaybackService::class.java))
        context.stopService(Intent(context, DestinationTrackingService::class.java))
        notifications(context).cancel(TRACKING_ID)
        notifications(context).cancel(ALARM_ID)
        try {
            LocationServices.getGeofencingClient(context).removeGeofences(geofenceIntent(context))
                .addOnCompleteListener {
                    // A stale geofence is harmless: trigger() ignores stopped alarms.
                    result?.success(null)
                    done?.invoke()
                }
        } catch (_: Exception) {
            result?.success(null)
            done?.invoke()
        }
    }

    fun trigger(context: Context, reason: String = "distance") {
        val stored = prefs(context)
        if (stored.getString("status", "inactive") != "active") return
        cancelTime(context)
        stored.edit().putString("status", "triggered").putString("triggerReason", reason).commit()
        if (DestinationTrackingService.ringIfRunning()) return
        val service = Intent(context, AlarmPlaybackService::class.java)
        try {
            if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(service) else context.startService(service)
        } catch (_: Exception) {
            // A high-priority notification still surfaces the alert if an OEM blocks the service.
            notifications(context).notify(ALARM_ID, alarmNotification(context))
        }
    }

    fun snooze(context: Context, minutes: Int) {
        if (minutes !in listOf(1, 2, 5)) return
        context.stopService(Intent(context, AlarmPlaybackService::class.java))
        prefs(context).edit().putString("status", "snoozed").commit()
        notifications(context).cancel(ALARM_ID)
        val monitoringStarted = if (DestinationTrackingService.snoozeIfRunning()) true else try {
            startTracking(context)
            true
        } catch (_: Exception) { false }
        showTracking(context, if (monitoringStarted) {
            "Alarm snoozed for $minutes minute${if (minutes == 1) "" else "s"}"
        } else "GPS monitoring paused. Open the app to resume.")
        val manager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        manager.setAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP, SystemClock.elapsedRealtime() + minutes * 60_000L, snoozeIntent(context))
    }

    fun snoozeExpired(context: Context, done: () -> Unit) {
        if (prefs(context).getString("status", "inactive") != "snoozed") { done(); return }
        val location = DestinationTrackingService.latestLocation()
            ?.takeIf { System.currentTimeMillis() - it.time <= 60_000L } ?: try {
            (context.getSystemService(Context.LOCATION_SERVICE) as LocationManager)
                .getLastKnownLocation(LocationManager.GPS_PROVIDER)
        } catch (_: Exception) { null }
        prefs(context).edit().putString("status", "active").commit()
        if (location != null && System.currentTimeMillis() - location.time <= 60_000L && inside(context, location)) {
            trigger(context)
        } else {
            // The running GPS monitor will check again on its next fix.
            showTracking(context, "Monitoring ${prefs(context).getString("name", "destination")}")
        }
        done()
    }

    private fun inside(context: Context, location: Location): Boolean {
        val stored = prefs(context)
        val distance = FloatArray(1)
        Location.distanceBetween(location.latitude, location.longitude,
            coordinate(stored, "latitude", "lat"), coordinate(stored, "longitude", "lng"), distance)
        return distance[0] <= stored.getFloat("radius", 500f) + location.accuracy
    }

    fun distanceToDestination(context: Context, location: Location): Float {
        val stored = prefs(context)
        val distance = FloatArray(1)
        Location.distanceBetween(location.latitude, location.longitude,
            coordinate(stored, "latitude", "lat"), coordinate(stored, "longitude", "lng"), distance)
        return distance[0]
    }

    private fun startTracking(context: Context) {
        val service = Intent(context, DestinationTrackingService::class.java)
        if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(service) else context.startService(service)
    }

    private fun cancelSnooze(context: Context) {
        val manager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        manager.cancel(snoozeIntent(context))
    }

    fun notifications(context: Context): NotificationManager {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(NotificationChannel(CHANNEL_TRACKING, "Destination tracking", NotificationManager.IMPORTANCE_LOW))
            val alarm = NotificationChannel(CHANNEL_ALARM, "Destination alarms", NotificationManager.IMPORTANCE_HIGH)
            val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            if (uri != null) alarm.setSound(uri, AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM).build())
            alarm.enableVibration(true)
            manager.createNotificationChannel(alarm)
        }
        return manager
    }

    fun trackingNotification(context: Context, message: String): Notification {
        notifications(context)
        val intent = PendingIntent.getActivity(context, 21, Intent(context, MainActivity::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        return builder(context, CHANNEL_TRACKING)
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setContentTitle("Destination Alarm active")
            .setContentText(message).setContentIntent(intent).setOngoing(true).build()
    }

    fun showTracking(context: Context, message: String) {
        notifications(context).notify(TRACKING_ID, trackingNotification(context, message))
    }

    fun alarmNotification(context: Context): Notification {
        notifications(context)
        val name = prefs(context).getString("name", "your destination")
        val open = Intent(context, MainActivity::class.java).setAction("tracker_alarm.ALARM")
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val fullScreen = PendingIntent.getActivity(context, 22, open, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val stop = PendingIntent.getBroadcast(context, 23, Intent(context, AlarmActionReceiver::class.java).setAction("tracker_alarm.STOP"), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val snooze = PendingIntent.getBroadcast(context, 24, Intent(context, AlarmActionReceiver::class.java).setAction("tracker_alarm.SNOOZE"), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        return builder(context, CHANNEL_ALARM)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle(if (prefs(context).getString("triggerReason", "distance") == "time") "Time alarm" else "Destination nearby")
            .setContentText(if (prefs(context).getString("triggerReason", "distance") == "time") "Time reached for $name" else "You are near $name")
            .setCategory(Notification.CATEGORY_ALARM)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setPriority(Notification.PRIORITY_MAX)
            .setContentIntent(fullScreen)
            .setFullScreenIntent(fullScreen, true)
            .addAction(Notification.Action.Builder(android.R.drawable.ic_media_pause, "Snooze 1 min", snooze).build())
            .addAction(Notification.Action.Builder(android.R.drawable.ic_delete, "Stop", stop).build())
            .setOngoing(true).build()
    }

    @Suppress("DEPRECATION")
    private fun builder(context: Context, channel: String): Notification.Builder =
        if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, channel) else Notification.Builder(context)
}
