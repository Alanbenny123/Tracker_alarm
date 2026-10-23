package com.trackeralarm.app

import com.google.android.gms.maps.model.LatLng
import com.google.android.libraries.places.api.Places
import com.google.android.libraries.places.api.model.CircularBounds
import com.google.android.libraries.places.api.model.Place
import com.google.android.libraries.places.api.net.SearchByTextRequest
import com.google.android.libraries.places.api.net.SearchNearbyRequest
import com.google.android.libraries.places.api.net.PlacesClient
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** Searches only on an explicit user action; the Flutter side handles caching and retries. */
class GooglePlacesBridge(private val activity: FlutterActivity, private val messenger: BinaryMessenger) {
    private val fields = listOf(Place.Field.ID, Place.Field.DISPLAY_NAME,
        Place.Field.LOCATION, Place.Field.FORMATTED_ADDRESS)
    private val lastSearchAt = mutableMapOf<String, Long>()
    private var placesClient: PlacesClient? = null

    fun register() {
        MethodChannel(messenger, "tracker_alarm/places").setMethodCallHandler { call, result ->
            val key = activity.getString(R.string.google_maps_api_key)
            if (key.isBlank()) {
                result.error("configuration", "Google Maps API key is missing. Add it to android/local.properties.", null)
                return@setMethodCallHandler
            }
            if (call.method != "search" && call.method != "nearbyStops") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val now = android.os.SystemClock.elapsedRealtime()
            if (now - (lastSearchAt[call.method] ?: 0L) < 1200) {
                result.error("rate_limit", "Please wait a moment before searching again.", null)
                return@setMethodCallHandler
            }
            lastSearchAt[call.method] = now
            try {
                if (!Places.isInitialized()) Places.initializeWithNewPlacesApiEnabled(activity.applicationContext, key)
                val client = placesClient ?: Places.createClient(activity).also { placesClient = it }
                if (call.method == "search") {
                    val query = call.argument<String>("query")?.trim().orEmpty()
                    if (query.length < 3) {
                        result.success(emptyList<Map<String, Any>>())
                        return@setMethodCallHandler
                    }
                    val builder = SearchByTextRequest.builder(query, fields)
                        .setMaxResultCount(10)
                    val latitude = call.argument<Double>("latitude")
                    val longitude = call.argument<Double>("longitude")
                    if (latitude != null && longitude != null && latitude.isFinite() &&
                        longitude.isFinite() && latitude in -90.0..90.0 &&
                        longitude in -180.0..180.0) {
                        // A preference, not a restriction: explicit searches for
                        // distant places can still return their matching result.
                        builder.setLocationBias(CircularBounds.newInstance(
                            LatLng(latitude, longitude), 50_000.0))
                    }
                    val request = builder.build()
                    client.searchByText(request)
                        .addOnSuccessListener { response -> result.success(response.places.mapNotNull(::toMap)) }
                        .addOnFailureListener { result.error("places", it.message ?: "Place search failed.", null) }
                } else {
                    val latitude = call.argument<Double>("latitude")
                    val longitude = call.argument<Double>("longitude")
                    val mode = call.argument<String>("mode")
                    if (latitude == null || longitude == null || !latitude.isFinite() || !longitude.isFinite() ||
                        latitude !in -90.0..90.0 || longitude !in -180.0..180.0) {
                        result.error("arguments", "Invalid search center.", null)
                        return@setMethodCallHandler
                    }
                    val types = when (mode) {
                        "bus" -> listOf("bus_stop", "bus_station")
                        "metro" -> listOf("subway_station", "light_rail_station")
                        "railway" -> listOf("train_station")
                        else -> emptyList()
                    }
                    if (types.isEmpty()) {
                        result.success(emptyList<Map<String, Any>>())
                        return@setMethodCallHandler
                    }
                    val radius = 5000.0
                    val request = SearchNearbyRequest.builder(
                        CircularBounds.newInstance(LatLng(latitude, longitude), radius), fields)
                        .setIncludedTypes(types)
                        .setMaxResultCount(20)
                        .setRankPreference(SearchNearbyRequest.RankPreference.DISTANCE)
                        .build()
                    client.searchNearby(request)
                        .addOnSuccessListener { response -> result.success(response.places.mapNotNull(::toMap)) }
                        .addOnFailureListener { result.error("places", it.message ?: "Stop search failed.", null) }
                }
            } catch (e: Exception) {
                result.error("places", e.message ?: "Google Places is unavailable.", null)
            }
        }
    }

    private fun toMap(place: Place): Map<String, Any>? {
        val location = place.location ?: return null
        return mapOf(
            "id" to (place.id ?: ""),
            "name" to (place.displayName ?: "Selected place"),
            "address" to (place.formattedAddress ?: ""),
            "latitude" to location.latitude,
            "longitude" to location.longitude,
        )
    }
}
