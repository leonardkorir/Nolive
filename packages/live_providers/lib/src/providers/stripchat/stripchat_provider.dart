import 'package:live_core/live_core.dart';

import '../../danmaku/provider_ticker_danmaku_session.dart';
import '../../danmaku/provider_unavailable_danmaku_session.dart';
import '../../danmaku/stripchat_danmaku_session.dart';
import 'stripchat_api_client.dart';
import 'stripchat_data_source.dart';
import 'stripchat_live_data_source.dart';
import 'stripchat_preview_data_source.dart';
import 'stripchat_danmaku_token.dart';

class StripchatProvider extends LiveProvider
    implements
        SupportsCategories,
        SupportsCategoryRooms,
        SupportsRecommendRooms,
        SupportsRoomSearch,
        SupportsRoomDetail,
        SupportsPlayQualities,
        SupportsPlayUrls,
        SupportsDanmaku {
  StripchatProvider({
    StripchatDataSource? dataSource,
    void Function()? disposeOwnedResources,
  }) : _dataSource = dataSource ?? const StripchatPreviewDataSource(),
       _disposeOwnedResources = disposeOwnedResources;

  factory StripchatProvider.preview() => StripchatProvider();

  factory StripchatProvider.live({
    String cookie = '',
    StripchatApiClient? apiClient,
  }) {
    final ownedClient = apiClient == null
        ? HttpStripchatApiClient(cookie: cookie)
        : null;
    final resolvedClient = apiClient ?? ownedClient!;
    return StripchatProvider(
      dataSource: StripchatLiveDataSource(apiClient: resolvedClient),
      disposeOwnedResources: ownedClient?.close,
    );
  }

  static const ProviderDescriptor kDescriptor = ProviderDescriptor(
    id: ProviderId.stripchat,
    displayName: 'Stripchat',
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
    roomIdPatterns: [r'^[A-Za-z0-9_-]+$', r'^\d+$'],
    maturity: ProviderMaturity.inMigration,
  );

  final StripchatDataSource _dataSource;
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
        providerId: descriptor.id,
        detail: detail,
      );
    }
    if (token is UnavailableDanmakuToken) {
      final reason = token.reason.trim();
      return ProviderUnavailableDanmakuSession(
        reason: reason.isNotEmpty
            ? reason
            : 'Stripchat 当前房间暂未拿到可用弹幕连接参数，请稍后刷新重试。',
      );
    }
    if (token is StripchatDanmakuToken) {
      if (token.modelId.trim().isEmpty) {
        return ProviderUnavailableDanmakuSession(
          reason: 'Stripchat 弹幕连接失败：弹幕Token缺少modelId。',
        );
      }
      if (token.jwt.trim().isEmpty) {
        return ProviderUnavailableDanmakuSession(
          reason: 'Stripchat 弹幕连接失败：弹幕Token JWT为空。',
        );
      }
      return StripchatDanmakuSession(danmakuToken: token);
    }
    return ProviderUnavailableDanmakuSession(
      reason: 'Stripchat 当前房间暂未拿到可用弹幕连接参数，请稍后刷新重试。',
    );
  }
}
