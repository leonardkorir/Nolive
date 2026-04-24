import 'package:live_core/live_core.dart';
import 'package:live_providers/live_providers.dart';
import 'package:live_providers/src/providers/chaturbate/chaturbate_api_client.dart';
import 'package:live_providers/src/providers/chaturbate/chaturbate_live_data_source.dart';
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
            containsAll([
              'female',
              'male',
              'couple',
              'trans',
            ]),
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
          expect(detail.danmakuToken, isA<Map>());

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
          expect(
            urls.single.url,
            detail.metadata?['hlsSource'],
          );
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
          expect(
            urls.single.headers['referer'],
            'https://chaturbate.com/',
          );
          expect(
            urls.single.headers['origin'],
            'https://chaturbate.com',
          );
        },
      );

      test(
          'fetch room detail primes playback bootstrap so play qualities avoid a second full hls wait',
          () async {
        final masterFixture = ChaturbateFixtureLoader.loadHlsMasterPlaylist();
        final apiClient = _FixtureChaturbateApiClient(
          roomPages: {
            'kittengirlxo': ChaturbateFixtureLoader.loadRoomPage(),
          },
          roomContexts: {
            'kittengirlxo': {
              'hls_source': masterFixture.url,
            },
          },
          hlsPlaylists: {
            masterFixture.url: masterFixture.content,
          },
          roomPageDelays: const {
            'kittengirlxo': Duration(milliseconds: 180),
          },
          roomContextDelays: const {
            'kittengirlxo': Duration(milliseconds: 30),
          },
          hlsPlaylistDelays: {
            masterFixture.url: const Duration(milliseconds: 180),
          },
        );
        final dataSource = ChaturbateLiveDataSource(apiClient: apiClient);

        final detail = await dataSource.fetchRoomDetail('kittengirlxo');
        final stopwatch = Stopwatch()..start();
        final qualities = await dataSource.fetchPlayQualities(detail);
        stopwatch.stop();

        expect(qualities, hasLength(greaterThan(1)));
        expect(
          stopwatch.elapsed,
          lessThan(const Duration(milliseconds: 150)),
        );
      });

      test('empty carousel response returns an empty recommend page', () async {
        final provider = ChaturbateProvider(
          dataSource: ChaturbateLiveDataSource(
            apiClient: _FixtureChaturbateApiClient(
              discoverCarousels: {
                _discoverKey('', 'recommended'):
                    ChaturbateFixtureLoader.loadCarousel(
                  'recommended',
                ),
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
        expect(
          urls.single.metadata?['hlsBitrate'],
          '3296000',
        );
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
        expect(
          urls.single.headers['origin'],
          'https://chaturbate.com',
        );
      });

      test(
          'play qualities refresh stale room context without forwarding request cookie to ll-hls playback',
          () async {
        const stalePlaylistUrl =
            'https://edge18-sin.live.mmcdn.com/v1/edge/streams/origin.dewdropdoll.stale/llhls.m3u8?token=stale';
        const refreshedPlaylistUrl =
            'https://edge3-lax.live.mmcdn.com/v1/edge/streams/origin.dewdropdoll.fresh/llhls.m3u8?token=fresh';
        final apiClient = _FixtureChaturbateApiClient(
          roomContexts: {
            'dewdropdoll': const {
              'hls_source': refreshedPlaylistUrl,
            },
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
          providerId: ProviderId.chaturbate.value,
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
        expect(qualities.first.metadata?['masterPlaylistUrl'],
            refreshedPlaylistUrl);
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
      });

      test(
          'play qualities refresh runs room context timeout and room page fallback in parallel',
          () async {
        const stalePlaylistUrl =
            'https://edge18-sin.live.mmcdn.com/v1/edge/streams/origin.kittengirlxo.stale/llhls.m3u8?token=stale';
        final apiClient = _FixtureChaturbateApiClient(
          roomPages: {
            'kittengirlxo': ChaturbateFixtureLoader.loadRoomPage(),
          },
          roomContexts: {
            'kittengirlxo': const {
              'hls_source': stalePlaylistUrl,
            },
          },
          defaultHlsPlaylist:
              ChaturbateFixtureLoader.loadHlsMasterPlaylist().content,
          failingHlsUrls: const {stalePlaylistUrl},
          roomContextDelays: const {
            'kittengirlxo': Duration(milliseconds: 200),
          },
          roomPageDelays: const {
            'kittengirlxo': Duration(milliseconds: 80),
          },
        );
        final dataSource = ChaturbateLiveDataSource(
          apiClient: apiClient,
          roomContextRequestTimeout: const Duration(milliseconds: 50),
          roomPageRequestTimeout: const Duration(milliseconds: 150),
          hlsPlaylistRequestTimeout: const Duration(milliseconds: 150),
        );
        final detail = LiveRoomDetail(
          providerId: ProviderId.chaturbate.value,
          roomId: 'kittengirlxo',
          title: 'kittengirlxo room',
          streamerName: 'kittengirlxo',
          sourceUrl: 'https://chaturbate.com/kittengirlxo/',
          metadata: const {
            'hlsSource': stalePlaylistUrl,
          },
        );

        final stopwatch = Stopwatch()..start();
        final qualities = await dataSource.fetchPlayQualities(detail);
        stopwatch.stop();

        expect(qualities, hasLength(greaterThan(1)));
        expect(
          stopwatch.elapsed,
          lessThan(const Duration(milliseconds: 150)),
        );
      });

      test(
          'play urls refresh stale auto fallback into a fresh chaturbate playback url',
          () async {
        const stalePlaylistUrl =
            'https://edge18-sin.live.mmcdn.com/v1/edge/streams/origin.ana_maria11.stale/llhls.m3u8?token=stale';
        const refreshedPlaylistUrl =
            'https://edge29-sin.live.mmcdn.com/v1/edge/streams/origin.ana_maria11.fresh/llhls.m3u8?token=fresh';
        final apiClient = _FixtureChaturbateApiClient(
          roomContexts: {
            'ana_maria11': const {
              'hls_source': refreshedPlaylistUrl,
            },
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
          providerId: ProviderId.chaturbate.value,
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
          quality: const LivePlayQuality(
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
      });

      test(
          'playback refresh falls back to room page when detail and room context miss hlsSource',
          () async {
        final masterFixture = ChaturbateFixtureLoader.loadHlsMasterPlaylist(
          harName: 'room-page-realcest-auto.har',
        );
        final apiClient = _FixtureChaturbateApiClient(
          roomPages: {
            'kittengirlxo': ChaturbateFixtureLoader.loadRoomPage(),
          },
          roomContexts: {
            'kittengirlxo': const {},
          },
          defaultHlsPlaylist: masterFixture.content,
        );
        final dataSource = ChaturbateLiveDataSource(apiClient: apiClient);
        const detail = LiveRoomDetail(
          providerId: 'chaturbate',
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
      });

      test('spy_shows carousel is filtered out of recommend flow', () async {
        final provider = ChaturbateProvider(
          dataSource: ChaturbateLiveDataSource(
            apiClient: _FixtureChaturbateApiClient(
              discoverCarousels: {
                _discoverKey('', 'most_popular'):
                    ChaturbateFixtureLoader.loadCarousel(
                  'most_popular',
                ),
                _discoverKey('', 'spy_shows'):
                    ChaturbateFixtureLoader.loadCarousel(
                  'spy_shows',
                ),
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

      test('chaturbate category rooms tolerate a transient carousel failure',
          () async {
        final apiClient = _FixtureChaturbateApiClient(
          discoverCarousels: {
            _discoverKey('f', 'most_popular'):
                ChaturbateFixtureLoader.loadCarousel(
              'most_popular',
              harName: 'discover-female.har',
              genders: 'f',
            ),
          },
          failOnceDiscoverKeys: {
            _discoverKey('f', 'most_popular'),
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

        expect(response.items, isNotEmpty);
        expect(
          apiClient.discoverRequestCounts[_discoverKey('f', 'most_popular')],
          2,
        );
      });
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
          ChaturbateFixtureLoader.loadCarousel(
        'recently_started',
      ),
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
    roomPages: {
      'kittengirlxo': ChaturbateFixtureLoader.loadRoomPage(),
    },
    defaultHlsPlaylist: ChaturbateFixtureLoader.loadHlsMasterPlaylist().content,
  );

  return ChaturbateProvider(
    dataSource: ChaturbateLiveDataSource(
      apiClient: apiClient,
    ),
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
    Set<String>? failingHlsUrls,
    Map<String, Duration>? roomPageDelays,
    Map<String, Duration>? roomContextDelays,
    Map<String, Duration>? hlsPlaylistDelays,
  })  : _discoverCarousels = discoverCarousels ?? const {},
        _searchResponses = searchResponses ?? const {},
        _roomPages = roomPages ?? const {},
        _roomContexts = roomContexts ?? const {},
        _hlsPlaylists = hlsPlaylists ?? const {},
        _defaultHlsPlaylist = defaultHlsPlaylist,
        _failOnceDiscoverKeys = {...?failOnceDiscoverKeys},
        _failingHlsUrls = {...?failingHlsUrls},
        _roomPageDelays = roomPageDelays ?? const {},
        _roomContextDelays = roomContextDelays ?? const {},
        _hlsPlaylistDelays = hlsPlaylistDelays ?? const {};

  final Map<String, Map<String, dynamic>> _discoverCarousels;
  final Map<String, Map<String, dynamic>> _searchResponses;
  final Map<String, String> _roomPages;
  final Map<String, Map<String, dynamic>> _roomContexts;
  final Map<String, String> _hlsPlaylists;
  final String? _defaultHlsPlaylist;
  final Set<String> _failOnceDiscoverKeys;
  final Set<String> _failingHlsUrls;
  final Map<String, Duration> _roomPageDelays;
  final Map<String, Duration> _roomContextDelays;
  final Map<String, Duration> _hlsPlaylistDelays;
  final Map<String, int> discoverRequestCounts = <String, int>{};
  final Map<String, String?> hlsPlaylistCookies = <String, String?>{};
  final Map<String, String?> roomContextCookies = <String, String?>{};

  @override
  Future<Map<String, dynamic>> fetchDiscoverCarousel(
    String carouselId, {
    String genders = '',
  }) async {
    final key = _discoverKey(genders, carouselId);
    discoverRequestCounts.update(key, (value) => value + 1, ifAbsent: () => 1);
    if (_failOnceDiscoverKeys.remove(key)) {
      throw ProviderParseException(
        providerId: ProviderId.chaturbate,
        message: 'fixture transient error for $key',
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
  }) async {
    final payload = _searchResponses[_searchKey(genders ?? '', query, offset)];
    if (payload == null) {
      fail(
        'Unexpected Chaturbate room-list request: '
        'query=$query genders=${genders ?? ''} offset=$offset',
      );
    }
    return payload;
  }

  @override
  Future<String> fetchRoomPage(String roomId) async {
    final delay = _roomPageDelays[roomId];
    if (delay != null) {
      await Future<void>.delayed(delay);
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
  }) async {
    roomContextCookies[roomId] = cookie;
    final delay = _roomContextDelays[roomId];
    if (delay != null) {
      await Future<void>.delayed(delay);
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
}

String _discoverKey(String genders, String carouselId) =>
    '$genders|$carouselId';

String _searchKey(String genders, String query, int offset) =>
    '$genders|$query|$offset';
