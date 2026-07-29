import 'package:live_core/live_core.dart';

import '../../danmaku/douyin_danmaku_session.dart';
import '../../danmaku/provider_ticker_danmaku_session.dart';
import 'douyin_data_source.dart';
import 'douyin_live_data_source.dart';
import 'douyin_preview_data_source.dart';
import 'douyin_sign_service.dart';
import 'douyin_transport.dart';
import 'douyin_danmaku_token.dart';

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
    void Function()? disposeOwnedResources,
  }) : _dataSource = dataSource ?? const DouyinPreviewDataSource(),
       _websocketSignatureBuilder = websocketSignatureBuilder,
       _disposeOwnedResources = disposeOwnedResources;

  factory DouyinProvider.preview() => DouyinProvider();

  factory DouyinProvider.live({
    String cookie = '',
    DouyinTransport? transport,
    DouyinSignService? signService,
    DouyinWebsocketSignatureBuilder? websocketSignatureBuilder,
  }) {
    final ownedTransport = transport == null ? HttpDouyinTransport() : null;
    final resolvedTransport = transport ?? ownedTransport!;
    final ownedSignService = signService == null
        ? HttpDouyinSignService(cookie: cookie)
        : null;
    final resolvedSignService = signService ?? ownedSignService!;
    return DouyinProvider(
      dataSource: DouyinLiveDataSource(
        transport: resolvedTransport,
        signService: resolvedSignService,
      ),
      websocketSignatureBuilder: websocketSignatureBuilder,
      disposeOwnedResources: () {
        ownedSignService?.close();
        ownedTransport?.close();
      },
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
    maturity: ProviderMaturity.experimental,
  );

  final DouyinDataSource _dataSource;
  final DouyinWebsocketSignatureBuilder? _websocketSignatureBuilder;
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
    if (token is DouyinDanmakuToken &&
        token.roomId.isNotEmpty &&
        token.userUniqueId.isNotEmpty &&
        _websocketSignatureBuilder != null) {
      return DouyinDanmakuSession(
        roomId: token.roomId,
        userUniqueId: token.userUniqueId,
        cookie: token.cookie,
        signatureBuilder: _websocketSignatureBuilder,
        serverUris: token.websocketUris.isEmpty ? null : token.websocketUris,
      );
    }
    return ProviderTickerDanmakuSession(
      providerId: descriptor.id,
      detail: detail,
    );
  }
}
