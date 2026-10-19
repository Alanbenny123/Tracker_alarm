package com.trackeralarm.app

import android.location.Location
import kotlin.math.*

/** First intersection of a short, credible GPS segment with an alert circle. */
object DestinationCrossing {
    fun fraction(previous: Location?, current: Location, latitude: Double,
                 longitude: Double, radius: Float): Double? {
        if (previous == null || !LocationEvidence.usable(previous, radius) ||
            !LocationEvidence.usable(current, radius)) return null
        val seconds = if (previous.elapsedRealtimeNanos > 0 && current.elapsedRealtimeNanos > 0)
            (current.elapsedRealtimeNanos - previous.elapsedRealtimeNanos) / 1e9
            else (current.time - previous.time) / 1000.0
        if (seconds <= 0 || seconds > 15 || previous.distanceTo(current) / seconds > 100) return null
        fun point(location: Location): Pair<Double, Double> {
            val delta = ((location.longitude - longitude + 540) % 360) - 180
            return delta * 111_195 * cos(Math.toRadians(latitude)) to
                (location.latitude - latitude) * 111_195
        }
        val (x, y) = point(previous)
        val (endX, endY) = point(current)
        val dx = endX - x
        val dy = endY - y
        val a = dx * dx + dy * dy
        val c = x * x + y * y - radius * radius
        if (c <= 0 || a < 0.001) return null
        val b = 2 * (x * dx + y * dy)
        val discriminant = b * b - 4 * a * c
        if (discriminant < 0) return null
        val first = (-b - sqrt(discriminant)) / (2 * a)
        return first.takeIf { it in 0.0..1.0 }
    }
}
