import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:live_core/live_core.dart';
import 'package:live_providers/live_providers.dart';
import 'package:live_providers/src/danmaku/chaturbate_danmaku_session.dart';
import 'package:live_providers/src/danmaku/provider_unavailable_danmaku_session.dart';
import 'package:live_providers/src/providers/chaturbate/chaturbate_api_client.dart';
import 'package:live_providers/src/providers/chaturbate/chaturbate_discover_policy.dart';
import 'package:live_providers/src/providers/chaturbate/chaturbate_live_data_source.dart';
import 'package:live_providers/src/providers/chaturbate/chaturbate_mapper.dart';
import 'package:test/test.dart';

import 'support/chaturbate_fixture_loader.dart';

void main() {
  group(
    'fixture-backed chaturbate runtime coverage',
    skip: ChaturbateFixtureLoader.skipReason,
    () {
      test(
        'live chaturbate runtime maps categories/search/detail/play flow from fixtures',
        () async {
          final provider = _buildFixtureProvider();

          final categories = await provider.fetchCategories();
          expect(categories, hasLength(1));
          expect(
            categories.single.children.map((item) => item.id),
            containsAll(['female', 'male', 'couple', 'trans']),
          );

          final female = categories.single.children.firstWhere(
            (item) => item.id == 'female',
          );
          final femaleRooms = await provider.fetchCategoryRooms(female);
          expect(femaleRooms.items, isNotEmpty);
          expect(femaleRooms.items.first.areaName, 'Female');
          expect(
            femaleRooms.items.any((item) => item.roomId == 'sigmasian'),
            isTrue,
          );

          final search = await provider.searchRooms('lucy');
          expect(search.items, isNotEmpty);
          expect(search.items.first.roomId, 'lucysalvatore');
          expect(search.items.first.streamerName, 'lucysalvatore');
          expect(search.items.first.areaName, 'Female');

          final detail = await provider.fetchRoomDetail('kittengirlxo');
          expect(detail.roomId, 'kittengirlxo');
          expect(detail.title, "Kittengirlxo's room");
          expect(detail.sourceUrl, 'https://chaturbate.com/kittengirlxo/');
          expect(detail.isLive, isTrue);
          expect(detail.danmakuToken, isA<ChaturbateDanmakuToken>());

          final qualities = await provider.fetchPlayQualities(detail);
          expect(qualities, hasLength(5));
          expect(qualities.first.id, 'auto');
          expect(qualities.first.isDefault, isTrue);
          expect(
            qualities.skip(1).map((item) => item.label),
            orderedEquals(const ['1080p', '720p', '480p', '240p']),
          );

          final urls = await provider.fetchPlayUrls(
            detail: detail,
            quality: qualities[1],
          );
          expect(urls, hasLength(1));
          expect(urls.single.url, detail.metadata?['hlsSource']);
          expect(urls.single.metadata?['hlsBitrate'], qualities[1].id);
          expect(
            urls.single.metadata?['resolvedVariantUrl'],
            contains('chunklist'),
          );
          expect(
            urls.single.metadata?['audioUrl'],
            anyOf(isNull, contains('chunklist')),
          );
          expect(urls.single.lineLabel, 'AUS');
          expect(urls.single.headers['referer'], 'https://chaturbate.com/');
          expect(urls.single.headers['origin'], 'https://chaturbate.com');
        },
      );

      test(
        'fetch room detail keeps context playback data and merges room page danmaku token',
        () async {
          final masterFixture = ChaturbateFixtureLoader.loadHlsMasterPlaylist();
          final apiClient = _FixtureChaturbateApiClient(
            roomPages: {'kittengirlxo': ChaturbateFixtureLoader.loadRoomPage()},
            roomContexts: {
              'kittengirlxo': {'hls_source': masterFixture.url},
            },
            hlsPlaylists: {masterFixture.url: masterFixture.content},
            roomPageDelays: const {'kittengirlxo': Duration(milliseconds: 180)},
            roomContextDelays: const {
              'kittengirlxo': Duration(milliseconds: 180),
            },
            hlsPlaylistDelays: {
              masterFixture.url: const Duration(milliseconds: 180),
            },
          );
          final dataSource = ChaturbateLiveDataSource(apiClient: apiClient);

          final detailStopwatch = Stopwatch()..start();
          final detail = await dataSource.fetchRoomDetail('kittengirlxo');
          detailStopwatch.stop();
          final stopwatch = Stopwatch()..start();
          final qualities = await dataSource.fetchPlayQualities(detail);
          stopwatch.stop();

          expect(detail.metadata?['hlsSource'], masterFixture.url);
          expect(detail.danmakuToken, isA<ChaturbateDanmakuToken>());
          // Context then page (sequential) when cookie lacks csrf — two ~180ms
          // fixture delays, no longer parallel.
          expect(
            detailStopwatch.elapsed,
            lessThan(const Duration(milliseconds: 500)),
          );
          expect(qualities, hasLength(greaterThan(1)));
          expect(
            stopwatch.elapsed,
            lessThan(const Duration(milliseconds: 250)),
          );
          expect(apiClient.roomPageRequestCounts['kittengirlxo'], 1);
          expect(apiClient.roomPageCookies['kittengirlxo'], '');
        },
      );

      test(
        'fetch room detail can merge danmaku token from page without parsing dossier',
        () async {
          const page = '''
<html><script>
window["tsInstance"] = new TS({
  push_services: JSON.parse('[{"backend":"a","host":"realtime.pa.highwebmedia.com","fallback_hosts":["b-fallback.pa.highwebmedia.com"],"rest_host":"realtime.pa.highwebmedia.com"}]'),
  csrftoken: 'csrf-from-page'
});
</script></html>
''';
          final apiClient = _FixtureChaturbateApiClient(
            roomPages: {'kittengirlxo': page},
            roomContexts: const {
              'kittengirlxo': {
                'broadcaster_username': 'kittengirlxo',
                'broadcaster_uid': '100',
                'room_uid': '200',
                'room_status': 'public',
                'hls_source': 'https://edge.example/live.m3u8',
              },
            },
          );
          final dataSource = ChaturbateLiveDataSource(apiClient: apiClient);

          final detail = await dataSource.fetchRoomDetail('kittengirlxo');
          final token = detail.danmakuToken;

          expect(token, isA<ChaturbateDanmakuToken>());
          expect((token as ChaturbateDanmakuToken).csrfToken, 'csrf-from-page');
          expect(token.broadcasterUid, '100');
          expect(token.roomUid, '200');
          expect(token.host, 'realtime.pa.highwebmedia.com');
        },
      );

      test(
        'fetch room detail merges separately parsed bootstrap when page dossier has no danmaku ids',
        () async {
          final pageDossier = jsonEncode(
            jsonEncode({
              'room_status': 'public',
              'room_title': 'Shell room',
              'hls_source': 'https://edge.example/page-shell.m3u8',
            }),
          );
          final page =
              '''
<html><script>
window.initialRoomDossier = $pageDossier;
window["tsInstance"] = new TS(extend({
  push_services: JSON.parse('[{"backend":"a","host":"realtime.pa.highwebmedia.com","fallback_hosts":["b-fallback.pa.highwebmedia.com"],"rest_host":"realtime.pa.highwebmedia.com"}]'),
  csrftoken: 'csrf-from-page'
}, {}));
</script></html>
''';
          final apiClient = _FixtureChaturbateApiClient(
            roomPages: {'kittengirlxo': page},
            roomContexts: const {
              'kittengirlxo': {
                'broadcaster_username': 'kittengirlxo',
                'broadcaster_uid': '100',
                'room_uid': '200',
                'room_status': 'public',
                'hls_source': 'https://edge.example/live.m3u8',
              },
            },
          );
          final dataSource = ChaturbateLiveDataSource(apiClient: apiClient);

          final detail = await dataSource.fetchRoomDetail('kittengirlxo');
          final token = detail.danmakuToken;

          expect(detail.roomId, 'kittengirlxo');
          expect(
            detail.metadata?['hlsSource'],
            'https://edge.example/live.m3u8',
          );
          expect(token, isA<ChaturbateDanmakuToken>());
          expect((token as ChaturbateDanmakuToken).csrfToken, 'csrf-from-page');
          expect(token.broadcasterUid, '100');
          expect(token.roomUid, '200');
          expect(token.host, 'realtime.pa.highwebmedia.com');
        },
      );

      test('playback bootstrap cache is capped', () {
        final dataSource = ChaturbateLiveDataSource(
          apiClient: _FixtureChaturbateApiClient(),
        );

        for (var index = 0; index < 72; index += 1) {
          dataSource.debugRememberPlaybackBootstrap('room-$index');
        }

        expect(dataSource.debugPlaybackBootstrapCacheSize, 64);
      });

      test('empty carousel response returns an empty recommend page', () async {
        final provider = ChaturbateProvider(
          dataSource: ChaturbateLiveDataSource(
            apiClient: _FixtureChaturbateApiClient(
              searchResponses: {
                _searchKey('', '', 0): const {
                  'rooms': <Object>[],
                  'total_count': 0,
                },
              },
              discoverCarousels: {
                _discoverKey('', 'recommended'):
                    ChaturbateFixtureLoader.loadCarousel('recommended'),
              },
            ),
            recommendCarouselIds: const ['recommended'],
          ),
        );

        final recommend = await provider.fetchRecommendRooms();
        expect(recommend.items, isEmpty);
        expect(recommend.hasMore, isFalse);
        expect(recommend.page, 1);
      });

      test(
        'll-hls runtime keeps split playback when room detail still exposes classic hls_source',
        () async {
          final provider = ChaturbateProvider(
            dataSource: ChaturbateLiveDataSource(
              apiClient: _FixtureChaturbateApiClient(
                roomPages: {
                  'kittengirlxo': ChaturbateFixtureLoader.loadRoomPage(),
                },
                defaultHlsPlaylist: '''
#EXTM3U
#EXT-X-VERSION:6
#EXT-X-INDEPENDENT-SEGMENTS
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio_aac_96",NAME="Audio_1_1_5",DEFAULT=NO,AUTOSELECT=NO,FORCED=NO,CHANNELS="2",URI="/v1/edge/streams/origin.pinkypuppa.01KNFDA17Y6RTSYE3GWA8VYTPT/chunklist_5_audio_3689313794811747259_llhls.m3u8?session=e92ff262-9461-43b8-9ee4-ef180e1ea521"

#EXT-X-STREAM-INF:BANDWIDTH=1296000,RESOLUTION=852x480,FRAME-RATE=30.000,CODECS="avc1.4d401f,mp4a.40.2",AUDIO="audio_aac_96"
/v1/edge/streams/origin.pinkypuppa.01KNFDA17Y6RTSYE3GWA8VYTPT/chunklist_2_video_3689313794811747259_llhls.m3u8?session=e92ff262-9461-43b8-9ee4-ef180e1ea521
#EXT-X-STREAM-INF:BANDWIDTH=3296000,RESOLUTION=1280x720,FRAME-RATE=30.000,CODECS="avc1.4d401f,mp4a.40.2",AUDIO="audio_aac_96"
/v1/edge/streams/origin.pinkypuppa.01KNFDA17Y6RTSYE3GWA8VYTPT/chunklist_4_video_3689313794811747259_llhls.m3u8?session=e92ff262-9461-43b8-9ee4-ef180e1ea521
''',
              ),
            ),
          );

          final detail = await provider.fetchRoomDetail('kittengirlxo');
          final qualities = await provider.fetchPlayQualities(detail);
          final urls = await provider.fetchPlayUrls(
            detail: detail,
            quality: qualities[1],
          );

          expect(qualities, hasLength(3));
          expect(
            qualities.first.metadata?['masterPlaylistUrl'],
            detail.metadata?['hlsSource'],
          );
          expect(qualities.first.metadata?['hlsBitrate'], '1296000');
          expect(
            qualities.first.metadata?['masterPlaylistContent'],
            contains('#EXT-X-STREAM-INF:'),
          );
          expect(urls.single.url, contains('chunklist_4_video'));
          expect(urls.single.metadata?['hlsBitrate'], '3296000');
          expect(
            urls.single.metadata?['masterPlaylistContent'],
            contains('#EXT-X-STREAM-INF:'),
          );
          expect(urls.single.metadata?['resolvedVariantUrl'], isNull);
          expect(
            urls.single.metadata?['audioUrl'],
            contains('chunklist_5_audio'),
          );
          expect(urls.single.headers['referer'], 'https://chaturbate.com/');
          expect(urls.single.headers['origin'], 'https://chaturbate.com');
        },
      );

      test(
        'play qualities refresh stale room context without forwarding request cookie to ll-hls playback',
        () async {
          const stalePlaylistUrl =
              'https://edge18-sin.live.mmcdn.com/v1/edge/streams/origin.dewdropdoll.stale/llhls.m3u8?token=stale';
          const refreshedPlaylistUrl =
              'https://edge3-lax.live.mmcdn.com/v1/edge/streams/origin.dewdropdoll.fresh/llhls.m3u8?token=fresh';
          final apiClient = _FixtureChaturbateApiClient(
            roomContexts: {
              'dewdropdoll': const {'hls_source': refreshedPlaylistUrl},
            },
            hlsPlaylists: {
              refreshedPlaylistUrl: '''
#EXTM3U
#EXT-X-VERSION:6
#EXT-X-INDEPENDENT-SEGMENTS
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio_aac_96",NAME="Audio_1_1_5",DEFAULT=NO,AUTOSELECT=NO,FORCED=NO,CHANNELS="2",URI="/v1/edge/streams/origin.dewdropdoll.fresh/chunklist_5_audio_llhls.m3u8?session=fresh"

#EXT-X-STREAM-INF:BANDWIDTH=1296000,RESOLUTION=852x480,FRAME-RATE=30.000,CODECS="avc1.4d401f,mp4a.40.2",AUDIO="audio_aac_96"
/v1/edge/streams/origin.dewdropdoll.fresh/chunklist_2_video_llhls.m3u8?session=fresh
#EXT-X-STREAM-INF:BANDWIDTH=3296000,RESOLUTION=1280x720,FRAME-RATE=30.000,CODECS="avc1.4d401f,mp4a.40.2",AUDIO="audio_aac_96"
/v1/edge/streams/origin.dewdropdoll.fresh/chunklist_4_video_llhls.m3u8?session=fresh
''',
            },
            failingHlsUrls: const {stalePlaylistUrl},
          );
          final dataSource = ChaturbateLiveDataSource(apiClient: apiClient);
          final detail = LiveRoomDetail(
            providerId: ProviderId.chaturbate,
            roomId: 'dewdropdoll',
            title: 'dewdropdoll room',
            streamerName: 'dewdropdoll',
            sourceUrl: 'https://chaturbate.com/dewdropdoll/',
            metadata: const {
              'hlsSource': stalePlaylistUrl,
              'requestCookie': 'cf_clearance=demo; csrftoken=demo',
            },
          );

          final qualities = await dataSource.fetchPlayQualities(detail);
          final urls = await dataSource.fetchPlayUrls(
            detail: detail,
            quality: qualities.first,
          );

          expect(qualities, hasLength(3));
          expect(
            qualities.first.metadata?['masterPlaylistUrl'],
            refreshedPlaylistUrl,
          );
          expect(qualities.first.metadata?['hlsBitrate'], '1296000');
          expect(
            qualities.first.metadata?['masterPlaylistContent'],
            contains('#EXT-X-STREAM-INF:'),
          );
          expect(urls.single.url, contains('chunklist_2_video_llhls.m3u8'));
          expect(urls.single.metadata?['hlsBitrate'], '1296000');
          expect(
            urls.single.metadata?['masterPlaylistUrl'],
            refreshedPlaylistUrl,
          );
          expect(
            urls.single.metadata?['masterPlaylistContent'],
            contains('#EXT-X-STREAM-INF:'),
          );
          expect(
            urls.single.metadata?['audioUrl'],
            contains('chunklist_5_audio_llhls.m3u8'),
          );
          expect(
            apiClient.hlsPlaylistCookies[stalePlaylistUrl],
            anyOf(isNull, isEmpty),
          );
          expect(
            apiClient.hlsPlaylistCookies[refreshedPlaylistUrl],
            anyOf(isNull, isEmpty),
          );
          expect(
            apiClient.roomContextCookies['dewdropdoll'],
            anyOf(isNull, isEmpty),
          );
        },
      );

      test(
        'play qualities refresh runs room context timeout and room page fallback in parallel',
        () async {
          const stalePlaylistUrl =
              'https://edge18-sin.live.mmcdn.com/v1/edge/streams/origin.kittengirlxo.stale/llhls.m3u8?token=stale';
          final apiClient = _FixtureChaturbateApiClient(
            roomPages: {'kittengirlxo': ChaturbateFixtureLoader.loadRoomPage()},
            roomContexts: {
              'kittengirlxo': const {'hls_source': stalePlaylistUrl},
            },
            defaultHlsPlaylist:
                ChaturbateFixtureLoader.loadHlsMasterPlaylist().content,
            failingHlsUrls: const {stalePlaylistUrl},
            roomContextDelays: const {
              'kittengirlxo': Duration(milliseconds: 200),
            },
            roomPageDelays: const {'kittengirlxo': Duration(milliseconds: 80)},
          );
          final dataSource = ChaturbateLiveDataSource(
            apiClient: apiClient,
            roomContextRequestTimeout: const Duration(milliseconds: 50),
            roomPageRequestTimeout: const Duration(milliseconds: 150),
            hlsPlaylistRequestTimeout: const Duration(milliseconds: 150),
          );
          final detail = LiveRoomDetail(
            providerId: ProviderId.chaturbate,
            roomId: 'kittengirlxo',
            title: 'kittengirlxo room',
            streamerName: 'kittengirlxo',
            sourceUrl: 'https://chaturbate.com/kittengirlxo/',
            metadata: const {'hlsSource': stalePlaylistUrl},
          );

          final stopwatch = Stopwatch()..start();
          final qualities = await dataSource.fetchPlayQualities(detail);
          stopwatch.stop();

          expect(qualities, hasLength(greaterThan(1)));
          expect(
            stopwatch.elapsed,
            lessThan(const Duration(milliseconds: 150)),
          );
        },
      );

      test(
        'play urls refresh stale auto fallback into a fresh chaturbate playback url',
        () async {
          const stalePlaylistUrl =
              'https://edge18-sin.live.mmcdn.com/v1/edge/streams/origin.ana_maria11.stale/llhls.m3u8?token=stale';
          const refreshedPlaylistUrl =
              'https://edge29-sin.live.mmcdn.com/v1/edge/streams/origin.ana_maria11.fresh/llhls.m3u8?token=fresh';
          final apiClient = _FixtureChaturbateApiClient(
            roomContexts: {
              'ana_maria11': const {'hls_source': refreshedPlaylistUrl},
            },
            hlsPlaylists: {
              refreshedPlaylistUrl: '''
#EXTM3U
#EXT-X-VERSION:6
#EXT-X-INDEPENDENT-SEGMENTS
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio_aac_96",NAME="Audio_1_1_5",DEFAULT=NO,AUTOSELECT=NO,FORCED=NO,CHANNELS="2",URI="/v1/edge/streams/origin.ana_maria11.fresh/chunklist_6_audio_llhls.m3u8?session=fresh"

#EXT-X-STREAM-INF:BANDWIDTH=3296000,RESOLUTION=1280x720,FRAME-RATE=30.000,CODECS="avc1.4d401f,mp4a.40.2",AUDIO="audio_aac_96"
/v1/edge/streams/origin.ana_maria11.fresh/chunklist_4_video_llhls.m3u8?session=fresh
''',
            },
            failingHlsUrls: const {stalePlaylistUrl},
          );
          final dataSource = ChaturbateLiveDataSource(apiClient: apiClient);
          final detail = LiveRoomDetail(
            providerId: ProviderId.chaturbate,
            roomId: 'ana_maria11',
            title: 'ana_maria11 room',
            streamerName: 'ana_maria11',
            sourceUrl: 'https://chaturbate.com/ana_maria11/',
            metadata: const {
              'hlsSource': stalePlaylistUrl,
              'requestCookie': 'cf_clearance=demo; csrftoken=demo',
            },
          );

          final urls = await dataSource.fetchPlayUrls(
            detail: detail,
            quality: LivePlayQuality(
              id: 'auto',
              label: 'Auto',
              isDefault: true,
            ),
          );

          expect(urls, hasLength(1));
          expect(urls.single.url, contains('chunklist_4_video_llhls.m3u8'));
          expect(urls.single.metadata?['hlsBitrate'], '3296000');
          expect(
            urls.single.metadata?['masterPlaylistUrl'],
            refreshedPlaylistUrl,
          );
          expect(
            urls.single.metadata?['audioUrl'],
            contains('chunklist_6_audio_llhls.m3u8'),
          );
          expect(
            apiClient.roomContextCookies['ana_maria11'],
            anyOf(isNull, isEmpty),
          );
          expect(
            apiClient.hlsPlaylistCookies[refreshedPlaylistUrl],
            anyOf(isNull, isEmpty),
          );
        },
      );

      test(
        'playback refresh falls back to room page when detail and room context miss hlsSource',
        () async {
          final masterFixture = ChaturbateFixtureLoader.loadHlsMasterPlaylist(
            harName: 'room-page-realcest-auto.har',
          );
          final apiClient = _FixtureChaturbateApiClient(
            roomPages: {'kittengirlxo': ChaturbateFixtureLoader.loadRoomPage()},
            roomContexts: {'kittengirlxo': const {}},
            defaultHlsPlaylist: masterFixture.content,
          );
          final dataSource = ChaturbateLiveDataSource(apiClient: apiClient);
          const detail = LiveRoomDetail(
            providerId: ProviderId.chaturbate,
            roomId: 'kittengirlxo',
            title: "Kittengirlxo's room",
            streamerName: 'kittengirlxo',
            sourceUrl: 'https://chaturbate.com/kittengirlxo/',
            isLive: true,
          );

          final qualities = await dataSource.fetchPlayQualities(detail);
          final urls = await dataSource.fetchPlayUrls(
            detail: detail,
            quality: qualities.first,
          );

          expect(qualities, isNotEmpty);
          expect(qualities.first.metadata?['masterPlaylistUrl'], isNotNull);
          expect(urls, hasLength(1));
          expect(urls.single.url, contains('.m3u8'));
          expect(urls.single.metadata?['masterPlaylistUrl'], isNotNull);
        },
      );

      test('spy_shows carousel is filtered out of recommend flow', () async {
        final provider = ChaturbateProvider(
          dataSource: ChaturbateLiveDataSource(
            apiClient: _FixtureChaturbateApiClient(
              searchResponses: {
                _searchKey('', '', 0): const {
                  'rooms': <Object>[],
                  'total_count': 0,
                },
              },
              discoverCarousels: {
                _discoverKey('', 'most_popular'):
                    ChaturbateFixtureLoader.loadCarousel('most_popular'),
                _discoverKey('', 'spy_shows'):
                    ChaturbateFixtureLoader.loadCarousel('spy_shows'),
              },
            ),
            recommendCarouselIds: const ['most_popular', 'spy_shows'],
          ),
        );

        final recommend = await provider.fetchRecommendRooms();
        expect(recommend.items, isNotEmpty);
        expect(
          recommend.items.any((item) => item.roomId == 'kittengirlxo'),
          isTrue,
        );
        expect(
          recommend.items.any((item) => item.roomId == 'yourlittlesunrise_'),
          isFalse,
        );
      });

      test(
        'chaturbate category rooms use carousel-first and stop on success',
        () async {
          final apiClient = _FixtureChaturbateApiClient(
            searchResponses: {
              _searchKey('f', '', 0): {
                'rooms': const [
                  {
                    'username': 'should_not_use_roomlist',
                    'gender': 'f',
                    'current_show': 'public',
                    'room_subject': 'list only',
                    'num_users': 1,
                    'has_password': false,
                  },
                ],
                'total_count': 1,
              },
            },
            discoverCarousels: {
              _discoverKey(
                'f',
                'most_popular',
              ): ChaturbateFixtureLoader.loadCarousel(
                'most_popular',
                harName: 'discover-female.har',
                genders: 'f',
              ),
            },
          );
          final provider = ChaturbateProvider(
            dataSource: ChaturbateLiveDataSource(
              apiClient: apiClient,
              recommendCarouselIds: const ['most_popular', 'trending'],
            ),
          );

          final female = ChaturbateMapper.categories.single.children.firstWhere(
            (item) => item.id == 'female',
          );
          final response = await provider.fetchCategoryRooms(female);

          expect(response.items, isNotEmpty);
          expect(
            response.items.any((item) => item.roomId == 'should_not_use_roomlist'),
            isFalse,
          );
          expect(
            apiClient.discoverRequestCounts[_discoverKey('f', 'most_popular')],
            1,
          );
          expect(
            apiClient.discoverRequestCounts[_discoverKey('f', 'trending')],
            isNull,
          );
          expect(apiClient.roomListRequestCounts[_searchKey('f', '', 0)], isNull);
        },
      );
    },
  );

  test(
    'follow budget path uses context only and never fetches room page',
    () async {
      final apiClient = _FixtureChaturbateApiClient(
        roomContexts: const {
          'kitayamachu': {
            'broadcaster_username': 'kitayamachu',
            'broadcaster_uid': '1',
            'room_uid': '2',
            'room_status': 'public',
            'room_title': 'follow status',
            'num_viewers': 42,
          },
        },
        // Page would succeed if called — status-only must not touch it.
        roomPages: const {
          'kitayamachu': '<html>should not be requested</html>',
        },
      );
      final dataSource = ChaturbateLiveDataSource(apiClient: apiClient);

      final detail = await ChaturbateRequestScheduler.runAsFollowBudget(
        () => dataSource.fetchRoomDetail('kitayamachu'),
      );

      expect(detail.roomId, 'kitayamachu');
      expect(detail.isLive, isTrue);
      expect(detail.viewerCount, 42);
      expect(detail.title, 'follow status');
      expect(apiClient.roomContextRequestCounts['kitayamachu'], 1);
      expect(apiClient.roomPageRequestCounts, isEmpty);
    },
  );

  test(
    'follow budget path does not fall back to room page when context fails',
    () async {
      final apiClient = _FixtureChaturbateApiClient(
        failingRoomContexts: const {'kitayamachu'},
        roomPages: const {
          'kitayamachu': '''
<html><script>
window.initialRoomDossier = "{\\"broadcaster_username\\":\\"kitayamachu\\",\\"room_status\\":\\"public\\",\\"room_title\\":\\"from page\\"}";
</script></html>
''',
        },
      );
      final dataSource = ChaturbateLiveDataSource(apiClient: apiClient);

      await expectLater(
        ChaturbateRequestScheduler.runAsFollowBudget(
          () => dataSource.fetchRoomDetail('kitayamachu'),
        ),
        throwsA(
          isA<ProviderParseException>().having(
            (e) => e.message,
            'message',
            contains('status 401'),
          ),
        ),
      );
      expect(apiClient.roomContextRequestCounts['kitayamachu'], 1);
      expect(apiClient.roomPageRequestCounts, isEmpty);
    },
  );

  test(
    'password-protected context returns locked detail without room page',
    () async {
      final apiClient = _FixtureChaturbateApiClient(
        passwordRoomContexts: const {'kitayamachu'},
        roomPages: const {
          'kitayamachu': '<html>should not be requested</html>',
        },
      );
      final dataSource = ChaturbateLiveDataSource(apiClient: apiClient);

      final detail = await dataSource.fetchRoomDetail('kitayamachu');

      expect(detail.roomId, 'kitayamachu');
      // Password rooms count as not publicly live (follow 未开播 filter).
      expect(detail.isLive, isFalse);
      expect(detail.metadata?['passwordProtected'], isTrue);
      expect(detail.metadata?['roomStatus'], 'password');
      expect(
        detail.metadata?['playbackUnavailableReason'],
        contains('加锁'),
      );
      expect(apiClient.roomContextRequestCounts['kitayamachu'], 1);
      expect(apiClient.roomPageRequestCounts, isEmpty);
      expect(await dataSource.fetchPlayQualities(detail), isEmpty);
    },
  );

  test(
    'follow budget password path returns locked detail without page',
    () async {
      final apiClient = _FixtureChaturbateApiClient(
        passwordRoomContexts: const {'kitayamachu'},
        roomPages: const {
          'kitayamachu': '<html>should not be requested</html>',
        },
      );
      final dataSource = ChaturbateLiveDataSource(apiClient: apiClient);

      final detail = await ChaturbateRequestScheduler.runAsFollowBudget(
        () => dataSource.fetchRoomDetail('kitayamachu'),
      );

      expect(detail.metadata?['passwordProtected'], isTrue);
      expect(apiClient.roomPageRequestCounts, isEmpty);
    },
  );

  test(
    'fetch room detail prefers anonymous room context over room page',
    () async {
      const hlsSource =
          'https://edge11-lax.live.mmcdn.com/v1/edge/streams/origin.demo/llhls.m3u8?token=fresh';
      final apiClient = _FixtureChaturbateApiClient(
        roomContexts: {
          'dianafrisky': const {
            'broadcaster_username': 'dianafrisky',
            'broadcaster_uid': '123',
            'room_uid': '456',
            'broadcaster_gender': 'female',
            'room_status': 'public',
            'room_title': 'Diana room',
            'num_viewers': 321,
            'hls_source': hlsSource,
          },
        },
        failingRoomPages: const {'dianafrisky'},
        hlsPlaylists: const {hlsSource: '#EXTM3U\n'},
      );
      final dataSource = ChaturbateLiveDataSource(apiClient: apiClient);

      final detail = await dataSource.fetchRoomDetail('dianafrisky');

      expect(detail.roomId, 'dianafrisky');
      expect(detail.title, 'Diana room');
      expect(detail.areaName, 'Female');
      expect(detail.isLive, isTrue);
      expect(detail.viewerCount, 321);
      expect(detail.metadata?['hlsSource'], hlsSource);
      expect(detail.danmakuToken, isNull);
      expect(
        apiClient.roomContextCookies['dianafrisky'],
        anyOf(isNull, isEmpty),
      );
      // Context-first detail skips room page when context succeeds.
      expect(
        apiClient.roomPageCookies['dianafrisky'],
        anyOf(isNull, isEmpty),
      );
    },
  );

  test('search rooms use anonymous room-list (HAR-aligned)', () async {
    final apiClient = _FixtureChaturbateApiClient(
      searchResponses: {
        _searchKey('', 'diana', 0): {
          'rooms': const [
            {
              'username': 'dianafrisky',
              'gender': 'f',
              'current_show': 'public',
              'room_subject': 'Diana room',
              'num_users': 321,
              'has_password': false,
            },
          ],
          'total_count': 1,
        },
      },
    );
    final provider = ChaturbateProvider(
      dataSource: ChaturbateLiveDataSource(apiClient: apiClient),
    );

    final response = await provider.searchRooms('diana');

    expect(response.items.single.roomId, 'dianafrisky');
    expect(apiClient.roomListCookies[_searchKey('', 'diana', 0)], isEmpty);
  });

  test(
    'discover rooms fall back to anonymous room-list when carousels empty',
    () async {
      final apiClient = _FixtureChaturbateApiClient(
        searchResponses: {
          _searchKey('f', '', 0): {
            'rooms': const [
              {
                'username': 'dianafrisky',
                'gender': 'f',
                'current_show': 'public',
                'room_subject': 'Diana room',
                'num_users': 321,
                'has_password': false,
                'spy_show_price': 6,
                'img': 'https://thumb.live.mmcdn.com/riw/dianafrisky.jpg',
              },
              {
                'username': 'hidden_room',
                'gender': 'f',
                'current_show': 'private',
                'room_subject': 'Hidden room',
                'num_users': 100,
                'has_password': false,
              },
            ],
            'total_count': 2,
          },
        },
        discoverCarousels: {
          _discoverKey('f', 'most_popular'): const {
            'rooms': <Object>[],
          },
        },
      );
      final provider = ChaturbateProvider(
        dataSource: ChaturbateLiveDataSource(
          apiClient: apiClient,
          recommendCarouselIds: const ['most_popular'],
        ),
      );

      final female = ChaturbateMapper.categories.single.children.firstWhere(
        (item) => item.id == 'female',
      );
      final response = await provider.fetchCategoryRooms(female);

      expect(response.items, hasLength(1));
      expect(response.items.single.roomId, 'dianafrisky');
      expect(response.items.single.viewerCount, 321);
      expect(apiClient.roomListRequireFingerprint[_searchKey('f', '', 0)], false);
      expect(apiClient.roomListCookies[_searchKey('f', '', 0)], isEmpty);
      expect(
        apiClient.discoverRequestCounts[_discoverKey('f', 'most_popular')],
        1,
      );
    },
  );

  test(
    'discover rooms skip room-list fallback when carousels are rate limited',
    () async {
      final apiClient = _FixtureChaturbateApiClient(
        failingRoomListKeys: {_searchKey('', '', 0)},
        roomListFailureStatus: 429,
        failingDiscoverKeys: {_discoverKey('', 'most_popular')},
      );
      final provider = ChaturbateProvider(
        dataSource: ChaturbateLiveDataSource(
          apiClient: apiClient,
          recommendCarouselIds: const ['most_popular', 'recently_started'],
          discoverBudget: const ChaturbateDiscoverBudget(),
        ),
      );

      final response = await provider.fetchRecommendRooms();

      expect(response.items, isEmpty);
      expect(response.hasMore, isFalse);
      expect(
        apiClient.discoverRequestCounts[_discoverKey('', 'most_popular')],
        1,
      );
      // 429 on carousel → do not also burn room-list.
      expect(apiClient.roomListRequestCounts[_searchKey('', '', 0)], isNull);
    },
  );

  test(
    'discover rooms return empty list when carousels are rate limited',
    () async {
      final apiClient = _FixtureChaturbateApiClient(
        searchResponses: {
          _searchKey('', '', 0): const {'rooms': <Object>[], 'total_count': 0},
        },
        failingDiscoverKeys: {
          _discoverKey('', 'most_popular'),
          _discoverKey('', 'recently_started'),
        },
      );
      final provider = ChaturbateProvider(
        dataSource: ChaturbateLiveDataSource(
          apiClient: apiClient,
          recommendCarouselIds: const ['most_popular', 'recently_started'],
        ),
      );

      final response = await provider.fetchRecommendRooms();

      expect(response.items, isEmpty);
      expect(response.hasMore, isFalse);
      expect(
        apiClient.discoverRequestCounts[_discoverKey('', 'most_popular')],
        1,
      );
      // Rate-limit breaks carousel walk; no second carousel / no room-list.
      expect(
        apiClient.discoverRequestCounts[_discoverKey('', 'recently_started')],
        isNull,
      );
      expect(apiClient.roomListRequestCounts[_searchKey('', '', 0)], isNull);
    },
  );

  test(
    'discover recommend completes when room-list hangs and carousels recover',
    () async {
      final apiClient = _FixtureChaturbateApiClient(
        hangingRoomListKeys: {_searchKey('', '', 0)},
        discoverCarousels: {
          _discoverKey('', 'most_popular'): {
            'rooms': const [
              {
                'room': 'recover_room',
                'viewers': 42,
                'room_subject': 'Recovered',
                'gender': 'f',
              },
            ],
          },
        },
      );
      final provider = ChaturbateProvider(
        dataSource: ChaturbateLiveDataSource(
          apiClient: apiClient,
          recommendCarouselIds: const ['most_popular'],
          discoverRequestTimeout: const Duration(milliseconds: 40),
          discoverOverallTimeout: const Duration(milliseconds: 200),
        ),
      );

      final startedAt = DateTime.now();
      final response = await provider.fetchRecommendRooms();
      final elapsed = DateTime.now().difference(startedAt);

      expect(response.items.single.roomId, 'recover_room');
      expect(elapsed, lessThan(const Duration(milliseconds: 180)));
    },
  );

  test(
    'discover category completes with empty list when room-list and carousels hang',
    () async {
      final apiClient = _FixtureChaturbateApiClient(
        hangingRoomListKeys: {_searchKey('f', '', 0)},
        hangingDiscoverKeys: {_discoverKey('f', 'most_popular')},
      );
      final provider = ChaturbateProvider(
        dataSource: ChaturbateLiveDataSource(
          apiClient: apiClient,
          recommendCarouselIds: const ['most_popular'],
          discoverRequestTimeout: const Duration(milliseconds: 30),
          discoverOverallTimeout: const Duration(milliseconds: 120),
        ),
      );
      final female = ChaturbateMapper.categories.single.children.firstWhere(
        (item) => item.id == 'female',
      );

      final startedAt = DateTime.now();
      final response = await provider.fetchCategoryRooms(female);
      final elapsed = DateTime.now().difference(startedAt);

      expect(response.items, isEmpty);
      expect(response.hasMore, isFalse);
      expect(elapsed, lessThan(const Duration(milliseconds: 250)));
    },
  );

  test(
    'fetch room detail builds danmaku token from context uid + cookie csrf when page lacks bootstrap',
    () async {
      final client = HttpChaturbateApiClient(
      requestScheduler: ChaturbateRequestScheduler(minSpacing: Duration.zero, maxConcurrent: 8),
        cookie: 'csrftoken=csrf-from-cookie; sessionid=abc',
        client: MockClient((request) async {
          if (request.url.path == '/api/chatvideocontext/milabunny_/') {
            return http.Response(
              jsonEncode({
                'broadcaster_username': 'milabunny_',
                'broadcaster_uid': '9001',
                'room_uid': '9002',
                'room_status': 'public',
                'hls_source': 'https://edge.example/live.m3u8',
              }),
              200,
            );
          }
          if (request.url.path == '/milabunny_/') {
            return http.Response('<html>anonymous shell</html>', 200);
          }
          fail('Unexpected request: ${request.url}');
        }),
      );
      final provider = ChaturbateProvider(
        dataSource: ChaturbateLiveDataSource(apiClient: client),
        danmakuApiClient: client,
      );

      final detail = await provider.fetchRoomDetail('milabunny_');
      final token = detail.danmakuToken;
      expect(token, isA<ChaturbateDanmakuToken>());
      expect((token as ChaturbateDanmakuToken).csrfToken, 'csrf-from-cookie');
      expect(token.broadcasterUid, '9001');
      expect(token.roomUid, '9002');

      final session = await provider.createDanmakuSession(detail);
      expect(session, isA<ChaturbateDanmakuSession>());
      expect(session, isNot(isA<ProviderUnavailableDanmakuSession>()));
    },
  );

  test(
    'fetch room detail retries room page with account cookie when anonymous page lacks realtime bootstrap',
    () async {
      final client = HttpChaturbateApiClient(
      requestScheduler: ChaturbateRequestScheduler(minSpacing: Duration.zero, maxConcurrent: 8),
        cookie: 'cf_clearance=test-clearance',
        client: MockClient((request) async {
          if (request.url.path == '/api/chatvideocontext/kittengirlxo/') {
            return http.Response(
              jsonEncode({
                'broadcaster_username': 'kittengirlxo',
                'broadcaster_uid': '100',
                'room_uid': '200',
                'room_status': 'public',
                'hls_source': 'https://edge.example/live.m3u8',
              }),
              200,
            );
          }
          if (request.url.path == '/kittengirlxo/') {
            final cookie = request.headers['cookie'] ?? '';
            if (cookie.isEmpty) {
              return http.Response('<html>anonymous shell</html>', 200);
            }
            return http.Response('''
<html><script>
window["tsInstance"] = new TS({
  push_services: JSON.parse('[{"backend":"a","host":"realtime.pa.highwebmedia.com"}]'),
  csrftoken: 'csrf-from-cookie-page'
});
</script></html>
''', 200);
          }
          fail('Unexpected request: ${request.url}');
        }),
      );
      final dataSource = ChaturbateLiveDataSource(apiClient: client);

      final detail = await dataSource.fetchRoomDetail('kittengirlxo');
      final token = detail.danmakuToken;

      expect(token, isA<ChaturbateDanmakuToken>());
      expect(
        (token as ChaturbateDanmakuToken).csrfToken,
        'csrf-from-cookie-page',
      );
      expect(token.broadcasterUid, '100');
      expect(token.roomUid, '200');
    },
  );
}

