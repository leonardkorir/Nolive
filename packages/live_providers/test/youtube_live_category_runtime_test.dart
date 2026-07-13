import 'package:live_core/live_core.dart';
import 'package:live_providers/src/providers/youtube/youtube_api_client.dart';
import 'package:live_providers/src/providers/youtube/youtube_hls_master_playlist_parser.dart';
import 'package:live_providers/src/providers/youtube/youtube_live_data_source.dart';
import 'package:test/test.dart';

void main() {
  test('youtube live data source exposes first-class category model', () async {
    final dataSource = _FakeYouTubeCategoryDataSource();

    final categories = await dataSource.fetchCategories();
    expect(categories, hasLength(1));

    final gaming = categories.single.children.firstWhere(
      (item) => item.id == 'gaming',
    );
    final rooms = await dataSource.fetchCategoryRooms(gaming, page: 1);
    expect(rooms.items, hasLength(2));
    expect(rooms.items.every((item) => item.areaName == '游戏'), isTrue);
    expect(rooms.items.map((item) => item.roomId), hasLength(2));
  });

  test('youtube category loading tolerates partial query failures', () async {
    final dataSource = _FakeYouTubeCategoryDataSource(
      failingQueries: const {'esports live'},
    );

    final gaming = (await dataSource.fetchCategories()).single.children
        .firstWhere((item) => item.id == 'gaming');
    final rooms = await dataSource.fetchCategoryRooms(gaming, page: 1);

    expect(rooms.items, isNotEmpty);
    expect(rooms.items.map((item) => item.roomId), contains('@WenzelTCG/live'));
  });

  test('youtube recommend rooms pages through query batches', () async {
    final dataSource = _FakeYouTubeCategoryDataSource();

    final firstPage = await dataSource.fetchRecommendRooms(page: 1);
    expect(firstPage.items, isNotEmpty);
    expect(firstPage.hasMore, isTrue);
    expect(
      firstPage.items.map((item) => item.roomId),
      contains('@NewsNow/live'),
    );
    expect(
      firstPage.items.map((item) => item.roomId),
      contains('@MusicNow/live'),
    );

    final secondPage = await dataSource.fetchRecommendRooms(page: 2);
    expect(secondPage.items, isNotEmpty);
    expect(secondPage.hasMore, isTrue);
    expect(
      secondPage.items.map((item) => item.roomId),
      contains('@BreakingDesk/live'),
    );
    expect(secondPage.items.map((item) => item.roomId), contains('@ESL/live'));
  });

  test('youtube live data source caps HLS caches', () {
    final dataSource = _FakeYouTubeCategoryDataSource();
    const limit = 64;

    for (var index = 0; index < limit + 8; index += 1) {
      final url = 'https://example.com/$index.m3u8';
      dataSource.debugRememberHlsVariantCache(url, [
        YouTubeHlsVariant(url: url, bandwidth: index, label: '$index p'),
      ]);
      dataSource.debugRememberHlsUsabilityCache(url, index.isEven);
    }

    expect(dataSource.debugHlsVariantCacheSize, limit);
    expect(dataSource.debugHlsUsabilityCacheSize, limit);
  });

  test('youtube live data source bounds recursive context merge depth', () {
    final dataSource = _FakeYouTubeCategoryDataSource();
    final base = <String, dynamic>{
      'client': _deepNestedMap(depth: 80, leafKey: 'baseLeaf', leafValue: 'ok'),
    };
    final overlay = <String, dynamic>{
      'client': _deepNestedMap(
        depth: 80,
        leafKey: 'overlayLeaf',
        leafValue: 'applied',
      ),
      'hl': 'en',
    };

    final merged = dataSource.debugMergeContextMaps(base, overlay);
    expect(merged['hl'], 'en');
    expect(
      _readNestedLeafValue(
        merged['client'] as Map<String, dynamic>,
        depth: 80,
        leafKey: 'overlayLeaf',
      ),
      'applied',
    );
  });
}

Map<String, dynamic> _deepNestedMap({
  required int depth,
  required String leafKey,
  required Object leafValue,
}) {
  Map<String, dynamic> current = <String, dynamic>{leafKey: leafValue};
  for (var index = 0; index < depth; index += 1) {
    current = <String, dynamic>{'child': current};
  }
  return current;
}

