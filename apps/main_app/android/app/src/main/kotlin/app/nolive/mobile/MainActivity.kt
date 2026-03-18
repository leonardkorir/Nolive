package app.nolive.mobile

import android.app.PictureInPictureParams
import android.content.Context
import android.content.pm.ActivityInfo
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.media.AudioManager
import android.os.Build
import android.os.LocaleList
import android.util.Rational
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
    }

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
            "enableSensorLandscape" -> {
                result.success(enableSensorLandscape())
            }
            "lockPortrait" -> {
                result.success(lockPortrait())
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

    private fun enableSensorLandscape(): Boolean {
        requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
        return true
    }

    private fun lockPortrait(): Boolean {
        requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
        return true
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