ChaturbateProvider _buildFixtureProvider() {
  final apiClient = _FixtureChaturbateApiClient(
    discoverCarousels: {
      _discoverKey('', 'most_popular'): ChaturbateFixtureLoader.loadCarousel(
        'most_popular',
      ),
      _discoverKey('', 'trending'): ChaturbateFixtureLoader.loadCarousel(
        'trending',
      ),
      _discoverKey('', 'top-rated'): ChaturbateFixtureLoader.loadCarousel(
        'top-rated',
      ),
      _discoverKey('', 'recently_started'):
          ChaturbateFixtureLoader.loadCarousel('recently_started'),
      _discoverKey('f', 'most_popular'): ChaturbateFixtureLoader.loadCarousel(
        'most_popular',
        harName: 'discover-female.har',
        genders: 'f',
      ),
      _discoverKey('f', 'trending'): ChaturbateFixtureLoader.loadCarousel(
        'trending',
        harName: 'discover-female.har',
        genders: 'f',
      ),
      _discoverKey('f', 'top-rated'): ChaturbateFixtureLoader.loadCarousel(
        'top-rated',
        harName: 'discover-female.har',
        genders: 'f',
      ),
      _discoverKey(
        'f',
        'recently_started',
      ): ChaturbateFixtureLoader.loadCarousel(
        'recently_started',
        harName: 'discover-female.har',
        genders: 'f',
      ),
    },
    searchResponses: {
      _searchKey('', 'lucy', 0): ChaturbateFixtureLoader.loadSearchResponse(
        query: 'lucy',
      ),
    },
    roomPages: {'kittengirlxo': ChaturbateFixtureLoader.loadRoomPage()},
    defaultHlsPlaylist: ChaturbateFixtureLoader.loadHlsMasterPlaylist().content,
  );

  return ChaturbateProvider(
    dataSource: ChaturbateLiveDataSource(apiClient: apiClient),
    danmakuApiClient: apiClient,
  );
}