Object? _readNestedLeafValue(
  Map<String, dynamic> source, {
  required int depth,
  required String leafKey,
}) {
  Map<String, dynamic> current = source;
  for (var index = 0; index < depth; index += 1) {
    current = current['child'] as Map<String, dynamic>;
  }
  return current[leafKey];
}

class _FakeYouTubeCategoryDataSource extends YouTubeLiveDataSource {
  _FakeYouTubeCategoryDataSource({this.failingQueries = const {}})
    : super(apiClient: _NoopYouTubeApiClient());

  final Set<String> failingQueries;

  @override
  Future<PagedResponse<LiveRoom>> searchRooms(
    String query, {
    int page = 1,
  }) async {
    if (failingQueries.contains(query)) {
      throw ProviderParseException(
        providerId: ProviderId.youtube,
        message: 'blocked query: $query',
      );
    }
    final rooms = <String, List<LiveRoom>>{
      'live news': const [
        LiveRoom(
          providerId: ProviderId.youtube,
          roomId: '@NewsNow/live',
          title: 'Live News Desk',
          streamerName: 'News Now',
          viewerCount: 9300,
        ),
      ],
      'breaking news live': const [
        LiveRoom(
          providerId: ProviderId.youtube,
          roomId: '@BreakingDesk/live',
          title: 'Breaking News',
          streamerName: 'Breaking Desk',
          viewerCount: 8700,
        ),
      ],
      'world news live': const [
        LiveRoom(
          providerId: ProviderId.youtube,
          roomId: '@WorldWire/live',
          title: 'World Wire Live',
          streamerName: 'World Wire',
          viewerCount: 8100,
        ),
      ],
      'politics live': const [
        LiveRoom(
          providerId: ProviderId.youtube,
          roomId: '@PoliticsNow/live',
          title: 'Politics Live',
          streamerName: 'Politics Now',
          viewerCount: 7600,
        ),
      ],
      'financial news live': const [
        LiveRoom(
          providerId: ProviderId.youtube,
          roomId: '@MarketWatch/live',
          title: 'Market Watch',
          streamerName: 'Market Watch',
          viewerCount: 7200,
        ),
      ],
      'gaming live': const [
        LiveRoom(
          providerId: ProviderId.youtube,
          roomId: '@WenzelTCG/live',
          title: 'WENZ VAULT!',
          streamerName: 'Wenzel TCG',
          viewerCount: 4821,
        ),
      ],
      'music live': const [
        LiveRoom(
          providerId: ProviderId.youtube,
          roomId: '@MusicNow/live',
          title: 'Music Now',
          streamerName: 'Music Now',
          viewerCount: 5400,
        ),
      ],
      'sports live': const [
        LiveRoom(
          providerId: ProviderId.youtube,
          roomId: '@SportsNow/live',
          title: 'Sports Live',
          streamerName: 'Sports Now',
          viewerCount: 6100,
        ),
      ],
      'podcast live': const [
        LiveRoom(
          providerId: ProviderId.youtube,
          roomId: '@TalkLive/live',
          title: 'Talk Live',
          streamerName: 'Talk Live',
          viewerCount: 4300,
        ),
      ],
      'esports live': const [
        LiveRoom(
          providerId: ProviderId.youtube,
          roomId: '@ESL/live',
          title: 'ESL Live Finals',
          streamerName: 'ESL',
          viewerCount: 16400,
        ),
      ],
      'gameplay live': const [
        LiveRoom(
          providerId: ProviderId.youtube,
          roomId: '@WenzelTCG/live',
          title: 'WENZ VAULT!',
          streamerName: 'Wenzel TCG',
          viewerCount: 4821,
        ),
      ],
    };
    return PagedResponse(
      items: rooms[query] ?? const [],
      hasMore: false,
      page: page,
    );
  }
}

class _NoopYouTubeApiClient implements YouTubeApiClient {
  @override
  Future<String> fetchText(
    String url, {
    Map<String, String> headers = const {},
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<int> probeStatus(
    String url, {
    Map<String, String> headers = const {},
  }) async {
    throw UnimplementedError();
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
    throw UnimplementedError();
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
    throw UnimplementedError();
  }
}
