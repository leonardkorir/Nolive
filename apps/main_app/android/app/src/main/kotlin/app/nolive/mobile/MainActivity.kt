package app.nolive.mobile

import android.app.PictureInPictureParams
import android.content.Context
import android.content.pm.ActivityInfo
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.util.Rational
import android.view.OrientationEventListener
import android.view.Surface
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.math.roundToInt

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "nolive/android_playback"
        private const val ORIENTATION_LOG_TAG = "NoliveOrientation"
        private const val FULLSCREEN_LANDSCAPE_MEMORY_CAPTURE_DELAY_MS = 30_000L
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val sensorManager by lazy(LazyThreadSafetyMode.NONE) {
        getSystemService(Context.SENSOR_SERVICE) as? SensorManager
    }
    private val fullscreenLandscapeSensor by lazy(LazyThreadSafetyMode.NONE) {
        sensorManager?.getDefaultSensor(Sensor.TYPE_GRAVITY)
            ?: sensorManager?.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
    }
    private val fullscreenLandscapeSensorListener by lazy(LazyThreadSafetyMode.NONE) {
        object : SensorEventListener {
            override fun onSensorChanged(event: SensorEvent) {
                onFullscreenLandscapeGravityChanged(event)
            }

            override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit
        }
    }
    private var fullscreenLandscapeMemoryCaptureRunnable: Runnable? = null
    private var fullscreenLandscapeSession: FullscreenLandscapeSession? = null
    private var fullscreenLandscapeSessionStartedAtMs: Long? = null
    private var fullscreenLandscapeSensorTrackingEnabled = false
    private var fullscreenOrientationEventListener: OrientationEventListener? = null
    private var lastKnownLandscapeSensorOrientation: Int? = null
    /// ARC landscape-only mode (not phone). No portrait at all on Chromebook.
    private var arcLandscapeOnlyMode = false
    private var lastArcPinnedOrientation: Int? = null
    private var orientationPassthrough = false
    /// Chrome UI lock pin when frozen without / with a landscape session.
    /// Kept across onResume so ARC does not re-arm SENSOR_LANDSCAPE over freeze.
    private var chromeLockFrozenPin: Int? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler(::handlePlaybackMethod)
        // Phone never enters here. ARC: landscape only for whole app lifecycle.
        mainHandler.post {
            if (isArcChromeOsDevice() && fullscreenLandscapeSession == null) {
                startArcLandscapeOnlyMode(reason = "engine")
            }
        }
        mainHandler.postDelayed({
            if (isArcChromeOsDevice() && fullscreenLandscapeSession == null) {
                startArcLandscapeOnlyMode(reason = "engine-delayed")
            }
        }, 500)
    }

    override fun setRequestedOrientation(requestedOrientation: Int) {
        // Phone path: never blocked (isArcChromeOsDevice is false).
        // ARC: reject portrait / free USER so the shell cannot leave landscape.
        if (
            isArcChromeOsDevice() &&
            !orientationPassthrough &&
            isArcForbiddenOrientation(requestedOrientation)
        ) {
            Log.i(
                ORIENTATION_LOG_TAG,
                "arc ignore orient=${orientationLabel(requestedOrientation)} " +
                    "keep=${orientationLabel(lastArcPinnedOrientation)}",
            )
            val keep = lastArcPinnedOrientation
                ?: ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
            if (this.requestedOrientation != keep) {
                pinActivityOrientation(keep, "reassert-landscapeOnly")
            }
            return
        }
        super.setRequestedOrientation(requestedOrientation)
        if (!isArcForbiddenOrientation(requestedOrientation)) {
            lastArcPinnedOrientation = requestedOrientation
        }
    }

    override fun onResume() {
        super.onResume()
        val session = fullscreenLandscapeSession
        when (
            val action = FullscreenLandscapeOrientationMemory.resolveResumeOrientationAction(
                landscapeSessionFrozen = session?.frozen == true,
                landscapeSessionActiveOrientation = session?.activeOrientation,
                chromeLockFrozenPin = chromeLockFrozenPin,
                hasLandscapeSession = session != null,
                isArcChromeOs = isArcChromeOsDevice(),
            )
        ) {
            is ResumeOrientationAction.KeepFrozen -> {
                pinActivityOrientation(action.pin, "resume-frozen")
            }
            ResumeOrientationAction.ResumeLandscapeSensors -> {
                // Shared landscape hard-lock path (phone + ARC fullscreen).
                stopArcLandscapeOnlyMode()
                startFullscreenLandscapeSensorTracking()
            }
            ResumeOrientationAction.StartArcLandscapeOnly -> {
                startArcLandscapeOnlyMode(reason = "resume")
            }
            ResumeOrientationAction.None -> Unit
        }
    }

    override fun onPause() {
        stopFullscreenLandscapeSensorTracking()
        super.onPause()
    }

    private fun isArcForbiddenOrientation(orientation: Int): Boolean {
        // Anything that can leave long-edge landscape on ARC.
        return when (orientation) {
            ActivityInfo.SCREEN_ORIENTATION_USER,
            ActivityInfo.SCREEN_ORIENTATION_FULL_USER,
            ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED,
            ActivityInfo.SCREEN_ORIENTATION_SENSOR,
            ActivityInfo.SCREEN_ORIENTATION_FULL_SENSOR,
            ActivityInfo.SCREEN_ORIENTATION_PORTRAIT,
            ActivityInfo.SCREEN_ORIENTATION_REVERSE_PORTRAIT,
            ActivityInfo.SCREEN_ORIENTATION_SENSOR_PORTRAIT,
            ActivityInfo.SCREEN_ORIENTATION_USER_PORTRAIT,
            -> true
            else -> false
        }
    }

    private fun pinActivityOrientation(orientation: Int, source: String) {
        orientationPassthrough = true
        try {
            super.setRequestedOrientation(orientation)
        } finally {
            orientationPassthrough = false
        }
        lastArcPinnedOrientation = orientation
        Log.i(
            ORIENTATION_LOG_TAG,
            "pin orient source=$source side=${orientationLabel(orientation)}",
        )
    }

    private fun handlePlaybackMethod(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            AndroidPlaybackMethodContract.isPictureInPictureSupported -> {
                result.success(isPictureInPictureSupported())
            }
            AndroidPlaybackMethodContract.isInPictureInPictureMode -> {
                result.success(
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                        isInPictureInPictureMode
                    } else {
                        false
                    }
                )
            }
            AndroidPlaybackMethodContract.enterPictureInPicture -> {
                result.success(enterPictureInPicture(call))
            }
            AndroidPlaybackMethodContract.getMediaVolume -> {
                result.success(getMediaVolume())
            }
            AndroidPlaybackMethodContract.setMediaVolume -> {
                result.success(setMediaVolume(call))
            }
            AndroidPlaybackMethodContract.lockPortrait -> {
                result.success(lockPortrait())
            }
            AndroidPlaybackMethodContract.lockLandscape -> {
                result.success(lockLandscape())
            }
            AndroidPlaybackMethodContract.lockPortraitFullscreen -> {
                result.success(lockPortraitFullscreen())
            }
            AndroidPlaybackMethodContract.freezeFullscreenOrientation -> {
                result.success(freezeFullscreenOrientation())
            }
            AndroidPlaybackMethodContract.prepareForPictureInPicture -> {
                result.success(prepareForPictureInPicture())
            }
            else -> result.notImplemented()
        }
    }

    private fun isPictureInPictureSupported(): Boolean {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
    }

    private fun enterPictureInPicture(call: MethodCall): Boolean {
        if (!isPictureInPictureSupported()) {
            return false
        }
        val width = (call.argument<Int>("width") ?: 16).coerceAtLeast(1)
        val height = (call.argument<Int>("height") ?: 9).coerceAtLeast(1)
        val params = PictureInPictureParams.Builder()
            .setAspectRatio(Rational(width, height))
            .build()
        return enterPictureInPictureMode(params)
    }

    private fun lockLandscape(): Boolean {
        // Fullscreen long-edge L/R via OrientationEventListener (works when
        // ChromeOS auto-rotate is off). Shell ARC uses SENSOR_LANDSCAPE;
        // fullscreen upgrades to a pinned L/R session.
        stopArcLandscapeOnlyMode()
        chromeLockFrozenPin = null
        val naturalLandscapePrimary = resolveNaturalLandscapePrimary()
        val existingSession = fullscreenLandscapeSession
        if (existingSession != null) {
            // Unlock path: clear UI freeze so long-edge L/R can work again.
            val resumed = existingSession.markResumed().markUnfrozen()
            fullscreenLandscapeSession = resumed
            startFullscreenLandscapeSensorTracking()
            val activeSession = fullscreenLandscapeSession ?: resumed
            val requestedOrientationForLock = activeSession.requestedOrientationForActiveLock()
            pinActivityOrientation(requestedOrientationForLock, "lockLandscape-reuse")
            Log.i(
                ORIENTATION_LOG_TAG,
                when {
                    existingSession.frozen ->
                        "unfreezeLandscape initial=${orientationLabel(activeSession.initialOrientation)} mode=${orientationLabel(requestedOrientationForLock)} naturalLand=${activeSession.naturalLandscapePrimary}"
                    existingSession.suspended ->
                        "resumeLandscape initial=${orientationLabel(activeSession.initialOrientation)} mode=${orientationLabel(requestedOrientationForLock)}"
                    else ->
                        "reuseLandscape initial=${orientationLabel(activeSession.initialOrientation)} mode=${orientationLabel(requestedOrientationForLock)}"
                },
            )
            if (
                (existingSession.suspended || existingSession.frozen) &&
                isLandscapeConfiguration()
            ) {
                val sessionAfter = fullscreenLandscapeSession
                if (sessionAfter != null && !sessionAfter.adjustmentUnlocked) {
                    fullscreenLandscapeSession = sessionAfter.markAdjustmentUnlocked()
                }
                onFullscreenLandscapeConfigurationChanged()
            }
            return true
        }
        val storedOrientation = readLastLandscapeOrientation()
        val initial = resolveInitialLandscapeOrientation(storedOrientation)
        val session = FullscreenLandscapeSession(
            initialOrientation = initial,
            naturalLandscapePrimary = naturalLandscapePrimary,
        )
        fullscreenLandscapeSession = session
        fullscreenLandscapeSessionStartedAtMs = SystemClock.elapsedRealtime()
        lastKnownLandscapeSensorOrientation = null
        cancelFullscreenLandscapeMemoryCapture(reason = "newSession")
        startFullscreenLandscapeSensorTracking()
        pinActivityOrientation(
            session.requestedOrientationForEntry(),
            "lockLandscape-new",
        )
        Log.i(
            ORIENTATION_LOG_TAG,
            "lockLandscape initial=${orientationLabel(session.initialOrientation)} " +
                "stored=${orientationLabel(storedOrientation)} " +
                "naturalLand=$naturalLandscapePrimary",
        )
        if (isLandscapeConfiguration()) {
            onFullscreenLandscapeConfigurationChanged()
        }
        return true
    }

    // Pin the current fullscreen pose and stop sensor rotation (UI lock).
    private fun freezeFullscreenOrientation(): Boolean {
        stopArcLandscapeOnlyMode()
        stopFullscreenLandscapeSensorTracking()
        val session = fullscreenLandscapeSession
        if (session != null) {
            val pin = session.activeOrientation
            fullscreenLandscapeSession = session.markFrozen()
            chromeLockFrozenPin = pin
            pinActivityOrientation(pin, "freezeLandscape")
            return true
        }
        // No landscape session: pin whatever pose we are in (portrait hard
        // fullscreen on phone, or current long-edge landscape on ARC shell).
        val pin = FullscreenLandscapeOrientationMemory.fixedOrientationForCurrentPose(
            displayRotation = currentDisplayRotation(),
            configurationOrientation = resources.configuration.orientation,
        )
        chromeLockFrozenPin = pin
        pinActivityOrientation(pin, "freezeCurrent")
        return true
    }

    private fun isArcChromeOsDevice(): Boolean {
        return FullscreenLandscapeOrientationMemory.looksLikeArcChromeOsDevice(
            fingerprint = Build.FINGERPRINT,
            display = Build.DISPLAY,
            incremental = Build.VERSION.INCREMENTAL,
        )
    }

    private fun resolveNaturalLandscapePrimary(): Boolean {
        // ARC convertibles are landscape-primary panels with installOrientation 270.
        if (isArcChromeOsDevice()) {
            return true
        }
        return FullscreenLandscapeOrientationMemory.isNaturalLandscapePrimary(
            displayRotation = currentDisplayRotation(),
            configurationOrientation = resources.configuration.orientation,
        )
    }

    /**
     * Restores app-shell orientation after fullscreen / PiP.
     *
     * Channel name remains `lockPortrait` for binary compatibility.
     * - **Phone**: clear landscape session → system free orientations.
     * - **ARC**: re-arm landscape-only shell (never portrait).
     */
    private fun lockPortrait(): Boolean {
        clearFullscreenLandscapeManagement()
        if (isArcChromeOsDevice()) {
            startArcLandscapeOnlyMode(reason = "restoreShell")
            return true
        }
        stopArcLandscapeOnlyMode()
        requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
        return true
    }

    private fun lockPortraitFullscreen(): Boolean {
        clearFullscreenLandscapeManagement()
        // Phone vertical fullscreen only. ARC never requests this path.
        if (isArcChromeOsDevice()) {
            startArcLandscapeOnlyMode(reason = "lockPortraitFullscreen-arc")
            return true
        }
        stopArcLandscapeOnlyMode()
        pinActivityOrientation(
            ActivityInfo.SCREEN_ORIENTATION_PORTRAIT,
            "lockPortraitFullscreen",
        )
        return true
    }

    private fun prepareForPictureInPicture(): Boolean {
        suspendFullscreenLandscapeManagement()
        stopArcLandscapeOnlyMode()
        orientationPassthrough = true
        try {
            // PiP: allow system freedom; ARC will re-arm landscape-only on resume.
            requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
        } finally {
            orientationPassthrough = false
        }
        return true
    }

    private fun startArcLandscapeOnlyMode(reason: String) {
        if (!isArcChromeOsDevice()) {
            return
        }
        val landscape = fullscreenLandscapeSession
        // Never override an active chrome freeze with SENSOR_LANDSCAPE.
        if (landscape != null && landscape.frozen) {
            pinActivityOrientation(
                landscape.activeOrientation,
                "arcLandscapeOnly-keepFrozen reason=$reason",
            )
            return
        }
        val freezePin = chromeLockFrozenPin
        if (freezePin != null) {
            pinActivityOrientation(
                freezePin,
                "arcLandscapeOnly-keepFrozen reason=$reason",
            )
            return
        }
        if (landscape != null && !landscape.suspended) {
            return
        }
        arcLandscapeOnlyMode = true
        // SENSOR_LANDSCAPE: long-edge L/R only, never portrait (no reverse flip).
        pinActivityOrientation(
            ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE,
            "arcLandscapeOnly reason=$reason",
        )
        Log.i(ORIENTATION_LOG_TAG, "arc landscape-only enabled reason=$reason")
    }

    private fun stopArcLandscapeOnlyMode() {
        if (!arcLandscapeOnlyMode) {
            return
        }
        arcLandscapeOnlyMode = false
        Log.i(ORIENTATION_LOG_TAG, "arc landscape-only disabled")
    }

    private fun scheduleFullscreenLandscapeMemoryCapture() {
        val session = fullscreenLandscapeSession ?: return
        if (persistFullscreenLandscapeMemoryIfDue(reason = "overdue")) {
            return
        }
        if (!session.shouldScheduleMemoryCapture()) {
            return
        }
        val startedAtMs = fullscreenLandscapeSessionStartedAtMs ?: SystemClock.elapsedRealtime()
            .also { fullscreenLandscapeSessionStartedAtMs = it }
        val elapsedMs = (SystemClock.elapsedRealtime() - startedAtMs).coerceAtLeast(0L)
        val remainingDelayMs =
            (FULLSCREEN_LANDSCAPE_MEMORY_CAPTURE_DELAY_MS - elapsedMs).coerceAtLeast(0L)
        cancelFullscreenLandscapeMemoryCapture(reason = "reschedule")
        val runnable = Runnable {
            fullscreenLandscapeMemoryCaptureRunnable = null
            val activeSession = fullscreenLandscapeSession ?: return@Runnable
            if (activeSession.suspended) {
                Log.i(ORIENTATION_LOG_TAG, "skip memory capture reason=suspended")
                fullscreenLandscapeSession = activeSession.markMemoryCaptureCanceled()
                return@Runnable
            }
            if (!persistFullscreenLandscapeMemoryIfDue(reason = "timer")) {
                scheduleFullscreenLandscapeMemoryCapture()
            }
        }
        fullscreenLandscapeMemoryCaptureRunnable = runnable
        fullscreenLandscapeSession = session.markMemoryCaptureScheduled()
        Log.i(
            ORIENTATION_LOG_TAG,
            "schedule memory capture delay=${remainingDelayMs}ms active=${orientationLabel(session.activeOrientation)}",
        )
        mainHandler.postDelayed(
            runnable,
            remainingDelayMs,
        )
    }

    private fun cancelFullscreenLandscapeMemoryCapture(reason: String) {
        val hadPendingCapture = fullscreenLandscapeMemoryCaptureRunnable != null
        fullscreenLandscapeMemoryCaptureRunnable?.let(mainHandler::removeCallbacks)
        fullscreenLandscapeMemoryCaptureRunnable = null
        if (hadPendingCapture) {
            Log.i(ORIENTATION_LOG_TAG, "cancel memory capture reason=$reason")
        }
        fullscreenLandscapeSession =
            fullscreenLandscapeSession?.markMemoryCaptureCanceled()
    }

    private fun persistFullscreenLandscapeMemoryIfDue(reason: String): Boolean {
        val session = fullscreenLandscapeSession ?: return false
        if (session.memoryCaptured) {
            return false
        }
        val startedAtMs = fullscreenLandscapeSessionStartedAtMs ?: return false
        val elapsedMs = (SystemClock.elapsedRealtime() - startedAtMs).coerceAtLeast(0L)
        if (elapsedMs < FULLSCREEN_LANDSCAPE_MEMORY_CAPTURE_DELAY_MS) {
            return false
        }
        cancelFullscreenLandscapeMemoryCapture(reason = "persist:$reason")
        persistCurrentLandscapeOrientation(session.activeOrientation)
        fullscreenLandscapeSession = session.markMemoryCaptured()
        Log.i(
            ORIENTATION_LOG_TAG,
            "persist landscape=${orientationLabel(session.activeOrientation)} source=$reason elapsed=${elapsedMs}ms",
        )
        return true
    }

    private fun suspendFullscreenLandscapeManagement() {
        persistFullscreenLandscapeMemoryIfDue(reason = "suspend")
        cancelFullscreenLandscapeMemoryCapture(reason = "suspend")
        val activeSession = fullscreenLandscapeSession ?: return
        if (activeSession.suspended) {
            return
        }
        fullscreenLandscapeSession = activeSession.markSuspended()
        stopFullscreenLandscapeSensorTracking()
        Log.i(
            ORIENTATION_LOG_TAG,
            "suspendLandscape initial=${orientationLabel(activeSession.initialOrientation)} mode=${orientationLabel(activeSession.requestedOrientationForActiveLock())}",
        )
    }

    private fun resolveInitialLandscapeOrientation(storedOrientation: Int?): Int {
        return FullscreenLandscapeOrientationMemory.resolveInitialOrientation(storedOrientation)
    }

    private fun clearFullscreenLandscapeManagement() {
        suspendFullscreenLandscapeManagement()
        fullscreenLandscapeSession = null
        fullscreenLandscapeSessionStartedAtMs = null
        lastKnownLandscapeSensorOrientation = null
        chromeLockFrozenPin = null
        stopFullscreenLandscapeSensorTracking()
    }

    private fun startFullscreenLandscapeSensorTracking() {
        if (fullscreenLandscapeSensorTrackingEnabled) {
            return
        }
        val session = fullscreenLandscapeSession
        if (session == null || !session.shouldTrackSensors()) {
            return
        }
        // Prefer OrientationEventListener: degrees are relative to natural
        // orientation, so landscape-primary Chromebooks map long-edge correctly
        // without ChromeOS free-rotate.
        val orientationListener = object : OrientationEventListener(
            this,
            SensorManager.SENSOR_DELAY_UI,
        ) {
            override fun onOrientationChanged(orientation: Int) {
                if (orientation == OrientationEventListener.ORIENTATION_UNKNOWN) {
                    return
                }
                val active = fullscreenLandscapeSession ?: return
                val nextOrientation =
                    FullscreenLandscapeOrientationMemory.orientationForSensorDegrees(
                        sensorDegrees = orientation,
                        naturalLandscapePrimary = active.naturalLandscapePrimary,
                    )
                if (nextOrientation != null) {
                    lastKnownLandscapeSensorOrientation = nextOrientation
                }
                applyLandscapeSensorOrientationIfNeeded(
                    orientation = nextOrientation,
                    source = "orientationEvent deg=$orientation",
                )
            }
        }
        if (orientationListener.canDetectOrientation()) {
            fullscreenOrientationEventListener = orientationListener
            orientationListener.enable()
            fullscreenLandscapeSensorTrackingEnabled = true
            Log.i(
                ORIENTATION_LOG_TAG,
                "landscape orientationEvent enabled naturalLand=${session.naturalLandscapePrimary}",
            )
            return
        }
        // Fallback: raw gravity (axis depends on natural landscape primary).
        val manager = sensorManager
        val sensor = fullscreenLandscapeSensor
        if (manager == null || sensor == null) {
            Log.w(ORIENTATION_LOG_TAG, "landscape sensor unavailable")
            return
        }
        fullscreenLandscapeSensorTrackingEnabled = manager.registerListener(
            fullscreenLandscapeSensorListener,
            sensor,
            SensorManager.SENSOR_DELAY_GAME,
        )
        if (fullscreenLandscapeSensorTrackingEnabled) {
            Log.i(
                ORIENTATION_LOG_TAG,
                "landscape gravity fallback enabled type=${sensor.name} naturalLand=${session.naturalLandscapePrimary}",
            )
            return
        }
        Log.w(ORIENTATION_LOG_TAG, "landscape sensor registration failed")
    }

    private fun stopFullscreenLandscapeSensorTracking() {
        if (!fullscreenLandscapeSensorTrackingEnabled) {
            return
        }
        fullscreenOrientationEventListener?.disable()
        fullscreenOrientationEventListener = null
        sensorManager?.unregisterListener(fullscreenLandscapeSensorListener)
        fullscreenLandscapeSensorTrackingEnabled = false
        Log.i(ORIENTATION_LOG_TAG, "landscape sensor disabled")
    }

    private fun onFullscreenLandscapeGravityChanged(event: SensorEvent) {
        if (event.values.size < 3) {
            return
        }
        val session = fullscreenLandscapeSession ?: return
        val nextOrientation = FullscreenLandscapeOrientationMemory.orientationForGravityVector(
            x = event.values[0],
            y = event.values[1],
            z = event.values[2],
            naturalLandscapePrimary = session.naturalLandscapePrimary,
        )
        lastKnownLandscapeSensorOrientation = nextOrientation
        if (nextOrientation == null) {
            return
        }
        applyLandscapeSensorOrientationIfNeeded(
            orientation = nextOrientation,
            source = "gravity",
        )
    }

    private fun applyLandscapeSensorOrientationIfNeeded(
        orientation: Int?,
        source: String,
    ) {
        val session = fullscreenLandscapeSession ?: return
        if (!session.adjustmentUnlocked || session.suspended || session.frozen) {
            return
        }
        val nextOrientation = orientation ?: return
        if (nextOrientation == session.activeOrientation) {
            return
        }
        fullscreenLandscapeSession = session.updateActiveOrientation(nextOrientation)
        if (lastArcPinnedOrientation != nextOrientation) {
            pinActivityOrientation(nextOrientation, "landscape-$source")
        }
    }

    private fun readLastLandscapeOrientation(): Int? {
        val preferences = getSharedPreferences(
            FullscreenLandscapeOrientationMemory.preferencesName,
            Context.MODE_PRIVATE,
        )
        val raw = preferences.getString(
            FullscreenLandscapeOrientationMemory.lastLandscapeSideKey,
            null,
        )
        val decoded = FullscreenLandscapeOrientationMemory.decode(raw)
        val mappingMigrated = preferences.getBoolean(
            FullscreenLandscapeOrientationMemory.lastLandscapeSideMappingMigrationKey,
            false,
        )
        if (mappingMigrated || decoded == null) {
            return decoded
        }
        val migratedOrientation =
            FullscreenLandscapeOrientationMemory.flipLandscapeOrientation(decoded)
        preferences.edit()
            .putBoolean(
                FullscreenLandscapeOrientationMemory.lastLandscapeSideMappingMigrationKey,
                true,
            )
            .putString(
                FullscreenLandscapeOrientationMemory.lastLandscapeSideKey,
                FullscreenLandscapeOrientationMemory.encode(migratedOrientation ?: decoded),
            )
            .apply()
        return migratedOrientation ?: decoded
    }

    private fun persistLastLandscapeOrientation(orientation: Int) {
        val encoded = FullscreenLandscapeOrientationMemory.encode(orientation) ?: return
        getSharedPreferences(
            FullscreenLandscapeOrientationMemory.preferencesName,
            Context.MODE_PRIVATE,
        ).edit()
            .putString(FullscreenLandscapeOrientationMemory.lastLandscapeSideKey, encoded)
            .putBoolean(
                FullscreenLandscapeOrientationMemory.lastLandscapeSideMappingMigrationKey,
                true,
            )
            .apply()
    }

    private fun persistCurrentLandscapeOrientation(orientation: Int? = null) {
        val persistedOrientation = orientation
            ?: fullscreenLandscapeSession?.activeOrientation
            ?: FullscreenLandscapeOrientationMemory.defaultLandscapeOrientation
        persistLastLandscapeOrientation(persistedOrientation)
    }

    private fun onFullscreenLandscapeConfigurationChanged() {
        val session = fullscreenLandscapeSession ?: return
        val rotation = currentDisplayRotation()
        Log.i(
            ORIENTATION_LOG_TAG,
            "landscape config rotation=${rotationLabel(rotation)} active=${orientationLabel(session.activeOrientation)} cached=${orientationLabel(lastKnownLandscapeSensorOrientation)} naturalLand=${session.naturalLandscapePrimary}",
        )
        if (session.frozen || session.suspended) {
            return
        }
        if (!session.adjustmentUnlocked) {
            fullscreenLandscapeSession = session.markAdjustmentUnlocked()
            Log.i(
                ORIENTATION_LOG_TAG,
                "unlock landscape adjustments initial=${orientationLabel(session.initialOrientation)} active=${orientationLabel(session.activeOrientation)} mode=manualSensor",
            )
            applyLandscapeSensorOrientationIfNeeded(
                orientation = lastKnownLandscapeSensorOrientation,
                source = "cached",
            )
            scheduleFullscreenLandscapeMemoryCapture()
            return
        }
        applyLandscapeSensorOrientationIfNeeded(
            orientation = lastKnownLandscapeSensorOrientation,
            source = "cached",
        )
        scheduleFullscreenLandscapeMemoryCapture()
    }

    private fun orientationLabel(orientation: Int?): String {
        return when (orientation) {
            ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE -> "landscape"
            ActivityInfo.SCREEN_ORIENTATION_REVERSE_LANDSCAPE -> "reverseLandscape"
            ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE -> "sensorLandscape"
            ActivityInfo.SCREEN_ORIENTATION_FULL_SENSOR -> "fullSensor"
            ActivityInfo.SCREEN_ORIENTATION_SENSOR -> "sensor"
            ActivityInfo.SCREEN_ORIENTATION_PORTRAIT -> "portrait"
            ActivityInfo.SCREEN_ORIENTATION_REVERSE_PORTRAIT -> "reversePortrait"
            ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED -> "unspecified"
            ActivityInfo.SCREEN_ORIENTATION_USER -> "user"
            else -> "unknown"
        }
    }

    private fun isManagingFullscreenLandscape(): Boolean {
        return fullscreenLandscapeSession != null
    }

    private fun isLandscapeConfiguration(): Boolean {
        return resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE
    }

    private fun rotationLabel(rotation: Int): String {
        return when (rotation) {
            Surface.ROTATION_0 -> "0"
            Surface.ROTATION_90 -> "90"
            Surface.ROTATION_180 -> "180"
            Surface.ROTATION_270 -> "270"
            else -> "unknown"
        }
    }

    private fun currentDisplayRotation(): Int {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            display?.rotation ?: Surface.ROTATION_0
        } else {
            @Suppress("DEPRECATION")
            windowManager.defaultDisplay.rotation
        }
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        if (
            newConfig.orientation == Configuration.ORIENTATION_LANDSCAPE &&
            isManagingFullscreenLandscape()
        ) {
            onFullscreenLandscapeConfigurationChanged()
        }
    }

    override fun onDestroy() {
        clearFullscreenLandscapeManagement()
        stopFullscreenLandscapeSensorTracking()
        lastKnownLandscapeSensorOrientation = null
        super.onDestroy()
    }

    private fun getAudioManager(): AudioManager? {
        return getSystemService(Context.AUDIO_SERVICE) as? AudioManager
    }

    private fun getMediaVolume(): Double {
        val audioManager = getAudioManager() ?: return 0.0
        val maxVolume = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        if (maxVolume <= 0) {
            return 0.0
        }
        val currentVolume = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)
        return (currentVolume.toDouble() / maxVolume.toDouble()).coerceIn(0.0, 1.0)
    }

    private fun setMediaVolume(call: MethodCall): Boolean {
        val audioManager = getAudioManager() ?: return false
        val value = (call.argument<Double>("value") ?: return false).coerceIn(0.0, 1.0)
        val maxVolume = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        if (maxVolume <= 0) {
            return false
        }
        val targetVolume = (value * maxVolume).roundToInt().coerceIn(0, maxVolume)
        // FLAG_SHOW_UI helps some ARC / tablet shells surface stream volume;
        // still may not move ChromeOS host chrome volume — app also drives player volume.
        audioManager.setStreamVolume(
            AudioManager.STREAM_MUSIC,
            targetVolume,
            AudioManager.FLAG_SHOW_UI,
        )
        return true
    }
}
