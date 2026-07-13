import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:live_core/live_core.dart';
import 'package:live_providers/src/providers/youtube/youtube_api_client.dart';
import 'package:live_providers/src/providers/youtube/youtube_page_parser.dart';
import 'package:live_providers/src/providers/youtube/youtube_playback_data_source.dart';
import 'package:live_providers/src/providers/youtube/youtube_playback_extractor.dart';
import 'package:live_providers/src/providers/youtube/youtube_playback_source.dart';
import 'package:test/test.dart';

void main() {
  group('YouTubePlaybackDataSource', () {
    test(
      'posts Streamlink Android player context without browser tokens',
      () async {
        late http.Request capturedRequest;
        final apiClient = HttpYouTubeApiClient(
          client: MockClient((request) async {
            capturedRequest = request;
            return http.Response(
              jsonEncode({
                'playabilityStatus': {'status': 'OK'},
              }),
              200,
            );
          }),
        );
        addTearDown(apiClient.close);

        await apiClient.postPlayer(
          apiKey: 'AIzaFixture',
          videoId: 'Z3eFGbFcaXs',
          originalUrl: 'https://www.youtube.com/@fixture/live',
          innertubeContext: const {
            'client': {
              'visitorData': 'visitor-fixture',
              'hl': 'zh-CN',
              'gl': 'CN',
            },
          },
          rolloutToken: 'rollout-fixture',
          poToken: 'po-fixture',
          clientProfile: YouTubePlayerClientProfile.streamlinkAndroid,
        );

        final body = jsonDecode(capturedRequest.body) as Map<String, dynamic>;
        final context = body['context'] as Map<String, dynamic>;
        final client = context['client'] as Map<String, dynamic>;

        expect(capturedRequest.url.host, 'www.youtube.com');
        expect(capturedRequest.url.path, '/youtubei/v1/player');
        expect(capturedRequest.url.queryParameters['key'], 'AIzaFixture');
        expect(capturedRequest.headers['content-type'], 'application/json');
        expect(
          capturedRequest.headers['user-agent'],
          YouTubeApiClient.browserUserAgent,
        );
        expect(
          capturedRequest.headers.containsKey('x-youtube-client-name'),
          isFalse,
        );
        expect(client['clientName'], 'ANDROID');
        expect(client['clientVersion'], '21.08.266');
        expect(client['platform'], 'DESKTOP');
        expect(client['clientScreen'], 'EMBED');
        expect(client['clientFormFactor'], 'UNKNOWN_FORM_FACTOR');
        expect(client['browserName'], 'Chrome');
        expect(client.containsKey('originalUrl'), isFalse);
        expect(client.containsKey('userAgent'), isFalse);
        expect(client.containsKey('visitorData'), isFalse);
        expect(body.containsKey('playbackContext'), isFalse);
        expect(body.containsKey('serviceIntegrityDimensions'), isFalse);
        expect(body.containsKey('attestationRequest'), isFalse);
      },
    );

    test(
      'requests Streamlink Android profile first and emits HLS first',
      () async {
        final apiClient = _PlaybackBundleYouTubeApiClient(
          playerResponses: {
            YouTubePlayerClientProfile.streamlinkAndroid: _playerResponse(
              hlsManifestUrl:
                  'https://manifest.googlevideo.com/fixture/streamlink/master.m3u8',
              includeAdaptiveFormats: true,
            ),
            YouTubePlayerClientProfile.web: _playerResponse(
              includeMuxedFormat: true,
            ),
          },
        );
        final dataSource = YouTubePlaybackDataSource(apiClient: apiClient);

        final bundle = await dataSource.loadPlaybackBundle(
          bootstrap: _bootstrap(),
          resolvedVideoId: 'Z3eFGbFcaXs',
          sourcePageUrl: 'https://www.youtube.com/@fixture/live',
        );

        expect(
          apiClient.playerProfiles.first,
          YouTubePlayerClientProfile.streamlinkAndroid,
        );
        expect(
          bundle.primarySource?.clientProfile,
          YouTubePlayerClientProfile.streamlinkAndroid,
        );
        expect(bundle.primarySource?.isHls, isTrue);
        expect(bundle.playbackSources.first.isHls, isTrue);
        expect(
          bundle.playbackSources.first.url,
          'https://manifest.googlevideo.com/fixture/streamlink/master.m3u8',
        );
        expect(
          bundle.playbackSources.first.headers['origin'],
          'https://www.youtube.com',
        );
        expect(
          bundle.playbackSources.first.headers['referer'],
          'https://www.youtube.com/@fixture/live',
        );
        expect(bundle.playbackSources.any((item) => item.isDirect), isTrue);
        expect(bundle.playbackSources.last.isDirect, isTrue);
        expect(bundle.playbackUnavailableReason, isNull);
      },
    );

    test(
      'does not promote adaptive direct formats when no HLS exists',
      () async {
        final apiClient = _PlaybackBundleYouTubeApiClient(
          playerResponses: {
            YouTubePlayerClientProfile.streamlinkAndroid: _playerResponse(
              includeAdaptiveFormats: true,
            ),
          },
        );
        final dataSource = YouTubePlaybackDataSource(apiClient: apiClient);

        final bundle = await dataSource.loadPlaybackBundle(
          bootstrap: _bootstrap(),
          resolvedVideoId: 'Z3eFGbFcaXs',
          sourcePageUrl: 'https://www.youtube.com/@fixture/live',
        );

        expect(bundle.primarySource, isNull);
        expect(
          bundle.playbackSources.where((item) => item.isDirect),
          isNotEmpty,
        );
        expect(
          bundle.playbackUnavailableReason,
          contains('streamlink_android'),
        );
        expect(bundle.playbackUnavailableReason, contains('adaptive=2'));
        expect(
          bundle.playbackUnavailableReason,
          contains('不会自动降级到 direct adaptive'),
        );
      },
    );

    test('keeps existing HLS manifest without refreshing player', () async {
      final apiClient = _PlaybackBundleYouTubeApiClient();
      final dataSource = YouTubePlaybackDataSource(apiClient: apiClient);

      final manifestUrl = await dataSource.resolveManifestUrl(
        _detail(source: _hlsSource()),
      );

      expect(manifestUrl, _manifestUrl);
      expect(apiClient.playerProfiles, isEmpty);
    });

    test(
      'defaults unknown playback metadata profiles to Streamlink Android',
      () {
        final source = YouTubePlaybackSource.fromMetadata(const {
          'strategy': 'hls',
          'clientProfile': 'legacy-or-unknown',
          'lineLabel': 'Legacy HLS',
          'url': 'https://manifest.googlevideo.com/fixture/master.m3u8',
        });
        final audioSource = YouTubePlaybackAudioSource.fromMetadata(const {
          'clientProfile': 'legacy-or-unknown',
          'lineLabel': 'Legacy Audio',
          'url': 'https://rr.googlevideo.com/audio.m4a',
        });

        expect(
          source.clientProfile,
          YouTubePlayerClientProfile.streamlinkAndroid,
        );
        expect(
          audioSource.clientProfile,
          YouTubePlayerClientProfile.streamlinkAndroid,
        );
      },
    );

    test(
      'plays fixed HLS quality from master playlist without direct audio',
      () async {
        final dataSource = YouTubePlaybackDataSource(
          apiClient: _ManifestOnlyYouTubeApiClient(
            manifest: '''
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=6200000,RESOLUTION=1920x1080,FRAME-RATE=60.0
1080p60.m3u8
''',
          ),
        );
        final source = _hlsSource();
        final detail = _detail(
          source: source,
          audioSource: YouTubePlaybackAudioSource(
            clientProfile: source.clientProfile,
            lineLabel: 'Safari Audio',
            url:
                'https://rr.googlevideo.com/videoplayback?itag=140&n=challenge',
            headers: source.headers,
            bitrate: 128000,
            mimeType: 'audio/mp4; codecs="mp4a.40.2"',
          ),
        );

        final urls = await dataSource.fetchPlayUrls(
          detail: detail,
          quality: LivePlayQuality(id: '1080', label: '1080p'),
        );

        expect(urls, hasLength(1));
        expect(
          urls.single.url,
          'https://manifest.googlevideo.com/fixture/1080p60.m3u8',
        );
        expect(urls.single.metadata?['hlsBitrate'], '6200000');
        expect(urls.single.metadata?['masterPlaylistUrl'], isNull);
        expect(
          urls.single.metadata?['resolvedVariantUrl'],
          'https://manifest.googlevideo.com/fixture/1080p60.m3u8',
        );
        expect(urls.single.metadata?['masterPlaylistContent'], isNull);
        expect(urls.single.metadata?['audioUrl'], isNull);
      },
    );

    test(
      'emits fixed HLS variant with external audio rendition metadata',
      () async {
        final dataSource = YouTubePlaybackDataSource(
          apiClient: _ManifestOnlyYouTubeApiClient(
            manifest: '''
#EXTM3U
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud-main",NAME="Default",DEFAULT=YES,AUTOSELECT=YES,URI="audio-main.m3u8"
#EXT-X-STREAM-INF:BANDWIDTH=6200000,RESOLUTION=1920x1080,FRAME-RATE=60.0,AUDIO="aud-main"
1080p60.m3u8
''',
          ),
        );

        final urls = await dataSource.fetchPlayUrls(
          detail: _detail(source: _hlsSource()),
          quality: LivePlayQuality(id: '1080', label: '1080p'),
        );

        expect(urls, hasLength(1));
        expect(
          urls.single.url,
          'https://manifest.googlevideo.com/fixture/1080p60.m3u8',
        );
        expect(urls.single.metadata?['hlsBitrate'], '6200000');
        expect(urls.single.metadata?['masterPlaylistUrl'], isNull);
        expect(
          urls.single.metadata?['resolvedVariantUrl'],
          'https://manifest.googlevideo.com/fixture/1080p60.m3u8',
        );
        expect(
          urls.single.metadata?['audioUrl'],
          'https://manifest.googlevideo.com/fixture/audio-main.m3u8',
        );
        expect(urls.single.metadata?['masterPlaylistContent'], isNull);
      },
    );

    test(
      'pairs adaptive direct video-only formats with the best audio format',
      () async {
        final candidate = YouTubePlayerResponseCandidate(
          profile: YouTubePlayerClientProfile.web,
          sourcePageUrl: 'https://www.youtube.com/watch?v=test',
          requestClientContext: const {},
          playerResponse: {
            'streamingData': {
              'formats': [
                {
                  'itag': 22,
                  'height': 720,
                  'qualityLabel': '720p',
                  'mimeType': 'video/mp4; codecs="avc1.64001F, mp4a.40.2"',
                  'audioQuality': 'AUDIO_QUALITY_MEDIUM',
                  'url': 'https://rr.googlevideo.com/video/720p-muxed.mp4',
                  'bitrate': 2500000,
                },
              ],
              'adaptiveFormats': [
                {
                  'itag': 299,
                  'height': 1080,
                  'qualityLabel': '1080p60',
                  'mimeType': 'video/mp4; codecs="avc1.64002a"',
                  'url': 'https://rr.googlevideo.com/video/1080p.mp4',
                  'bitrate': 6686125,
                },
                {
                  'itag': 298,
                  'height': 720,
                  'qualityLabel': '720p60',
                  'mimeType': 'video/mp4; codecs="avc1.4d4020"',
                  'url': 'https://rr.googlevideo.com/video/720p.mp4',
                  'bitrate': 4018075,
                },
                {
                  'itag': 251,
                  'mimeType': 'audio/webm; codecs="opus"',
                  'url': 'https://rr.googlevideo.com/audio/opus.webm',
                  'bitrate': 96000,
                },
                {
                  'itag': 140,
                  'mimeType': 'audio/mp4; codecs="mp4a.40.2"',
                  'url': 'https://rr.googlevideo.com/audio/medium.m4a',
                  'bitrate': 144000,
                },
              ],
            },
          },
        );

        final directSources = YouTubePlaybackExtractor.extractDirectSources(
          candidate,
          (profile, sourcePageUrl) => {
            'referer': sourcePageUrl,
            'user-agent': profile.userAgent,
          },
        );

        expect(directSources, hasLength(2));
        expect(directSources.first.qualityLabel, '1080p60');
        expect(
          directSources.first.audioUrl,
          'https://rr.googlevideo.com/audio/medium.m4a',
        );
        expect(directSources.first.audioMimeType, contains('audio/mp4'));
        expect(directSources.last.qualityLabel, '720p');
        expect(directSources.last.audioUrl, isNull);

        final dataSource = YouTubePlaybackDataSource(
          apiClient: const _ManifestOnlyYouTubeApiClient(manifest: ''),
        );
        final urls = await dataSource.fetchPlayUrls(
          detail: _detail(source: directSources.first),
          quality: LivePlayQuality(
            id: '1080',
            label: '1080p60',
            metadata: {'playbackMode': 'direct'},
          ),
        );

        expect(urls, hasLength(1));
        expect(urls.single.url, 'https://rr.googlevideo.com/video/1080p.mp4');
        expect(
          urls.single.metadata?['audioUrl'],
          'https://rr.googlevideo.com/audio/medium.m4a',
        );
      },
    );

    test('does not emit direct fallback when HLS quality resolves', () async {
      final dataSource = YouTubePlaybackDataSource(
        apiClient: _ManifestOnlyYouTubeApiClient(
          manifest: '''
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=6200000,RESOLUTION=1920x1080,FRAME-RATE=60.0,CODECS="avc1.64002a,mp4a.40.2"
1080p60.m3u8
''',
        ),
      );
      final hlsSource = _hlsSource();
      const directSource = YouTubePlaybackSource(
        strategy: 'direct',
        clientProfile: YouTubePlayerClientProfile.web,
        lineLabel: 'Web Direct',
        url: 'https://rr.googlevideo.com/videoplayback?itag=137',
        headers: {
          'referer': 'https://www.youtube.com/watch?v=test',
          'user-agent': 'fixture-agent',
        },
        qualityId: '1080',
        qualityLabel: '1080p',
        sortOrder: 1080,
        mimeType: 'video/mp4; codecs="avc1.640028"',
        audioUrl: 'https://rr.googlevideo.com/videoplayback?itag=140',
        audioHeaders: {
          'referer': 'https://www.youtube.com/watch?v=test',
          'user-agent': 'fixture-agent',
        },
      );

      final urls = await dataSource.fetchPlayUrls(
        detail: _detailFromSources([hlsSource, directSource]),
        quality: LivePlayQuality(id: '1080', label: '1080p'),
      );

      expect(urls, hasLength(1));
      expect(
        urls.single.url,
        'https://manifest.googlevideo.com/fixture/1080p60.m3u8',
      );
      expect(urls.single.metadata?['strategy'], 'hls');
      expect(urls.single.metadata?['audioUrl'], isNull);
    });

    test('emits direct sources that require external audio', () async {
      final dataSource = YouTubePlaybackDataSource(
        apiClient: const _ManifestOnlyYouTubeApiClient(manifest: ''),
      );
      const directSource = YouTubePlaybackSource(
        strategy: 'direct',
        clientProfile: YouTubePlayerClientProfile.web,
        lineLabel: 'Web Direct',
        url: 'https://rr.googlevideo.com/videoplayback?itag=299',
        headers: {
          'referer': 'https://www.youtube.com/watch?v=test',
          'user-agent': 'fixture-agent',
        },
        qualityId: '1080',
        qualityLabel: '1080p60',
        sortOrder: 1080,
        mimeType: 'video/mp4; codecs="avc1.64002a"',
        audioUrl: 'https://rr.googlevideo.com/videoplayback?itag=140',
      );

      final urls = await dataSource.fetchPlayUrls(
        detail: _detail(source: directSource),
        quality: LivePlayQuality(
          id: '1080',
          label: '1080p60',
          metadata: {'playbackMode': 'direct'},
        ),
      );

      expect(urls, hasLength(1));
      expect(
        urls.single.url,
        'https://rr.googlevideo.com/videoplayback?itag=299',
      );
      expect(
        urls.single.metadata?['audioUrl'],
        'https://rr.googlevideo.com/videoplayback?itag=140',
      );
    });

    test('does not expose direct sources as default qualities', () async {
      final dataSource = YouTubePlaybackDataSource(
        apiClient: const _ManifestOnlyYouTubeApiClient(manifest: ''),
      );
      const directSource = YouTubePlaybackSource(
        strategy: 'direct',
        clientProfile: YouTubePlayerClientProfile.web,
        lineLabel: 'Web Direct',
        url: 'https://rr.googlevideo.com/videoplayback?itag=299',
        headers: {
          'referer': 'https://www.youtube.com/watch?v=test',
          'user-agent': 'fixture-agent',
        },
        qualityId: '1080',
        qualityLabel: '1080p60',
        sortOrder: 1080,
        mimeType: 'video/mp4; codecs="avc1.64002a"',
        audioUrl: 'https://rr.googlevideo.com/videoplayback?itag=140',
      );

      final qualities = await dataSource.fetchPlayQualities(
        _detail(source: directSource),
      );

      expect(qualities, isEmpty);
    });

    test('does not fallback to direct sources for normal quality', () async {
      final dataSource = YouTubePlaybackDataSource(
        apiClient: const _ManifestOnlyYouTubeApiClient(manifest: ''),
      );
      const directSource = YouTubePlaybackSource(
        strategy: 'direct',
        clientProfile: YouTubePlayerClientProfile.web,
        lineLabel: 'Web Direct',
        url: 'https://rr.googlevideo.com/videoplayback?itag=299',
        headers: {
          'referer': 'https://www.youtube.com/watch?v=test',
          'user-agent': 'fixture-agent',
        },
        qualityId: '1080',
        qualityLabel: '1080p60',
        sortOrder: 1080,
        mimeType: 'video/mp4; codecs="avc1.64002a"',
        audioUrl: 'https://rr.googlevideo.com/videoplayback?itag=140',
      );

      final urls = await dataSource.fetchPlayUrls(
        detail: _detail(source: directSource),
        quality: LivePlayQuality(id: '1080', label: '1080p60'),
      );

      expect(urls, isEmpty);
    });

    test(
      'prefers compatible HLS codec and emits direct variant playback',
      () async {
        final dataSource = YouTubePlaybackDataSource(
          apiClient: _ManifestOnlyYouTubeApiClient(
            manifest: '''
#EXTM3U
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud-main",NAME="Default",DEFAULT=YES,AUTOSELECT=YES,CHANNELS="2",URI="audio-main.m3u8"
#EXT-X-STREAM-INF:BANDWIDTH=7100000,RESOLUTION=1920x1080,FRAME-RATE=60.0,CODECS="av01.0.08M.08,mp4a.40.2",AUDIO="aud-main"
1080p60-av1.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=6200000,AVERAGE-BANDWIDTH=5800000,RESOLUTION=1920x1080,FRAME-RATE=60.0,CODECS="avc1.64002a,mp4a.40.2",VIDEO-RANGE=SDR,AUDIO="aud-main"
1080p60-avc.m3u8
''',
          ),
        );

        final urls = await dataSource.fetchPlayUrls(
          detail: _detail(source: _hlsSource()),
          quality: LivePlayQuality(id: '1080', label: '1080p'),
        );

        expect(urls, hasLength(1));
        expect(
          urls.single.url,
          'https://manifest.googlevideo.com/fixture/1080p60-avc.m3u8',
        );
        expect(
          urls.single.metadata?['resolvedVariantUrl'],
          'https://manifest.googlevideo.com/fixture/1080p60-avc.m3u8',
        );
        expect(
          urls.single.metadata?['audioUrl'],
          'https://manifest.googlevideo.com/fixture/audio-main.m3u8',
        );
        expect(urls.single.metadata?['masterPlaylistContent'], isNull);
      },
    );
  });
}

