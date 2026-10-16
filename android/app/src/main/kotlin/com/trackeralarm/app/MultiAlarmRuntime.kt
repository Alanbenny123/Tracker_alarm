package com.trackeralarm.app

import android.app.AlarmManager
import android.app.Notification
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.location.Location
import android.os.Build
import com.google.android.gms.location.Geofence
import com.google.android.gms.location.GeofencingRequest
import com.google.android.gms.location.LocationServices
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar

/** Native source of truth for independently monitored destination alarms. */
object MultiAlarmRuntime {
    const val TRACKING_ID = 201
    const val ALARM_ID = 202
    private const val MAX_ALARMS = 10
    private const val KEY = "alarms"
    private var scheduledAt = 0L

    data class Entry(
        val id: String,
        val name: String,
        val address: String,
        val latitude: Double,
        val longitude: Double,
        val radius: Float,
        val vibration: Boolean,
        val sound: String,
        val startedAt: Long,
        var alertAt: Long,
        var status: String = "active",
        var timeFired: Boolean = false,
        var distanceFired: Boolean = false,
        var triggerReason: String = "distance",
        var snoozedUntil: Long = 0L,
        var triggeredAt: Long = 0L,
        var repeatDays: Int = 0,
        val leadMinutes: Int = 0,
        val targetMinute: Int = 0,
        var cycleDay: Long = 0L,
        var cycleDate: Int = 0,
        val hasTime: Boolean = alertAt > 0L,
    ) {
        fun live() = status == "active" || status == "triggered" || status == "snoozed"
        fun distanceReady(now: Long): Boolean {
            if (repeatDays == 0) return true
            if (now < cycleDay) return false
            val end = Calendar.getInstance().apply {
                timeInMillis = cycleDay
                add(Calendar.DAY_OF_MONTH, 1)
            }.timeInMillis
            return now < end
        }
        fun map(): Map<String, Any> = mutableMapOf<String, Any>(
            "id" to id, "name" to name, "address" to address,
            "latitude" to latitude, "longitude" to longitude, "radius" to radius.toDouble(),
            "vibration" to vibration, "sound" to sound, "startedAt" to startedAt,
            "status" to status, "timeFired" to timeFired, "distanceFired" to distanceFired,
            "triggerReason" to triggerReason, "triggeredAt" to triggeredAt,
            "repeatDays" to repeatDays, "leadMinutes" to leadMinutes,
            "distanceReady" to distanceReady(System.currentTimeMillis()),
        ).also { if (alertAt > 0L) it["alertAt"] = alertAt }
            .also { if (repeatDays != 0) it["repeatStartDay"] = cycleDay }

        fun json() = JSONObject().apply {
            put("id", id); put("name", name); put("address", address)
            put("latitude", latitude); put("longitude", longitude); put("radius", radius.toDouble())
            put("vibration", vibration); put("sound", sound); put("startedAt", startedAt)
            put("alertAt", alertAt); put("status", status); put("timeFired", timeFired)
            put("distanceFired", distanceFired); put("triggerReason", triggerReason)
            put("snoozedUntil", snoozedUntil); put("triggeredAt", triggeredAt)
            put("repeatDays", repeatDays); put("leadMinutes", leadMinutes)
            put("targetMinute", targetMinute); put("cycleDay", cycleDay)
            put("cycleDate", cycleDate)
            put("hasTime", hasTime)
        }

        companion object {
            fun from(json: JSONObject) = Entry(
                id = json.getString("id"), name = json.optString("name", "Destination"),
                address = json.optString("address", ""), latitude = json.getDouble("latitude"),
                longitude = json.getDouble("longitude"), radius = json.getDouble("radius").toFloat(),
                vibration = json.optBoolean("vibration", true), sound = json.optString("sound", "Default alarm"),
                startedAt = json.optLong("startedAt", System.currentTimeMillis()),
                alertAt = json.optLong("alertAt", 0L), status = json.optString("status", "active"),
                timeFired = json.optBoolean("timeFired", false),
                distanceFired = json.optBoolean("distanceFired", false),
                triggerReason = json.optString("triggerReason", "distance"),
                snoozedUntil = json.optLong("snoozedUntil", 0L),
                triggeredAt = json.optLong("triggeredAt", 0L),
                repeatDays = json.optInt("repeatDays", 0).takeIf { it in 1..127 } ?: 0,
                leadMinutes = json.optInt("leadMinutes", 0),
                targetMinute = json.optInt("targetMinute", 0),
                cycleDay = json.optLong("cycleDay", 0L),
                cycleDate = json.optInt("cycleDate", 0),
                hasTime = json.optBoolean("hasTime", json.optLong("alertAt", 0L) > 0L),
            )
        }
    }

