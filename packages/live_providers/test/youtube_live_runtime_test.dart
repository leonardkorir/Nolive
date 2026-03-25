import 'package:live_providers/live_providers.dart';
import 'package:live_providers/src/providers/youtube/youtube_api_client.dart';
import 'package:test/test.dart';

import 'support/youtube_fixture_loader.dart';

void main() {
  group(
    'fixture-backed youtube runtime coverage',
    skip: YouTubeFixtureLoader.skipReason,
    () {
      test('live youtube runtime maps detail and play flow from fixtures',
          () async {
        final provider = YouTubeProvider.live(
          apiClient: _FixtureYouTubeApiClient(),
        );

        final recommend = await provider.fetchRecommendRooms();
        expect(recommend.items, isNotEmpty);
        expect(recommend.items.first.providerId, 'youtube');

        final detail = await provider.fetchRoomDetail('Z3eFGbFcaXs');
        expect(detail.providerId, 'youtube');
        expect(detail.roomId, '@Wenzel_TCG/live');
        expect(detail.title, 'WENZ VAULT!');
        expect(detail.streamerName, 'Wenzel TCG');
        expect(detail.isLive, isTrue);
        expect(detail.viewerCount, 1279);
        expect(
          detail.streamerAvatarUrl,
          contains('yt3.ggpht.com/jyb36VGQ9_JX8kSFb8lK4axC8UFXHg3m'),
        );
        expect(detail.danmakuToken, isA<Map>());
        expect(detail.metadata?['playerClientProfile'], 'web_safari');

        final qualities = await provider.fetchPlayQualities(detail);
        expect(qualities.length, greaterThan(1));
        expect(qualities.first.id, 'auto');
        expect(
          qualities.any((item) => item.label.contains('1080')),
          isTrue,
        );

        final urls = await provider.fetchPlayUrls(
          detail: detail,
          quality: qualities[1],
        );
        expect(urls.length, greaterThanOrEqualTo(4));
        expect(urls.first.lineLabel, 'Safari HLS');
        expect(urls[1].lineLabel, 'MWEB HLS');
        expect(urls[2].lineLabel, 'iOS HLS');
        expect(
          urls[2].metadata?['audioUrl'],
          contains('fixture/Z3eFGbFcaXs/ios/audio-default.m3u8'),
        );
        expect(urls[2].metadata?['audioSource'], 'hls-rendition');
        expect(urls[3].lineLabel, 'WEB Direct');
        expect(urls.first.url, contains('safari/1080p60.m3u8'));
        expect(urls[3].url, contains('/direct/Z3eFGbFcaXs/1080p.mp4'));

        final autoUrls = await provider.fetchPlayUrls(
          detail: detail,
          quality: qualities.first,
        );
        expect(autoUrls[2].lineLabel, 'iOS HLS');
        expect(autoUrls[2].metadata?['audioUrl'], isNull);
      });

      test('falls back to direct playback when hls media probe is forbidden',
          () async {
        final provider = YouTubeProvider.live(
          apiClient: _FixtureYouTubeApiClient(
            forbidHlsSegments: true,
          ),
        );

        final detail = await provider.fetchRoomDetail('Z3eFGbFcaXs');
        final qualities = await provider.fetchPlayQualities(detail);
        expect(qualities, isNotEmpty);
        expect(qualities.first.metadata?['playbackMode'], 'direct');

        final urls = await provider.fetchPlayUrls(
          detail: detail,
          quality: qualities.first,
        );
        expect(urls, isNotEmpty);
        expect(urls.first.lineLabel, 'WEB Direct');
        expect(urls.first.url, contains('/direct/Z3eFGbFcaXs/1080p.mp4'));
      });
    },
  );
}

