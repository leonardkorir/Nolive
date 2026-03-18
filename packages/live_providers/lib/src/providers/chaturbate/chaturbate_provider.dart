import 'package:live_core/live_core.dart';

import '../../danmaku/chaturbate_danmaku_session.dart';
import '../../danmaku/provider_ticker_danmaku_session.dart';
import '../../danmaku/provider_unavailable_danmaku_session.dart';
import 'chaturbate_api_client.dart';
import 'chaturbate_data_source.dart';
import 'chaturbate_live_data_source.dart';
import 'chaturbate_preview_data_source.dart';
import 'chaturbate_room_page_parser.dart';

class ChaturbateProvider extends LiveProvider
    implements
        SupportsCategories,
        SupportsCategoryRooms,
        SupportsRecommendRooms,
        SupportsRoomSearch,
        SupportsRoomDetail,
        SupportsPlayQualities,
        SupportsPlayUrls,
        SupportsDanmaku {
  ChaturbateProvider({
    ChaturbateDataSource? dataSource,
    ChaturbateApiClient? danmakuApiClient,
  })  : _dataSource = dataSource ?? const ChaturbatePreviewDataSource(),
        _danmakuApiClient = danmakuApiClient;

  factory ChaturbateProvider.preview() => ChaturbateProvider();

  factory ChaturbateProvider.live({
    String cookie = '',
    ChaturbateApiClient? apiClient,
    ChaturbateRoomPageParser roomPageParser = const ChaturbateRoomPageParser(),
    List<String>? recommendCarouselIds,
  }) {
    final resolvedApiClient =
        apiClient ?? HttpChaturbateApiClient(cookie: cookie);
    return ChaturbateProvider(
      dataSource: ChaturbateLiveDataSource(
        apiClient: resolvedApiClient,
        roomPageParser: roomPageParser,
        recommendCarouselIds: recommendCarouselIds,
      ),
      danmakuApiClient: resolvedApiClient,
    );
  }

  static const ProviderDescriptor kDescriptor = ProviderDescriptor(
    id: ProviderId.chaturbate,
    displayName: 'Chaturbate',
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
    roomIdPatterns: [r'^[A-Za-z0-9_]+$'],
    maturity: ProviderMaturity.inMigration,
  );

  static const String browserUserAgent =
      HttpChaturbateApiClient.browserUserAgent;

  final ChaturbateDataSource _dataSource;
  final ChaturbateApiClient? _danmakuApiClient;

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
    final broadcasterUid =
        token is Map ? token['broadcasterUid']?.toString() ?? '' : '';
    final csrfToken = token is Map ? token['csrfToken']?.toString() ?? '' : '';
    final backend = token is Map ? token['backend']?.toString() ?? 'a' : 'a';
    final requestCookie =
        detail.metadata?['requestCookie']?.toString().trim() ?? '';
    if (broadcasterUid.isNotEmpty && csrfToken.isNotEmpty) {
      final apiClient = requestCookie.isNotEmpty
          ? HttpChaturbateApiClient(cookie: requestCookie)
          : _danmakuApiClient ?? HttpChaturbateApiClient();
      return ChaturbateDanmakuSession(
        roomId: detail.roomId,
        broadcasterUid: broadcasterUid,
        csrfToken: csrfToken,
        backend: backend,
        apiClient: apiClient,
      );
    }
    return ProviderUnavailableDanmakuSession(
      reason: 'Chaturbate 当前房间暂未拿到可用弹幕参数，请稍后刷新重试。',
    );
  }
}
