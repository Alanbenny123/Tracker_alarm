package com.trackeralarm.app

import android.Manifest
import android.content.pm.PackageManager
import android.content.Context
import android.os.Build
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel

class MainActivity : FlutterActivity() {
    private val batteryConfirmation = BatteryConfirmation()
    private var batterySettingsVisited = false

    override fun onPause() {
        batteryConfirmation.invalidate()
        super.onPause()
    }

    private var statusChannel: EventChannel? = null
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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tracker_alarm/google_maps_config")
            .setMethodCallHandler { call, result ->
                if (call.method == "configured") result.success(getString(R.string.google_maps_api_key).isNotBlank())
                else result.notImplemented()
            }
        GooglePlacesBridge(this, flutterEngine.dartExecutor.binaryMessenger).register()
        statusChannel = EventChannel(flutterEngine.dartExecutor.binaryMessenger, "tracker_alarm/status")
        statusChannel?.setStreamHandler(AlarmStatusEvents)
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
                "testAlarmStop" -> { TestAlarmService.stop(this); result.success(null) }
                "testAlarmStart" -> {
                    if (!AlarmReadiness.notificationsReady(this) || !AlarmReadiness.fullScreenReady(this)) {
                        result.error("permission", "Allow alarm notifications and lock-screen alarms before testing.", null)
                    } else if (MultiAlarmRuntime.ringing(this) != null) {
                        result.error("state", "Stop the ringing destination alert before testing.", null)
                    } else try {
                        val service = Intent(this, TestAlarmService::class.java)
                            .putExtra("sound", call.argument<String>("sound") ?: "Default alarm")
                            .putExtra("vibration", call.argument<Boolean>("vibration") ?: true)
                        if (Build.VERSION.SDK_INT >= 26) startForegroundService(service) else startService(service)
                        result.success(null)
                    } catch (_: Exception) { result.error("test", "Could not start the test alarm", null) }
                }
                "multiRename" -> MultiAlarmRuntime.rename(this, call.argument<String>("id") ?: "", call.argument<String>("label") ?: "", result)
                "multiPause" -> {
                    val paused = call.argument<Boolean>("paused") ?: true
                    val settings = AlarmReadiness.values(this, batteryConfirmation.valid())
                    val ready = listOf("preciseLocation", "backgroundLocation", "notifications", "exactAlarms", "fullScreenAlarms")
                        .all { settings[it] == true } && (settings["batteryOptimizationOff"] == true || settings["batteryManuallyConfirmed"] == true)
                    if (!paused && !ready) result.error("permission", "Complete the phone settings in alarm setup before resuming.", null)
                    else MultiAlarmRuntime.pause(this, call.argument<String>("id") ?: "", paused, result)
                }
                "multiUpdate" -> {
                    @Suppress("UNCHECKED_CAST")
                    val args = call.arguments as? Map<String, Any>
                    if (args == null) result.error("arguments", "Missing alarm settings", null)
                    else MultiAlarmRuntime.update(this, args, result)
                }
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
                    MultiAlarmRuntime.migrateLegacy(this)
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
                "multiFinish", "multiForget", "multiDismiss", "multiSnooze", "multiTriggerAt" -> {
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
                        "multiTriggerAt" -> {
                            val latitude = call.argument<Double>("latitude")
                            val longitude = call.argument<Double>("longitude")
                            val accuracy = call.argument<Double>("accuracy")
                            val fixAt = call.argument<Long>("fixAt")
                            if (latitude != null && longitude != null && accuracy != null && fixAt != null) {
                                MultiAlarmRuntime.triggerAt(this, id, latitude, longitude, accuracy, fixAt)
                            }
                        }
                    }
                    result.success(null)
                }
                "status" -> result.success(LegacyAlarmMigration.status(this))
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
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        statusChannel?.setStreamHandler(null)
        AlarmStatusEvents.onCancel(null)
        statusChannel = null
        shareChannel?.setMethodCallHandler(null)
        shareChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

}
