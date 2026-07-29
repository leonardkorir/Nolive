import 'package:live_core/live_core.dart';

import '../../danmaku/chaturbate_danmaku_session.dart';
import '../../danmaku/provider_ticker_danmaku_session.dart';
import '../../danmaku/provider_unavailable_danmaku_session.dart';
import 'chaturbate_api_client.dart';
import 'chaturbate_data_source.dart';
import 'chaturbate_live_data_source.dart';
import 'chaturbate_preview_data_source.dart';
import 'chaturbate_room_page_parser.dart';
import 'chaturbate_danmaku_token.dart';

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
    void Function()? disposeOwnedResources,
    void Function(String message)? diagnostics,
  }) : _dataSource = dataSource ?? const ChaturbatePreviewDataSource(),
       _danmakuApiClient = danmakuApiClient,
       _disposeOwnedResources = disposeOwnedResources,
       _diagnostics = diagnostics;

  /// Account cookie bound at provider create time (from secure settings).
  /// Test/diagnostic access only — not part of the public product API surface.
  String get debugConfiguredCookie {
    final client = _danmakuApiClient;
    if (client is HttpChaturbateApiClient) {
      return client.cookie;
    }
    return '';
  }

  factory ChaturbateProvider.preview() => ChaturbateProvider();

  factory ChaturbateProvider.live({
    String cookie = '',
    ChaturbateApiClient? apiClient,
    ChaturbateRoomPageParser roomPageParser = const ChaturbateRoomPageParser(),
    List<String>? recommendCarouselIds,
    void Function(String message)? diagnostics,
  }) {
    final ownedApiClient = apiClient == null
        ? HttpChaturbateApiClient(cookie: cookie, diagnostics: diagnostics)
        : null;
    final resolvedApiClient = apiClient ?? ownedApiClient!;
    return ChaturbateProvider(
      dataSource: ChaturbateLiveDataSource(
        apiClient: resolvedApiClient,
        roomPageParser: roomPageParser,
        recommendCarouselIds: recommendCarouselIds,
        diagnostics: diagnostics,
      ),
      danmakuApiClient: resolvedApiClient,
      disposeOwnedResources: ownedApiClient?.close,
      diagnostics: diagnostics,
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
  final void Function()? _disposeOwnedResources;
  final void Function(String message)? _diagnostics;

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
    final requestCookie =
        detail.metadata?['requestCookie']?.toString().trim() ?? '';
    if (token is ChaturbateDanmakuToken &&
        token.broadcasterUid.isNotEmpty &&
        token.csrfToken.isNotEmpty) {
      final apiClient = requestCookie.isNotEmpty
          ? HttpChaturbateApiClient(
              cookie: requestCookie,
              diagnostics: _diagnostics,
            )
          : _danmakuApiClient ?? HttpChaturbateApiClient();
      return ChaturbateDanmakuSession(
        roomId: detail.roomId,
        broadcasterUid: token.broadcasterUid,
        csrfToken: token.csrfToken,
        backend: token.backend,
        apiClient: apiClient,
        realtimeHosts: [
          if (token.host != null) token.host!,
          if (token.restHost != null) token.restHost!,
          ...token.fallbackHosts,
        ],
        disposeOwnedApiClient: requestCookie.isNotEmpty
            ? apiClient.close
            : null,
        diagnostics: _diagnostics,
      );
    }
    // Reached when the room page shell did not yield realtime bootstrap data —
    // most often a Cloudflare challenge on that path. Playback uses a different
    // path and usually still works, so the message must not imply the room is
    // broken, and must not imply a refresh alone will fix it.
    //
    // The advice differs by whether a cookie was even sent: with no cookie the
    // fix is to add one, and telling the user to "update" a cookie they never
    // configured sends them looking for something that is not there.
    // Record which advice the user actually got: the two branches send them to
    // different places, and a log that only says "unavailable" cannot tell them
    // apart afterwards.
    _diagnostics?.call(
      'chaturbate provider: danmaku unavailable roomId=${detail.roomId} '
      'hasCookie=${requestCookie.isNotEmpty} '
      'advice=${requestCookie.isEmpty ? 'add-cookie' : 'update-cookie'}',
    );
    return ProviderUnavailableDanmakuSession(
      reason: requestCookie.isEmpty
          ? 'Chaturbate 未能获取本房间的弹幕连接参数，本次进房无法接收弹幕（播放不受影响）。'
                '当前未配置 Chaturbate Cookie，请到「设置 → 账号」添加带 cf_clearance 的 Cookie 后重进房间。'
          : 'Chaturbate 未能获取本房间的弹幕连接参数，本次进房无法接收弹幕（播放不受影响）。'
                '可先刷新房间重试；若仍然如此，说明已配置的 Cookie 可能已失效，'
                '请到「设置 → 账号」更新 Chaturbate Cookie。',
    );
  }
}
