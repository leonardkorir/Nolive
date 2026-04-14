package app.nolive.mobile

import android.content.pm.ActivityInfo

internal data class FullscreenLandscapeSession(
    val initialOrientation: Int,
    val activeOrientation: Int = initialOrientation,
    val adjustmentUnlockScheduled: Boolean = false,
    val adjustmentUnlocked: Boolean = false,
    val memoryCaptureScheduled: Boolean = false,
    val memoryCaptured: Boolean = false,
    val suspended: Boolean = false,
) {
    fun requestedOrientationForEntry(): Int {
        return initialOrientation
    }

    fun requestedOrientationForActiveLock(): Int {
        return activeOrientation
    }

    fun shouldTrackSensors(): Boolean {
        return !suspended
    }

    fun updateActiveOrientation(orientation: Int): FullscreenLandscapeSession {
        return when (orientation) {
            ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE,
            ActivityInfo.SCREEN_ORIENTATION_REVERSE_LANDSCAPE -> copy(activeOrientation = orientation)
            else -> this
        }
    }

    fun shouldScheduleAdjustmentUnlock(): Boolean {
        return !suspended && !adjustmentUnlockScheduled && !adjustmentUnlocked
    }

    fun markAdjustmentUnlockScheduled(): FullscreenLandscapeSession {
        return if (shouldScheduleAdjustmentUnlock()) {
            copy(adjustmentUnlockScheduled = true)
        } else {
            this
        }
    }

    fun markAdjustmentUnlockCanceled(): FullscreenLandscapeSession {
        return if (adjustmentUnlockScheduled && !adjustmentUnlocked) {
            copy(adjustmentUnlockScheduled = false)
        } else {
            this
        }
    }

    fun markAdjustmentUnlocked(): FullscreenLandscapeSession {
        return copy(
            adjustmentUnlockScheduled = false,
            adjustmentUnlocked = true,
            suspended = false,
        )
    }

    fun shouldScheduleMemoryCapture(): Boolean {
        return !suspended && !memoryCaptureScheduled && !memoryCaptured
    }

    fun markMemoryCaptureScheduled(): FullscreenLandscapeSession {
        return if (shouldScheduleMemoryCapture()) {
            copy(memoryCaptureScheduled = true)
        } else {
            this
        }
    }

    fun markMemoryCaptureCanceled(): FullscreenLandscapeSession {
        return if (memoryCaptureScheduled) {
            copy(memoryCaptureScheduled = false)
        } else {
            this
        }
    }

    fun markMemoryCaptured(): FullscreenLandscapeSession {
        return copy(
            memoryCaptureScheduled = false,
            memoryCaptured = true,
        )
    }

    fun markSuspended(): FullscreenLandscapeSession {
        return copy(
            adjustmentUnlockScheduled = false,
            memoryCaptureScheduled = false,
            suspended = true,
        )
    }

    fun markResumed(): FullscreenLandscapeSession {
        return if (suspended) {
            copy(suspended = false)
        } else {
            this
        }
    }
}