const _manifestUrl = 'https://manifest.googlevideo.com/fixture/master.m3u8';

YouTubePlaybackSource _hlsSource() {
  return const YouTubePlaybackSource(
    strategy: 'hls',
    clientProfile: YouTubePlayerClientProfile.streamlinkAndroid,
    lineLabel: 'Streamlink Android HLS',
    url: _manifestUrl,
    headers: {
      'origin': 'https://www.youtube.com',
      'referer': 'https://www.youtube.com/watch?v=test',
      'user-agent': 'fixture-agent',
    },
  );
}

YouTubePageBootstrap _bootstrap() {
  return const YouTubePageBootstrap(
    apiKey: 'AIzaFixture',
    initialPlayerResponse: {
      'videoDetails': {
        'title': 'Fixture Live',
        'author': 'Fixture Channel',
        'isLive': true,
        'isLiveContent': true,
      },
      'microformat': {
        'playerMicroformatRenderer': {
          'ownerProfileUrl': '/@fixture',
          'liveBroadcastDetails': {'isLiveNow': true},
        },
      },
    },
    innertubeContext: {
      'client': {'visitorData': 'visitor-fixture', 'hl': 'en', 'gl': 'US'},
    },
    rolloutToken: 'rollout-fixture',
    poToken: 'po-fixture',
  );
}