class _FixtureChaturbateApiClient implements ChaturbateApiClient {
  _FixtureChaturbateApiClient({
    Map<String, Map<String, dynamic>>? discoverCarousels,
    Map<String, Map<String, dynamic>>? searchResponses,
    Map<String, String>? roomPages,
    Map<String, Map<String, dynamic>>? roomContexts,
    Map<String, String>? hlsPlaylists,
    String? defaultHlsPlaylist,
    Set<String>? failOnceDiscoverKeys,
    Set<String>? failingDiscoverKeys,
    Set<String>? hangingDiscoverKeys,
    Set<String>? hangingRoomListKeys,
    Set<String>? failingRoomListKeys,
    int roomListFailureStatus = 500,
    Set<String>? failingRoomPages,
    Set<String>? failingRoomContexts,
    Set<String>? passwordRoomContexts,
    Set<String>? failingHlsUrls,
    Map<String, Duration>? roomPageDelays,
    Map<String, Duration>? roomContextDelays,
    Map<String, Duration>? hlsPlaylistDelays,
    Map<String, Duration>? roomListDelays,
    Map<String, Duration>? discoverDelays,
  }) : _discoverCarousels = discoverCarousels ?? const {},
       _searchResponses = searchResponses ?? const {},
       _roomPages = roomPages ?? const {},
       _roomContexts = roomContexts ?? const {},
       _hlsPlaylists = hlsPlaylists ?? const {},
       _defaultHlsPlaylist = defaultHlsPlaylist,
       _failOnceDiscoverKeys = {...?failOnceDiscoverKeys},
       _failingDiscoverKeys = {...?failingDiscoverKeys},
       _hangingDiscoverKeys = {...?hangingDiscoverKeys},
       _hangingRoomListKeys = {...?hangingRoomListKeys},
       _failingRoomListKeys = {...?failingRoomListKeys},
       _roomListFailureStatus = roomListFailureStatus,
       _failingRoomPages = {...?failingRoomPages},
       _failingRoomContexts = {...?failingRoomContexts},
       _passwordRoomContexts = {...?passwordRoomContexts},
       _failingHlsUrls = {...?failingHlsUrls},
       _roomPageDelays = roomPageDelays ?? const {},
       _roomContextDelays = roomContextDelays ?? const {},
       _hlsPlaylistDelays = hlsPlaylistDelays ?? const {},
       _roomListDelays = roomListDelays ?? const {},
       _discoverDelays = discoverDelays ?? const {};

