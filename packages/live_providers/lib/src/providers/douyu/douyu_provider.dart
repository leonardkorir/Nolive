import 'package:live_core/live_core.dart';

import '../../danmaku/douyu_danmaku_session.dart';
import '../../danmaku/provider_ticker_danmaku_session.dart';
import 'douyu_data_source.dart';
import 'douyu_live_data_source.dart';
import 'douyu_preview_data_source.dart';
import 'douyu_sign_service.dart';
import 'douyu_transport.dart';

class DouyuProvider extends LiveProvider
    implements
        SupportsCategories,
        SupportsCategoryRooms,
        SupportsRecommendRooms,
        SupportsRoomSearch,
        SupportsRoomDetail,
        SupportsPlayQualities,
        SupportsPlayUrls,
        SupportsDanmaku {
  DouyuProvider({
    DouyuDataSource? dataSource,
    void Function()? disposeOwnedResources,
  }) : _dataSource = dataSource ?? const DouyuPreviewDataSource(),
       _disposeOwnedResources = disposeOwnedResources;

  factory DouyuProvider.preview() => DouyuProvider();

  factory DouyuProvider.live({
    DouyuTransport? transport,
    DouyuSignService? signService,
    String? deviceId,
  }) {
    final ownedTransport = transport == null ? HttpDouyuTransport() : null;
    final resolvedTransport = transport ?? ownedTransport!;
    final ownedSignService = signService == null
        ? HttpDouyuSignService(
            transport: resolvedTransport,
            deviceId: deviceId,
          )
        : null;
    final resolvedSignService = signService ?? ownedSignService!;
    return DouyuProvider(
      dataSource: DouyuLiveDataSource(
        transport: resolvedTransport,
        signService: resolvedSignService,
      ),
      disposeOwnedResources: () {
        ownedSignService?.dispose();
        ownedTransport?.close();
      },
    );
  }

  static const ProviderDescriptor kDescriptor = ProviderDescriptor(
    id: ProviderId.douyu,
    displayName: '斗鱼',
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
    roomIdPatterns: [r'^\d+$'],
    maturity: ProviderMaturity.ready,
  );

  final DouyuDataSource _dataSource;
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
    final roomId = token is DouyuDanmakuToken ? token.roomId : detail.roomId;
    if (roomId.isNotEmpty) {
      return DouyuDanmakuSession(
        roomId: roomId,
        socketUrls: token is DouyuDanmakuToken && token.socketUrls.isNotEmpty
            ? token.socketUrls
            : null,
      );
    }
    return ProviderTickerDanmakuSession(
      providerId: descriptor.id,
      detail: detail,
    );
  }
}
