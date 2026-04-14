package app.nolive.mobile

import android.content.pm.ActivityInfo
import android.view.Surface
import kotlin.math.abs

internal object FullscreenLandscapeOrientationMemory {
    const val preferencesName = "nolive_android_playback"
    const val lastLandscapeSideKey = "last_fullscreen_landscape_side"
    const val lastLandscapeSideMappingMigrationKey =
        "last_fullscreen_landscape_side_mapping_migrated"
    const val defaultLandscapeOrientation = ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE

    private const val landscapeValue = "landscape"
    private const val reverseLandscapeValue = "reverse_landscape"

    fun encode(orientation: Int): String? {
        return when (orientation) {
            ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE -> landscapeValue
            ActivityInfo.SCREEN_ORIENTATION_REVERSE_LANDSCAPE -> reverseLandscapeValue
            else -> null
        }
    }

    fun decode(raw: String?): Int? {
        return when (raw) {
            landscapeValue -> ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
            reverseLandscapeValue -> ActivityInfo.SCREEN_ORIENTATION_REVERSE_LANDSCAPE
            else -> null
        }
    }

    fun resolveInitialOrientation(storedOrientation: Int?): Int {
        return storedOrientation ?: defaultLandscapeOrientation
    }

    fun orientationForSensorDegrees(sensorDegrees: Int): Int? {
        if (sensorDegrees < 0) {
            return null
        }
        return when (sensorDegrees) {
            in 60..120 -> ActivityInfo.SCREEN_ORIENTATION_REVERSE_LANDSCAPE
            in 240..300 -> ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
            else -> null
        }
    }

    fun orientationForGravityVector(
        x: Float,
        y: Float,
        z: Float,
    ): Int? {
        val absX = abs(x)
        if (abs(z) > 7.0f || absX < 5.5f || absX <= abs(y)) {
            return null
        }
        return if (x > 0f) {
            ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
        } else {
            ActivityInfo.SCREEN_ORIENTATION_REVERSE_LANDSCAPE
        }
    }

    fun orientationForDisplayRotation(displayRotation: Int): Int {
        return when (displayRotation) {
            Surface.ROTATION_90 -> ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
            Surface.ROTATION_270 -> ActivityInfo.SCREEN_ORIENTATION_REVERSE_LANDSCAPE
            else -> defaultLandscapeOrientation
        }
    }

    fun flipLandscapeOrientation(orientation: Int?): Int? {
        return when (orientation) {
            ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE ->
                ActivityInfo.SCREEN_ORIENTATION_REVERSE_LANDSCAPE
            ActivityInfo.SCREEN_ORIENTATION_REVERSE_LANDSCAPE ->
                ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
            else -> null
        }
    }
}