    private fun prefs(context: Context) = context.getSharedPreferences("destination_multi_monitor", Context.MODE_PRIVATE)
    private fun read(context: Context): MutableList<Entry> {
        val raw = prefs(context).getString(KEY, "[]") ?: "[]"
        return try {
            val array = JSONArray(raw)
            MutableList(array.length()) { Entry.from(array.getJSONObject(it)) }
        } catch (_: Exception) { mutableListOf() }
    }
    private fun write(context: Context, entries: List<Entry>): Boolean {
        val array = JSONArray()
        entries.forEach { array.put(it.json()) }
        return prefs(context).edit().putString(KEY, array.toString()).commit()
    }

    @Synchronized fun states(context: Context): List<Map<String, Any>> {
        migrateLegacy(context)
        checkDue(context)
        return read(context).map { it.map() }
    }
    @Synchronized fun live(context: Context): List<Entry> = read(context).filter { it.live() }
    @Synchronized fun ringing(context: Context): Entry? = read(context)
        .filter { it.status == "triggered" }
        .minWithOrNull(compareBy<Entry> { it.triggeredAt }.thenBy { it.startedAt })

    private fun nextTriggerTime(entries: List<Entry>): Long = maxOf(
        System.currentTimeMillis(), (entries.maxOfOrNull { it.triggeredAt } ?: 0L) + 1L)

    private fun dayStart(instant: Long): Long = Calendar.getInstance().apply {
        timeInMillis = instant
        set(Calendar.HOUR_OF_DAY, 0)
        set(Calendar.MINUTE, 0)
        set(Calendar.SECOND, 0)
        set(Calendar.MILLISECOND, 0)
    }.timeInMillis

    private fun dateNumber(day: Calendar): Int =
        day.get(Calendar.YEAR) * 10_000 + (day.get(Calendar.MONTH) + 1) * 100 +
            day.get(Calendar.DAY_OF_MONTH)

    private fun cycleCalendar(entry: Entry): Calendar {
        val date = entry.cycleDate
        if (date == 0) return Calendar.getInstance().apply {
            timeInMillis = dayStart(entry.cycleDay)
        }
        return Calendar.getInstance().apply {
            clear()
            set(date / 10_000, (date / 100) % 100 - 1, date % 100)
        }
    }

    private fun nextCycle(entry: Entry): Pair<Long, Long> {
        val day = cycleCalendar(entry)
        do {
            day.add(Calendar.DAY_OF_MONTH, 1)
            val weekday = (day.get(Calendar.DAY_OF_WEEK) + 5) % 7 // Monday = 0.
            if ((entry.repeatDays and (1 shl weekday)) != 0) break
        } while (true)
        val midnight = day.timeInMillis
        day.set(Calendar.HOUR_OF_DAY, entry.targetMinute / 60)
        day.set(Calendar.MINUTE, entry.targetMinute % 60)
        day.set(Calendar.SECOND, 0)
        day.set(Calendar.MILLISECOND, 0)
        return midnight to if (entry.hasTime)
            day.timeInMillis - entry.leadMinutes * 60_000L else 0L
    }