class _FixtureYouTubeApiClient implements YouTubeApiClient {
  _FixtureYouTubeApiClient({
    this.forbidHlsSegments = false,
  })  : _pageHtml = YouTubeFixtureLoader.loadChannelPageHtml(),
        _liveChatPageHtml = YouTubeFixtureLoader.loadLiveChatPageHtml(),
        _liveChatResponses = YouTubeFixtureLoader.loadLiveChatResponses(),
        _webPlayerResponse = {
          ...YouTubeFixtureLoader.loadPlayerResponse('Z3eFGbFcaXs'),
          'playabilityStatus': const {'status': 'OK'},
          'streamingData': {
            'formats': [
              {
                'qualityLabel': '1080p',
                'height': 1080,
                'mimeType': 'video/mp4; codecs="avc1.64002a, mp4a.40.2"',
                'url':
                    'https://rr.googlevideo.com/direct/Z3eFGbFcaXs/1080p.mp4',
              },
            ],
          },
        },
        _webSafariPlayerResponse = {
          ...YouTubeFixtureLoader.loadPlayerResponse('Z3eFGbFcaXs'),
          'playabilityStatus': const {'status': 'OK'},
          'streamingData': {
            'hlsManifestUrl':
                'https://manifest.googlevideo.com/api/manifest/hls_variant/fixture/Z3eFGbFcaXs/safari/master.m3u8',
          },
        },
        _mwebPlayerResponse = {
          ...YouTubeFixtureLoader.loadPlayerResponse('Z3eFGbFcaXs'),
          'playabilityStatus': const {'status': 'OK'},
          'streamingData': {
            'hlsManifestUrl':
                'https://manifest.googlevideo.com/api/manifest/hls_variant/fixture/Z3eFGbFcaXs/mweb/master.m3u8',
          },
        },
        _iosPlayerResponse = {
          ...YouTubeFixtureLoader.loadPlayerResponse('Z3eFGbFcaXs'),
          'playabilityStatus': const {'status': 'OK'},
          'streamingData': {
            'hlsManifestUrl':
                'https://manifest.googlevideo.com/api/manifest/hls_variant/fixture/Z3eFGbFcaXs/ios/master.m3u8',
            'adaptiveFormats': [
              {
                'mimeType': 'audio/mp4; codecs="mp4a.40.2"',
                'bitrate': 128000,
                'url':
                    'https://rr.googlevideo.com/audio/Z3eFGbFcaXs/english.m4a',
              },
            ],
          },
        };

  final bool forbidHlsSegments;

  static const String _searchHtml = '''
<html><script>
var ytInitialData = {
  "contents": {
    "twoColumnSearchResultsRenderer": {
      "primaryContents": {
        "sectionListRenderer": {
          "contents": [{
            "itemSectionRenderer": {
              "contents": [{
                "videoRenderer": {
                  "videoId": "Z3eFGbFcaXs",
                  "title": {"runs": [{"text": "WENZ VAULT!"}]},
                  "ownerText": {
                    "runs": [{
                      "text": "Wenzel TCG",
                      "navigationEndpoint": {
                        "commandMetadata": {
                          "webCommandMetadata": {"url": "/@Wenzel_TCG"}
                        }
                      }
                    }]
                  },
                  "thumbnail": {
                    "thumbnails": [{
                      "url": "https://i.ytimg.com/vi/Z3eFGbFcaXs/hqdefault_live.jpg"
                    }]
                  },
                  "thumbnailOverlays": [{
                    "thumbnailOverlayTimeStatusRenderer": {"style": "LIVE"}
                  }],
                  "viewCountText": {"simpleText": "4.8K watching"}
                }
              }]
            }
          }]
        }
      }
    }
  }
};
</script></html>
''';

  final String _pageHtml;
  final String _liveChatPageHtml;
  final List<Map<String, dynamic>> _liveChatResponses;
  final Map<String, dynamic> _webPlayerResponse;
  final Map<String, dynamic> _webSafariPlayerResponse;
  final Map<String, dynamic> _mwebPlayerResponse;
  final Map<String, dynamic> _iosPlayerResponse;
  int _liveChatIndex = 0;

