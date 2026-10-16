package com.trackeralarm.app

import android.Manifest
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioManager
import android.os.Build
import android.os.PowerManager
import android.os.SystemClock
import android.provider.Settings

/** Manufacturer battery settings cannot be verified by a persistent checkbox. */
class BatteryConfirmation {
    private var confirmedUntil = 0L
    fun confirm() { confirmedUntil = SystemClock.elapsedRealtime() + 15 * 60_000L }
    fun valid() = SystemClock.elapsedRealtime() < confirmedUntil
    fun invalidate() { confirmedUntil = 0L }
}

object AlarmReadiness {
    fun blockedChannel(context: Context): String? {
        val manager = AlarmNotifications.notifications(context)
        if (Build.VERSION.SDK_INT < 26) return null
        if ((manager.getNotificationChannel(AlarmNotifications.CHANNEL_ALARM)?.importance ?: 0) < NotificationManager.IMPORTANCE_HIGH)
            return AlarmNotifications.CHANNEL_ALARM
        if ((manager.getNotificationChannel(AlarmNotifications.CHANNEL_TRACKING)?.importance ?: 0) == NotificationManager.IMPORTANCE_NONE)
            return AlarmNotifications.CHANNEL_TRACKING
        return null
    }

    fun notificationsReady(context: Context): Boolean {
        val manager = AlarmNotifications.notifications(context)
        return manager.areNotificationsEnabled() &&
            (Build.VERSION.SDK_INT < 33 || context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) &&
            blockedChannel(context) == null
    }

    fun fullScreenReady(context: Context): Boolean = Build.VERSION.SDK_INT < 34 ||
        AlarmNotifications.notifications(context).canUseFullScreenIntent()

    fun notificationSettings(context: Context): Intent {
        val channel = blockedChannel(context)
        return if (Build.VERSION.SDK_INT >= 26 && channel != null) {
            Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
                .putExtra(Settings.EXTRA_CHANNEL_ID, channel)
        } else if (Build.VERSION.SDK_INT >= 26) {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
        } else Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            android.net.Uri.parse("package:${context.packageName}"))
    }

    fun values(context: Context, manualBattery: Boolean): Map<String, Any> {
        val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val manager = AlarmNotifications.notifications(context)
        val warnings = mutableListOf<String>()
        if (audio.getStreamVolume(AudioManager.STREAM_ALARM) == 0)
            warnings.add("Alarm volume is zero. Raise alarm volume to hear the alert.")
        if (manager.currentInterruptionFilter == NotificationManager.INTERRUPTION_FILTER_NONE ||
            manager.currentInterruptionFilter == NotificationManager.INTERRUPTION_FILTER_PRIORITY)
            warnings.add("Do Not Disturb may silence alarms. Check its alarm exceptions.")
        return mapOf(
            "preciseLocation" to (context.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED),
            "backgroundLocation" to (Build.VERSION.SDK_INT < 29 || context.checkSelfPermission(Manifest.permission.ACCESS_BACKGROUND_LOCATION) == PackageManager.PERMISSION_GRANTED),
            "notifications" to notificationsReady(context),
            "exactAlarms" to AlarmScheduler.canScheduleExact(context),
            "fullScreenAlarms" to fullScreenReady(context),
            "batteryOptimizationOff" to (context.getSystemService(Context.POWER_SERVICE) as PowerManager).isIgnoringBatteryOptimizations(context.packageName),
            "batteryManuallyConfirmed" to manualBattery,
            "warnings" to warnings,
        )
    }
}
