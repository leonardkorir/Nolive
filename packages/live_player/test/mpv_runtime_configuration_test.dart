import 'package:flutter_test/flutter_test.dart';
import 'package:live_player/live_player.dart';

void main() {
  test('resolveMpvRuntimeConfiguration sanitizes empty custom output values',
      () {
    final config = resolveMpvRuntimeConfiguration(
      enableHardwareAcceleration: true,
      compatMode: false,
      doubleBufferingEnabled: false,
      customOutputEnabled: true,
      videoOutputDriver: '   ',
      hardwareDecoder: '',
      logEnabled: false,
    );

    expect(config.controllerConfiguration.vo, 'gpu-next');
    expect(config.controllerConfiguration.hwdec, 'auto-safe');
  });

  test('shouldForceSeekableForSource keeps twitch ad-guard proxy seekable', () {
    final source = PlaybackSource(
      url: Uri.parse('http://127.0.0.1:19190/twitch-ad-guard/master.m3u8'),
    );

    expect(shouldForceSeekableForSource(source), isTrue);
  });

  test('shouldForceSeekableForSource enables split ll-hls playback', () {
    final source = PlaybackSource(
      url: Uri.parse(
        'https://edge144.live.mmcdn.com/live-hls/amlst:onlykira/chunklist_w2054492412_b1228000_video.m3u8',
      ),
      externalAudio: PlaybackExternalMedia(
        url: Uri.parse(
          'https://edge144.live.mmcdn.com/live-hls/amlst:onlykira/chunklist_w2054492412_b96000_audio.m3u8',
        ),
        mimeType: 'application/x-mpegURL',
      ),
    );

    expect(shouldForceSeekableForSource(source), isTrue);
  });

  test('shouldForceSeekableForSource enables generic hls live playback', () {
    final source = PlaybackSource(
      url: Uri.parse(
        'https://edge144.live.mmcdn.com/live-hls/amlst:edithgalpin/master.m3u8',
      ),
    );

    expect(shouldForceSeekableForSource(source), isTrue);
  });

  test('shouldForceSeekableForSource enables flv live playback', () {
    final source = PlaybackSource(
      url: Uri.parse(
        'https://pull-flv-q11.douyincdn.com/thirdgame/stream-407383673798656830.flv',
      ),
    );

    expect(shouldForceSeekableForSource(source), isTrue);
  });

  test('shouldForceSeekableForSource keeps split dash playback untouched', () {
    final source = PlaybackSource(
      url: Uri.parse('https://rr1---sn.example.googlevideo.com/videoplayback'),
      externalAudio: PlaybackExternalMedia(
        url: Uri.parse('https://rr1---sn.example.googlevideo.com/audio'),
        mimeType: 'audio/mp4',
      ),
    );

    expect(shouldForceSeekableForSource(source), isFalse);
  });

  test('shouldIgnoreMpvErrorMessage ignores ll-hls seekability warnings', () {
    final source = PlaybackSource(
      url: Uri.parse(
        'https://edge144.live.mmcdn.com/live-hls/amlst:onlykira/chunklist_w2054492412_b1228000_video.m3u8',
      ),
      externalAudio: PlaybackExternalMedia(
        url: Uri.parse(
          'https://edge144.live.mmcdn.com/live-hls/amlst:onlykira/chunklist_w2054492412_b96000_audio.m3u8',
        ),
        mimeType: 'application/x-mpegURL',
      ),
    );

    expect(
      shouldIgnoreMpvErrorMessage(
        source: source,
        message:
            'Cannot seek in this stream. You can force it with --force-seekable=yes.',
      ),
      isTrue,
    );
  });

  test('shouldIgnoreMpvErrorMessage ignores flv live seekability warnings', () {
    final source = PlaybackSource(
      url: Uri.parse(
        'https://pull-flv-q11.douyincdn.com/thirdgame/stream-407383673798656830.flv',
      ),
    );

    expect(
      shouldIgnoreMpvErrorMessage(
        source: source,
        message:
            'Cannot seek in this stream. You can force it with --force-seekable=yes.',
      ),
      isTrue,
    );
  });

  test(
      'shouldIgnoreMpvErrorMessage ignores generic hls live seekability warnings',
      () {
    final source = PlaybackSource(
      url: Uri.parse(
        'https://edge144.live.mmcdn.com/live-hls/amlst:edithgalpin/master.m3u8',
      ),
    );

    expect(
      shouldIgnoreMpvErrorMessage(
        source: source,
        message:
            'Cannot seek in this stream. You can force it with --force-seekable=yes.',
      ),
      isTrue,
    );
  });

  test('shouldIgnoreMpvErrorMessage keeps other mpv errors visible', () {
    final source = PlaybackSource(
      url: Uri.parse(
        'https://edge144.live.mmcdn.com/live-hls/amlst:onlykira/chunklist_w2054492412_b1228000_video.m3u8',
      ),
      externalAudio: PlaybackExternalMedia(
        url: Uri.parse(
          'https://edge144.live.mmcdn.com/live-hls/amlst:onlykira/chunklist_w2054492412_b96000_audio.m3u8',
        ),
        mimeType: 'application/x-mpegURL',
      ),
    );

    expect(
      shouldIgnoreMpvErrorMessage(
        source: source,
        message: 'HTTP 403 while opening segment',
      ),
      isFalse,
    );
  });
}
