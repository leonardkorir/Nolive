package app.nolive.mobile

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AndroidPlaybackMethodContractTest {
    @Test
    fun `playback method contract exposes expected channel methods`() {
        val expected = setOf(
            "isPictureInPictureSupported",
            "isInPictureInPictureMode",
            "enterPictureInPicture",
            "getMediaVolume",
            "setMediaVolume",
            "lockPortrait",
            "lockLandscape",
            "lockPortraitFullscreen",
            "freezeFullscreenOrientation",
            "prepareForPictureInPicture",
        )

        assertEquals(expected, AndroidPlaybackMethodContract.methodNames)
    }

    @Test
    fun `playback method constants stay unique`() {
        assertTrue(
            "Method channel names must be unique",
            AndroidPlaybackMethodContract.methodNames.size == 10,
        )
    }
}
