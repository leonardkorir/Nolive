import 'package:live_core/live_core.dart';

import '../../danmaku/provider_ticker_danmaku_session.dart';
import '../../danmaku/provider_unavailable_danmaku_session.dart';
import '../../danmaku/youtube_danmaku_session.dart';
import 'youtube_api_client.dart';
import 'youtube_data_source.dart';
import 'youtube_live_data_source.dart';
import 'youtube_preview_data_source.dart';

typedef YouTubeApiClientBuilder = YouTubeApiClient Function();
typedef YouTubeApiClientDisposer = void Function(YouTubeApiClient apiClient);

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
    YouTubeApiClientBuilder? createOwnedDanmakuApiClient,
    YouTubeApiClientDisposer? disposeOwnedDanmakuApiClient,
    void Function()? disposeOwnedResources,
  })  : _dataSource = dataSource ?? const YouTubePreviewDataSource(),
        _danmakuApiClient = danmakuApiClient,
        _createOwnedDanmakuApiClient = createOwnedDanmakuApiClient,
        _disposeOwnedDanmakuApiClient = disposeOwnedDanmakuApiClient,
        _disposeOwnedResources = disposeOwnedResources;

  factory YouTubeProvider.preview() => YouTubeProvider();

  factory YouTubeProvider.live({
    YouTubeApiClient? apiClient,
    YouTubeApiClientBuilder apiClientBuilder = _defaultYouTubeApiClientBuilder,
    YouTubeApiClientDisposer apiClientDisposer =
        _defaultYouTubeApiClientDisposer,
  }) {
    final ownedApiClient = apiClient == null ? apiClientBuilder() : null;
    final resolvedApiClient = apiClient ?? ownedApiClient!;
    return YouTubeProvider(
      dataSource: YouTubeLiveDataSource(
        apiClient: resolvedApiClient,
      ),
      danmakuApiClient: apiClient,
      createOwnedDanmakuApiClient: apiClient == null ? apiClientBuilder : null,
      disposeOwnedDanmakuApiClient:
          apiClient == null ? apiClientDisposer : null,
      disposeOwnedResources: ownedApiClient == null
          ? null
          : () => apiClientDisposer(ownedApiClient),
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
  final YouTubeApiClientBuilder? _createOwnedDanmakuApiClient;
  final YouTubeApiClientDisposer? _disposeOwnedDanmakuApiClient;
  final void Function()? _disposeOwnedResources;

  @override
  ProviderDescriptor get descriptor => kDescriptor;

  @override
  void dispose() {
    _disposeOwnedResources?.call();
  }

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
    if (token is PreviewDanmakuToken) {
      return ProviderTickerDanmakuSession(
        providerId: descriptor.id.value,
        detail: detail,
      );
    }
    final sessionApiClient =
        _danmakuApiClient ?? _createOwnedDanmakuApiClient?.call();
    if (token is YouTubeDanmakuToken &&
        sessionApiClient != null &&
        token.apiKey.isNotEmpty &&
        token.continuation.isNotEmpty &&
        token.visitorData.isNotEmpty &&
        token.liveChatPageUrl.isNotEmpty) {
      return YouTubeDanmakuSession(
        apiClient: sessionApiClient,
        apiKey: token.apiKey,
        continuation: token.continuation,
        visitorData: token.visitorData,
        referer: token.liveChatPageUrl,
        clientVersion: token.clientVersion.isNotEmpty
            ? token.clientVersion
            : YouTubeApiClient.defaultWebClientVersion,
        disposeResources: _danmakuApiClient == null
            ? () => (_disposeOwnedDanmakuApiClient ??
                _defaultYouTubeApiClientDisposer)(sessionApiClient)
            : null,
      );
    }
    return ProviderUnavailableDanmakuSession(
      reason: 'YouTube 当前房间未返回可用直播聊天入口，可能是未开启聊天、登录/地区限制或页面结构变更；视频播放不受影响。',
    );
  }
}

YouTubeApiClient _defaultYouTubeApiClientBuilder() => HttpYouTubeApiClient();

void _defaultYouTubeApiClientDisposer(YouTubeApiClient apiClient) {
  if (apiClient is HttpYouTubeApiClient) {
    apiClient.close();
  }
}
