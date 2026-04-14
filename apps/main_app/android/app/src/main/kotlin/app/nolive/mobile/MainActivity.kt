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
import android.os.LocaleList
import android.os.SystemClock
import android.util.Log
import android.util.Rational
import android.view.Surface
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.Locale
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
                onFullscreenLandscapeSensorChanged(event)
            }

            override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit
        }
    }
    private var fullscreenLandscapeMemoryCaptureRunnable: Runnable? = null
    private var fullscreenLandscapeSession: FullscreenLandscapeSession? = null
    private var fullscreenLandscapeSessionStartedAtMs: Long? = null
    private var fullscreenLandscapeSensorTrackingEnabled = false
    private var lastKnownLandscapeSensorOrientation: Int? = null

    override fun attachBaseContext(newBase: Context) {
        super.attachBaseContext(newBase.createConfigurationContext(createZhHansConfiguration(newBase.resources.configuration)))
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler(::handlePlaybackMethod)
    }

    override fun applyOverrideConfiguration(overrideConfiguration: Configuration?) {
        val baseConfiguration = overrideConfiguration ?: Configuration()
        super.applyOverrideConfiguration(createZhHansConfiguration(baseConfiguration))
    }

    override fun onResume() {
        super.onResume()
        if (fullscreenLandscapeSession != null) {
            startFullscreenLandscapeSensorTracking()
        }
    }

    override fun onPause() {
        stopFullscreenLandscapeSensorTracking()
        super.onPause()
    }

    private fun createZhHansConfiguration(configuration: Configuration): Configuration {
        val locale = Locale.Builder()
            .setLanguage("zh")
            .setScript("Hans")
            .setRegion("CN")
            .build()
        return Configuration(configuration).apply {
            setLocale(locale)
            setLocales(LocaleList(locale))
            fontScale = 1.0f
        }
    }

    private fun handlePlaybackMethod(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isPictureInPictureSupported" -> {
                result.success(isPictureInPictureSupported())
            }
            "isInPictureInPictureMode" -> {
                result.success(
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                        isInPictureInPictureMode
                    } else {
                        false
                    }
                )
            }
            "enterPictureInPicture" -> {
                result.success(enterPictureInPicture(call))
            }
            "getMediaVolume" -> {
                result.success(getMediaVolume())
            }
            "setMediaVolume" -> {
                result.success(setMediaVolume(call))
            }
            "lockPortrait" -> {
                result.success(lockPortrait())
            }
            "lockLandscape" -> {
                result.success(lockLandscape())
            }
            "prepareForPictureInPicture" -> {
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
        val existingSession = fullscreenLandscapeSession
        if (existingSession != null) {
            startFullscreenLandscapeSensorTracking()
            fullscreenLandscapeSession = existingSession.markResumed()
            val activeSession = fullscreenLandscapeSession ?: existingSession
            val requestedOrientationForLock = activeSession.requestedOrientationForActiveLock()
            if (requestedOrientation != requestedOrientationForLock) {
                requestedOrientation = requestedOrientationForLock
            }
            Log.i(
                ORIENTATION_LOG_TAG,
                if (existingSession.suspended) {
                    "resumeLandscape initial=${orientationLabel(activeSession.initialOrientation)} mode=${orientationLabel(requestedOrientationForLock)}"
                } else {
                    "reuseLandscape initial=${orientationLabel(activeSession.initialOrientation)} mode=${orientationLabel(requestedOrientationForLock)}"
                },
            )
            if (existingSession.suspended && isLandscapeConfiguration()) {
                onFullscreenLandscapeConfigurationChanged()
            }
            return true
        }
        val storedOrientation = readLastLandscapeOrientation()
        val session = FullscreenLandscapeSession(
            initialOrientation = resolveInitialLandscapeOrientation(storedOrientation),
        )
        fullscreenLandscapeSession = session
        fullscreenLandscapeSessionStartedAtMs = SystemClock.elapsedRealtime()
        lastKnownLandscapeSensorOrientation = null
        cancelFullscreenLandscapeMemoryCapture(reason = "newSession")
        startFullscreenLandscapeSensorTracking()
        requestedOrientation = session.requestedOrientationForEntry()
        Log.i(
            ORIENTATION_LOG_TAG,
            "lockLandscape initial=${orientationLabel(session.initialOrientation)} stored=${orientationLabel(storedOrientation)}",
        )
        if (isLandscapeConfiguration()) {
            onFullscreenLandscapeConfigurationChanged()
        }
        return true
    }

    private fun lockPortrait(): Boolean {
        clearFullscreenLandscapeManagement()
        requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
        return true
    }

    private fun prepareForPictureInPicture(): Boolean {
        suspendFullscreenLandscapeManagement()
        requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
        return true
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
                "landscape sensor enabled type=${sensor.name}",
            )
            return
        }
        Log.w(ORIENTATION_LOG_TAG, "landscape sensor registration failed")
    }

    private fun stopFullscreenLandscapeSensorTracking() {
        if (!fullscreenLandscapeSensorTrackingEnabled) {
            return
        }
        sensorManager?.unregisterListener(fullscreenLandscapeSensorListener)
        fullscreenLandscapeSensorTrackingEnabled = false
        Log.i(ORIENTATION_LOG_TAG, "landscape sensor disabled")
    }

    private fun onFullscreenLandscapeSensorChanged(event: SensorEvent) {
        if (event.values.size < 3) {
            return
        }
        val nextOrientation = FullscreenLandscapeOrientationMemory.orientationForGravityVector(
            x = event.values[0],
            y = event.values[1],
            z = event.values[2],
        )
        lastKnownLandscapeSensorOrientation = nextOrientation
        if (nextOrientation == null) {
            return
        }
        applyLandscapeSensorOrientationIfNeeded(
            orientation = nextOrientation,
            source = "sensor",
        )
    }

    private fun applyLandscapeSensorOrientationIfNeeded(
        orientation: Int?,
        source: String,
    ) {
        val session = fullscreenLandscapeSession ?: return
        if (!session.adjustmentUnlocked || session.suspended) {
            return
        }
        val nextOrientation = orientation ?: return
        if (nextOrientation == session.activeOrientation) {
            return
        }
        fullscreenLandscapeSession = session.updateActiveOrientation(nextOrientation)
        if (requestedOrientation != nextOrientation) {
            requestedOrientation = nextOrientation
            Log.i(
                ORIENTATION_LOG_TAG,
                "rotate landscape source=$source side=${orientationLabel(nextOrientation)}",
            )
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
        Log.i(
            ORIENTATION_LOG_TAG,
            "landscape config rotation=${rotationLabel(currentDisplayRotation())} active=${orientationLabel(session.activeOrientation)} cached=${orientationLabel(lastKnownLandscapeSensorOrientation)}",
        )
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
            ActivityInfo.SCREEN_ORIENTATION_PORTRAIT -> "portrait"
            ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED -> "unspecified"
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
        audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, targetVolume, 0)
        return true
    }
}