    private fun nextCycleStart(entry: Entry): Long {
        val (day, alert) = nextCycle(entry)
        return if (alert > 0L) minOf(day, alert) else day
    }

    private fun advanceCycle(entry: Entry, now: Long, force: Boolean = false): Boolean {
        if (entry.repeatDays == 0 || entry.status != "active") return false
        var changed = false
        var shouldAdvance = force
        // An old alarm can be restored after days or weeks without the app running.
        while (shouldAdvance || now >= nextCycleStart(entry)) {
            val (day, alert) = nextCycle(entry)
            entry.cycleDay = day
            entry.cycleDate = dateNumber(Calendar.getInstance().apply { timeInMillis = day })
            entry.alertAt = alert
            entry.timeFired = false
            entry.distanceFired = false
            entry.triggerReason = "distance"
            entry.triggeredAt = 0L
            changed = true
            shouldAdvance = false
        }
        return changed
    }

    @Synchronized fun realignClock(context: Context) {
        val entries = read(context)
        var changed = false
        for (entry in entries) {
            if (!entry.live() || entry.repeatDays == 0) continue
            val day = cycleCalendar(entry)
            entry.cycleDate = dateNumber(day)
            entry.cycleDay = day.timeInMillis
            day.set(Calendar.HOUR_OF_DAY, entry.targetMinute / 60)
            day.set(Calendar.MINUTE, entry.targetMinute % 60)
            entry.alertAt = if (entry.hasTime)
                day.timeInMillis - entry.leadMinutes * 60_000L else 0L
            changed = true
        }
        if (changed) write(context, entries)
    }

    private fun migrateLegacy(context: Context) {
        val legacy = AlarmRuntime.state(context) ?: return
        val status = AlarmRuntime.prefs(context).getString("status", "inactive")
        if (status != "active" && status != "triggered" && status != "snoozed") return
        val id = legacy["id"] as String
        val entries = read(context)
        if (entries.none { it.id == id }) {
            entries.add(Entry(
                id, legacy["name"] as String, legacy["address"] as String,
                legacy["latitude"] as Double, legacy["longitude"] as Double,
                (legacy["radius"] as Double).toFloat(), legacy["vibration"] as Boolean,
                legacy["sound"] as String, legacy["startedAt"] as Long,
                legacy["alertAt"] as? Long ?: 0L, status ?: "active",
                legacy["timeFired"] as Boolean, legacy["distanceFired"] as Boolean,
                legacy["triggerReason"] as String,
            ))
            if (!write(context, entries)) return
        }
        AlarmRuntime.finish(context, "cancelled")
        refresh(context)
        ensureGeofences(context)
    }

