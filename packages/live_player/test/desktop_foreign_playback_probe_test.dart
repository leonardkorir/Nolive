import 'package:flutter_test/flutter_test.dart';
import 'package:live_player/live_player.dart';

/// Evidence probe: prints shipped property maps for desktop foreign profiles.
void main() {
  test('probe desktop foreign playback property maps', () {
    final cases = <(String, PlaybackSource, bool)>[
      (
        'domestic_flv_heavy',
        PlaybackSource(
          url: Uri.parse('https://example.com/live.flv'),
          bufferProfile: PlaybackBufferProfile.heavyStreamStable,
        ),
        false,
      ),
      (
        'twitch_desktopStableLive',
        PlaybackSource(
          url: Uri.parse(
            'http://127.0.0.1:9999/twitch-ad-guard/s/stream.m3u8',
          ),
          bufferProfile: PlaybackBufferProfile.desktopStableLive,
        ),
        false,
      ),
      (
        'youtube_desktopStableLive',
        PlaybackSource(
          url: Uri.parse(
            'https://manifest.googlevideo.com/api/manifest/hls_variant/id/d/file/index.m3u8',
          ),
          masterPlaylistUrl: Uri.parse(
            'https://manifest.googlevideo.com/api/manifest/hls_variant/id/d/file/index.m3u8',
          ),
          masterPlaylistContent:
              '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1\nhttps://rr.googlevideo.com/x.m3u8\n',
          bufferProfile: PlaybackBufferProfile.desktopStableLive,
        ),
        false,
      ),
      (
        'sc_loopback_desktop',
        PlaybackSource(
          url: Uri.parse(
            'http://127.0.0.1:9999/stripchat-llhls/s/playlist.m3u8',
          ),
          bufferProfile: PlaybackBufferProfile.loopbackStableHls,
        ),
        false,
      ),
      (
        'sc_loopback_android',
        PlaybackSource(
          url: Uri.parse(
            'http://127.0.0.1:9999/stripchat-llhls/s/playlist.m3u8',
          ),
          bufferProfile: PlaybackBufferProfile.loopbackStableHls,
        ),
        true,
      ),
      (
        'cb_proxy_desktop',
        PlaybackSource(
          url: Uri.parse(
            'http://127.0.0.1:9999/chaturbate-llhls/s/stream.m3u8',
          ),
          bufferProfile: PlaybackBufferProfile.chaturbateLlHlsProxyStable,
        ),
        false,
      ),
      (
        'cb_direct_fallback_desktop',
        PlaybackSource(
          url: Uri.parse(
            'https://edge6-phx.live.mmcdn.com/live-hls/amlst:demo-sd/playlist.m3u8',
          ),
          bufferProfile: PlaybackBufferProfile.chaturbateLlHlsProxyStable,
        ),
        false,
      ),
      (
        'legacy_defaultLowLatency',
        PlaybackSource(
          url: Uri.parse('https://example.com/plain.m3u8'),
          bufferProfile: PlaybackBufferProfile.defaultLowLatency,
        ),
        false,
      ),
    ];

    for (final c in cases) {
      final props = resolveMpvSourcePlatformProperties(
        source: c.$2,
        doubleBufferingEnabled: false,
        hardwareDecoder: 'auto-copy',
        isAndroid: c.$3,
      );
      // ignore: avoid_print
      print(
        'PROFILE ${c.$1} '
        'bufferProfile=${c.$2.bufferProfile.name} '
        'cache=${props['cache']} '
        'cache-secs=${props['cache-secs']} '
        'readahead=${props['demuxer-readahead-secs']} '
        'max-bytes=${props['demuxer-max-bytes']} '
        'video-sync=${props['video-sync']} '
        'hwdec=${props['hwdec'] ?? 'inherit'}',
      );

      if (c.$1 == 'twitch_desktopStableLive' ||
          c.$1 == 'youtube_desktopStableLive') {
        expect(props['cache'], 'yes');
        expect(int.parse(props['demuxer-readahead-secs']!), greaterThanOrEqualTo(8));
        expect(props['cache'], isNot(equals('no')));
      }
      if (c.$1 == 'sc_loopback_desktop') {
        expect(int.parse(props['cache-secs']!), greaterThanOrEqualTo(12));
        expect(int.parse(props['demuxer-readahead-secs']!), greaterThanOrEqualTo(12));
        expect(props['hwdec'], 'auto-copy');
      }
      if (c.$1 == 'cb_proxy_desktop') {
        expect(props['video-sync'], 'display-tempo');
        expect(props['hwdec'], isNot(equals('auto-safe')));
      }
      if (c.$1 == 'cb_direct_fallback_desktop') {
        expect(props['hwdec'], 'auto-copy');
        expect(props['hwdec'], isNot(equals('auto-safe')));
      }
      if (c.$1 == 'domestic_flv_heavy') {
        expect(props['cache'], 'yes');
        expect(props['cache-secs'], '10');
      }
    }

    final delay = resolveMpvHwdecActiveSampleDelay();
    // ignore: avoid_print
    print('hwdec-active-sample-delay-ms=${delay.inMilliseconds}');
    expect(delay.inMilliseconds, greaterThanOrEqualTo(500));
  });
}
