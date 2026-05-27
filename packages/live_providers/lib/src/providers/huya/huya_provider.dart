import 'package:live_core/live_core.dart';

import '../../danmaku/huya_danmaku_session.dart';
import '../../danmaku/provider_ticker_danmaku_session.dart';
import 'huya_data_source.dart';
import 'huya_live_data_source.dart';
import 'huya_preview_data_source.dart';
import 'huya_sign_service.dart';
import 'huya_transport.dart';

class HuyaProvider extends LiveProvider
    implements
        SupportsCategories,
        SupportsCategoryRooms,
        SupportsRecommendRooms,
        SupportsRoomSearch,
        SupportsRoomDetail,
        SupportsPlayQualities,
        SupportsPlayUrls,
        SupportsDanmaku {
  HuyaProvider({
    HuyaDataSource? dataSource,
    void Function()? disposeOwnedResources,
  })  : _dataSource = dataSource ?? const HuyaPreviewDataSource(),
        _disposeOwnedResources = disposeOwnedResources;

  factory HuyaProvider.preview() => HuyaProvider();

  factory HuyaProvider.live({
    HuyaTransport? transport,
    HuyaSignService? signService,
  }) {
    final ownedTransport = transport == null ? HttpHuyaTransport() : null;
    final resolvedTransport = transport ?? ownedTransport!;
    final resolvedSignService = signService ?? HttpHuyaSignService();
    return HuyaProvider(
      dataSource: HuyaLiveDataSource(
        transport: resolvedTransport,
        signService: resolvedSignService,
      ),
      disposeOwnedResources: ownedTransport?.close,
    );
  }

  static const ProviderDescriptor kDescriptor = ProviderDescriptor(
    id: ProviderId.huya,
    displayName: '虎牙',
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
    roomIdPatterns: [r'^yy/\d+$', r'^\d+$', r'^[A-Za-z0-9_-]+$'],
    maturity: ProviderMaturity.inMigration,
  );

  final HuyaDataSource _dataSource;
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
    if (token is HuyaDanmakuToken &&
        token.ayyuid > 0 &&
        token.topSid > 0 &&
        token.subSid > 0) {
      return HuyaDanmakuSession(
        ayyuid: token.ayyuid,
        topSid: token.topSid,
        subSid: token.subSid,
      );
    }
    return ProviderTickerDanmakuSession(
      providerId: descriptor.id.value,
      detail: detail,
    );
  }
}
