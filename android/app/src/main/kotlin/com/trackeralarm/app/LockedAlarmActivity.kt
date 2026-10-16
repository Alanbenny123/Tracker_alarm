package com.trackeralarm.app

import android.app.Activity
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

/** Alarm controls only: saved places and the rest of the app stay behind keyguard. */
class LockedAlarmActivity : Activity() {
    private val handler = Handler(Looper.getMainLooper())
    private lateinit var title: TextView
    private val refresh = object : Runnable {
        override fun run() {
            val alarm = MultiAlarmRuntime.ringing(this@LockedAlarmActivity)
            if (alarm == null) { finish(); return }
            title.text = "Destination alarm\n\n${alarm.name}"
            handler.postDelayed(this, 1000)
        }
    }

    @Suppress("DEPRECATION")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (MultiAlarmRuntime.ringing(this) == null) { finish(); return }
        if (Build.VERSION.SDK_INT >= 27) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else window.addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON)
        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(32, 64, 32, 32)
        }
        title = TextView(this).apply { textSize = 26f }
        layout.addView(title)
        fun button(label: String, action: (String) -> Unit) {
            layout.addView(Button(this).apply {
                text = label
                setOnClickListener {
                    MultiAlarmRuntime.ringing(this@LockedAlarmActivity)?.let { action(it.id) }
                    handler.removeCallbacks(refresh)
                    refresh.run()
                }
            })
        }
        button("Stop this alert") { MultiAlarmRuntime.dismiss(this, it) }
        button("Snooze 1 minute") { MultiAlarmRuntime.snooze(this, it, 1) }
        button("End this trip") { MultiAlarmRuntime.finish(this, it, "completed") }
        setContentView(android.widget.ScrollView(this).apply { addView(layout) })
        MultiAlarmRuntime.setPlaybackResumeRequired(this, false)
        MultiAlarmRuntime.refresh(this)
    }

    override fun onResume() {
        super.onResume()
        if (::title.isInitialized) refresh.run()
    }

    override fun onPause() {
        handler.removeCallbacks(refresh)
        super.onPause()
    }
}
