package com.trackeralarm.app

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.Build
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager

/** Shared playback for alarms started by the tracker or by an Android event. */
class AlarmSoundPlayer(private val context: Context) {
    private var player: MediaPlayer? = null
    private var vibrator: Vibrator? = null

    @Suppress("DEPRECATION")
    fun start(sound: String, vibration: Boolean) {
        if (player != null) return
        val resId = when (sound) {
            "Bell" -> R.raw.bell
            "Digital" -> R.raw.digital
            "Beep" -> R.raw.beep
            "Wake up" -> R.raw.wakeup
            else -> 0
        }
        player = try {
            createPlayer(resId)
        } catch (_: Exception) {
            try { createPlayer(R.raw.beep) } catch (_: Exception) { null }
        }
        if (vibration) {
            try {
                vibrator = getVibratorCompat()
                val pattern = longArrayOf(0, 500, 350, 500, 700)
                if (Build.VERSION.SDK_INT >= 26) {
                    vibrator?.vibrate(VibrationEffect.createWaveform(pattern, 1))
                } else {
                    vibrator?.vibrate(pattern, 1)
                }
            } catch (_: Exception) { vibrator = null }
        }
    }

    private fun createPlayer(resId: Int): MediaPlayer {
        val player = MediaPlayer()
        try {
            // Keep looping alarm audio playing when the display is off.
            player.setWakeMode(context.applicationContext, PowerManager.PARTIAL_WAKE_LOCK)
            player.setAudioAttributes(AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build())
            val uri = if (resId == 0) RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION) else null
            if (resId != 0 || uri == null) {
                context.resources.openRawResourceFd(if (resId != 0) resId else R.raw.beep).use { descriptor ->
                    player.setDataSource(descriptor.fileDescriptor, descriptor.startOffset, descriptor.length)
                }
            } else player.setDataSource(context, uri)
            player.isLooping = true
            player.prepare()
            player.start()
            return player
        } catch (e: Exception) {
            player.release()
            throw e
        }
    }

    @Suppress("DEPRECATION")
    private fun getVibratorCompat(): Vibrator = if (Build.VERSION.SDK_INT >= 31)
        (context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
    else context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator

    fun stop() {
        try { player?.stop() } catch (_: Exception) { }
        player?.release()
        player = null
        vibrator?.cancel()
        vibrator = null
    }
}