    @Synchronized fun register(context: Context, args: Map<String, Any>, result: MethodChannel.Result) {
        migrateLegacy(context)
        val id = args["id"] as? String
        val name = args["name"] as? String
        val lat = (args["latitude"] as? Number)?.toDouble()
        val lon = (args["longitude"] as? Number)?.toDouble()
        val radius = (args["radius"] as? Number)?.toFloat()
        val repeatDays = (args["repeatDays"] as? Number)?.toInt() ?: 0
        val leadMinutes = (args["leadMinutes"] as? Number)?.toInt() ?: 0
        val alertAt = (args["alertAt"] as? Number)?.toLong() ?: 0L
        val repeatStartAt = (args["repeatStartDay"] as? Number)?.toLong() ?: 0L
        val targetAt = if (alertAt > 0L) alertAt + leadMinutes * 60_000L else repeatStartAt
        val targetCalendar = Calendar.getInstance().apply { timeInMillis = targetAt }
        val targetWeekday = (targetCalendar.get(Calendar.DAY_OF_WEEK) + 5) % 7
        if (id.isNullOrBlank() || name.isNullOrBlank() || lat == null || lon == null ||
            !lat.isFinite() || !lon.isFinite() || lat !in -90.0..90.0 || lon !in -180.0..180.0 ||
            radius == null || !radius.isFinite() || radius !in 100f..2000f ||
            repeatDays !in 0..127 || leadMinutes !in listOf(0, 5, 15, 30, 60) ||
            (repeatDays != 0 && (targetAt <= 0L ||
                dayStart(targetAt) < dayStart(System.currentTimeMillis()) ||
                (alertAt > 0L && alertAt <= System.currentTimeMillis()) ||
                (repeatDays and (1 shl targetWeekday)) == 0 ||
                (repeatStartAt > 0L && dayStart(repeatStartAt) != dayStart(targetAt))))) {
            result.error("arguments", "Invalid destination, radius, or repeat schedule", null); return
        }
        val entries = read(context)
        if (entries.count { it.live() } >= MAX_ALARMS) {
            result.error("limit", "Up to $MAX_ALARMS active alarms are supported", null); return
        }
        if (entries.any { it.id == id }) {
            result.error("duplicate", "Alarm already exists", null); return
        }
        val entry = Entry(id, name, args["address"] as? String ?: "", lat, lon, radius,
            args["vibration"] as? Boolean ?: true, args["sound"] as? String ?: "Default alarm",
            (args["startedAt"] as? Number)?.toLong() ?: System.currentTimeMillis(),
            alertAt, repeatDays = repeatDays, leadMinutes = leadMinutes,
            targetMinute = targetCalendar.get(Calendar.HOUR_OF_DAY) * 60 + targetCalendar.get(Calendar.MINUTE),
            cycleDay = if (repeatDays == 0) 0L else dayStart(targetAt),
            cycleDate = if (repeatDays == 0) 0 else dateNumber(targetCalendar),
            hasTime = alertAt > 0L)
        entries.add(entry)
        if (!write(context, entries)) { result.error("storage", "Could not save alarm", null); return }
        try { refresh(context, strict = true) } catch (e: Exception) {
            entries.remove(entry); write(context, entries)
            scheduleNext(context, entries)
            result.error("tracking", "Could not start background GPS: ${e.message}", null); return
        }
        result.success(null)
        if (entry.distanceReady(System.currentTimeMillis())) addGeofence(context, entry)
    }

    @Synchronized fun finish(context: Context, id: String, status: String) {
        val entries = read(context)
        val entry = entries.firstOrNull { it.id == id && it.live() } ?: return
        entry.status = status
        entry.snoozedUntil = 0L
        if (write(context, entries)) {
            removeGeofence(context, id)
            refresh(context)
        }
    }

    @Synchronized fun forget(context: Context, id: String) {
        val entries = read(context)
        if (entries.removeAll { it.id == id && !it.live() }) write(context, entries)
    }

    @Synchronized fun updateRepeat(context: Context, id: String, days: Int, result: MethodChannel.Result) {
        if (days !in 0..127) {
            result.error("arguments", "Choose valid repeat days", null); return
        }
        val entries = read(context)
        val entry = entries.firstOrNull { it.id == id && it.status == "active" } ?: run {
            result.error("state", "Alarm must be active to edit repeat days", null); return
        }
        if (days == entry.repeatDays) { result.success(null); return }
        if (days == 0) {
            entry.repeatDays = 0
            entry.cycleDay = 0L
            entry.cycleDate = 0
        } else {
            val now = System.currentTimeMillis()
            val day = Calendar.getInstance().apply { timeInMillis = dayStart(now) }
            var nextAlert = 0L
            while (true) {
                val weekday = (day.get(Calendar.DAY_OF_WEEK) + 5) % 7
                if ((days and (1 shl weekday)) != 0) {
                    val candidate = Calendar.getInstance().apply {
                        timeInMillis = day.timeInMillis
                        set(Calendar.HOUR_OF_DAY, entry.targetMinute / 60)
                        set(Calendar.MINUTE, entry.targetMinute % 60)
                    }.timeInMillis - entry.leadMinutes * 60_000L
                    if (!entry.hasTime || candidate > now) {
                        nextAlert = if (entry.hasTime) candidate else 0L
                        break
                    }
                }
                day.add(Calendar.DAY_OF_MONTH, 1)
            }
            entry.repeatDays = days
            entry.cycleDay = day.timeInMillis
            entry.cycleDate = dateNumber(day)
            entry.alertAt = nextAlert
            entry.timeFired = false
            entry.distanceFired = false
        }
        if (!write(context, entries)) {
            result.error("storage", "Could not save repeat days", null); return
        }
        removeGeofence(context, id)
        refresh(context)
        if (entry.distanceReady(System.currentTimeMillis()) && !entry.distanceFired) addGeofence(context, entry)
        result.success(null)
    }

