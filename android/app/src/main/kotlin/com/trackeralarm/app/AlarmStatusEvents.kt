package com.trackeralarm.app

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

/** One engine-owned subscription, coalescing writes and GPS/health changes. */
object AlarmStatusEvents : EventChannel.StreamHandler {
    private val handler = Handler(Looper.getMainLooper())
    @Volatile private var sink: EventChannel.EventSink? = null
    private val deliver = Runnable { sink?.success(null) }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        handler.removeCallbacks(deliver)
        sink = events
        events.success(null) // Resuming/reattaching always requests a fresh snapshot.
    }

    override fun onCancel(arguments: Any?) {
        sink = null
        handler.removeCallbacks(deliver)
    }

    fun changed() {
        if (sink == null) return
        handler.removeCallbacks(deliver)
        handler.postDelayed(deliver, 200L)
    }
}