Map<String, dynamic> _playerResponse({
  String? hlsManifestUrl,
  bool includeAdaptiveFormats = false,
  bool includeMuxedFormat = false,
}) {
  return {
    'playabilityStatus': {'status': 'OK'},
    'videoDetails': {
      'title': 'Fixture Live',
      'author': 'Fixture Channel',
      'isLive': true,
      'isLiveContent': true,
    },
    'streamingData': {
      if (hlsManifestUrl != null) 'hlsManifestUrl': hlsManifestUrl,
      if (includeMuxedFormat)
        'formats': [
          {
            'itag': 22,
            'height': 720,
            'qualityLabel': '720p',
            'mimeType': 'video/mp4; codecs="avc1.64001F, mp4a.40.2"',
            'audioQuality': 'AUDIO_QUALITY_MEDIUM',
            'url': 'https://rr.googlevideo.com/video/720p-muxed.mp4',
            'bitrate': 2500000,
          },
        ],
      if (includeAdaptiveFormats)
        'adaptiveFormats': [
          {
            'itag': 299,
            'height': 1080,
            'qualityLabel': '1080p60',
            'mimeType': 'video/mp4; codecs="avc1.64002a"',
            'url': 'https://rr.googlevideo.com/video/1080p.mp4',
            'bitrate': 6686125,
          },
          {
            'itag': 140,
            'mimeType': 'audio/mp4; codecs="mp4a.40.2"',
            'url': 'https://rr.googlevideo.com/audio/medium.m4a',
            'bitrate': 144000,
          },
        ],
    },
  };
}