  final Map<String, Map<String, dynamic>> _discoverCarousels;
  final Map<String, Map<String, dynamic>> _searchResponses;
  final Map<String, String> _roomPages;
  final Map<String, Map<String, dynamic>> _roomContexts;
  final Map<String, String> _hlsPlaylists;
  final String? _defaultHlsPlaylist;
  final Set<String> _failOnceDiscoverKeys;
  final Set<String> _failingDiscoverKeys;
  final Set<String> _hangingDiscoverKeys;
  final Set<String> _hangingRoomListKeys;
  final Set<String> _failingRoomListKeys;
  final int _roomListFailureStatus;
  final Set<String> _failingRoomPages;
  final Set<String> _failingRoomContexts;
  final Set<String> _passwordRoomContexts;
  final Set<String> _failingHlsUrls;
  final Map<String, Duration> _roomPageDelays;
  final Map<String, Duration> _roomContextDelays;
  final Map<String, Duration> _hlsPlaylistDelays;
  final Map<String, Duration> _roomListDelays;
  final Map<String, Duration> _discoverDelays;
  final Map<String, int> discoverRequestCounts = <String, int>{};
  final Map<String, int> roomListRequestCounts = <String, int>{};
  final Map<String, int> roomPageRequestCounts = <String, int>{};
  final Map<String, int> roomContextRequestCounts = <String, int>{};
  final Map<String, String?> hlsPlaylistCookies = <String, String?>{};
  final Map<String, String?> roomContextCookies = <String, String?>{};
  final Map<String, String?> roomPageCookies = <String, String?>{};
  final Map<String, bool> roomListRequireFingerprint = <String, bool>{};
  final Map<String, String?> roomListCookies = <String, String?>{};

