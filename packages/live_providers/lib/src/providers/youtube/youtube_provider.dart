import 'package:live_core/live_core.dart';

import '../../danmaku/provider_ticker_danmaku_session.dart';
import '../../danmaku/provider_unavailable_danmaku_session.dart';
import '../../danmaku/youtube_danmaku_session.dart';
import 'youtube_api_client.dart';
import 'youtube_data_source.dart';
import 'youtube_live_data_source.dart';
import 'youtube_preview_data_source.dart';

class YouTubeProvider extends LiveProvider
    implements
        SupportsCategories,
        SupportsCategoryRooms,
        SupportsRecommendRooms,
        SupportsRoomSearch,
        SupportsRoomDetail,
        SupportsPlayQualities,
        SupportsPlayUrls,
        SupportsDanmaku {
  YouTubeProvider({
    YouTubeDataSource? dataSource,
    YouTubeApiClient? danmakuApiClient,
  })  : _dataSource = dataSource ?? const YouTubePreviewDataSource(),
        _danmakuApiClient = danmakuApiClient;

  factory YouTubeProvider.preview() => YouTubeProvider();

  factory YouTubeProvider.live({YouTubeApiClient? apiClient}) {
    final resolvedApiClient = apiClient ?? HttpYouTubeApiClient();
    return YouTubeProvider(
      dataSource: YouTubeLiveDataSource(
        apiClient: resolvedApiClient,
      ),
      danmakuApiClient: resolvedApiClient,
    );
  }

  static const ProviderDescriptor kDescriptor = ProviderDescriptor(
    id: ProviderId.youtube,
    displayName: 'YouTube',
    capabilities: {
      ProviderCapability.categories,
      ProviderCapability.recommendRooms,
      ProviderCapability.searchRooms,
      ProviderCapability.roomDetail,
      ProviderCapability.playQualities,
      ProviderCapability.playUrls,
      ProviderCapability.danmaku,
    },
    supportedPlatforms: {
      ProviderPlatform.android,
      ProviderPlatform.ios,
      ProviderPlatform.windows,
      ProviderPlatform.macos,
      ProviderPlatform.linux,
      ProviderPlatform.androidTv,
    },
    roomIdPatterns: [
      r'^[A-Za-z0-9_-]{11}$',
      r'^@[A-Za-z0-9._-]{3,64}/live$',
      r'^(channel|c|user)/[A-Za-z0-9._-]{1,128}/live$',
    ],
    maturity: ProviderMaturity.inMigration,
  );

  final YouTubeDataSource _dataSource;
  final YouTubeApiClient? _danmakuApiClient;

  @override
  ProviderDescriptor get descriptor => kDescriptor;

  @override
  Future<List<LiveCategory>> fetchCategories() {
    requireCapability(ProviderCapability.categories);
    return _dataSource.fetchCategories();
  }

  @override
  Future<PagedResponse<LiveRoom>> fetchCategoryRooms(
    LiveSubCategory category, {
    int page = 1,
  }) {
    requireCapability(ProviderCapability.categories);
    return _dataSource.fetchCategoryRooms(category, page: page);
  }

  @override
  Future<PagedResponse<LiveRoom>> fetchRecommendRooms({int page = 1}) {
    requireCapability(ProviderCapability.recommendRooms);
    return _dataSource.fetchRecommendRooms(page: page);
  }

  @override
  Future<PagedResponse<LiveRoom>> searchRooms(String query, {int page = 1}) {
    requireCapability(ProviderCapability.searchRooms);
    return _dataSource.searchRooms(query, page: page);
  }

  @override
  Future<LiveRoomDetail> fetchRoomDetail(String roomId) {
    requireCapability(ProviderCapability.roomDetail);
    return _dataSource.fetchRoomDetail(roomId);
  }

  @override
  Future<List<LivePlayQuality>> fetchPlayQualities(LiveRoomDetail detail) {
    requireCapability(ProviderCapability.playQualities);
    return _dataSource.fetchPlayQualities(detail);
  }

  @override
  Future<List<LivePlayUrl>> fetchPlayUrls({
    required LiveRoomDetail detail,
    required LivePlayQuality quality,
  }) {
    requireCapability(ProviderCapability.playUrls);
    return _dataSource.fetchPlayUrls(detail: detail, quality: quality);
  }

  @override
  Future<DanmakuSession> createDanmakuSession(LiveRoomDetail detail) async {
    requireCapability(ProviderCapability.danmaku);
    final token = detail.danmakuToken;
    if (token is Map && token['mode']?.toString() == 'preview') {
      return ProviderTickerDanmakuSession(
        providerId: descriptor.id.value,
        detail: detail,
      );
    }
    final apiKey = token is Map ? token['apiKey']?.toString().trim() ?? '' : '';
    final continuation =
        token is Map ? token['continuation']?.toString().trim() ?? '' : '';
    final visitorData =
        token is Map ? token['visitorData']?.toString().trim() ?? '' : '';
    final clientVersion =
        token is Map ? token['clientVersion']?.toString().trim() ?? '' : '';
    final referer =
        token is Map ? token['liveChatPageUrl']?.toString().trim() ?? '' : '';
    if (_danmakuApiClient != null &&
        apiKey.isNotEmpty &&
        continuation.isNotEmpty &&
        visitorData.isNotEmpty &&
        referer.isNotEmpty) {
      return YouTubeDanmakuSession(
        apiClient: _danmakuApiClient,
        apiKey: apiKey,
        continuation: continuation,
        visitorData: visitorData,
        referer: referer,
        clientVersion: clientVersion.isNotEmpty
            ? clientVersion
            : YouTubeApiClient.defaultWebClientVersion,
      );
    }
    return ProviderUnavailableDanmakuSession(
      reason: 'YouTube 当前房间暂未拿到可用直播聊天参数，请稍后刷新重试。',
    );
  }
}
