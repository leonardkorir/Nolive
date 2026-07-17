/// Linux H/W path smoke: opens media_kit VideoController so VideoOutput
/// initializes (Flutter EGL or GDK EGL fallback) and plays a local H.264 file
/// with hwdec=auto-copy. Pass criteria:
/// - native stdout/stderr contains H/W rendering (not only S/W)
/// - player reports non-empty hwdec-current that is not "no"
///
/// Run (from apps/main_app, with DISPLAY):
///   flutter test integration_test/linux_hwdec_video_output_smoke_test.dart -d linux
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  testWidgets('linux media_kit VideoOutput uses H/W path + hwdec-current', (
    tester,
  ) async {
    expect(Platform.isLinux, isTrue);

    final videoPath = Platform.environment['NOLIVE_HW_TEST_VIDEO'] ??
        '/tmp/grok-goal-858430f9b6a5/implementer/test-hw.mp4';
    final videoFile = File(videoPath);
    expect(
      videoFile.existsSync(),
      isTrue,
      reason: 'test video missing at $videoPath — generate with ffmpeg first',
    );

    final logPath =
        '/tmp/grok-goal-858430f9b6a5/implementer/linux-hwdec-smoke-native.log';
    final logFile = File(logPath);
    logFile.writeAsStringSync('=== linux_hwdec_video_output_smoke start ===\n');

    // Native VideoOutput writes the successful EGL path (or "software") here.
    final markerPath =
        '/tmp/grok-goal-858430f9b6a5/implementer/video-output-hw-marker.txt';
    final markerFile = File(markerPath);
    if (markerFile.existsSync()) {
      markerFile.deleteSync();
    }
    // Ensure the native plugin can see the marker path (set in outer shell too).
    // Flutter test may not pass arbitrary env; write path is fixed in C++ env read.

    final player = Player(
      configuration: PlayerConfiguration(
        title: 'nolive-hwdec-smoke',
        logLevel: MPVLogLevel.info,
      ),
    );
    final controller = VideoController(
      player,
      configuration: const VideoControllerConfiguration(
        enableHardwareAcceleration: true,
        hwdec: 'auto-copy',
        vo: 'libmpv',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 640,
              height: 360,
              child: Video(controller: controller),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await player.open(Media(videoFile.uri.toString()), play: true);

    // Allow VideoOutput construction + first frames. Cap wall time tightly —
    // dual-GPU hosts can hang in texture interop; native H/W marker + hwdec
    // are the pass criteria.
    String hwdec = '';
    String hwdecCurrent = '';
    String currentVo = '';
    var sawPlaying = false;
    for (var i = 0; i < 24; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      try {
        final platform = player.platform;
        if (platform is NativePlayer) {
          hwdec = (await platform.getProperty('hwdec')).trim();
          hwdecCurrent = (await platform.getProperty('hwdec-current')).trim();
          currentVo = (await platform.getProperty('current-vo')).trim();
        }
      } catch (_) {}
      if (player.state.playing || player.state.position > Duration.zero) {
        sawPlaying = true;
      }
      final earlyMarker =
          markerFile.existsSync() ? markerFile.readAsStringSync().trim() : '';
      final hwOk = hwdecCurrent.isNotEmpty &&
          hwdecCurrent != 'no' &&
          hwdecCurrent != 'none';
      final voHw = earlyMarker == 'flutter-display' ||
          earlyMarker == 'gdk-display' ||
          earlyMarker == 'gdk-gl-context';
      if (hwOk && (voHw || sawPlaying)) {
        break;
      }
    }

    final marker =
        markerFile.existsSync() ? markerFile.readAsStringSync().trim() : '';
    final summary =
        'hwdec=$hwdec hwdec-current=$hwdecCurrent current-vo=$currentVo '
        'playing=$sawPlaying position=${player.state.position} '
        'width=${player.state.width} height=${player.state.height} '
        'video_output_marker=$marker\n';
    logFile.writeAsStringSync(summary, mode: FileMode.append);
    // ignore: avoid_print
    print('linux_hwdec_smoke: $summary');

    try {
      await player.dispose().timeout(const Duration(seconds: 3));
    } catch (_) {
      // Best-effort dispose; H/W criteria already captured.
    }
    await tester.pump(const Duration(milliseconds: 100));

    // Hardware *decode* must engage on this machine (shared player path for
    // every provider). On dual-GPU X11 with Flutter GLX, OpenGL *texture* H/W
    // may stay on S/W upload by design (isolated EGL crashes raster); that is
    // acceptable when hwdec-current is a real backend.
    expect(
      hwdecCurrent.isNotEmpty &&
          hwdecCurrent != 'no' &&
          hwdecCurrent != 'none',
      isTrue,
      reason:
          'expected active hardware decode (hwdec-current not no/none), got '
          'hwdec=$hwdec current=$hwdecCurrent vo=$currentVo marker=$marker',
    );
    // AC1: on machines with GPU/libEGL, VideoOutput must take an OpenGL H/W
    // path (flutter-display / gdk-display / gdk-gl-context / flutter-raster),
    // not silent or permanent software when init can succeed.
    final hwTexture = marker == 'flutter-display' ||
        marker == 'gdk-display' ||
        marker == 'gdk-gl-context' ||
        marker == 'flutter-raster';
    // ignore: avoid_print
    print('linux_hwdec_smoke: texture_marker=$marker hwTexture=$hwTexture');
    expect(
      hwTexture,
      isTrue,
      reason:
          'expected H/W OpenGL VideoOutput marker '
          '(flutter-display|gdk-display|gdk-gl-context|flutter-raster), '
          'got "$marker". Dual-GPU hosts should use isolated EGL + readback.',
    );
  });
}
