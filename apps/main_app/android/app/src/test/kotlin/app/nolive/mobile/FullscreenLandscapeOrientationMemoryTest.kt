package app.nolive.mobile

import android.content.pm.ActivityInfo
import android.view.Surface
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
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
                Surface.ROTATION_90,
            ),
        )
        assertEquals(
            ActivityInfo.SCREEN_ORIENTATION_REVERSE_LANDSCAPE,
            FullscreenLandscapeOrientationMemory.orientationForDisplayRotation(
                Surface.ROTATION_270,
            ),
        )
        assertEquals(
            ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE,
            FullscreenLandscapeOrientationMemory.orientationForDisplayRotation(
                Surface.ROTATION_0,
            ),
        )
    }

    @Test
    fun `sensor degrees only produce landscape sides near landscape zones`() {
        assertNull(FullscreenLandscapeOrientationMemory.orientationForSensorDegrees(10))
        assertEquals(
            ActivityInfo.SCREEN_ORIENTATION_REVERSE_LANDSCAPE,
            FullscreenLandscapeOrientationMemory.orientationForSensorDegrees(90),
        )
        assertEquals(
            ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE,
            FullscreenLandscapeOrientationMemory.orientationForSensorDegrees(270),
        )
    }

    @Test
    fun `gravity vector detects both landscape sides and ignores flat portrait states`() {
        assertEquals(
            ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE,
            FullscreenLandscapeOrientationMemory.orientationForGravityVector(
                8.6f,
                1.1f,
                1.0f,
            ),
        )
        assertEquals(
            ActivityInfo.SCREEN_ORIENTATION_REVERSE_LANDSCAPE,
            FullscreenLandscapeOrientationMemory.orientationForGravityVector(
                -8.6f,
                1.1f,
                1.0f,
            ),
        )
        assertNull(
            FullscreenLandscapeOrientationMemory.orientationForGravityVector(
                0.8f,
                9.3f,
                0.4f,
            ),
        )
        assertNull(
            FullscreenLandscapeOrientationMemory.orientationForGravityVector(
                0.4f,
                0.8f,
                9.4f,
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
}
