package com.trackeralarm.app

import android.app.Activity
import android.app.Notification
import android.app.PendingIntent
import android.app.Service
import android.content.res.ColorStateList
import android.graphics.Color
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

/** An isolated, bounded preview: never registers or completes a destination. */
class TestAlarmService : Service() {
    companion object {
        const val NOTIFICATION_ID = 301
        const val COUNTDOWN_ID = 302
        private var running: TestAlarmService? = null
        fun isRinging() = running?.ringing == true
        fun stop(context: Context) {
            running?.finishTest()
            context.stopService(Intent(context, TestAlarmService::class.java))
        }
    }

    private val handler = Handler(Looper.getMainLooper())
    private val sound by lazy { AlarmSoundPlayer(this) }
    private val wakeLock by lazy {
        (getSystemService(Context.POWER_SERVICE) as PowerManager)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "$packageName:alarm-test")
            .apply { setReferenceCounted(false) }
    }
    private var ringing = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent == null || MultiAlarmRuntime.ringing(this) != null) {
            stopSelf(); return START_NOT_STICKY
        }
        running = this
        handler.removeCallbacksAndMessages(null)
        sound.stop()
        ringing = false
        wakeLock.acquire(20_000L)
        try {
            val notification = notification(false)
            if (Build.VERSION.SDK_INT >= 29) startForeground(COUNTDOWN_ID, notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
            else startForeground(COUNTDOWN_ID, notification)
        } catch (_: Exception) { finishTest(); return START_NOT_STICKY }
        val selectedSound = intent.getStringExtra("sound") ?: "Default alarm"
        val vibration = intent.getBooleanExtra("vibration", true)
        handler.postDelayed({
            if (MultiAlarmRuntime.ringing(this) != null) { finishTest(); return@postDelayed }
            ringing = true
            sound.start(selectedSound, vibration)
            val alert = notification(true)
            if (Build.VERSION.SDK_INT >= 29) startForeground(NOTIFICATION_ID, alert,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
            else startForeground(NOTIFICATION_ID, alert)
            AlarmNotifications.notifications(this).cancel(COUNTDOWN_ID)
        }, 5_000L)
        handler.postDelayed({ finishTest() }, 15_000L)
        return START_NOT_STICKY
    }

    @Suppress("DEPRECATION")
    private fun notification(ringing: Boolean): Notification {
        val stop = PendingIntent.getBroadcast(this, 71, Intent(this, TestAlarmReceiver::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val open = PendingIntent.getActivity(this, 72, Intent(this, TestAlarmActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this,
            if (ringing) AlarmNotifications.CHANNEL_ALARM else AlarmNotifications.CHANNEL_TRACKING)
            else Notification.Builder(this)
        builder.setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle(if (ringing) "Test alarm" else "Test alarm in 5 seconds")
            .setContentText(if (ringing) "Stops automatically after 10 seconds" else "Lock your phone to check its alarm screen")
            .setSound(null).setVibrate(null).setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_ALARM).setPriority(Notification.PRIORITY_MAX)
            .setVisibility(Notification.VISIBILITY_PUBLIC).setContentIntent(open)
            .addAction(Notification.Action.Builder(android.R.drawable.ic_media_pause, "Stop test", stop).build())
            .setOngoing(true)
        if (ringing) builder.setFullScreenIntent(open, true)
        return builder.build()
    }

    private fun finishTest() {
        handler.removeCallbacksAndMessages(null)
        sound.stop()
        ringing = false
        if (wakeLock.isHeld) wakeLock.release()
        AlarmNotifications.notifications(this).cancel(NOTIFICATION_ID)
        AlarmNotifications.notifications(this).cancel(COUNTDOWN_ID)
        stopForeground(STOP_FOREGROUND_REMOVE)
        if (running === this) running = null
        stopSelf()
    }

    override fun onDestroy() {
        finishTest()
        super.onDestroy()
    }
}

class TestAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) { TestAlarmService.stop(context) }
}

class TestAlarmActivity : Activity() {
    private val handler = Handler(Looper.getMainLooper())
    private val check = object : Runnable {
        override fun run() {
            if (!TestAlarmService.isRinging()) finish()
            else handler.postDelayed(this, 500L)
        }
    }

    @Suppress("DEPRECATION")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (!TestAlarmService.isRinging()) { finish(); return }
        if (Build.VERSION.SDK_INT >= 27) {
            setShowWhenLocked(true); setTurnScreenOn(true)
        } else window.addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON)
        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL; setPadding(32, 64, 32, 32)
            setBackgroundColor(Color.BLACK)
            addView(TextView(this@TestAlarmActivity).apply {
                text = "Test alarm\n\nThis is a preview. Your destination alarms are kept."
                textSize = 26f
                setTextColor(Color.WHITE)
            })
            addView(Button(this@TestAlarmActivity).apply {
                text = "Stop test"
                setTextColor(Color.BLACK)
                backgroundTintList = ColorStateList.valueOf(Color.WHITE)
                setOnClickListener { TestAlarmService.stop(this@TestAlarmActivity); finish() }
            })
        }
        setContentView(android.widget.ScrollView(this).apply {
            setBackgroundColor(Color.BLACK)
            addView(layout)
        })
    }
    override fun onResume() { super.onResume(); if (!isFinishing) check.run() }
    override fun onPause() { handler.removeCallbacks(check); super.onPause() }
}
