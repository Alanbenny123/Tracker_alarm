package com.trackeralarm.app

import android.location.Location

/** A location must be plausible and precise enough to support an arrival alert. */
internal object LocationEvidence {
    fun validCoordinates(location: Location): Boolean =
        location.latitude.isFinite() && location.longitude.isFinite() &&
            location.latitude in -90.0..90.0 && location.longitude in -180.0..180.0

    fun usableAccuracy(accuracy: Float, radius: Float): Boolean =
        accuracy.isFinite() && accuracy >= 0f && accuracy <= maxOf(100f, radius)

    fun usable(location: Location, radius: Float): Boolean =
        validCoordinates(location) && location.hasAccuracy() &&
            usableAccuracy(location.accuracy, radius)
}
