import 'package:live_providers/src/providers/youtube/youtube_mapper.dart';
import 'package:live_providers/src/providers/youtube/youtube_page_parser.dart';
import 'package:test/test.dart';

void main() {
  test('youtube mapper surfaces anti-bot login requirement clearly', () {
    final detail = YouTubeMapper.mapRoomDetail(
      requestedRoomId: '@livenowfox/live',
      resolvedVideoId: 'C96oohpWBGw',
      playerResponse: const {
        'playabilityStatus': {
          'status': 'LOGIN_REQUIRED',
          'reason': 'Sign in to confirm you’re not a bot',
        },
        'videoDetails': {
          'title': 'LiveNOW from FOX',
          'author': 'LiveNOW from FOX',
        },
        'microformat': {
          'playerMicroformatRenderer': {
            'ownerProfileUrl': '/@livenowfox',
          },
        },
      },
      sourcePageUrl: 'https://www.youtube.com/watch?v=C96oohpWBGw',
      apiKey: 'AIzaTest',
    );

    expect(detail.metadata?['requiresLogin'], isTrue);
    expect(detail.metadata?['antiBotBlocked'], isTrue);
    expect(
      detail.metadata?['playbackUnavailableReason'],
      'YouTube 当前触发风控校验，需要有效浏览器登录态 / Cookie 才能继续拿到可播流。',
    );
  });

  test('youtube mapper preserves playback metadata overlays', () {
    final detail = YouTubeMapper.mapRoomDetail(
      requestedRoomId: '@Wenzel_TCG/live',
      resolvedVideoId: 'Z3eFGbFcaXs',
      playerResponse: const {
        'playabilityStatus': {'status': 'OK'},
        'videoDetails': {
          'title': 'WENZ VAULT!',
          'author': 'Wenzel TCG',
          'isLive': true,
          'isLiveContent': true,
        },
        'microformat': {
          'playerMicroformatRenderer': {
            'ownerProfileUrl': '/@Wenzel_TCG',
            'liveBroadcastDetails': {'isLiveNow': true},
          },
        },
        'streamingData': {
          'hlsManifestUrl': 'https://manifest.googlevideo.com/master.m3u8',
        },
      },
      sourcePageUrl: 'https://www.youtube.com/watch?v=Z3eFGbFcaXs',
      apiKey: 'AIzaTest',
      additionalMetadata: const {
        'playerClientProfile': 'web_safari',
        'playbackSources': [
          {
            'strategy': 'hls',
            'clientProfile': 'web_safari',
            'lineLabel': 'Safari HLS',
            'url': 'https://manifest.googlevideo.com/master.m3u8',
          },
        ],
      },
    );

    expect(detail.metadata?['playerClientProfile'], 'web_safari');
    expect((detail.metadata?['playbackSources'] as List).single['lineLabel'],
        'Safari HLS');
  });

  test('youtube mapper prefers live page candidate viewer count and avatar',
      () {
    final detail = YouTubeMapper.mapRoomDetail(
      requestedRoomId: '@Wenzel_TCG/live',
      resolvedVideoId: 'Z3eFGbFcaXs',
      playerResponse: const {
        'playabilityStatus': {'status': 'OK'},
        'videoDetails': {
          'title': 'WENZ VAULT!',
          'author': 'Wenzel TCG',
          'viewCount': '168632',
        },
        'microformat': {
          'playerMicroformatRenderer': {
            'ownerProfileUrl': '/@Wenzel_TCG',
            'liveBroadcastDetails': {'isLiveNow': true},
          },
        },
      },
      sourcePageUrl: 'https://www.youtube.com/watch?v=Z3eFGbFcaXs',
      apiKey: 'AIzaTest',
      pageCandidate: const YouTubeSearchCandidate(
        videoId: 'Z3eFGbFcaXs',
        title: 'WENZ VAULT!',
        streamerName: 'Wenzel TCG',
        streamerAvatarUrl: 'https://yt3.ggpht.com/demo-avatar=s176',
        viewerCount: 1279,
      ),
    );

    expect(detail.viewerCount, 1279);
    expect(detail.streamerAvatarUrl, 'https://yt3.ggpht.com/demo-avatar=s176');
  });
}
