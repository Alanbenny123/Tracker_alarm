package com.trackeralarm.app

import android.Manifest
import android.content.pm.PackageManager
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import android.os.PowerManager
import android.content.Intent
import android.net.Uri
import android.location.Address
import android.location.Geocoder
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

class MainActivity : FlutterActivity() {
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
        if (intent.action == "tracker_alarm.ALARM") wakeScreen()
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
                "requirements" -> {
                    val precise = checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
                    val background = Build.VERSION.SDK_INT < 29 || checkSelfPermission(Manifest.permission.ACCESS_BACKGROUND_LOCATION) == PackageManager.PERMISSION_GRANTED
                    val notifications = if (Build.VERSION.SDK_INT >= 33) {
                        checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED &&
                            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).areNotificationsEnabled()
                    } else (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).areNotificationsEnabled()
                    val battery = if (Build.VERSION.SDK_INT >= 23) {
                        (getSystemService(Context.POWER_SERVICE) as PowerManager).isIgnoringBatteryOptimizations(packageName)
                    } else true
                    result.success(mapOf(
                        "preciseLocation" to precise,
                        "backgroundLocation" to background,
                        "notifications" to notifications,
                        "batteryOptimizationOff" to battery,
                        "batteryManuallyConfirmed" to getSharedPreferences("alarm_requirement_setup", MODE_PRIVATE).getBoolean("battery_confirmed", false),
                    ))
                }
                "confirmBatterySettings" -> {
                    getSharedPreferences("alarm_requirement_setup", MODE_PRIVATE).edit().putBoolean("battery_confirmed", true).apply()
                    result.success(null)
                }
                "openBatterySettings" -> {
                    try {
                        startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("settings", "Could not open battery optimization settings: ${e.message}", null)
                    }
                }
                "openAppBatterySettings" -> {
                    try {
                        startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")))
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
        if (intent?.action == "tracker_alarm.ALARM") wakeScreen()
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        shareChannel?.setMethodCallHandler(null)
        shareChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    @Suppress("DEPRECATION")
    private fun wakeScreen() {
        if (Build.VERSION.SDK_INT >= 27) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else window.addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON)
    }

    @Suppress("DEPRECATION")
    private fun legacySearch(geocoder: Geocoder, query: String): List<Address> = geocoder.getFromLocationName(query, 5) ?: emptyList()
}
