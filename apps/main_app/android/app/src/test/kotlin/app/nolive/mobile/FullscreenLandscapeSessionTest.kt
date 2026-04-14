package app.nolive.mobile

import android.content.pm.ActivityInfo
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class FullscreenLandscapeSessionTest {
    @Test
    fun `entry keeps fixed orientation as active landscape side`() {
        val session = FullscreenLandscapeSession(
            initialOrientation = ActivityInfo.SCREEN_ORIENTATION_REVERSE_LANDSCAPE,
        )

        assertEquals(
            ActivityInfo.SCREEN_ORIENTATION_REVERSE_LANDSCAPE,
            session.requestedOrientationForEntry(),
        )
        assertEquals(
            ActivityInfo.SCREEN_ORIENTATION_REVERSE_LANDSCAPE,
            session.requestedOrientationForActiveLock(),
        )
        assertEquals(
            ActivityInfo.SCREEN_ORIENTATION_REVERSE_LANDSCAPE,
            session.activeOrientation,
        )
    }

    @Test
    fun `user adjustment unlock is only scheduled once until it runs or is canceled`() {
        val session = FullscreenLandscapeSession(
            initialOrientation = ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE,
        )

        assertTrue(session.shouldScheduleAdjustmentUnlock())

        val scheduled = session.markAdjustmentUnlockScheduled()

        assertFalse(scheduled.shouldScheduleAdjustmentUnlock())
        assertEquals(scheduled, scheduled.markAdjustmentUnlockScheduled())

        val retried = scheduled.markAdjustmentUnlockCanceled()

        assertTrue(retried.shouldScheduleAdjustmentUnlock())

        val unlocked = retried.markAdjustmentUnlocked()

        assertFalse(unlocked.shouldScheduleAdjustmentUnlock())
        assertEquals(unlocked, unlocked.markAdjustmentUnlockCanceled())
    }

    @Test
    fun `memory capture is only scheduled once until it is canceled or completed`() {
        val session = FullscreenLandscapeSession(
            initialOrientation = ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE,
        )

        assertTrue(session.shouldScheduleMemoryCapture())

        val scheduled = session.markMemoryCaptureScheduled()

        assertFalse(scheduled.shouldScheduleMemoryCapture())
        assertEquals(scheduled, scheduled.markMemoryCaptureScheduled())

        val retried = scheduled.markMemoryCaptureCanceled()

        assertTrue(retried.shouldScheduleMemoryCapture())
    }

    @Test
    fun `completed memory capture stays terminal for the fullscreen session`() {
        val captured = FullscreenLandscapeSession(
            initialOrientation = ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE,
        ).markMemoryCaptureScheduled()
            .markMemoryCaptured()

        assertFalse(captured.shouldScheduleMemoryCapture())
        assertEquals(captured, captured.markMemoryCaptureScheduled())
        assertEquals(captured, captured.markMemoryCaptureCanceled())
    }

    @Test
    fun `active lock follows latest user-selected landscape side after unlock`() {
        val unlocked = FullscreenLandscapeSession(
            initialOrientation = ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE,
        ).markAdjustmentUnlocked()
            .updateActiveOrientation(ActivityInfo.SCREEN_ORIENTATION_REVERSE_LANDSCAPE)

        assertEquals(
            ActivityInfo.SCREEN_ORIENTATION_REVERSE_LANDSCAPE,
            unlocked.requestedOrientationForActiveLock(),
        )
    }

    @Test
    fun `suspended session pauses scheduling until resumed`() {
        val session = FullscreenLandscapeSession(
            initialOrientation = ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE,
        ).markAdjustmentUnlocked()
            .markSuspended()

        assertFalse(session.shouldScheduleAdjustmentUnlock())
        assertFalse(session.shouldScheduleMemoryCapture())
        assertFalse(session.shouldTrackSensors())

        val resumed = session.markResumed()

        assertEquals(
            ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE,
            resumed.requestedOrientationForActiveLock(),
        )
        assertTrue(resumed.shouldScheduleMemoryCapture())
        assertTrue(resumed.shouldTrackSensors())
    }

    @Test
    fun `update active orientation ignores non-landscape requests`() {
        val session = FullscreenLandscapeSession(
            initialOrientation = ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE,
        )

        assertEquals(
            session,
            session.updateActiveOrientation(ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED),
        )
    }
}