  @override
  Future<Map<String, dynamic>> fetchDiscoverCarousel(
    String carouselId, {
    String genders = '',
  }) async {
    final key = _discoverKey(genders, carouselId);
    discoverRequestCounts.update(key, (value) => value + 1, ifAbsent: () => 1);
    final delay = _discoverDelays[key];
    if (delay != null) {
      await Future<void>.delayed(delay);
    }
    if (_hangingDiscoverKeys.contains(key)) {
      return Completer<Map<String, dynamic>>().future;
    }
    if (_failOnceDiscoverKeys.remove(key)) {
      throw ProviderParseException(
        providerId: ProviderId.chaturbate,
        message: 'fixture transient error for $key',
      );
    }
    if (_failingDiscoverKeys.contains(key)) {
      throw ProviderParseException(
        providerId: ProviderId.chaturbate,
        message:
            'Chaturbate carousel $carouselId request failed with status 429.',
      );
    }
    final payload = _discoverCarousels[key];
    if (payload == null) {
      fail(
        'Unexpected Chaturbate carousel request: $carouselId genders=$genders',
      );
    }
    return payload;
  }

  @override
  Future<Map<String, dynamic>> fetchRoomList({
    required String query,
    String? genders,
    int limit = ChaturbateApiClient.searchPageSize,
    int offset = 0,
    bool requireFingerprint = true,
    String? cookie,
  }) async {
    final key = _searchKey(genders ?? '', query, offset);
    roomListRequestCounts.update(key, (value) => value + 1, ifAbsent: () => 1);
    roomListRequireFingerprint[key] = requireFingerprint;
    roomListCookies[key] = cookie;
    final delay = _roomListDelays[key];
    if (delay != null) {
      await Future<void>.delayed(delay);
    }
    if (_hangingRoomListKeys.contains(key)) {
      return Completer<Map<String, dynamic>>().future;
    }
    if (_failingRoomListKeys.contains(key)) {
      throw ProviderParseException(
        providerId: ProviderId.chaturbate,
        message:
            'Chaturbate room list request failed with status '
            '$_roomListFailureStatus.',
      );
    }
    final payload = _searchResponses[key];
    if (payload == null) {
      fail(
        'Unexpected Chaturbate room-list request: '
        'query=$query genders=${genders ?? ''} offset=$offset',
      );
    }
    return payload;
  }