    @Synchronized fun trigger(context: Context, id: String, reason: String) {
        if (reason == "distance") checkDue(context)
        val entries = read(context)
        val entry = entries.firstOrNull { it.id == id && it.live() } ?: return
        if (reason == "time") {
            if (entry.alertAt <= 0L || entry.timeFired) return
            entry.timeFired = true
        } else if (reason == "distance") {
            if (entry.distanceFired || !entry.distanceReady(System.currentTimeMillis())) return
            entry.distanceFired = true
        } else return
        val alreadyRinging = entry.status == "triggered"
        entry.triggerReason = if (alreadyRinging && entry.timeFired && entry.distanceFired) "both" else reason
        if (!alreadyRinging) entry.triggeredAt = nextTriggerTime(entries)
        entry.status = "triggered"
        entry.snoozedUntil = 0L
        if (write(context, entries)) {
            if (reason == "distance") removeGeofence(context, id)
            refresh(context)
        }
    }

    @Synchronized fun dismiss(context: Context, id: String) {
        val entries = read(context)
        val entry = entries.firstOrNull { it.id == id && it.status == "triggered" } ?: return
        val finished = entry.distanceFired && (entry.alertAt <= 0L || entry.timeFired)
        entry.status = if (finished && entry.repeatDays == 0) "completed" else "active"
        entry.triggeredAt = 0L
        advanceCycle(entry, System.currentTimeMillis(), force = finished)
        if (write(context, entries)) {
            refresh(context)
            if (entry.repeatDays != 0 && !entry.distanceFired &&
                entry.distanceReady(System.currentTimeMillis())) addGeofence(context, entry)
        }
    }

    @Synchronized fun snooze(context: Context, id: String, minutes: Int) {
        if (minutes !in listOf(1, 2, 5)) return
        val entries = read(context)
        val entry = entries.firstOrNull { it.id == id && it.status == "triggered" } ?: return
        entry.status = "snoozed"
        entry.snoozedUntil = System.currentTimeMillis() + minutes * 60_000L
        entry.triggeredAt = 0L
        if (write(context, entries)) refresh(context)
    }

    @Synchronized fun checkDue(context: Context) {
        val entries = read(context)
        val now = System.currentTimeMillis()
        var changed = false
        val advanced = mutableListOf<Entry>()
        entries.filter { it.live() }.forEach { entry ->
            if (advanceCycle(entry, now)) {
                changed = true
                advanced.add(entry)
            }
        }
        val due = entries.filter { entry -> entry.live() &&
            ((entry.alertAt > 0L && !entry.timeFired && entry.alertAt <= now) ||
             (entry.status == "snoozed" && entry.snoozedUntil > 0L && entry.snoozedUntil <= now))
        }.sortedBy { entry ->
            if (entry.alertAt > 0L && !entry.timeFired && entry.alertAt <= now) entry.alertAt
            else entry.snoozedUntil
        }
        var triggerTime = nextTriggerTime(entries)
        for (entry in due) {
            val alreadyRinging = entry.status == "triggered"
            if (entry.alertAt > 0L && !entry.timeFired && entry.alertAt <= now) {
                entry.timeFired = true
                entry.triggerReason = if (alreadyRinging && entry.distanceFired) "both" else "time"
                entry.status = "triggered"
                entry.snoozedUntil = 0L
                changed = true
            } else if (entry.status == "snoozed" && entry.snoozedUntil > 0L && entry.snoozedUntil <= now) {
                entry.status = "triggered"
                entry.snoozedUntil = 0L
                changed = true
            }
            if (!alreadyRinging && entry.status == "triggered") entry.triggeredAt = triggerTime++
        }
        if (changed && write(context, entries)) {
            refresh(context)
            advanced.filter { it.distanceReady(now) }.forEach { addGeofence(context, it) }
        } else scheduleNext(context, entries)
    }

