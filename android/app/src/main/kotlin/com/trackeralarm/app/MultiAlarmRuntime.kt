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
    private var scheduledExact = false
    private var scheduledAudible = false
    private var previousFix: Location? = null

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
        val label: String = "",
        var paused: Boolean = false,
        var monitoringSince: Long = startedAt,
        var endedAt: Long = 0L,
        val sourceExpiresAt: Long = 0L,
        val locationRedacted: Boolean = false,
    ) {
        fun live() = status == "active" || status == "triggered" || status == "snoozed"
        val displayName: String get() = label.ifBlank { name }
        fun monitoring() = live() && !paused
        fun distanceReady(now: Long): Boolean {
            if (paused) return false
            if (repeatDays == 0) return true
            if (now < cycleDay) return false
            val end = Calendar.getInstance().apply {
                timeInMillis = cycleDay
                add(Calendar.DAY_OF_MONTH, 1)
            }.timeInMillis
            return now < end
        }
        fun map(): Map<String, Any> = mutableMapOf<String, Any>(
            "id" to id, "name" to name, "label" to label, "address" to address,
            "latitude" to latitude, "longitude" to longitude, "radius" to radius.toDouble(),
            "vibration" to vibration, "sound" to sound, "startedAt" to startedAt,
            "status" to (if (paused && live()) "paused" else status), "timeFired" to timeFired, "distanceFired" to distanceFired,
            "triggerReason" to triggerReason, "triggeredAt" to triggeredAt,
            "endedAt" to endedAt,
            "sourceExpiresAt" to sourceExpiresAt,
            "locationRedacted" to locationRedacted,
            "repeatDays" to repeatDays, "leadMinutes" to leadMinutes,
            "distanceReady" to distanceReady(System.currentTimeMillis()),
        ).also { if (alertAt > 0L) it["alertAt"] = alertAt }
            .also {
                if (repeatDays != 0) {
                    it["repeatStartDay"] = cycleDay
                    if (!paused) it["nextRepeatAt"] = if (cycleDay > System.currentTimeMillis()) cycleDay
                        else MultiAlarmRuntime.nextCycle(this).first
                }
            }

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
            put("hasTime", hasTime); put("label", label); put("paused", paused)
            put("monitoringSince", monitoringSince)
            put("endedAt", endedAt)
            put("sourceExpiresAt", sourceExpiresAt)
            put("locationRedacted", locationRedacted)
        }

        companion object {
            fun from(json: JSONObject): Entry {
                val legacy = !json.has("sourceExpiresAt")
                val startedAt = json.optLong("startedAt", System.currentTimeMillis())
                val sourceExpiresAt = if (legacy) startedAt + 30L * 24 * 60 * 60 * 1000
                    else json.optLong("sourceExpiresAt", 0L)
                val entry = Entry(
                id = json.getString("id"), name = json.optString("name", "Destination"),
                address = json.optString("address", ""), latitude = json.getDouble("latitude"),
                longitude = json.getDouble("longitude"), radius = json.getDouble("radius").toFloat(),
                vibration = json.optBoolean("vibration", true), sound = json.optString("sound", "Default alarm"),
                startedAt = startedAt,
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
                label = json.optString("label", ""), paused = json.optBoolean("paused", false),
                monitoringSince = json.optLong("monitoringSince", json.optLong("startedAt", 0L)),
                endedAt = json.optLong("endedAt", 0L),
                sourceExpiresAt = sourceExpiresAt,
                locationRedacted = json.optBoolean("locationRedacted",
                    json.optString("name") == "Google destination · reselect" &&
                        json.optDouble("latitude") == 0.0 && json.optDouble("longitude") == 0.0),
            )
                // Older entries have no source marker. Keep live alarms for at most
                // 30 days from creation; finished entries no longer need coordinates.
                return if (legacy && !entry.live()) entry.withoutGoogleCoordinates()
                    else entry
            }
        }
    }

    private fun prefs(context: Context) = context.getSharedPreferences("destination_multi_monitor", Context.MODE_PRIVATE)
    private fun decode(raw: String): Pair<MutableList<Entry>, Boolean> {
        val array = JSONArray(raw)
        val entries = mutableListOf<Entry>()
        val ids = mutableSetOf<String>()
        var damaged = false
        for (index in 0 until array.length()) {
            try {
                val entry = Entry.from(array.getJSONObject(index))
                require(entry.id.isNotBlank() && entry.latitude.isFinite() && entry.longitude.isFinite() &&
                    entry.latitude in -90.0..90.0 && entry.longitude in -180.0..180.0 &&
                    entry.radius.isFinite() && entry.radius in 100f..2000f &&
                    entry.status in listOf("active", "triggered", "snoozed", "completed", "cancelled") &&
                    entry.startedAt > 0L && entry.alertAt >= 0L && entry.snoozedUntil >= 0L &&
                    entry.sourceExpiresAt >= 0L &&
                    entry.targetMinute in 0..1439 && ids.add(entry.id))
                entries.add(entry)
            } catch (_: Exception) { damaged = true }
        }
        return entries to damaged
    }

    @Synchronized private fun read(context: Context): MutableList<Entry> {
        val stored = prefs(context)
        val raw = stored.getString(KEY, "[]") ?: "[]"
        var damaged = false
        val decoded = try { decode(raw) } catch (_: Exception) {
            damaged = true
            try { decode(stored.getString("last_good_alarms", "[]") ?: "[]") }
            catch (_: Exception) { mutableListOf<Entry>() to true }
        }
        damaged = damaged || decoded.second
        val valid = JSONArray().apply { decoded.first.forEach { put(it.json()) } }.toString()
        if (damaged) {
            stored.edit().putString("recovery_alarms", raw)
                .putString("storage_warning", "Alarm storage contained damaged data. ${decoded.first.size} alarms recovered. Check your active alarms and recreate any missing alarms.")
                .putString(KEY, valid).putString("last_good_alarms", valid).commit()
        } else if (stored.getString(KEY, null) != valid ||
            stored.getString("last_good_alarms", null) != valid) {
            stored.edit().putString(KEY, valid).putString("last_good_alarms", valid).commit()
        }
        return decoded.first
    }

    @Synchronized private fun write(context: Context, entries: List<Entry>): Boolean {
        val array = JSONArray()
        entries.forEach { array.put(it.json()) }
        val saved = prefs(context).edit().putString(KEY, array.toString())
            .putString("last_good_alarms", array.toString()).commit()
        if (saved) AlarmStatusEvents.changed()
        return saved
    }

    @Synchronized fun storageWarning(context: Context): String? {
        read(context)
        return prefs(context).getString("storage_warning", null) ?: LegacyAlarmMigration.problem(context)
    }

    @Synchronized fun clearFinished(context: Context): Boolean =
        write(context, read(context).filter { it.live() })

    @Synchronized fun clearStorageRecovery(context: Context): Boolean =
        prefs(context).edit().remove("recovery_alarms").remove("storage_warning").commit()

    @Synchronized fun states(context: Context): List<Map<String, Any>> {
        migrateLegacy(context)
        checkDue(context)
        return read(context).map { entry ->
            entry.map() + MultiTrackingService.health(context, entry) + mapOf(
                "geofenceStatus" to (geofenceStatus[entry.id] ?: "Not confirmed"))
        }
    }
    @Synchronized fun live(context: Context): List<Entry> = read(context).filter { it.monitoring() }
    @Synchronized fun ringing(context: Context): Entry? = read(context)
        .filter { it.status == "triggered" && !it.paused }
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
        if (entry.repeatDays == 0 || entry.status != "active" || entry.paused) return false
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
        scheduledAt = 0L // Clock changes and permission grants must replace the OS alarm.
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

    /** Storage-only migration: callers decide when Android permits playback. */
    @Synchronized fun migrateLegacy(context: Context) {
        val entry = LegacyAlarmMigration.readEntry(context) ?: return
        val entries = read(context)
        if (entries.none { it.id == entry.id }) {
            entries.add(entry)
            if (!write(context, entries)) return
        }
        LegacyAlarmMigration.retire(context)
    }

    @Synchronized fun register(context: Context, args: Map<String, Any>, result: MethodChannel.Result) {
        migrateLegacy(context)
        val label = (args["label"] as? String ?: "").trim()
        val id = args["id"] as? String
        val name = args["name"] as? String
        val lat = (args["latitude"] as? Number)?.toDouble()
        val lon = (args["longitude"] as? Number)?.toDouble()
        val radius = (args["radius"] as? Number)?.toFloat()
        val repeatDays = (args["repeatDays"] as? Number)?.toInt() ?: 0
        val leadMinutes = (args["leadMinutes"] as? Number)?.toInt() ?: 0
        val alertAt = (args["alertAt"] as? Number)?.toLong() ?: 0L
        val repeatStartAt = (args["repeatStartDay"] as? Number)?.toLong() ?: 0L
        val sourceExpiresAt = (args["sourceExpiresAt"] as? Number)?.toLong() ?: 0L
        val targetAt = if (alertAt > 0L) alertAt + leadMinutes * 60_000L else repeatStartAt
        val targetCalendar = Calendar.getInstance().apply { timeInMillis = targetAt }
        val targetWeekday = (targetCalendar.get(Calendar.DAY_OF_WEEK) + 5) % 7
        if (label.length > 80 || id.isNullOrBlank() || name.isNullOrBlank() || lat == null || lon == null ||
            !lat.isFinite() || !lon.isFinite() || lat !in -90.0..90.0 || lon !in -180.0..180.0 ||
            radius == null || !radius.isFinite() || radius !in 100f..2000f ||
            (sourceExpiresAt != 0L && sourceExpiresAt <= System.currentTimeMillis()) ||
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
            hasTime = alertAt > 0L, label = label, sourceExpiresAt = sourceExpiresAt)
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
        val index = entries.indexOfFirst { it.id == id && it.live() }
        if (index < 0) return
        val entry = entries[index]
        entry.status = status
        entry.endedAt = System.currentTimeMillis()
        entry.snoozedUntil = 0L
        if (entry.sourceExpiresAt > 0L) entries[index] = entry.withoutGoogleCoordinates()
        if (write(context, entries)) {
            removeGeofence(context, id)
            refresh(context)
        }
    }

    @Synchronized fun forget(context: Context, id: String) {
        val entries = read(context)
        if (entries.removeAll { it.id == id && !it.live() }) write(context, entries)
    }

    private fun applyRepeat(entry: Entry, days: Int) {
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
    }

    @Synchronized fun rename(context: Context, id: String, label: String, result: MethodChannel.Result) {
        val entries = read(context)
        val index = entries.indexOfFirst { it.id == id && it.live() }
        if (index < 0 || label.trim().length > 80) {
            result.error("arguments", "Alarm missing or name is too long", null); return
        }
        entries[index] = entries[index].copy(label = label.trim())
        if (!write(context, entries)) { result.error("storage", "Could not save alarm name", null); return }
        refresh(context)
        result.success(null)
    }

    @Synchronized fun pause(context: Context, id: String, paused: Boolean, result: MethodChannel.Result) {
        val entries = read(context)
        val entry = entries.firstOrNull { it.id == id && it.status == "active" } ?: run {
            result.error("state", "Handle the ringing or snoozed alert before pausing or resuming", null); return
        }
        if (entry.paused == paused) { result.success(null); return }
        val before = entry.copy()
        entry.paused = paused
        val now = System.currentTimeMillis()
        if (!paused) {
            entry.monitoringSince = now
            advanceCycle(entry, now)
            // Resuming skips time reminders missed while paused.
            if (entry.alertAt in 1..now && !entry.timeFired) entry.timeFired = true
            if (entry.repeatDays == 0 && entry.distanceFired && (entry.alertAt == 0L || entry.timeFired))
                entry.status = "completed"
        }
        if (!write(context, entries)) { result.error("storage", "Could not save pause setting", null); return }
        removeGeofence(context, id)
        try { refresh(context, strict = !paused) } catch (_: Exception) {
            entries[entries.indexOf(entry)] = before
            write(context, entries)
            refresh(context)
            result.error("tracking", "Could not resume monitoring. Recheck phone settings.", null); return
        }
        if (!paused && entry.monitoring() && !entry.distanceFired) addGeofence(context, entry)
        result.success(null)
    }

    @Synchronized fun update(context: Context, args: Map<String, Any>, result: MethodChannel.Result) {
        val entries = read(context)
        val index = entries.indexOfFirst { it.id == args["id"] && it.status == "active" }
        if (index < 0) { result.error("state", "Stop the ringing alert before editing this alarm", null); return }
        val old = entries[index]
        val lat = (args["latitude"] as? Number)?.toDouble()
        val lon = (args["longitude"] as? Number)?.toDouble()
        val radius = (args["radius"] as? Number)?.toFloat()
        val days = (args["repeatDays"] as? Number)?.toInt()
        val sourceExpiresAt = (args["sourceExpiresAt"] as? Number)?.toLong() ?: 0L
        val label = (args["label"] as? String ?: "").trim()
        val name = args["name"] as? String
        if (name.isNullOrBlank() || lat == null || lon == null || !lat.isFinite() || !lon.isFinite() ||
            lat !in -90.0..90.0 || lon !in -180.0..180.0 || radius == null ||
            !radius.isFinite() || radius !in 100f..2000f || days == null || days !in 0..127 || label.length > 80 ||
            (sourceExpiresAt != 0L && sourceExpiresAt <= System.currentTimeMillis())) {
            result.error("arguments", "Invalid alarm settings", null); return
        }
        val destinationChanged = lat != old.latitude || lon != old.longitude || radius != old.radius
        val changed = old.copy(name = name, address = args["address"] as? String ?: "",
            latitude = lat, longitude = lon, radius = radius,
            sourceExpiresAt = sourceExpiresAt,
            vibration = args["vibration"] as? Boolean ?: old.vibration,
            sound = args["sound"] as? String ?: old.sound, label = label)
        if (destinationChanged) {
            changed.distanceFired = false
            changed.monitoringSince = System.currentTimeMillis()
        }
        if (days != old.repeatDays) applyRepeat(changed, days)
        entries[index] = changed
        if (!write(context, entries)) { result.error("storage", "Could not save alarm changes", null); return }
        if (destinationChanged || days != old.repeatDays) removeGeofence(context, old.id)
        refresh(context)
        if (changed.monitoring() && !changed.distanceFired) addGeofence(context, changed)
        result.success(null)
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
        applyRepeat(entry, days)
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
        val entry = entries.firstOrNull { it.id == id && it.monitoring() } ?: return
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
        val index = entries.indexOfFirst { it.id == id && it.status == "triggered" }
        if (index < 0) return
        val entry = entries[index]
        val finished = entry.distanceFired && (entry.alertAt <= 0L || entry.timeFired)
        val completedCycle = if (finished && entry.repeatDays != 0)
            entry.copy(id = "${entry.id}:cycle:${entry.cycleDate}", status = "completed",
                repeatDays = 0, endedAt = System.currentTimeMillis()).let {
                    if (it.sourceExpiresAt > 0L) it.withoutGoogleCoordinates() else it
                } else null
        entry.status = if (finished && entry.repeatDays == 0) "completed" else "active"
        if (entry.status == "completed") entry.endedAt = System.currentTimeMillis()
        entry.triggeredAt = 0L
        advanceCycle(entry, System.currentTimeMillis(), force = finished)
        if (entry.status == "completed" && entry.sourceExpiresAt > 0L)
            entries[index] = entry.withoutGoogleCoordinates()
        if (completedCycle != null && entries.none { it.id == completedCycle.id })
            entries.add(completedCycle)
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

    @Synchronized fun checkDue(context: Context, refreshService: Boolean = true) {
        val entries = read(context)
        val now = System.currentTimeMillis()
        var changed = false
        val expiredIds = mutableListOf<String>()
        for (index in entries.indices) {
            val entry = entries[index]
            if (entry.live() && entry.sourceExpiresAt > 0L && now >= entry.sourceExpiresAt) {
                expiredIds.add(entry.id)
                // Never retain Places-derived coordinates beyond their allowed lifetime.
                entries[index] = entry.withoutGoogleCoordinates().copy(
                    status = "cancelled", paused = false, endedAt = now)
                changed = true
            }
        }
        val advanced = mutableListOf<Entry>()
        entries.filter { it.monitoring() }.forEach { entry ->
            if (advanceCycle(entry, now)) {
                changed = true
                advanced.add(entry)
            }
        }
        val due = entries.filter { entry -> entry.monitoring() &&
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
            expiredIds.forEach { removeGeofence(context, it) }
            if (expiredIds.isNotEmpty()) {
                val open = PendingIntent.getActivity(context, 203,
                    Intent(context, MainActivity::class.java),
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                AlarmNotifications.notifications(context).notify(203,
                    builder(context, AlarmNotifications.CHANNEL_TRACKING)
                        .setSmallIcon(android.R.drawable.ic_dialog_alert)
                        .setContentTitle("Destination needs reselection")
                        .setContentText("A saved Google location expired. Open the app to choose it again.")
                        .setContentIntent(open)
                        .setAutoCancel(true).build())
            }
            if (refreshService) refresh(context)
            advanced.filter { it.distanceReady(now) }.forEach { addGeofence(context, it) }
        } else scheduleNext(context, entries)
    }

    private fun Entry.withoutGoogleCoordinates() = copy(
        latitude = 0.0, longitude = 0.0, address = "",
        name = "Google destination · reselect", sourceExpiresAt = 0L,
        locationRedacted = true)

    @Synchronized fun checkLocation(context: Context, location: Location): Long {
        checkDue(context)
        if (System.currentTimeMillis() - location.time !in 0..30_000L) return 30_000L
        if (!LocationEvidence.validCoordinates(location)) return 5_000L
        val previous = previousFix
        previousFix = Location(location)
        val entries = live(context)
        if (entries.none { !it.distanceFired && it.distanceReady(System.currentTimeMillis()) }) {
            return 30 * 60_000L
        }
        var closest = Float.MAX_VALUE
        val reached = mutableListOf<Triple<Entry, Float, Double>>()
        var speedInterval = 30_000L
        for (entry in entries) {
            if (location.time < entry.monitoringSince || entry.distanceFired || !entry.distanceReady(System.currentTimeMillis())) continue
            val distances = FloatArray(1)
            Location.distanceBetween(location.latitude, location.longitude, entry.latitude, entry.longitude, distances)
            val remaining = distances[0] - entry.radius
            val crossing = if (previous != null && previous.time >= maxOf(entry.startedAt, entry.cycleDay, entry.monitoringSince))
                DestinationCrossing.fraction(previous, location, entry.latitude, entry.longitude, entry.radius)
                else null
            if (remaining <= 5_000f && location.hasSpeed() && location.speed > 1f) {
                speedInterval = minOf(speedInterval,
                    (entry.radius / location.speed * 500).toLong().coerceIn(1_000L, 30_000L))
            }
            if (remaining <= 0f) {
                if (!LocationEvidence.usable(location, entry.radius)) {
                    closest = 0f // Seek a verified, accurate fix before ringing.
                } else reached.add(Triple(entry, distances[0], crossing ?: 1.0))
            }
            else if (crossing != null) reached.add(Triple(entry, distances[0], crossing))
            else if (remaining < closest) closest = remaining
        }
        reached.sortedWith(compareBy<Triple<Entry, Float, Double>> { it.third }.thenBy { it.second })
            .forEach { (entry, _, _) -> trigger(context, entry.id, "distance") }
        return minOf(speedInterval, when {
            closest <= 1_000f -> 5_000L
            closest <= 5_000f -> 10_000L
            else -> 30_000L
        })
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

    private val geofenceStatus = mutableMapOf<String, String>()

    fun playbackResumeRequired(context: Context) = prefs(context).getBoolean("playback_resume_required", false)
    fun setPlaybackResumeRequired(context: Context, required: Boolean) {
        prefs(context).edit().putBoolean("playback_resume_required", required).commit()
        AlarmStatusEvents.changed()
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
                    geofenceStatus[entry.id] = "Registered"
                    AlarmStatusEvents.changed()
                    if (live(context).none { it.id == entry.id && !it.distanceFired &&
                            it.distanceReady(System.currentTimeMillis()) }) {
                        removeGeofence(context, entry.id)
                    }
                }
                .addOnFailureListener {
                    geofenceStatus[entry.id] = "Unavailable: ${it.message ?: "registration failed"}"
                    AlarmStatusEvents.changed()
                }
        } catch (e: Exception) {
            geofenceStatus[entry.id] = "Unavailable: ${e.message ?: "registration failed"}"
        }
    }

    private fun removeGeofence(context: Context, id: String) {
        geofenceStatus.remove(id)
        try { LocationServices.getGeofencingClient(context).removeGeofences(listOf(id)) }
        catch (_: Exception) { }
    }

    fun ensureGeofences(context: Context) {
        live(context).filter { !it.distanceFired && it.distanceReady(System.currentTimeMillis()) }
            .forEach { addGeofence(context, it) }
    }

    @Synchronized private fun scheduleNext(context: Context, entries: List<Entry>) {
        val next = entries.filter { it.monitoring() }.flatMap { entry ->
            listOf(if (!entry.timeFired) entry.alertAt else 0L,
                if (entry.status == "snoozed") entry.snoozedUntil else 0L,
                if (entry.repeatDays != 0 && entry.status == "active") nextCycleStart(entry) else 0L,
                if (entry.repeatDays != 0 && entry.status == "active" &&
                    entry.cycleDay > System.currentTimeMillis()) entry.cycleDay else 0L,
                entry.sourceExpiresAt)
        }.filter { it > 0L }.minOrNull() ?: 0L
        val exact = AlarmScheduler.canScheduleExact(context)
        val audible = entries.any { it.monitoring() &&
            ((!it.timeFired && it.alertAt == next && next > 0L) ||
             (it.status == "snoozed" && it.snoozedUntil == next && next > 0L)) }
        if (next == scheduledAt && exact == scheduledExact && audible == scheduledAudible) return
        val manager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = timeIntent(context)
        manager.cancel(intent)
        if (next > 0L) AlarmScheduler.schedule(context, next, intent, audible)
        scheduledAt = next
        scheduledExact = exact
        scheduledAudible = audible
    }

    fun refresh(context: Context, strict: Boolean = false) {
        AlarmStatusEvents.changed()
        scheduleNext(context, read(context))
        val service = Intent(context, MultiTrackingService::class.java)
        if (live(context).isEmpty()) {
            previousFix = null
            context.stopService(service)
            AlarmNotifications.notifications(context).cancel(TRACKING_ID)
            AlarmNotifications.notifications(context).cancel(ALARM_ID)
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
                    AlarmNotifications.notifications(context).notify(ALARM_ID, alarmNotification(context, ringing))
                } else {
                    AlarmNotifications.notifications(context).notify(TRACKING_ID, trackingNotification(context, live(context).size))
                }
            }
        }
    }

    private fun action(context: Context, id: String, verb: String, code: Int): PendingIntent =
        PendingIntent.getBroadcast(context, code,
            Intent(context, MultiAlarmReceiver::class.java).setAction("tracker_alarm.MULTI_$verb").putExtra("id", id),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

    fun alarmNotification(context: Context, entry: Entry): Notification {
        AlarmNotifications.notifications(context)
        val waiting = live(context).count { it.status == "triggered" && it.id != entry.id }
        val open = PendingIntent.getActivity(context, 42,
            Intent(context, MainActivity::class.java).setAction("tracker_alarm.ALARM")
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val lockedAlarm = PendingIntent.getActivity(context, 48,
            Intent(context, LockedAlarmActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        return builder(context, AlarmNotifications.CHANNEL_ALARM)
            .setSound(null).setVibrate(null).setOnlyAlertOnce(true)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle(when (entry.triggerReason) { "time" -> "Time alarm"; "both" -> "Time and distance alarm"; else -> "Destination nearby" })
            .setContentText(if (waiting == 0) entry.displayName else "${entry.displayName} · $waiting more alert${if (waiting == 1) "" else "s"} waiting")
            .setCategory(Notification.CATEGORY_ALARM)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setPriority(Notification.PRIORITY_MAX)
            .setContentIntent(open).setFullScreenIntent(lockedAlarm, true)
            .addAction(Notification.Action.Builder(android.R.drawable.ic_media_pause, "Snooze 1 min", action(context, entry.id, "SNOOZE", 43)).build())
            .addAction(Notification.Action.Builder(android.R.drawable.ic_delete, "Stop alert", action(context, entry.id, "DISMISS", 44)).build())
            .addAction(Notification.Action.Builder(android.R.drawable.ic_menu_close_clear_cancel, "End trip", action(context, entry.id, "END", 45)).build())
            .setOngoing(true).build()
    }

    fun trackingNotification(context: Context, count: Int, message: String? = null): Notification {
        AlarmNotifications.notifications(context)
        val open = PendingIntent.getActivity(context, 46, Intent(context, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        return builder(context, AlarmNotifications.CHANNEL_TRACKING)
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setContentTitle("Destination alarms active")
            .setContentText(message ?: "Monitoring $count destination${if (count == 1) "" else "s"}")
            .setContentIntent(open).setOngoing(true).build()
    }

    @Suppress("DEPRECATION")
    private fun builder(context: Context, channel: String): Notification.Builder =
        if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, channel)
        else Notification.Builder(context)
}