  @override
  Future<String> fetchRoomPage(
    String roomId, {
    String? cookie,
    ChaturbateRequestPriority priority = ChaturbateRequestPriority.normal,
  }) async {
    roomPageCookies[roomId] = cookie;
    roomPageRequestCounts.update(
      roomId,
      (value) => value + 1,
      ifAbsent: () => 1,
    );
    final delay = _roomPageDelays[roomId];
    if (delay != null) {
      await Future<void>.delayed(delay);
    }
    if (_failingRoomPages.contains(roomId)) {
      throw ProviderParseException(
        providerId: ProviderId.chaturbate,
        message: 'fixture room page failed: $roomId',
      );
    }
    final roomPage = _roomPages[roomId];
    if (roomPage == null) {
      fail('Unexpected Chaturbate room page request: $roomId');
    }
    return roomPage;
  }

  @override
  Future<Map<String, dynamic>> fetchRoomContext(
    String roomId, {
    String? cookie,
    ChaturbateRequestPriority priority = ChaturbateRequestPriority.normal,
  }) async {
    roomContextCookies[roomId] = cookie;
    roomContextRequestCounts.update(
      roomId,
      (value) => value + 1,
      ifAbsent: () => 1,
    );
    final delay = _roomContextDelays[roomId];
    if (delay != null) {
      await Future<void>.delayed(delay);
    }
    if (_passwordRoomContexts.contains(roomId)) {
      throw ProviderParseException(
        providerId: ProviderId.chaturbate,
        message:
            'Chaturbate room context request for $roomId: '
            'room requires a password.',
      );
    }
    if (_failingRoomContexts.contains(roomId)) {
      throw ProviderParseException(
        providerId: ProviderId.chaturbate,
        message:
            'Chaturbate room context request for $roomId failed with status 401.',
      );
    }
    final payload = _roomContexts[roomId];
    if (payload == null) {
      fail('Unexpected Chaturbate room context request: $roomId');
    }
    return payload;
  }