    @Synchronized fun checkLocation(context: Context, location: Location): Long {
        checkDue(context)
        if (System.currentTimeMillis() - location.time > 30_000L) return 30_000L
        val entries = live(context)
        if (entries.none { !it.distanceFired && it.distanceReady(System.currentTimeMillis()) }) {
            return 30 * 60_000L
        }
        var closest = Float.MAX_VALUE
        val reached = mutableListOf<Pair<Entry, Float>>()
        for (entry in entries) {
            if (entry.distanceFired || !entry.distanceReady(System.currentTimeMillis())) continue
            val distances = FloatArray(1)
            Location.distanceBetween(location.latitude, location.longitude, entry.latitude, entry.longitude, distances)
            val remaining = distances[0] - entry.radius
            if (remaining <= 0f) {
                if (location.hasAccuracy() && location.accuracy > maxOf(100f, entry.radius)) {
                    closest = 0f // Seek a more accurate fix before ringing.
                } else reached.add(entry to distances[0])
            }
            else if (remaining < closest) closest = remaining
        }
        reached.sortedBy { it.second }.forEach { (entry, _) -> trigger(context, entry.id, "distance") }
        return when {
            closest <= 1_000f -> 5_000L
            closest <= 5_000f -> 10_000L
            else -> 30_000L
        }
    }

    private fun timeIntent(context: Context) = PendingIntent.getBroadcast(
        context, 41, Intent(context, MultiAlarmReceiver::class.java).setAction("tracker_alarm.MULTI_TIME"),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

    private fun geofenceIntent(context: Context): PendingIntent {
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0
        return PendingIntent.getBroadcast(context, 47,
            Intent(context, MultiGeofenceReceiver::class.java), flags)
    }

    private fun addGeofence(context: Context, entry: Entry) {
        if (!entry.live() || entry.distanceFired || !entry.distanceReady(System.currentTimeMillis())) return
        try {
            val fence = Geofence.Builder()
                .setRequestId(entry.id)
                .setCircularRegion(entry.latitude, entry.longitude, entry.radius)
                .setTransitionTypes(Geofence.GEOFENCE_TRANSITION_ENTER)
                .setExpirationDuration(Geofence.NEVER_EXPIRE).build()
            val request = GeofencingRequest.Builder()
                .setInitialTrigger(GeofencingRequest.INITIAL_TRIGGER_ENTER)
                .addGeofence(fence).build()
            val client = LocationServices.getGeofencingClient(context)
            client.addGeofences(request, geofenceIntent(context))
                .addOnSuccessListener {
                    if (live(context).none { it.id == entry.id && !it.distanceFired &&
                            it.distanceReady(System.currentTimeMillis()) }) {
                        removeGeofence(context, entry.id)
                    }
                }
        } catch (_: Exception) {
            // Foreground GPS monitoring is still active without this backup.
        }
    }

    private fun removeGeofence(context: Context, id: String) {
        try { LocationServices.getGeofencingClient(context).removeGeofences(listOf(id)) }
        catch (_: Exception) { }
    }

    fun ensureGeofences(context: Context) {
        live(context).filter { !it.distanceFired && it.distanceReady(System.currentTimeMillis()) }
            .forEach { addGeofence(context, it) }
    }

    @Synchronized private fun scheduleNext(context: Context, entries: List<Entry>) {
        val next = entries.filter { it.live() }.flatMap { entry ->
            listOf(if (!entry.timeFired) entry.alertAt else 0L,
                if (entry.status == "snoozed") entry.snoozedUntil else 0L,
                if (entry.repeatDays != 0 && entry.status == "active") nextCycleStart(entry) else 0L,
                if (entry.repeatDays != 0 && entry.status == "active" &&
                    entry.cycleDay > System.currentTimeMillis()) entry.cycleDay else 0L)
        }.filter { it > 0L }.minOrNull() ?: 0L
        if (next == scheduledAt) return
        val manager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = timeIntent(context)
        manager.cancel(intent)
        if (next > 0L) manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next, intent)
        scheduledAt = next
    }

