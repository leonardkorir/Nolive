package app.nolive.mobile

import android.content.pm.ActivityInfo
import android.content.res.Configuration
import android.view.Surface
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class FullscreenLandscapeOrientationMemoryTest {
    @Test
    fun `decode returns null for unknown raw value`() {
        assertNull(FullscreenLandscapeOrientationMemory.decode("unknown"))
        assertNull(FullscreenLandscapeOrientationMemory.decode(null))
    }

    @Test
    fun `encode and decode preserve both landscape sides`() {
        val landscape = ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
        val reverseLandscape = ActivityInfo.SCREEN_ORIENTATION_REVERSE_LANDSCAPE

        assertEquals(
            landscape,
            FullscreenLandscapeOrientationMemory.decode(
                FullscreenLandscapeOrientationMemory.encode(landscape),
            ),
        )
        assertEquals(
            reverseLandscape,
            FullscreenLandscapeOrientationMemory.decode(
                FullscreenLandscapeOrientationMemory.encode(reverseLandscape),
            ),
        )
    }

    @Test
    fun `resolve initial orientation prefers stored side when available`() {
        val stored = ActivityInfo.SCREEN_ORIENTATION_REVERSE_LANDSCAPE

        val actual = FullscreenLandscapeOrientationMemory.resolveInitialOrientation(
            storedOrientation = stored,
        )

        assertEquals(stored, actual)
    }

    @Test
    fun `resolve initial orientation falls back to default landscape side`() {
        assertEquals(
            ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE,
            FullscreenLandscapeOrientationMemory.resolveInitialOrientation(
                storedOrientation = null,
            ),
        )
    }

    @Test
    fun `display rotation mapping keeps both fixed landscape sides explicit`() {
        assertEquals(
            ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE,
            FullscreenLandscapeOrientationMemory.orientationForDisplayRotation(
                Surface.ROTATION_0,
            ),
        )
        assertEquals(
            ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE,
            FullscreenLandscapeOrientationMemory.orientationForDisplayRotation(
                Surface.ROTATION_90,
            ),
        )
        assertEquals(
            ActivityInfo.SCREEN_ORIENTATION_REVERSE_LANDSCAPE,
            FullscreenLandscapeOrientationMemory.orientationForDisplayRotation(
                Surface.ROTATION_180,
            ),
        )
        assertEquals(
            ActivityInfo.SCREEN_ORIENTATION_REVERSE_LANDSCAPE,
            FullscreenLandscapeOrientationMemory.orientationForDisplayRotation(
                Surface.ROTATION_270,
            ),
        )
    }

    @Test
    fun `portrait-primary sensor degrees only produce landscape near 90 and 270`() {
        assertNull(
            FullscreenLandscapeOrientationMemory.orientationForSensorDegrees(
                sensorDegrees = 10,
                naturalLandscapePrimary = false,
            ),
        )
        assertEquals(
            ActivityInfo.SCREEN_ORIENTATION_REVERSE_LANDSCAPE,
            FullscreenLandscapeOrientationMemory.orientationForSensorDegrees(
                sensorDegrees = 90,
                naturalLandscapePrimary = false,
            ),
        )
        assertEquals(
            ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE,
            FullscreenLandscapeOrientationMemory.orientationForSensorDegrees(
                sensorDegrees = 270,
                naturalLandscapePrimary = false,
            ),
        )
    }

    @Test
    fun `landscape-primary sensor degrees map long-edge 0 and 180 only`() {
        assertEquals(
            ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE,
            FullscreenLandscapeOrientationMemory.orientationForSensorDegrees(
                sensorDegrees = 5,
                naturalLandscapePrimary = true,
            ),
        )
        assertEquals(
            ActivityInfo.SCREEN_ORIENTATION_REVERSE_LANDSCAPE,
            FullscreenLandscapeOrientationMemory.orientationForSensorDegrees(
                sensorDegrees = 180,
                naturalLandscapePrimary = true,
            ),
        )
        // Short-edge tilts must not rotate (portrait-ish holds).
        assertNull(
            FullscreenLandscapeOrientationMemory.orientationForSensorDegrees(
                sensorDegrees = 90,
                naturalLandscapePrimary = true,
            ),
        )
        assertNull(
            FullscreenLandscapeOrientationMemory.orientationForSensorDegrees(
                sensorDegrees = 270,
                naturalLandscapePrimary = true,
            ),
        )
    }

    @Test
    fun `gravity vector respects natural landscape primary axis`() {
        assertEquals(
            ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE,
            FullscreenLandscapeOrientationMemory.orientationForGravityVector(
                8.6f,
                1.1f,
                1.0f,
                naturalLandscapePrimary = false,
            ),
        )
        assertNull(
            FullscreenLandscapeOrientationMemory.orientationForGravityVector(
                0.8f,
                9.3f,
                0.4f,
                naturalLandscapePrimary = false,
            ),
        )
        // Landscape-primary: Y-dominant long edge.
        assertEquals(
            ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE,
            FullscreenLandscapeOrientationMemory.orientationForGravityVector(
                1.1f,
                8.6f,
                1.0f,
                naturalLandscapePrimary = true,
            ),
        )
        assertNull(
            FullscreenLandscapeOrientationMemory.orientationForGravityVector(
                9.3f,
                0.8f,
                0.4f,
                naturalLandscapePrimary = true,
            ),
        )
    }

    @Test
    fun `natural landscape primary detection matches phone vs chromebook poses`() {
        // Chromebook natural landscape at rotation 0.
        assertTrue(
            FullscreenLandscapeOrientationMemory.isNaturalLandscapePrimary(
                displayRotation = Surface.ROTATION_0,
                configurationOrientation = Configuration.ORIENTATION_LANDSCAPE,
            ),
        )
        // Phone forced landscape usually reports rotation 90.
        assertFalse(
            FullscreenLandscapeOrientationMemory.isNaturalLandscapePrimary(
                displayRotation = Surface.ROTATION_90,
                configurationOrientation = Configuration.ORIENTATION_LANDSCAPE,
            ),
        )
        // Phone natural portrait.
        assertFalse(
            FullscreenLandscapeOrientationMemory.isNaturalLandscapePrimary(
                displayRotation = Surface.ROTATION_0,
                configurationOrientation = Configuration.ORIENTATION_PORTRAIT,
            ),
        )
    }

    @Test
    fun `arc chromeos detection matches cheets fingerprints and R-build strings`() {
        assertTrue(
            FullscreenLandscapeOrientationMemory.looksLikeArcChromeOsDevice(
                fingerprint = "google/geralt/geralt_cheets:13/R149-16667.61.0/15578697:user/release-keys",
            ),
        )
        assertFalse(
            FullscreenLandscapeOrientationMemory.looksLikeArcChromeOsDevice(
                fingerprint = "Sony/SO-51A/SO-51A:12/58.2.A.7.93/058002A007009304241871766:user/release-keys",
                display = "58.2.A.7.93",
                incremental = "058002A007009304241871766",
            ),
        )
    }

    @Test
    fun `flip landscape orientation swaps both fixed landscape sides`() {
        assertEquals(
            ActivityInfo.SCREEN_ORIENTATION_REVERSE_LANDSCAPE,
            FullscreenLandscapeOrientationMemory.flipLandscapeOrientation(
                ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE,
            ),
        )
        assertEquals(
            ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE,
            FullscreenLandscapeOrientationMemory.flipLandscapeOrientation(
                ActivityInfo.SCREEN_ORIENTATION_REVERSE_LANDSCAPE,
            ),
        )
        assertNull(
            FullscreenLandscapeOrientationMemory.flipLandscapeOrientation(
                ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED,
            ),
        )
    }

    @Test
    fun `fixed orientation for current pose preserves portrait hard fullscreen`() {
        // Phone vertical hard-portrait: freeze must pin portrait, not landscape.
        assertEquals(
            ActivityInfo.SCREEN_ORIENTATION_PORTRAIT,
            FullscreenLandscapeOrientationMemory.fixedOrientationForCurrentPose(
                displayRotation = Surface.ROTATION_0,
                configurationOrientation = Configuration.ORIENTATION_PORTRAIT,
            ),
        )
        assertEquals(
            ActivityInfo.SCREEN_ORIENTATION_REVERSE_PORTRAIT,
            FullscreenLandscapeOrientationMemory.fixedOrientationForCurrentPose(
                displayRotation = Surface.ROTATION_180,
                configurationOrientation = Configuration.ORIENTATION_PORTRAIT,
            ),
        )
    }

    @Test
    fun `fixed orientation for current pose pins long-edge landscape sides`() {
        assertEquals(
            ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE,
            FullscreenLandscapeOrientationMemory.fixedOrientationForCurrentPose(
                displayRotation = Surface.ROTATION_90,
                configurationOrientation = Configuration.ORIENTATION_LANDSCAPE,
            ),
        )
        assertEquals(
            ActivityInfo.SCREEN_ORIENTATION_REVERSE_LANDSCAPE,
            FullscreenLandscapeOrientationMemory.fixedOrientationForCurrentPose(
                displayRotation = Surface.ROTATION_270,
                configurationOrientation = Configuration.ORIENTATION_LANDSCAPE,
            ),
        )
    }

    @Test
    fun `resume keeps frozen landscape session pin on ARC instead of sensor landscape`() {
        val action = FullscreenLandscapeOrientationMemory.resolveResumeOrientationAction(
            landscapeSessionFrozen = true,
            landscapeSessionActiveOrientation =
                ActivityInfo.SCREEN_ORIENTATION_REVERSE_LANDSCAPE,
            chromeLockFrozenPin = ActivityInfo.SCREEN_ORIENTATION_REVERSE_LANDSCAPE,
            hasLandscapeSession = true,
            isArcChromeOs = true,
        )
        assertEquals(
            ResumeOrientationAction.KeepFrozen(
                ActivityInfo.SCREEN_ORIENTATION_REVERSE_LANDSCAPE,
            ),
            action,
        )
    }

    @Test
    fun `resume keeps portrait chrome freeze pin without landscape session`() {
        val action = FullscreenLandscapeOrientationMemory.resolveResumeOrientationAction(
            landscapeSessionFrozen = false,
            landscapeSessionActiveOrientation = null,
            chromeLockFrozenPin = ActivityInfo.SCREEN_ORIENTATION_PORTRAIT,
            hasLandscapeSession = false,
            isArcChromeOs = false,
        )
        assertEquals(
            ResumeOrientationAction.KeepFrozen(ActivityInfo.SCREEN_ORIENTATION_PORTRAIT),
            action,
        )
    }

    @Test
    fun `resume re-arms ARC landscape-only only when not frozen`() {
        val action = FullscreenLandscapeOrientationMemory.resolveResumeOrientationAction(
            landscapeSessionFrozen = false,
            landscapeSessionActiveOrientation = null,
            chromeLockFrozenPin = null,
            hasLandscapeSession = false,
            isArcChromeOs = true,
        )
        assertEquals(ResumeOrientationAction.StartArcLandscapeOnly, action)
    }

    @Test
    fun `resume restores landscape sensors for unfrozen fullscreen session`() {
        val action = FullscreenLandscapeOrientationMemory.resolveResumeOrientationAction(
            landscapeSessionFrozen = false,
            landscapeSessionActiveOrientation = ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE,
            chromeLockFrozenPin = null,
            hasLandscapeSession = true,
            isArcChromeOs = true,
        )
        assertEquals(ResumeOrientationAction.ResumeLandscapeSensors, action)
    }
}