  @override
  Future<String> fetchHlsPlaylist(
    String url, {
    String? referer,
    String? cookie,
    ChaturbateRequestPriority priority = ChaturbateRequestPriority.normal,
  }) async {
    hlsPlaylistCookies[url] = cookie;
    final delay = _hlsPlaylistDelays[url];
    if (delay != null) {
      await Future<void>.delayed(delay);
    }
    if (_failingHlsUrls.contains(url)) {
      throw ProviderParseException(
        providerId: ProviderId.chaturbate,
        message: 'fixture stale hls playlist: $url',
      );
    }
    final payload = _hlsPlaylists[url] ?? _defaultHlsPlaylist;
    if (payload == null) {
      fail(
        'Unexpected Chaturbate HLS playlist request: '
        'url=$url referer=${referer ?? ''} cookie=${cookie ?? ''}',
      );
    }
    return payload;
  }

  @override
  Future<Map<String, dynamic>> authenticatePushService({
    required String roomId,
    required String csrfToken,
    required String backend,
    required String presenceId,
    required Map<String, dynamic> topics,
  }) async {
    fail('Unexpected push_service/auth request in runtime fixture test');
  }

  @override
  Future<List<Map<String, dynamic>>> fetchRoomHistory({
    required String roomId,
    required String csrfToken,
    required Map<String, dynamic> topics,
  }) async {
    fail('Unexpected room_history request in runtime fixture test');
  }

  @override
  void close() {}
}

String _discoverKey(String genders, String carouselId) =>
    '$genders|$carouselId';

String _searchKey(String genders, String query, int offset) =>
    '$genders|$query|$offset';
