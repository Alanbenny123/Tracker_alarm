package com.trackeralarm.app

import android.Manifest
import android.content.pm.PackageManager
import android.content.Context
import android.os.Build
import android.content.Intent
import android.net.Uri
import android.location.Address
import android.location.Geocoder
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

class MainActivity : FlutterActivity() {
    private val batteryConfirmation = BatteryConfirmation()
    private var batterySettingsVisited = false

    override fun onPause() {
        batteryConfirmation.invalidate()
        super.onPause()
    }

    private var shareChannel: MethodChannel? = null
    private var pendingSharedText: String? = null

    private fun acceptShare(intent: Intent?) {
        if (intent?.action != Intent.ACTION_SEND || intent.type != "text/plain") return
        val text = intent.getStringExtra(Intent.EXTRA_TEXT)?.trim()
        if (text.isNullOrEmpty()) return
        val subject = intent.getCharSequenceExtra(Intent.EXTRA_SUBJECT)?.toString()?.trim()
        val title = intent.getCharSequenceExtra(Intent.EXTRA_TITLE)?.toString()?.trim()
        val label = sequenceOf(subject, title)
            .firstOrNull { !it.isNullOrBlank() && !it.startsWith("http") && it != text }
        pendingSharedText = if (label == null) text else "$label\n$text"
        shareChannel?.invokeMethod("sharedText", pendingSharedText)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        acceptShare(intent)
    }
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        shareChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tracker_alarm/share")
        shareChannel?.setMethodCallHandler { call, result ->
            if (call.method == "takePendingShare") {
                result.success(pendingSharedText)
                pendingSharedText = null
            } else result.notImplemented()
        }
        acceptShare(intent)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tracker_alarm/geofence").setMethodCallHandler { call, result ->
            when (call.method) {
                "multiClearFinished" -> {
                    if (MultiAlarmRuntime.clearFinished(this)) result.success(null)
                    else result.error("storage", "Could not clear finished alarms", null)
                }
                "multiStorageWarning" -> result.success(MultiAlarmRuntime.storageWarning(this))
                "multiClearStorageRecovery" -> {
                    if (MultiAlarmRuntime.clearStorageRecovery(this)) result.success(null)
                    else result.error("storage", "Could not delete damaged recovery copies", null)
                }
                "multiStates" -> result.success(MultiAlarmRuntime.states(this))
                "multiRegister" -> {
                    val readiness = AlarmReadiness.values(this, batteryConfirmation.valid())
                    val ready = listOf("preciseLocation", "backgroundLocation", "notifications", "exactAlarms", "fullScreenAlarms")
                        .all { readiness[it] == true } &&
                        (readiness["batteryOptimizationOff"] == true || readiness["batteryManuallyConfirmed"] == true)
                    if (!ready) {
                        result.error("permission", "Phone settings changed. Recheck the alarm requirements before starting.", null)
                        return@setMethodCallHandler
                    }
                    @Suppress("UNCHECKED_CAST")
                    val args = call.arguments as? Map<String, Any> ?: run {
                        result.error("arguments", "Missing destination", null); return@setMethodCallHandler
                    }
                    MultiAlarmRuntime.register(this, args, result)
                }
                "multiEnsure" -> {
                    MultiAlarmRuntime.setPlaybackResumeRequired(this, false)
                    MultiAlarmRuntime.refresh(this)
                    MultiAlarmRuntime.ensureGeofences(this)
                    result.success(null)
                }
                "multiUpdateRepeat" -> {
                    val id = call.argument<String>("id")
                    val days = call.argument<Int>("days")
                    if (id == null || days == null) result.error("arguments", "Missing repeat settings", null)
                    else MultiAlarmRuntime.updateRepeat(this, id, days, result)
                }
                "multiFinish", "multiForget", "multiDismiss", "multiSnooze", "multiTrigger" -> {
                    val id = call.argument<String>("id")
                    if (id.isNullOrBlank()) {
                        result.error("arguments", "Missing alarm ID", null)
                        return@setMethodCallHandler
                    }
                    when (call.method) {
                        "multiFinish" -> {
                            val status = call.argument<String>("status")
                            if (status != "cancelled" && status != "completed") {
                                result.error("arguments", "Invalid finish status", null)
                                return@setMethodCallHandler
                            }
                            MultiAlarmRuntime.finish(this, id, status)
                        }
                        "multiForget" -> MultiAlarmRuntime.forget(this, id)
                        "multiDismiss" -> MultiAlarmRuntime.dismiss(this, id)
                        "multiSnooze" -> MultiAlarmRuntime.snooze(this, id, call.argument<Int>("minutes") ?: 1)
                        "multiTrigger" -> MultiAlarmRuntime.trigger(this, id, "distance")
                    }
                    result.success(null)
                }
                "register" -> {
                    if (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED ||
                        (Build.VERSION.SDK_INT >= 29 && checkSelfPermission(Manifest.permission.ACCESS_BACKGROUND_LOCATION) != PackageManager.PERMISSION_GRANTED)) {
                        result.error("permission", "Precise and background location permission are required for geofencing.", null)
                        return@setMethodCallHandler
                    }
                    @Suppress("UNCHECKED_CAST")
                    val args = call.arguments as? Map<String, Any> ?: run {
                        result.error("arguments", "Missing destination", null); return@setMethodCallHandler
                    }
                    AlarmRuntime.register(this, args, result)
                }
                "cancel" -> AlarmRuntime.finish(this, "cancelled", result)
                "stop" -> AlarmRuntime.finish(this, "completed", result)
                "dismissCurrent" -> AlarmRuntime.dismissCurrent(this, result)
                "ensure" -> AlarmRuntime.ensure(this, result)
                "resumeTriggered" -> {
                    AlarmRuntime.resumeTriggered(this)
                    result.success(null)
                }
                "trigger" -> {
                    AlarmRuntime.trigger(this)
                    result.success(null)
                }
                "snooze" -> {
                    val minutes = call.argument<Int>("minutes") ?: 1
                    AlarmRuntime.snooze(this, minutes)
                    result.success(null)
                }
                "status" -> result.success(AlarmRuntime.prefs(this).getString("status", "inactive"))
                "state" -> result.success(AlarmRuntime.state(this))
                "requirements" -> result.success(AlarmReadiness.values(this, batteryConfirmation.valid()))
                "openNotificationSettings" -> {
                    try {
                        startActivity(AlarmReadiness.notificationSettings(this))
                        result.success(null)
                    } catch (e: Exception) { result.error("settings", "Could not open notification settings", null) }
                }
                "openFullScreenSettings" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= 34) startActivity(Intent(
                            Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT, Uri.parse("package:$packageName")))
                        result.success(null)
                    } catch (e: Exception) { result.error("settings", "Could not open lock-screen alarm settings", null) }
                }
                "openExactAlarmSettings" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= 31) {
                            startActivity(Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                                Uri.parse("package:$packageName")))
                        }
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("settings", "Could not open Alarms & reminders settings: ${e.message}", null)
                    }
                }
                "confirmBatterySettings" -> {
                    if (!batterySettingsVisited) result.error("settings", "Open battery settings and check No restrictions before confirming again.", null)
                    else {
                        batteryConfirmation.confirm()
                        batterySettingsVisited = false
                        result.success(null)
                    }
                }
                "openBatterySettings" -> {
                    try {
                        batteryConfirmation.invalidate()
                        startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                        batterySettingsVisited = true
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("settings", "Could not open battery optimization settings: ${e.message}", null)
                    }
                }
                "openAppBatterySettings" -> {
                    try {
                        batteryConfirmation.invalidate()
                        startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")))
                        batterySettingsVisited = true
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("settings", "Could not open app settings: ${e.message}", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tracker_alarm/places").setMethodCallHandler { call, result ->
            if (call.method != "search") { result.notImplemented(); return@setMethodCallHandler }
            val query = call.argument<String>("query")?.trim()
            if (query.isNullOrBlank()) { result.success(emptyList<Map<String, Any>>()); return@setMethodCallHandler }
            if (!Geocoder.isPresent()) { result.error("geocoder", "Place search is unavailable on this device. Tap the map to choose a destination.", null); return@setMethodCallHandler }
            val geocoder = Geocoder(this, Locale.getDefault())
            fun deliver(addresses: List<Address>) {
                runOnUiThread {
                    result.success(addresses.filter { it.hasLatitude() && it.hasLongitude() }.map { address ->
                        mapOf(
                            "name" to (address.featureName ?: address.locality ?: query),
                            "address" to (address.getAddressLine(0) ?: query),
                            "latitude" to address.latitude,
                            "longitude" to address.longitude,
                        )
                    })
                }
            }
            if (Build.VERSION.SDK_INT >= 33) {
                try { geocoder.getFromLocationName(query, 5, object : Geocoder.GeocodeListener {
                    override fun onGeocode(addresses: MutableList<Address>) { deliver(addresses) }
                    override fun onError(errorMessage: String?) {
                        runOnUiThread { result.error("geocoder", errorMessage ?: "Place search failed. Tap the map to choose a destination.", null) }
                    }
                }) }
                catch (e: Exception) { result.error("geocoder", e.message, null) }
            } else {
                Thread {
                    try { deliver(legacySearch(geocoder, query)) }
                    catch (e: Exception) { runOnUiThread { result.error("geocoder", e.message, null) } }
                }.start()
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        shareChannel?.setMethodCallHandler(null)
        shareChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    @Suppress("DEPRECATION")
    private fun legacySearch(geocoder: Geocoder, query: String): List<Address> = geocoder.getFromLocationName(query, 5) ?: emptyList()
}
