package app.nolive.mobile

internal object AndroidPlaybackMethodContract {
    const val isPictureInPictureSupported = "isPictureInPictureSupported"
    const val isInPictureInPictureMode = "isInPictureInPictureMode"
    const val enterPictureInPicture = "enterPictureInPicture"
    const val getMediaVolume = "getMediaVolume"
    const val setMediaVolume = "setMediaVolume"
    const val lockPortrait = "lockPortrait"
    const val lockLandscape = "lockLandscape"
    const val lockPortraitFullscreen = "lockPortraitFullscreen"
    const val prepareForPictureInPicture = "prepareForPictureInPicture"

    val methodNames = setOf(
        isPictureInPictureSupported,
        isInPictureInPictureMode,
        enterPictureInPicture,
        getMediaVolume,
        setMediaVolume,
        lockPortrait,
        lockLandscape,
        lockPortraitFullscreen,
        prepareForPictureInPicture,
    )
}
