import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Structural regression lock: Linux media_kit_video must ship the GDK EGL
/// fallback so Flutter 3.38+ does not silently force S/W rendering.
void main() {
  test('vendored media_kit_video linux video_output has GDK EGL H/W fallback', () {
    // Resolve from this test file location (packages/live_player/test/...).
    final testFile = File.fromUri(Platform.script);
    final packageRoot = testFile.parent.parent; // packages/live_player
    final repoRoot = packageRoot.parent.parent; // simplelive
    final candidates = <File>[
      File.fromUri(
        repoRoot.uri.resolve(
          'third_party/media_kit_video/linux/video_output.cc',
        ),
      ),
      File(
        '${Directory.current.path}/../../third_party/media_kit_video/linux/video_output.cc',
      ),
      File(
        '${Directory.current.path}/third_party/media_kit_video/linux/video_output.cc',
      ),
    ];
    File? source;
    for (final file in candidates) {
      if (file.existsSync()) {
        source = file;
        break;
      }
    }
    expect(
      source,
      isNotNull,
      reason:
          'third_party/media_kit_video/linux/video_output.cc must exist '
          '(path override for H/W rendering fix). tried=$candidates',
    );
    final text = source!.readAsStringSync();
    expect(text, contains('video_output_init_hw_from_gdk_display'));
    expect(text, contains('video_output_init_hw_from_flutter_egl'));
    expect(text, contains('video_output_init_hw_from_gdk_gl_context'));
    expect(text, contains('gdk-display fallback'));
    expect(text, contains('gdk-gl-context'));
    expect(text, contains('H/W rendering with isolated EGL context'));
    // Must not be the old silent-only path without fallback.
    expect(text, contains('video_output_ensure_render_context'));
    expect(text, contains('flutter-raster'));
    expect(text, contains('video_output_init_hw_from_gdk_display'));
    expect(text, contains('gdk-display fallback'));
  });
}
