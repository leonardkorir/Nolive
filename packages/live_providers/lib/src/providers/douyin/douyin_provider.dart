import 'package:live_core/live_core.dart';

import '../../danmaku/douyin_danmaku_session.dart';
import '../../danmaku/provider_ticker_danmaku_session.dart';
import 'douyin_data_source.dart';
import 'douyin_live_data_source.dart';
import 'douyin_preview_data_source.dart';
import 'douyin_sign_service.dart';
import 'douyin_transport.dart';

class DouyinProvider extends LiveProvider
    implements
        SupportsCategories,
        SupportsCategoryRooms,
        SupportsRecommendRooms,
        SupportsRoomSearch,
        SupportsRoomDetail,
        SupportsPlayQualities,
        SupportsPlayUrls,
        SupportsDanmaku {
  DouyinProvider({
    DouyinDataSource? dataSource,
    DouyinWebsocketSignatureBuilder? websocketSignatureBuilder,
  })  : _dataSource = dataSource ?? const DouyinPreviewDataSource(),
        _websocketSignatureBuilder = websocketSignatureBuilder;

  factory DouyinProvider.preview() => DouyinProvider();

  factory DouyinProvider.live({
    String cookie = '',
    DouyinTransport? transport,
    DouyinSignService? signService,
    DouyinWebsocketSignatureBuilder? websocketSignatureBuilder,
  }) {
    final resolvedTransport = transport ?? HttpDouyinTransport();
    final resolvedSignService =
        signService ?? HttpDouyinSignService(cookie: cookie);
    return DouyinProvider(
      dataSource: DouyinLiveDataSource(
        transport: resolvedTransport,
        signService: resolvedSignService,
      ),
      websocketSignatureBuilder: websocketSignatureBuilder,
    );
  }

  static const ProviderDescriptor kDescriptor = ProviderDescriptor(
    id: ProviderId.douyin,
    displayName: '抖音',
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
    roomIdPatterns: [r'^[0-9a-zA-Z_]+$'],
    maturity: ProviderMaturity.inMigration,
  );

  final DouyinDataSource _dataSource;
  final DouyinWebsocketSignatureBuilder? _websocketSignatureBuilder;

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
    final roomId = token is Map ? token['roomId']?.toString() ?? '' : '';
    final userUniqueId =
        token is Map ? token['userUniqueId']?.toString() ?? '' : '';
    final cookie = token is Map ? token['cookie']?.toString() ?? '' : '';
    if (roomId.isNotEmpty &&
        userUniqueId.isNotEmpty &&
        _websocketSignatureBuilder != null) {
      return DouyinDanmakuSession(
        roomId: roomId,
        userUniqueId: userUniqueId,
        cookie: cookie,
        signatureBuilder: _websocketSignatureBuilder,
      );
    }
    return ProviderTickerDanmakuSession(
      providerId: descriptor.id.value,
      detail: detail,
    );
  }
}