  @override
  Future<String> fetchText(
    String url, {
    Map<String, String> headers = const {},
  }) async {
    if (url.contains('/channel/UC4R8DWoMoI7CAwX8_LjQHig/live')) {
      return _pageHtml;
    }
    if (url.contains('/watch?v=Z3eFGbFcaXs')) {
      return _pageHtml;
    }
    if (url.contains('/results?search_query=')) {
      return _searchHtml;
    }
    if (url.contains('/live_chat?')) {
      return _liveChatPageHtml;
    }
    if (url.contains('fixture/Z3eFGbFcaXs/safari/1080p60.m3u8') ||
        url.contains('fixture/Z3eFGbFcaXs/mweb/1080p60.m3u8') ||
        url.contains('fixture/Z3eFGbFcaXs/ios/1080p60.m3u8')) {
      return '''
#EXTM3U
#EXT-X-TARGETDURATION:5
#EXTINF:5.0,
https://rr.googlevideo.com/segment/Z3eFGbFcaXs/1080p60.ts
''';
    }
    if (url.contains('fixture/Z3eFGbFcaXs/safari/720p60.m3u8') ||
        url.contains('fixture/Z3eFGbFcaXs/mweb/720p60.m3u8') ||
        url.contains('fixture/Z3eFGbFcaXs/ios/720p60.m3u8')) {
      return '''
#EXTM3U
#EXT-X-TARGETDURATION:5
#EXTINF:5.0,
https://rr.googlevideo.com/segment/Z3eFGbFcaXs/720p60.ts
''';
    }
    if (url.contains('fixture/Z3eFGbFcaXs/safari/480p30.m3u8') ||
        url.contains('fixture/Z3eFGbFcaXs/mweb/480p30.m3u8') ||
        url.contains('fixture/Z3eFGbFcaXs/ios/480p30.m3u8')) {
      return '''
#EXTM3U
#EXT-X-TARGETDURATION:5
#EXTINF:5.0,
https://rr.googlevideo.com/segment/Z3eFGbFcaXs/480p30.ts
''';
    }
    if (url.contains('fixture/Z3eFGbFcaXs/ios/audio-default.m3u8')) {
      return '''
#EXTM3U
#EXT-X-TARGETDURATION:5
#EXTINF:5.0,
https://rr.googlevideo.com/audio-segment/Z3eFGbFcaXs/default-audio.aac
''';
    }
    if (url.contains('manifest.googlevideo.com') &&
        url.contains('fixture/Z3eFGbFcaXs/safari')) {
      return '''
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=6200000,RESOLUTION=1920x1080,FRAME-RATE=60.0
1080p60.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=3200000,RESOLUTION=1280x720,FRAME-RATE=60.0
720p60.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=1500000,RESOLUTION=854x480,FRAME-RATE=30.0
480p30.m3u8
''';
    }
    if (url.contains('manifest.googlevideo.com') &&
        url.contains('fixture/Z3eFGbFcaXs/mweb')) {
      return '''
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=6200000,RESOLUTION=1920x1080,FRAME-RATE=60.0
1080p60.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=3200000,RESOLUTION=1280x720,FRAME-RATE=60.0
720p60.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=1500000,RESOLUTION=854x480,FRAME-RATE=30.0
480p30.m3u8
''';
    }
    if (url.contains('manifest.googlevideo.com') &&
        url.contains('fixture/Z3eFGbFcaXs/ios')) {
      return '''
#EXTM3U
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud-main",NAME="Default",DEFAULT=YES,AUTOSELECT=YES,URI="audio-default.m3u8"
#EXT-X-STREAM-INF:BANDWIDTH=6200000,RESOLUTION=1920x1080,FRAME-RATE=60.0,AUDIO="aud-main"
1080p60.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=3200000,RESOLUTION=1280x720,FRAME-RATE=60.0,AUDIO="aud-main"
720p60.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=1500000,RESOLUTION=854x480,FRAME-RATE=30.0,AUDIO="aud-main"
480p30.m3u8
''';
    }
    throw StateError('Unexpected YouTube fetchText url: $url');
  }

  @override
  Future<int> probeStatus(
    String url, {
    Map<String, String> headers = const {},
  }) async {
    if (url.contains('rr.googlevideo.com/segment/')) {
      return forbidHlsSegments ? 403 : 200;
    }
    throw StateError('Unexpected YouTube probeStatus url: $url');
  }

  @override
  Future<Map<String, dynamic>> postPlayer({
    required String apiKey,
    required String videoId,
    required String originalUrl,
    Map<String, dynamic> innertubeContext = const {},
    String rolloutToken = '',
    String poToken = '',
    YouTubePlayerClientProfile clientProfile = YouTubePlayerClientProfile.web,
  }) async {
    if (videoId == 'Z3eFGbFcaXs') {
      switch (clientProfile) {
        case YouTubePlayerClientProfile.webSafari:
          return _webSafariPlayerResponse;
        case YouTubePlayerClientProfile.mweb:
          return _mwebPlayerResponse;
        case YouTubePlayerClientProfile.web:
          return _webPlayerResponse;
        case YouTubePlayerClientProfile.ios:
          return _iosPlayerResponse;
      }
    }
    throw StateError('Unexpected YouTube player request for $videoId');
  }

  @override
  Future<Map<String, dynamic>> postLiveChat({
    required String apiKey,
    required String continuation,
    required String visitorData,
    required String referer,
    String clientVersion = YouTubeApiClient.defaultWebClientVersion,
  }) async {
    final index = _liveChatIndex < _liveChatResponses.length
        ? _liveChatIndex
        : _liveChatResponses.length - 1;
    _liveChatIndex += 1;
    return _liveChatResponses[index];
  }
}