LiveRoomDetail _detail({
  required YouTubePlaybackSource source,
  YouTubePlaybackAudioSource? audioSource,
}) {
  return _detailFromSources(
    [source],
    audioSources: [if (audioSource != null) audioSource],
  );
}

LiveRoomDetail _detailFromSources(
  List<YouTubePlaybackSource> sources, {
  List<YouTubePlaybackAudioSource> audioSources = const [],
}) {
  return LiveRoomDetail(
    providerId: ProviderId.youtube,
    roomId: '@fixture/live',
    title: 'Fixture',
    streamerName: 'Fixture',
    sourceUrl: 'https://www.youtube.com/watch?v=test',
    metadata: {
      'playbackSources': [for (final source in sources) source.toMetadata()],
      if (audioSources.isNotEmpty)
        'playbackAudioSources': [
          for (final source in audioSources) source.toMetadata(),
        ],
    },
  );
}

class _ManifestOnlyYouTubeApiClient implements YouTubeApiClient {
  const _ManifestOnlyYouTubeApiClient({required this.manifest});

  final String manifest;

  @override
  Future<String> fetchText(
    String url, {
    Map<String, String> headers = const {},
  }) async {
    if (url == _manifestUrl) {
      return manifest;
    }
    throw StateError('Unexpected fetchText url: $url');
  }

