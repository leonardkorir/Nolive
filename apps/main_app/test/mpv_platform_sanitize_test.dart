import 'package:flutter_test/flutter_test.dart';
import 'package:nolive_app/src/features/settings/application/manage_player_preferences_use_case.dart';

void main() {
  group('sanitizeMpv*ForPlatform after mobile sync', () {
    test('Linux rejects Android mediacodec vo/hwdec leftovers', () {
      expect(
        sanitizeMpvVideoOutputDriverForPlatform(
          'mediacodec_embed',
          isAndroid: false,
          isLinux: true,
          isWindows: false,
          isApple: false,
        ),
        kDesktopEmbedSafeMpvVideoOutputDriver,
      );
      expect(
        sanitizeMpvHardwareDecoderForPlatform(
          'mediacodec',
          isAndroid: false,
          isLinux: true,
          isWindows: false,
          isApple: false,
        ),
        kDefaultMpvHardwareDecoderLinux,
      );
      expect(
        sanitizeMpvAudioOutputDriverForPlatform(
          'opensles',
          isAndroid: false,
          isLinux: true,
          isWindows: false,
          isApple: false,
        ),
        kDefaultMpvAudioOutputDriver,
      );
    });

    test('Android keeps mediacodec values', () {
      expect(
        sanitizeMpvVideoOutputDriverForPlatform(
          'mediacodec_embed',
          isAndroid: true,
          isLinux: false,
          isWindows: false,
          isApple: false,
        ),
        'mediacodec_embed',
      );
      expect(
        sanitizeMpvHardwareDecoderForPlatform(
          'mediacodec',
          isAndroid: true,
          isLinux: false,
          isWindows: false,
          isApple: false,
        ),
        'mediacodec',
      );
    });

    test('Linux rewrites window-opening VO to libmpv (embed-safe)', () {
      expect(
        sanitizeMpvVideoOutputDriverForPlatform(
          'gpu-next',
          isAndroid: false,
          isLinux: true,
          isWindows: false,
          isApple: false,
        ),
        kDesktopEmbedSafeMpvVideoOutputDriver,
      );
      expect(
        sanitizeMpvVideoOutputDriverForPlatform(
          'libmpv',
          isAndroid: false,
          isLinux: true,
          isWindows: false,
          isApple: false,
        ),
        'libmpv',
      );
      expect(
        sanitizeMpvHardwareDecoderForPlatform(
          'auto-safe',
          isAndroid: false,
          isLinux: true,
          isWindows: false,
          isApple: false,
        ),
        kDefaultMpvHardwareDecoderLinux,
      );
      expect(
        sanitizeMpvHardwareDecoderForPlatform(
          'vaapi-copy',
          isAndroid: false,
          isLinux: true,
          isWindows: false,
          isApple: false,
        ),
        'vaapi-copy',
      );
      expect(
        sanitizeMpvAudioOutputDriverForPlatform(
          'pulse',
          isAndroid: false,
          isLinux: true,
          isWindows: false,
          isApple: false,
        ),
        'pulse',
      );
    });

    test('Linux keeps gpu-next when external native window is allowed', () {
      expect(
        sanitizeMpvVideoOutputDriverForPlatform(
          'gpu-next',
          isAndroid: false,
          isLinux: true,
          isWindows: false,
          isApple: false,
          allowExternalNativeWindow: true,
        ),
        'gpu-next',
      );
      expect(
        sanitizeMpvVideoOutputDriverForPlatform(
          'gpu',
          isAndroid: false,
          isLinux: true,
          isWindows: false,
          isApple: false,
          allowExternalNativeWindow: true,
        ),
        'gpu',
      );
      expect(
        sanitizeMpvVideoOutputDriverForPlatform(
          null,
          isAndroid: false,
          isLinux: true,
          isWindows: false,
          isApple: false,
          allowExternalNativeWindow: true,
        ),
        kDefaultMpvVideoOutputDriver,
      );
    });

    test('env helpers resolve external window allow / VO override', () {
      expect(
        resolveAllowExternalNativeMpvWindow(
          preferenceEnabled: false,
          environment: const <String, String>{
            kNoliveAllowExternalMpvWindowEnv: '1',
          },
        ),
        isTrue,
      );
      expect(
        resolveAllowExternalNativeMpvWindow(
          preferenceEnabled: true,
          environment: const <String, String>{},
        ),
        isTrue,
      );
      expect(
        resolveAllowExternalNativeMpvWindow(
          preferenceEnabled: false,
          environment: const <String, String>{},
        ),
        isFalse,
      );
      expect(
        resolveExternalMpvVoFromEnvironment(const <String, String>{
          kNoliveExternalMpvVoEnv: 'gpu',
        }),
        'gpu',
      );
      expect(
        resolveExternalMpvVoFromEnvironment(const <String, String>{}),
        isNull,
      );
    });
  });
}
