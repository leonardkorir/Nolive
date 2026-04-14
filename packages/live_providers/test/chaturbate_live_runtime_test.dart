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
            contains('chunklist'),
          );
          expect(urls.single.lineLabel, 'AUS');
        },
      );

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

      test('ll-hls runtime exposes separate audio rendition in play urls',
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
          qualities.first.metadata?['audioUrl'],
          contains('chunklist_5_audio_3689313794811747259_llhls.m3u8'),
        );
        expect(
          urls.single.metadata?['audioUrl'],
          contains('chunklist_5_audio_3689313794811747259_llhls.m3u8'),
        );
        expect(urls.single.url, contains('chunklist_4_video'));
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
    Map<String, String>? hlsPlaylists,
    String? defaultHlsPlaylist,
    Set<String>? failOnceDiscoverKeys,
  })  : _discoverCarousels = discoverCarousels ?? const {},
        _searchResponses = searchResponses ?? const {},
        _roomPages = roomPages ?? const {},
        _hlsPlaylists = hlsPlaylists ?? const {},
        _defaultHlsPlaylist = defaultHlsPlaylist,
        _failOnceDiscoverKeys = {...?failOnceDiscoverKeys};

  final Map<String, Map<String, dynamic>> _discoverCarousels;
  final Map<String, Map<String, dynamic>> _searchResponses;
  final Map<String, String> _roomPages;
  final Map<String, String> _hlsPlaylists;
  final String? _defaultHlsPlaylist;
  final Set<String> _failOnceDiscoverKeys;
  final Map<String, int> discoverRequestCounts = <String, int>{};

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
    final roomPage = _roomPages[roomId];
    if (roomPage == null) {
      fail('Unexpected Chaturbate room page request: $roomId');
    }
    return roomPage;
  }

  @override
  Future<String> fetchHlsPlaylist(
    String url, {
    String? referer,
  }) async {
    final payload = _hlsPlaylists[url] ?? _defaultHlsPlaylist;
    if (payload == null) {
      fail(
        'Unexpected Chaturbate HLS playlist request: '
        'url=$url referer=${referer ?? ''}',
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