    fun refresh(context: Context, strict: Boolean = false) {
        scheduleNext(context, read(context))
        val service = Intent(context, MultiTrackingService::class.java)
        if (live(context).isEmpty()) {
            context.stopService(service)
            AlarmRuntime.notifications(context).cancel(TRACKING_ID)
            AlarmRuntime.notifications(context).cancel(ALARM_ID)
        } else {
            // Dispatch to the existing foreground service immediately. A geofence
            // or notification action must not wait for the next GPS fix or UI resume.
            if (MultiTrackingService.refreshIfRunning()) return
            try {
                if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(service)
                else context.startService(service)
            } catch (e: Exception) {
                if (strict) throw e
                val ringing = ringing(context)
                if (ringing != null) {
                    AlarmRuntime.notifications(context).notify(ALARM_ID, alarmNotification(context, ringing))
                } else {
                    AlarmRuntime.notifications(context).notify(TRACKING_ID, trackingNotification(context, live(context).size))
                }
            }
        }
    }

    private fun action(context: Context, id: String, verb: String, code: Int): PendingIntent =
        PendingIntent.getBroadcast(context, code,
            Intent(context, MultiAlarmReceiver::class.java).setAction("tracker_alarm.MULTI_$verb").putExtra("id", id),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

    fun alarmNotification(context: Context, entry: Entry): Notification {
        AlarmRuntime.notifications(context)
        val waiting = live(context).count { it.status == "triggered" && it.id != entry.id }
        val open = PendingIntent.getActivity(context, 42,
            Intent(context, MainActivity::class.java).setAction("tracker_alarm.ALARM")
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        return builder(context, AlarmRuntime.CHANNEL_ALARM)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle(when (entry.triggerReason) { "time" -> "Time alarm"; "both" -> "Time and distance alarm"; else -> "Destination nearby" })
            .setContentText(if (waiting == 0) entry.name else "${entry.name} · $waiting more alert${if (waiting == 1) "" else "s"} waiting")
            .setCategory(Notification.CATEGORY_ALARM)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setPriority(Notification.PRIORITY_MAX)
            .setContentIntent(open).setFullScreenIntent(open, true)
            .addAction(Notification.Action.Builder(android.R.drawable.ic_media_pause, "Snooze 1 min", action(context, entry.id, "SNOOZE", 43)).build())
            .addAction(Notification.Action.Builder(android.R.drawable.ic_delete, "Stop alert", action(context, entry.id, "DISMISS", 44)).build())
            .addAction(Notification.Action.Builder(android.R.drawable.ic_menu_close_clear_cancel, "End trip", action(context, entry.id, "END", 45)).build())
            .setOngoing(true).build()
    }

    fun trackingNotification(context: Context, count: Int): Notification {
        AlarmRuntime.notifications(context)
        val open = PendingIntent.getActivity(context, 46, Intent(context, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        return builder(context, AlarmRuntime.CHANNEL_TRACKING)
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setContentTitle("Destination alarms active")
            .setContentText("Monitoring $count destination${if (count == 1) "" else "s"}")
            .setContentIntent(open).setOngoing(true).build()
    }

    @Suppress("DEPRECATION")
    private fun builder(context: Context, channel: String): Notification.Builder =
        if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, channel)
        else Notification.Builder(context)
}