  @override
  Future<int> probeStatus(
    String url, {
    Map<String, String> headers = const {},
  }) async {
    return 200;
  }

  @override
  Future<Map<String, dynamic>> postLiveChat({
    required String apiKey,
    required String continuation,
    required String visitorData,
    required String referer,
    String clientVersion = YouTubeApiClient.defaultWebClientVersion,
    Duration timeout = YouTubeApiClient.liveChatRequestTimeout,
  }) async {
    return const {};
  }

  @override
  Future<Map<String, dynamic>> postPlayer({
    required String apiKey,
    required String videoId,
    required String originalUrl,
    Map<String, dynamic> innertubeContext = const {},
    String rolloutToken = '',
    String poToken = '',
    YouTubePlayerClientProfile clientProfile =
        YouTubePlayerClientProfile.streamlinkAndroid,
  }) async {
    return const {};
  }
}

class _PlaybackBundleYouTubeApiClient implements YouTubeApiClient {
  _PlaybackBundleYouTubeApiClient({
    this.playerResponses = const {},
    this.manifest = '',
  });

  final Map<YouTubePlayerClientProfile, Map<String, dynamic>> playerResponses;
  final String manifest;
  final List<YouTubePlayerClientProfile> playerProfiles =
      <YouTubePlayerClientProfile>[];

  @override
  Future<String> fetchText(
    String url, {
    Map<String, String> headers = const {},
  }) async {
    if (url == _manifestUrl || url.contains('manifest.googlevideo.com')) {
      return manifest;
    }
    throw StateError('Unexpected fetchText url: $url');
  }

  @override
  Future<int> probeStatus(
    String url, {
    Map<String, String> headers = const {},
  }) async {
    return 200;
  }

  @override
  Future<Map<String, dynamic>> postLiveChat({
    required String apiKey,
    required String continuation,
    required String visitorData,
    required String referer,
    String clientVersion = YouTubeApiClient.defaultWebClientVersion,
    Duration timeout = YouTubeApiClient.liveChatRequestTimeout,
  }) async {
    return const {};
  }

  @override
  Future<Map<String, dynamic>> postPlayer({
    required String apiKey,
    required String videoId,
    required String originalUrl,
    Map<String, dynamic> innertubeContext = const {},
    String rolloutToken = '',
    String poToken = '',
    YouTubePlayerClientProfile clientProfile =
        YouTubePlayerClientProfile.streamlinkAndroid,
  }) async {
    playerProfiles.add(clientProfile);
    return playerResponses[clientProfile] ?? const {};
  }
}
