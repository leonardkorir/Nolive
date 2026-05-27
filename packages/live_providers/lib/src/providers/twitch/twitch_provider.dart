import 'package:live_core/live_core.dart';

import '../../danmaku/provider_ticker_danmaku_session.dart';
import '../../danmaku/provider_unavailable_danmaku_session.dart';
import '../../danmaku/twitch_danmaku_session.dart';
import 'twitch_api_client.dart';
import 'twitch_data_source.dart';
import 'twitch_live_data_source.dart';
import 'twitch_playback_bootstrap.dart';
import 'twitch_preview_data_source.dart';

class TwitchProvider extends LiveProvider
    implements
        SupportsCategories,
        SupportsCategoryRooms,
        SupportsRecommendRooms,
        SupportsRoomSearch,
        SupportsRoomDetail,
        SupportsPlayQualities,
        SupportsPlayUrls,
        SupportsDanmaku {
  TwitchProvider({
    TwitchDataSource? dataSource,
    void Function()? disposeOwnedResources,
  })  : _dataSource = dataSource ?? const TwitchPreviewDataSource(),
        _disposeOwnedResources = disposeOwnedResources;

  factory TwitchProvider.preview() => TwitchProvider();

  factory TwitchProvider.live({
    TwitchApiClient? apiClient,
    String clientIntegrity = '',
    String cookie = '',
    TwitchPlaybackBootstrapResolver? playbackBootstrapResolver,
  }) {
    final ownedApiClient =
        apiClient == null ? HttpTwitchApiClient(cookie: cookie) : null;
    return TwitchProvider(
      dataSource: TwitchLiveDataSource(
        apiClient: apiClient ?? ownedApiClient!,
        clientIntegrity: clientIntegrity,
        playbackBootstrapResolver: playbackBootstrapResolver,
      ),
      disposeOwnedResources: ownedApiClient?.close,
    );
  }

  static const ProviderDescriptor kDescriptor = ProviderDescriptor(
    id: ProviderId.twitch,
    displayName: 'Twitch',
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
      r'^[A-Za-z0-9_]{3,30}$',
    ],
    maturity: ProviderMaturity.inMigration,
  );

  final TwitchDataSource _dataSource;
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
    final roomId = token is TwitchDanmakuToken ? token.roomId : detail.roomId;
    if (roomId.trim().isNotEmpty) {
      final oauthToken = token is TwitchDanmakuToken ? token.oauthToken : '';
      return TwitchDanmakuSession(
        roomId: roomId.trim().toLowerCase(),
        oauthToken: oauthToken.trim(),
      );
    }
    return ProviderUnavailableDanmakuSession(
      reason: 'Twitch 当前没有可用弹幕房间参数。',
    );
  }
}
