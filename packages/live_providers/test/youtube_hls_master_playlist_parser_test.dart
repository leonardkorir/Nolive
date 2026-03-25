import 'package:live_providers/src/providers/youtube/youtube_hls_master_playlist_parser.dart';
import 'package:test/test.dart';

void main() {
  group('YouTubeHlsMasterPlaylistParser', () {
    test('maps audio renditions onto HLS variants', () {
      const parser = YouTubeHlsMasterPlaylistParser();
      final variants = parser.parse(
        playlistUrl:
            'https://manifest.googlevideo.com/api/manifest/hls_variant/fixture/master.m3u8',
        source: '''
#EXTM3U
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud-low",NAME="Default",DEFAULT=YES,AUTOSELECT=YES,URI="audio-low.m3u8"
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud-main",NAME="Default",DEFAULT=YES,AUTOSELECT=YES,URI="audio-main.m3u8"
#EXT-X-STREAM-INF:BANDWIDTH=6200000,RESOLUTION=1920x1080,FRAME-RATE=60.0,AUDIO="aud-main"
1080p60.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=3200000,RESOLUTION=1280x720,FRAME-RATE=60.0,AUDIO="aud-main"
720p60.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=290288,RESOLUTION=256x144,FRAME-RATE=15.0,AUDIO="aud-low"
144p15.m3u8
''',
      );

      expect(variants, hasLength(3));
      expect(variants[0].label, '1080p60');
      expect(variants[0].audioGroupId, 'aud-main');
      expect(
        variants[0].audioUrl,
        'https://manifest.googlevideo.com/api/manifest/hls_variant/fixture/audio-main.m3u8',
      );
      expect(variants[1].audioGroupId, 'aud-main');
      expect(
        variants[2].audioUrl,
        'https://manifest.googlevideo.com/api/manifest/hls_variant/fixture/audio-low.m3u8',
      );
    });
  });
}
