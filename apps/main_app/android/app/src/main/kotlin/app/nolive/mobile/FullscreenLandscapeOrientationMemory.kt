package app.nolive.mobile

import android.content.pm.ActivityInfo
import android.content.res.Configuration
import android.view.Surface
import kotlin.math.abs

/**
 * Helpers for fullscreen long-edge landscape orientation (phones + ARC).
 *
 * Product (Chromebook ARC): shell is landscape-only — never portrait free-spin.
 * Phone: portrait-primary gravity/OrientationEventListener for L/R landscape
 * during horizontal fullscreen.
 */
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

    /**
     * Map [android.view.OrientationEventListener] degrees to fixed landscape sides.
     *
     * Degrees are relative to the device **natural** orientation (0 = natural).
     * - Portrait-primary (phones): landscape L/R near 90° / 270°.
     * - Landscape-primary (tablets / Chromebook): natural landscape near 0°,
     *   reverse near 180°. Short-edge tilts return null (no portrait follow).
     */
    fun orientationForSensorDegrees(
        sensorDegrees: Int,
        naturalLandscapePrimary: Boolean,
    ): Int? {
        if (sensorDegrees < 0) {
            return null
        }
        return if (naturalLandscapePrimary) {
            when (sensorDegrees) {
                in 0..35, in 325..359 -> ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
                in 145..215 -> ActivityInfo.SCREEN_ORIENTATION_REVERSE_LANDSCAPE
                else -> null
            }
        } else {
            when (sensorDegrees) {
                in 60..120 -> ActivityInfo.SCREEN_ORIENTATION_REVERSE_LANDSCAPE
                in 240..300 -> ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
                else -> null
            }
        }
    }

    /**
     * Gravity fallback when OrientationEventListener is unavailable.
     * Used only for long-edge landscape (never portrait).
     */
    fun orientationForGravityVector(
        x: Float,
        y: Float,
        z: Float,
        naturalLandscapePrimary: Boolean = false,
    ): Int? {
        if (abs(z) > 7.0f) {
            return null
        }
        return if (naturalLandscapePrimary) {
            val absY = abs(y)
            if (absY < 5.5f || absY <= abs(x)) {
                return null
            }
            if (y > 0f) {
                ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
            } else {
                ActivityInfo.SCREEN_ORIENTATION_REVERSE_LANDSCAPE
            }
        } else {
            val absX = abs(x)
            if (absX < 5.5f || absX <= abs(y)) {
                return null
            }
            if (x > 0f) {
                ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
            } else {
                ActivityInfo.SCREEN_ORIENTATION_REVERSE_LANDSCAPE
            }
        }
    }

    fun orientationForDisplayRotation(displayRotation: Int): Int {
        return when (displayRotation) {
            Surface.ROTATION_0,
            Surface.ROTATION_90,
            -> ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
            Surface.ROTATION_180,
            Surface.ROTATION_270,
            -> ActivityInfo.SCREEN_ORIENTATION_REVERSE_LANDSCAPE
            else -> defaultLandscapeOrientation
        }
    }

    /**
     * Infer natural landscape-primary before forcing a landscape lock.
     * Phone in landscape reports rotation 90/270 + LANDSCAPE config.
     * Chromebook / landscape tablets report rotation 0/180 + LANDSCAPE.
     */
    fun isNaturalLandscapePrimary(
        displayRotation: Int,
        configurationOrientation: Int,
    ): Boolean {
        return when (displayRotation) {
            Surface.ROTATION_0,
            Surface.ROTATION_180,
            -> configurationOrientation == Configuration.ORIENTATION_LANDSCAPE
            Surface.ROTATION_90,
            Surface.ROTATION_270,
            -> configurationOrientation == Configuration.ORIENTATION_PORTRAIT
            else -> false
        }
    }

    /**
     * ChromeOS ARC detection for orientation + decode gates.
     * Prefer fingerprint "cheets"; also accept ChromeOS R{milestone}-{build}.
     */
    fun looksLikeArcChromeOsDevice(
        fingerprint: String,
        display: String = "",
        incremental: String = "",
    ): Boolean {
        val fp = fingerprint.lowercase()
        if (fp.contains("cheets")) {
            return true
        }
        val arcVersion = Regex("""R\d{2,4}-\d+""")
        return arcVersion.containsMatchIn(display) ||
            arcVersion.containsMatchIn(incremental)
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

    /**
     * Resolve a **fixed** orientation pin for the current display pose.
     *
     * Used by chrome freeze when there is no landscape session (e.g. phone
     * vertical hard-portrait fullscreen). Must preserve portrait — never force
     * landscape just because a freeze was requested.
     */
    fun fixedOrientationForCurrentPose(
        displayRotation: Int,
        configurationOrientation: Int,
    ): Int {
        return when (configurationOrientation) {
            Configuration.ORIENTATION_PORTRAIT -> when (displayRotation) {
                Surface.ROTATION_180 -> ActivityInfo.SCREEN_ORIENTATION_REVERSE_PORTRAIT
                else -> ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
            }
            else -> orientationForDisplayRotation(displayRotation)
        }
    }

    /**
     * What [MainActivity.onResume] should do for orientation.
     *
     * Frozen chrome lock must keep its pin (including ARC) — never re-arm
     * SENSOR_LANDSCAPE while frozen.
     */
    fun resolveResumeOrientationAction(
        landscapeSessionFrozen: Boolean,
        landscapeSessionActiveOrientation: Int?,
        chromeLockFrozenPin: Int?,
        hasLandscapeSession: Boolean,
        isArcChromeOs: Boolean,
    ): ResumeOrientationAction {
        if (landscapeSessionFrozen) {
            val pin = landscapeSessionActiveOrientation
                ?: chromeLockFrozenPin
                ?: return ResumeOrientationAction.None
            return ResumeOrientationAction.KeepFrozen(pin)
        }
        val freezePin = chromeLockFrozenPin
        if (freezePin != null) {
            return ResumeOrientationAction.KeepFrozen(freezePin)
        }
        if (hasLandscapeSession) {
            return ResumeOrientationAction.ResumeLandscapeSensors
        }
        if (isArcChromeOs) {
            return ResumeOrientationAction.StartArcLandscapeOnly
        }
        return ResumeOrientationAction.None
    }
}

/** Decision for [MainActivity.onResume] orientation handling. */
internal sealed class ResumeOrientationAction {
    data class KeepFrozen(val pin: Int) : ResumeOrientationAction()
    data object ResumeLandscapeSensors : ResumeOrientationAction()
    data object StartArcLandscapeOnly : ResumeOrientationAction()
    data object None : ResumeOrientationAction()
}
