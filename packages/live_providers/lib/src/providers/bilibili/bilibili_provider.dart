import 'package:live_core/live_core.dart';

import '../../danmaku/bilibili_danmaku_session.dart';
import '../../danmaku/provider_ticker_danmaku_session.dart';
import '../../danmaku/provider_unavailable_danmaku_session.dart';
import 'bilibili_auth_context.dart';
import 'bilibili_data_source.dart';
import 'bilibili_live_data_source.dart';
import 'bilibili_preview_data_source.dart';
import 'bilibili_sign_service.dart';
import 'bilibili_transport.dart';
import 'bilibili_danmaku_token.dart';

class BilibiliProvider extends LiveProvider
    implements
        SupportsCategories,
        SupportsCategoryRooms,
        SupportsRecommendRooms,
        SupportsRoomSearch,
        SupportsRoomDetail,
        SupportsPlayQualities,
        SupportsPlayUrls,
        SupportsDanmaku {
  BilibiliProvider({
    BilibiliDataSource? dataSource,
    void Function()? disposeOwnedResources,
  }) : _dataSource = dataSource ?? const BilibiliPreviewDataSource(),
       _disposeOwnedResources = disposeOwnedResources;

  factory BilibiliProvider.preview() => BilibiliProvider();

  factory BilibiliProvider.live({String cookie = '', int userId = 0}) {
    final authContext = BilibiliAuthContext(cookie: cookie, userId: userId);
    final transport = HttpBilibiliTransport();
    final signService = BilibiliSignService(
      transport: transport,
      authContext: authContext,
    );
    return BilibiliProvider(
      dataSource: BilibiliLiveDataSource(
        transport: transport,
        signService: signService,
        authContext: authContext,
      ),
      disposeOwnedResources: transport.close,
    );
  }

  static const ProviderDescriptor kDescriptor = ProviderDescriptor(
    id: ProviderId.bilibili,
    displayName: '哔哩哔哩',
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

  final BilibiliDataSource _dataSource;
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
        reason: reason.isNotEmpty ? reason : '哔哩哔哩当前房间暂未拿到可用弹幕连接参数，请稍后刷新重试。',
      );
    }
    if (token is BilibiliDanmakuToken &&
        token.roomId > 0 &&
        token.token.trim().isNotEmpty) {
      return BilibiliDanmakuSession(danmakuToken: token);
    }
    return ProviderUnavailableDanmakuSession(
      reason: '哔哩哔哩当前房间暂未拿到可用弹幕连接参数，请稍后刷新重试。',
    );
  }
}
