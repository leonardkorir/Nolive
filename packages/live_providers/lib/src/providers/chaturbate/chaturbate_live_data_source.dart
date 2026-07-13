import 'dart:async';

import 'package:live_core/live_core.dart';

import '../provider_json.dart';
import '../provider_runtime_support.dart';
import 'chaturbate_api_client.dart';
import 'chaturbate_data_source.dart';
import 'chaturbate_discover_policy.dart';
import 'chaturbate_hls_master_playlist_parser.dart';
import 'chaturbate_mapper.dart';
import 'chaturbate_request_scheduler.dart';
import 'chaturbate_room_page_parser.dart';

typedef _ChaturbateVariantLoadResult = ({
  List<ChaturbateHlsVariant> variants,
  String masterPlaylistContent,
});

typedef _ChaturbatePlaybackBootstrap = ({
  String hlsSource,
  List<ChaturbateHlsVariant> variants,
  String masterPlaylistContent,
});

typedef _ChaturbatePageBootstrap = ({
  LiveRoomDetail? detail,
  String csrfToken,
  Map<String, dynamic> pushService,
});

class ChaturbateLiveDataSource implements ChaturbateDataSource {
  static const int _maxPlaybackBootstrapCacheEntries = 64;

  ChaturbateLiveDataSource({
    required ChaturbateApiClient apiClient,
    ChaturbateRoomPageParser roomPageParser = const ChaturbateRoomPageParser(),
    ChaturbateHlsMasterPlaylistParser hlsMasterPlaylistParser =
        const ChaturbateHlsMasterPlaylistParser(),
    List<String>? recommendCarouselIds,
    Duration roomPageRequestTimeout = const Duration(seconds: 6),
    Duration roomContextRequestTimeout = const Duration(seconds: 3),
    Duration hlsPlaylistRequestTimeout = const Duration(seconds: 4),
    Duration discoverRequestTimeout = const Duration(seconds: 8),
    Duration discoverOverallTimeout = const Duration(seconds: 12),
    ChaturbateDiscoverBudget discoverBudget =
        kDefaultChaturbateDiscoverBudget,
    void Function(String message)? diagnostics,
  }) : _apiClient = apiClient,
       _roomPageParser = roomPageParser,
       _hlsMasterPlaylistParser = hlsMasterPlaylistParser,
       _roomPageRequestTimeout = roomPageRequestTimeout,
       _roomContextRequestTimeout = roomContextRequestTimeout,
       _hlsPlaylistRequestTimeout = hlsPlaylistRequestTimeout,
       _discoverRequestTimeout = discoverRequestTimeout,
       _discoverOverallTimeout = discoverOverallTimeout,
       _discoverBudget = discoverBudget,
       _diagnostics = diagnostics,
       _recommendCarouselIds = List.unmodifiable(
         recommendCarouselIds ??
             ChaturbateApiClient.defaultRecommendCarouselIds,
       );

  final ChaturbateApiClient _apiClient;
  final ChaturbateRoomPageParser _roomPageParser;
  final ChaturbateHlsMasterPlaylistParser _hlsMasterPlaylistParser;
  final Duration _roomPageRequestTimeout;
  final Duration _roomContextRequestTimeout;
  final Duration _hlsPlaylistRequestTimeout;
  final Duration _discoverRequestTimeout;
  final Duration _discoverOverallTimeout;
  final ChaturbateDiscoverBudget _discoverBudget;
  final void Function(String message)? _diagnostics;
  final List<String> _recommendCarouselIds;
  final Map<String, Future<_ChaturbatePlaybackBootstrap?>>
  _roomPlaybackBootstrapFutures =
      <String, Future<_ChaturbatePlaybackBootstrap?>>{};
  final Map<String, _ChaturbatePlaybackBootstrap> _roomPlaybackBootstrapCache =
      <String, _ChaturbatePlaybackBootstrap>{};

  @override
  Future<List<LiveCategory>> fetchCategories() async {
    return ChaturbateMapper.categories;
  }

  @override
  Future<PagedResponse<LiveRoom>> fetchCategoryRooms(
    LiveSubCategory category, {
    int page = 1,
  }) async {
    if (page != 1) {
      return PagedResponse(items: const [], hasMore: false, page: page);
    }
    final genders = ChaturbateMapper.genderQueryForCategory(category);
    if (genders == null) {
      return PagedResponse(items: const [], hasMore: false, page: page);
    }
    final items = await _loadDiscoverRooms(genders: genders);
    return PagedResponse(items: items, hasMore: false, page: page);
  }

  @override
  Future<PagedResponse<LiveRoom>> fetchRecommendRooms({int page = 1}) async {
    if (page != 1) {
      return PagedResponse(items: const [], hasMore: false, page: page);
    }
    final items = await _loadDiscoverRooms(genders: '');
    return PagedResponse(items: items, hasMore: false, page: page);
  }

  @override
  Future<PagedResponse<LiveRoom>> searchRooms(
    String query, {
    int page = 1,
  }) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      return fetchRecommendRooms(page: page);
    }
    final normalizedPage = page < 1 ? 1 : page;
    final offset = (normalizedPage - 1) * ChaturbateApiClient.searchPageSize;
    // HAR-aligned: anonymous room-list (no account cookie on list endpoints).
    final response = await _apiClient.fetchRoomList(
      query: normalizedQuery,
      offset: offset,
      limit: ChaturbateApiClient.searchPageSize,
      requireFingerprint: false,
      cookie: '',
    );
    final rooms = _asList(response['rooms']);
    final items = rooms
        .map((item) => _asMap(item))
        .where((item) => item.isNotEmpty)
        .map(ChaturbateMapper.mapSearchRoom)
        .where((room) => room.roomId.isNotEmpty)
        .toList(growable: false);
    final totalCount = _asInt(response['total_count']) ?? items.length;
    final hasMore = offset + items.length < totalCount;
    return PagedResponse(items: items, hasMore: hasMore, page: normalizedPage);
  }

  @override
  Future<LiveRoomDetail> fetchRoomDetail(String roomId) async {
    // Enter-room / room open uses normal priority (default). Follow fan-out
    // must wrap work with [ChaturbateRequestScheduler.runAsFollowBudget] so
    // only that path demotes to low + long 429 backoff.
    final normalizedRoomId = roomId.trim();
    if (normalizedRoomId.isEmpty) {
      return _attachRequestCookie(
        await _fetchRoomDetailFromPage(
          roomId,
          normalizedRoomId: normalizedRoomId,
        ),
      );
    }
    // B: status path — context first (isLive/title). Never prime HLS bootstrap
    // here (that is C / enter-room). Soft page only if still missing danmaku
    // token after cookie csrf (enter-room / play needs token; follow with
    // csrftoken in account cookie stays at 1 request).
    try {
      final contextDetail = await _fetchRoomDetailFromContext(normalizedRoomId);
      var merged = _mergeRealtimeBootstrap(
        detail: contextDetail,
        csrfToken: _configuredCookieCsrfToken(),
      );
      if (merged.danmakuToken == null) {
        final pageBootstrap = await _tryFetchRoomPageBootstrap(
          roomId,
          normalizedRoomId: normalizedRoomId,
        );
        if (pageBootstrap != null) {
          merged = _mergeRealtimeBootstrap(
            detail: merged,
            realtimeDetail: pageBootstrap.detail,
            csrfToken: pageBootstrap.csrfToken,
            pushService: pageBootstrap.pushService,
          );
        }
      }
      return _attachRequestCookie(merged);
    } catch (error, stackTrace) {
      // Context API often 401s while page/play still works — not a dead cookie.
      reportProviderDiagnostic(
        providerId: ProviderId.chaturbate,
        scope: 'chaturbate room detail context',
        message:
            'context unavailable for roomId=$normalizedRoomId; falling back to room page (not necessarily cookie failure)',
        error: error,
        stackTrace: stackTrace,
        diagnostics: _diagnostics,
      );
    }
    try {
      final pageBootstrap = await _tryFetchRoomPageBootstrap(
        roomId,
        normalizedRoomId: normalizedRoomId,
      );
      if (pageBootstrap?.detail != null) {
        return _attachRequestCookie(pageBootstrap!.detail!);
      }
    } catch (error, stackTrace) {
      reportProviderDiagnostic(
        providerId: ProviderId.chaturbate,
        scope: 'chaturbate room detail page',
        message: 'failed for roomId=$normalizedRoomId',
        error: error,
        stackTrace: stackTrace,
        diagnostics: _diagnostics,
      );
    }
    return _attachRequestCookie(
      await _fetchRoomDetailFromPage(
        roomId,
        normalizedRoomId: normalizedRoomId,
      ),
    );
  }

  Future<_ChaturbatePageBootstrap?> _tryFetchRoomPageBootstrap(
    String roomId, {
    required String normalizedRoomId,
    ChaturbateRequestPriority priority = ChaturbateRequestPriority.normal,
  }) async {
    try {
      var html = await _fetchRoomPageHtml(roomId, priority: priority);
      var realtimeBootstrap = _parseRealtimeBootstrap(
        html: html,
        roomId: normalizedRoomId,
        source: 'anonymous',
      );
      if (!_hasRealtimeBootstrap(realtimeBootstrap) && _hasConfiguredCookie) {
        _diagnostic(
          'room page anonymous missing realtime bootstrap '
          'roomId=$normalizedRoomId; retrying with account cookie',
        );
        html = await _fetchRoomPageHtml(
          roomId,
          useAccountCookie: true,
          priority: priority,
        );
        realtimeBootstrap = _parseRealtimeBootstrap(
          html: html,
          roomId: normalizedRoomId,
          source: 'account-cookie',
        );
      }
      // Cookie may still carry csrftoken when the HTML shell is stripped.
      realtimeBootstrap = _withCookieCsrfFallback(
        realtimeBootstrap,
        source: 'cookie-fallback',
        roomId: normalizedRoomId,
      );
      final csrfToken = realtimeBootstrap.csrfToken;
      final pushService = realtimeBootstrap.pushService;
      LiveRoomDetail? detail;
      try {
        final context = _roomPageParser.parsePageContext(html);
        detail = _applyCachedPlaybackBootstrap(
          roomId: normalizedRoomId,
          detail: ChaturbateMapper.mapRoomDetailFromPageContext(context),
        );
      } catch (error, stackTrace) {
        // csrf alone is enough to build a session once context provides uids.
        if (csrfToken.isEmpty && pushService.isEmpty) {
          Error.throwWithStackTrace(error, stackTrace);
        }
        reportProviderDiagnostic(
          providerId: ProviderId.chaturbate,
          scope: 'chaturbate room page dossier',
          message:
              'failed for roomId=$normalizedRoomId; using realtime bootstrap only',
          error: error,
          stackTrace: stackTrace,
          diagnostics: _diagnostics,
        );
      }
      return (detail: detail, csrfToken: csrfToken, pushService: pushService);
    } catch (error, stackTrace) {
      reportProviderDiagnostic(
        providerId: ProviderId.chaturbate,
        scope: 'chaturbate room detail realtime bootstrap',
        message:
            'realtime/danmaku bootstrap unavailable for roomId=$normalizedRoomId; '
            'continuing room open without danmaku token (playback may still work)',
        error: error,
        stackTrace: stackTrace,
        diagnostics: _diagnostics,
      );
      // Still return cookie csrf when present so context+cookie can form a token.
      final cookieCsrf = _configuredCookieCsrfToken();
      if (cookieCsrf.isEmpty) {
        return null;
      }
      return (
        detail: null,
        csrfToken: cookieCsrf,
        pushService: const <String, dynamic>{},
      );
    }
  }

  ({String csrfToken, Map<String, dynamic> pushService})
  _parseRealtimeBootstrap({
    required String html,
    required String roomId,
    required String source,
  }) {
    final csrfToken = _roomPageParser.tryExtractCsrfToken(html) ?? '';
    final pushServicesRawValue = _roomPageParser.tryExtractPushServicesRawValue(
      html,
    );
    final pushServices = pushServicesRawValue == null
        ? const <Map<String, dynamic>>[]
        : _roomPageParser.decodePushServices(pushServicesRawValue);
    _diagnostic(
      'room page bootstrap source=$source roomId=$roomId '
      'htmlBytes=${html.length} csrf=${csrfToken.isNotEmpty} '
      'pushServices=${pushServices.length}',
    );
    return (
      csrfToken: csrfToken,
      pushService: pushServices.isEmpty
          ? const <String, dynamic>{}
          : pushServices.first,
    );
  }

  ({String csrfToken, Map<String, dynamic> pushService})
  _withCookieCsrfFallback(
    ({String csrfToken, Map<String, dynamic> pushService}) bootstrap, {
    required String source,
    required String roomId,
  }) {
    if (bootstrap.csrfToken.isNotEmpty) {
      return bootstrap;
    }
    final cookieCsrf = _configuredCookieCsrfToken();
    if (cookieCsrf.isEmpty) {
      return bootstrap;
    }
    _diagnostic(
      'room page bootstrap source=$source roomId=$roomId '
      'csrf=true from configured cookie pushServices='
      '${bootstrap.pushService.isEmpty ? 0 : 1}',
    );
    return (csrfToken: cookieCsrf, pushService: bootstrap.pushService);
  }

  bool _hasRealtimeBootstrap(
    ({String csrfToken, Map<String, dynamic> pushService}) realtimeBootstrap,
  ) {
    // csrf is the hard requirement for push auth; push host can come from
    // auth response or defaults once a session is created.
    return realtimeBootstrap.csrfToken.isNotEmpty;
  }

  String _configuredCookieCsrfToken() {
    final cookie = switch (_apiClient) {
      HttpChaturbateApiClient client => client.cookie,
      _ => '',
    };
    return ChaturbateRoomPageParser.tryExtractCsrfTokenFromCookie(cookie) ??
        '';
  }

  Future<LiveRoomDetail> _fetchRoomDetailFromPage(
    String roomId, {
    required String normalizedRoomId,
    ChaturbateRequestPriority priority = ChaturbateRequestPriority.normal,
  }) async {
    final html = await _fetchRoomPageHtml(roomId, priority: priority);
    final context = _roomPageParser.parsePageContext(html);
    final detail = ChaturbateMapper.mapRoomDetailFromPageContext(context);
    return _applyCachedPlaybackBootstrap(
      roomId: normalizedRoomId,
      detail: detail,
    );
  }

  Future<String> _fetchRoomPageHtml(
    String roomId, {
    bool useAccountCookie = false,
    ChaturbateRequestPriority priority = ChaturbateRequestPriority.normal,
  }) async {
    // When account cookie (often with cf_clearance) is configured, use it on
    // the first request — anonymous-first doubles traffic and triggers CF/429.
    if (useAccountCookie || _hasConfiguredCookie) {
      return _apiClient
          .fetchRoomPage(roomId, priority: priority)
          .timeout(_roomPageRequestTimeout);
    }
    return _apiClient
        .fetchRoomPage(roomId, cookie: '', priority: priority)
        .timeout(_roomPageRequestTimeout);
  }

  bool get _hasConfiguredCookie {
    return switch (_apiClient) {
      HttpChaturbateApiClient client => client.cookie.trim().isNotEmpty,
      _ => false,
    };
  }

  Future<LiveRoomDetail> _fetchRoomDetailFromContext(
    String roomId, {
    ChaturbateRequestPriority priority = ChaturbateRequestPriority.normal,
  }) async {
    // Prefer account cookie (cf_clearance) when present; omit override.
    final roomContext = await _apiClient
        .fetchRoomContext(roomId, priority: priority)
        .timeout(_roomContextRequestTimeout);
    final detail = ChaturbateMapper.mapRoomDetail(roomContext);
    return _applyCachedPlaybackBootstrap(roomId: roomId, detail: detail);
  }

  LiveRoomDetail _applyCachedPlaybackBootstrap({
    required String roomId,
    required LiveRoomDetail detail,
  }) {
    final bootstrap = roomId.isEmpty
        ? null
        : _roomPlaybackBootstrapCache[roomId];
    if (bootstrap == null) {
      return detail;
    }
    return _applyPlaybackBootstrap(detail: detail, bootstrap: bootstrap);
  }

  LiveRoomDetail _attachRequestCookie(LiveRoomDetail detail) {
    final requestCookie = switch (_apiClient) {
      HttpChaturbateApiClient client => client.cookie.trim(),
      _ => '',
    };
    if (requestCookie.isEmpty) {
      return detail;
    }
    return LiveRoomDetail(
      providerId: detail.providerId,
      roomId: detail.roomId,
      title: detail.title,
      streamerName: detail.streamerName,
      streamerAvatarUrl: detail.streamerAvatarUrl,
      coverUrl: detail.coverUrl,
      keyframeUrl: detail.keyframeUrl,
      areaName: detail.areaName,
      description: detail.description,
      sourceUrl: detail.sourceUrl,
      startedAt: detail.startedAt,
      isLive: detail.isLive,
      viewerCount: detail.viewerCount,
      danmakuToken: detail.danmakuToken,
      metadata: {...?detail.metadata, 'requestCookie': requestCookie},
    );
  }

  LiveRoomDetail _mergeRealtimeBootstrap({
    required LiveRoomDetail detail,
    LiveRoomDetail? realtimeDetail,
    String csrfToken = '',
    Map<String, dynamic> pushService = const {},
  }) {
    final realtimeToken = realtimeDetail?.danmakuToken;
    if (realtimeToken != null) {
      return LiveRoomDetail(
        providerId: detail.providerId,
        roomId: detail.roomId,
        title: detail.title,
        streamerName: detail.streamerName,
        streamerAvatarUrl: detail.streamerAvatarUrl,
        coverUrl: detail.coverUrl,
        keyframeUrl: detail.keyframeUrl,
        areaName: detail.areaName,
        description: detail.description,
        sourceUrl: detail.sourceUrl,
        startedAt: detail.startedAt,
        isLive: detail.isLive,
        viewerCount: detail.viewerCount,
        danmakuToken: realtimeToken,
        metadata: {...?realtimeDetail?.metadata, ...?detail.metadata},
      );
    }
    final resolvedCsrf = csrfToken.trim().isNotEmpty
        ? csrfToken.trim()
        : _configuredCookieCsrfToken();
    return ChaturbateMapper.attachDanmakuBootstrap(
      detail: detail,
      csrfToken: resolvedCsrf,
      pushService: pushService,
    );
  }

  @override
  Future<List<LivePlayQuality>> fetchPlayQualities(
    LiveRoomDetail detail,
  ) async {
    final enrichedDetail = await _detailWithPlaybackBootstrap(detail);
    final metadata = enrichedDetail.metadata ?? const <String, Object?>{};
    final referer = enrichedDetail.sourceUrl;
    final initialHlsSource = metadata['hlsSource']?.toString().trim() ?? '';
    final preloadedVariants = _readVariantsFromMetadata(
      metadata: metadata,
      hlsSource: initialHlsSource,
    );

    final initialVariants =
        preloadedVariants ??
        await _loadVariants(hlsSource: initialHlsSource, referer: referer);
    if (initialVariants != null && initialVariants.variants.isNotEmpty) {
      return ChaturbateMapper.mapPlayQualitiesFromVariants(
        variants: initialVariants.variants,
        fallbackPlaylistUrl: initialHlsSource,
        masterPlaylistContent: initialVariants.masterPlaylistContent,
      );
    }

    final refreshed = await _refreshPlaybackDetail(
      detail: enrichedDetail,
      referer: referer,
    );
    if (refreshed != null) {
      if (refreshed.variants.isNotEmpty) {
        return ChaturbateMapper.mapPlayQualitiesFromVariants(
          variants: refreshed.variants,
          fallbackPlaylistUrl: refreshed.detail.metadata?['hlsSource']
              ?.toString()
              .trim(),
          masterPlaylistContent: refreshed.masterPlaylistContent,
        );
      }
      return ChaturbateMapper.mapPlayQualities(refreshed.detail);
    }
    return ChaturbateMapper.mapPlayQualities(enrichedDetail);
  }

  @override
  Future<List<LivePlayUrl>> fetchPlayUrls({
    required LiveRoomDetail detail,
    required LivePlayQuality quality,
  }) async {
    final resolved = await _resolvePlayableQuality(
      detail: detail,
      quality: quality,
    );
    return ChaturbateMapper.mapPlayUrls(resolved.detail, resolved.quality);
  }

  bool _isExcludedCarouselId(String carouselId) {
    return carouselId.trim().toLowerCase() == 'spy_shows';
  }

  bool _looksLikeSpyShow(Map<String, dynamic> payload) {
    final raw = payload['spy_show_price'];
    if (raw == null) {
      return false;
    }
    if (raw is num) {
      return raw > 0;
    }
    final text = raw.toString().trim();
    if (text.isEmpty || text == 'null') {
      return false;
    }
    return true;
  }

  Future<List<LiveRoom>> _loadDiscoverRooms({required String genders}) async {
    try {
      return await _loadDiscoverRoomsBounded(
        genders: genders,
      ).timeout(_discoverOverallTimeout);
    } on TimeoutException catch (error, stackTrace) {
      reportProviderDiagnostic(
        providerId: ProviderId.chaturbate,
        scope: 'chaturbate discover overall',
        message:
            'overall timeout after ${_discoverOverallTimeout.inMilliseconds}ms '
            'genders=$genders; returning empty list',
        error: error,
        stackTrace: stackTrace,
        diagnostics: _diagnostics,
      );
      return const <LiveRoom>[];
    }
  }

  Future<List<LiveRoom>> _loadDiscoverRoomsBounded({
    required String genders,
  }) async {
    // A: carousel-first (pre-HAR stable home/category path).
    final uniqueRooms = <String, LiveRoom>{};
    var successfulCarouselCount = 0;
    Object? lastCarouselError;
    var carouselsTried = 0;
    final maxCarousels = _discoverBudget.maxCarouselAttempts < 1
        ? 1
        : _discoverBudget.maxCarouselAttempts;
    for (final carouselId in _recommendCarouselIds) {
      if (_isExcludedCarouselId(carouselId)) {
        continue;
      }
      if (carouselsTried >= maxCarousels) {
        break;
      }
      carouselsTried += 1;

      Map<String, dynamic> response;
      try {
        response = await _fetchCarouselOnce(carouselId, genders: genders);
        successfulCarouselCount += 1;
      } catch (error, stackTrace) {
        reportProviderDiagnostic(
          providerId: ProviderId.chaturbate,
          scope: 'chaturbate discover carousel',
          message: 'failed for carousel=$carouselId genders=$genders',
          error: error,
          stackTrace: stackTrace,
          diagnostics: _diagnostics,
        );
        lastCarouselError = error;
        if (isChaturbateRateLimitedError(error)) {
          break;
        }
        continue;
      }
      final rooms = _asList(response['rooms']);
      for (final item in rooms) {
        final payload = _asMap(item);
        if (payload.isEmpty || _looksLikeSpyShow(payload)) {
          continue;
        }
        final room = ChaturbateMapper.mapRecommendRoom(payload);
        if (room.roomId.isEmpty) {
          continue;
        }
        uniqueRooms.putIfAbsent(room.roomId, () => room);
      }
      if (uniqueRooms.isNotEmpty) {
        break;
      }
    }

    if (uniqueRooms.isNotEmpty) {
      final items = uniqueRooms.values.toList(growable: false)
        ..sort((left, right) {
          final compare = (right.viewerCount ?? -1).compareTo(
            left.viewerCount ?? -1,
          );
          if (compare != 0) {
            return compare;
          }
          return left.roomId.compareTo(right.roomId);
        });
      return items;
    }

    if (shouldAttemptDiscoverRoomListFallback(
      budget: _discoverBudget,
      carouselsSucceededWithRooms: false,
      lastCarouselError: lastCarouselError,
    )) {
      final roomListOutcome = await _loadDiscoverRoomsFromRoomList(
        genders: genders,
      );
      final roomListItems = roomListOutcome.rooms;
      if (roomListItems != null && roomListItems.isNotEmpty) {
        return roomListItems;
      }
      if (roomListOutcome.error != null &&
          !isChaturbateRecoverableDiscoverError(roomListOutcome.error!) &&
          successfulCarouselCount == 0 &&
          lastCarouselError == null) {
        throw roomListOutcome.error!;
      }
    }

    if (successfulCarouselCount == 0 && lastCarouselError != null) {
      if (isChaturbateRecoverableDiscoverError(lastCarouselError)) {
        _diagnostic(
          'discover carousels exhausted by recoverable errors '
          'genders=$genders; returning empty list',
        );
        return const <LiveRoom>[];
      }
      throw lastCarouselError;
    }
    return const <LiveRoom>[];
  }

  Future<({List<LiveRoom>? rooms, Object? error})>
  _loadDiscoverRoomsFromRoomList({
    required String genders,
  }) async {
    Object? lastError;
    final attempts = _discoverBudget.maxRoomListAttempts < 1
        ? 1
        : _discoverBudget.maxRoomListAttempts;
    for (var attempt = 0; attempt < attempts; attempt += 1) {
      try {
        // Anonymous room-list fallback only (HAR). Prefer carousel for feed.
        final response = await _apiClient
            .fetchRoomList(
              query: '',
              genders: genders.trim().isEmpty ? null : genders,
              limit: ChaturbateApiClient.searchPageSize,
              requireFingerprint: false,
              cookie: '',
            )
            .timeout(_discoverRequestTimeout);
        final rooms = _asList(response['rooms']);
        final items = rooms
            .map((item) => _asMap(item))
            .where((item) => item.isNotEmpty)
            .where(_isPublicRoomListEntry)
            .map(ChaturbateMapper.mapSearchRoom)
            .where((room) => room.roomId.isNotEmpty)
            .toList(growable: false);
        return (rooms: items, error: null);
      } catch (error, stackTrace) {
        lastError = error;
        reportProviderDiagnostic(
          providerId: ProviderId.chaturbate,
          scope: 'chaturbate discover room-list',
          message:
              'attempt ${attempt + 1}/$attempts failed for genders=$genders',
          error: error,
          stackTrace: stackTrace,
          diagnostics: _diagnostics,
        );
        if (isChaturbateRateLimitedError(error)) {
          break;
        }
      }
    }
    return (rooms: null, error: lastError);
  }

  bool _isPublicRoomListEntry(Map<String, dynamic> payload) {
    final currentShow = payload['current_show']?.toString().trim() ?? '';
    if (currentShow.isNotEmpty && currentShow != 'public') {
      return false;
    }
    return payload['has_password'] != true;
  }

  Future<Map<String, dynamic>> _fetchCarouselOnce(
    String carouselId, {
    required String genders,
  }) async {
    return _apiClient
        .fetchDiscoverCarousel(carouselId, genders: genders)
        .timeout(_discoverRequestTimeout);
  }

  List<dynamic> _asList(Object? value) {
    return ProviderJson.asList(value);
  }

  Map<String, dynamic> _asMap(Object? value) {
    return ProviderJson.asMap(value);
  }

  int? _asInt(Object? value) {
    return ProviderJson.asInt(value, allowNum: true);
  }

  Future<_ChaturbateVariantLoadResult?> _loadVariants({
    required String hlsSource,
    required String? referer,
  }) async {
    if (hlsSource.isEmpty) {
      return null;
    }
    try {
      final playlistText = await _apiClient
          .fetchHlsPlaylist(hlsSource, referer: referer, cookie: '')
          .timeout(_hlsPlaylistRequestTimeout);
      return (
        variants: _hlsMasterPlaylistParser.parse(
          playlistUrl: hlsSource,
          source: playlistText,
        ),
        masterPlaylistContent: playlistText,
      );
    } catch (error, stackTrace) {
      reportProviderDiagnostic(
        providerId: ProviderId.chaturbate,
        scope: 'chaturbate HLS variant load',
        message: 'failed for hlsSource=$hlsSource',
        error: error,
        stackTrace: stackTrace,
        diagnostics: _diagnostics,
      );
      return null;
    }
  }

  Future<({LiveRoomDetail detail, LivePlayQuality quality})>
  _resolvePlayableQuality({
    required LiveRoomDetail detail,
    required LivePlayQuality quality,
  }) async {
    final enrichedDetail = await _detailWithPlaybackBootstrap(detail);
    final playlistUrl =
        quality.metadata?['playlistUrl']?.toString().trim() ?? '';
    if (playlistUrl.isNotEmpty) {
      return (detail: enrichedDetail, quality: quality);
    }

    final metadata = enrichedDetail.metadata ?? const <String, Object?>{};
    final referer = enrichedDetail.sourceUrl;
    final currentHlsSource = metadata['hlsSource']?.toString().trim() ?? '';

    final inlineVariants =
        _readVariantsFromMetadata(
          metadata: metadata,
          hlsSource: currentHlsSource,
        ) ??
        await _loadVariants(hlsSource: currentHlsSource, referer: referer);
    if (inlineVariants != null && inlineVariants.variants.isNotEmpty) {
      final refreshedQuality = ChaturbateMapper.mapPlayQualitiesFromVariants(
        variants: inlineVariants.variants,
        fallbackPlaylistUrl: currentHlsSource,
        masterPlaylistContent: inlineVariants.masterPlaylistContent,
      ).firstWhere((item) => item.id == quality.id, orElse: () => quality);
      return (detail: enrichedDetail, quality: refreshedQuality);
    }

    final refreshed = await _refreshPlaybackDetail(
      detail: enrichedDetail,
      referer: referer,
    );
    if (refreshed == null) {
      return (detail: enrichedDetail, quality: quality);
    }

    final refreshedQuality = ChaturbateMapper.mapPlayQualitiesFromVariants(
      variants: refreshed.variants,
      fallbackPlaylistUrl: refreshed.detail.metadata?['hlsSource']?.toString(),
      masterPlaylistContent: refreshed.masterPlaylistContent,
    ).firstWhere((item) => item.id == quality.id, orElse: () => quality);
    return (detail: refreshed.detail, quality: refreshedQuality);
  }

  void _primeRoomPlaybackBootstrap({
    required String roomId,
    required String? referer,
  }) {
    if (roomId.isEmpty || _roomPlaybackBootstrapFutures.containsKey(roomId)) {
      return;
    }
    _roomPlaybackBootstrapCache.remove(roomId);
    final future = _loadRoomPlaybackBootstrap(roomId: roomId, referer: referer);
    _roomPlaybackBootstrapFutures[roomId] = future;
    unawaited(() async {
      try {
        final bootstrap = await future;
        if (bootstrap != null) {
          _rememberPlaybackBootstrap(roomId, bootstrap);
        }
      } finally {
        if (identical(_roomPlaybackBootstrapFutures[roomId], future)) {
          _roomPlaybackBootstrapFutures.remove(roomId);
        }
      }
    }());
  }

  Future<_ChaturbatePlaybackBootstrap?> _awaitRoomPlaybackBootstrap({
    required String roomId,
    required String? referer,
  }) async {
    if (roomId.isEmpty) {
      return null;
    }
    final cached = _roomPlaybackBootstrapCache[roomId];
    if (cached != null) {
      _rememberPlaybackBootstrap(roomId, cached);
      return cached;
    }
    _primeRoomPlaybackBootstrap(roomId: roomId, referer: referer);
    final future = _roomPlaybackBootstrapFutures[roomId];
    if (future == null) {
      return null;
    }
    final bootstrap = await future;
    if (bootstrap != null) {
      _rememberPlaybackBootstrap(roomId, bootstrap);
    }
    return bootstrap;
  }

  void _rememberPlaybackBootstrap(
    String roomId,
    _ChaturbatePlaybackBootstrap bootstrap,
  ) {
    _roomPlaybackBootstrapCache.remove(roomId);
    _roomPlaybackBootstrapCache[roomId] = bootstrap;
    if (_roomPlaybackBootstrapCache.length <=
        _maxPlaybackBootstrapCacheEntries) {
      return;
    }
    _roomPlaybackBootstrapCache.remove(_roomPlaybackBootstrapCache.keys.first);
  }

  int get debugPlaybackBootstrapCacheSize => _roomPlaybackBootstrapCache.length;

  void debugRememberPlaybackBootstrap(String roomId) {
    _rememberPlaybackBootstrap(roomId, (
      hlsSource: 'https://example.com/$roomId.m3u8',
      variants: const <ChaturbateHlsVariant>[],
      masterPlaylistContent: '',
    ));
  }

  Future<_ChaturbatePlaybackBootstrap?> _loadRoomPlaybackBootstrap({
    required String roomId,
    required String? referer,
  }) async {
    try {
      // C: enter-room / play path — use configured account cookie when present.
      final roomContext = await _apiClient
          .fetchRoomContext(roomId)
          .timeout(_roomContextRequestTimeout);
      final hlsSource = roomContext['hls_source']?.toString().trim() ?? '';
      if (hlsSource.isEmpty) {
        return null;
      }
      final variants = await _loadVariants(
        hlsSource: hlsSource,
        referer: referer,
      );
      return (
        hlsSource: hlsSource,
        variants: variants?.variants ?? const <ChaturbateHlsVariant>[],
        masterPlaylistContent: variants?.masterPlaylistContent ?? '',
      );
    } catch (error, stackTrace) {
      reportProviderDiagnostic(
        providerId: ProviderId.chaturbate,
        scope: 'chaturbate playback bootstrap',
        message: 'failed for roomId=$roomId',
        error: error,
        stackTrace: stackTrace,
        diagnostics: _diagnostics,
      );
      return null;
    }
  }

  Future<LiveRoomDetail> _detailWithPlaybackBootstrap(
    LiveRoomDetail detail,
  ) async {
    final inlineBootstrap = _readPlaybackBootstrapFromDetail(detail);
    if (inlineBootstrap != null) {
      return _applyPlaybackBootstrap(
        detail: detail,
        bootstrap: inlineBootstrap,
      );
    }
    final bootstrap = await _awaitRoomPlaybackBootstrap(
      roomId: detail.roomId.trim(),
      referer: detail.sourceUrl,
    );
    if (bootstrap == null) {
      return detail;
    }
    return _applyPlaybackBootstrap(detail: detail, bootstrap: bootstrap);
  }

  _ChaturbatePlaybackBootstrap? _readPlaybackBootstrapFromDetail(
    LiveRoomDetail detail,
  ) {
    final metadata = detail.metadata ?? const <String, Object?>{};
    final hlsSource = metadata['hlsSource']?.toString().trim() ?? '';
    final masterPlaylistContent =
        metadata['hlsMasterPlaylistContent']?.toString().trim() ?? '';
    if (hlsSource.isEmpty || masterPlaylistContent.isEmpty) {
      return null;
    }
    final variants = _hlsMasterPlaylistParser.parse(
      playlistUrl: hlsSource,
      source: masterPlaylistContent,
    );
    return (
      hlsSource: hlsSource,
      variants: variants,
      masterPlaylistContent: masterPlaylistContent,
    );
  }

  _ChaturbateVariantLoadResult? _readVariantsFromMetadata({
    required Map<String, Object?> metadata,
    required String hlsSource,
  }) {
    final masterPlaylistContent =
        metadata['hlsMasterPlaylistContent']?.toString().trim() ?? '';
    if (hlsSource.isEmpty || masterPlaylistContent.isEmpty) {
      return null;
    }
    return (
      variants: _hlsMasterPlaylistParser.parse(
        playlistUrl: hlsSource,
        source: masterPlaylistContent,
      ),
      masterPlaylistContent: masterPlaylistContent,
    );
  }

  LiveRoomDetail _applyPlaybackBootstrap({
    required LiveRoomDetail detail,
    required _ChaturbatePlaybackBootstrap bootstrap,
  }) {
    final metadata = <String, Object?>{
      ...?detail.metadata,
      if (bootstrap.hlsSource.isNotEmpty) 'hlsSource': bootstrap.hlsSource,
      if (bootstrap.masterPlaylistContent.trim().isNotEmpty)
        'hlsMasterPlaylistContent': bootstrap.masterPlaylistContent,
    };
    return LiveRoomDetail(
      providerId: detail.providerId,
      roomId: detail.roomId,
      title: detail.title,
      streamerName: detail.streamerName,
      streamerAvatarUrl: detail.streamerAvatarUrl,
      coverUrl: detail.coverUrl,
      keyframeUrl: detail.keyframeUrl,
      areaName: detail.areaName,
      description: detail.description,
      sourceUrl: detail.sourceUrl,
      startedAt: detail.startedAt,
      isLive: detail.isLive,
      viewerCount: detail.viewerCount,
      danmakuToken: detail.danmakuToken,
      metadata: metadata,
    );
  }

  Future<
    ({
      LiveRoomDetail detail,
      List<ChaturbateHlsVariant> variants,
      String masterPlaylistContent,
    })?
  >
  _refreshPlaybackDetail({
    required LiveRoomDetail detail,
    required String? referer,
  }) async {
    final results = await Future.wait([
      _refreshPlaybackDetailFromRoomContext(detail: detail, referer: referer),
      _refreshPlaybackDetailFromRoomPage(detail: detail, referer: referer),
    ]);
    for (final result in results) {
      if (result != null && result.variants.isNotEmpty) {
        return result;
      }
    }
    for (final result in results) {
      if (result != null) {
        return result;
      }
    }
    return null;
  }

  Future<
    ({
      LiveRoomDetail detail,
      List<ChaturbateHlsVariant> variants,
      String masterPlaylistContent,
    })?
  >
  _refreshPlaybackDetailFromRoomContext({
    required LiveRoomDetail detail,
    required String? referer,
  }) async {
    final roomId = detail.roomId.trim();
    if (roomId.isEmpty) {
      return null;
    }
    try {
      // C: play refresh uses account cookie (same as enter-room context).
      final roomContext = await _apiClient
          .fetchRoomContext(roomId)
          .timeout(_roomContextRequestTimeout);
      final refreshedHlsSource =
          roomContext['hls_source']?.toString().trim() ?? '';
      return _buildPlaybackRefreshResult(
        detail: detail,
        referer: referer,
        hlsSource: refreshedHlsSource,
      );
    } catch (error, stackTrace) {
      reportProviderDiagnostic(
        providerId: ProviderId.chaturbate,
        scope: 'chaturbate playback refresh context',
        message: 'failed for roomId=$roomId',
        error: error,
        stackTrace: stackTrace,
        diagnostics: _diagnostics,
      );
      return null;
    }
  }

  Future<
    ({
      LiveRoomDetail detail,
      List<ChaturbateHlsVariant> variants,
      String masterPlaylistContent,
    })?
  >
  _refreshPlaybackDetailFromRoomPage({
    required LiveRoomDetail detail,
    required String? referer,
  }) async {
    final roomId = detail.roomId.trim();
    if (roomId.isEmpty) {
      return null;
    }
    try {
      final html = await _fetchRoomPageHtml(roomId);
      final context = _roomPageParser.parsePageContext(html);
      final refreshedDetail = ChaturbateMapper.mapRoomDetailFromPageContext(
        context,
      );
      final refreshedMetadata =
          refreshedDetail.metadata ?? const <String, Object?>{};
      final refreshedHlsSource =
          refreshedMetadata['hlsSource']?.toString().trim() ?? '';
      return _buildPlaybackRefreshResult(
        detail: detail,
        referer: refreshedDetail.sourceUrl ?? referer,
        hlsSource: refreshedHlsSource,
        extraMetadata: refreshedMetadata,
      );
    } catch (error, stackTrace) {
      reportProviderDiagnostic(
        providerId: ProviderId.chaturbate,
        scope: 'chaturbate playback refresh room page',
        message: 'failed for roomId=$roomId',
        error: error,
        stackTrace: stackTrace,
        diagnostics: _diagnostics,
      );
      return null;
    }
  }

  Future<
    ({
      LiveRoomDetail detail,
      List<ChaturbateHlsVariant> variants,
      String masterPlaylistContent,
    })?
  >
  _buildPlaybackRefreshResult({
    required LiveRoomDetail detail,
    required String? referer,
    required String hlsSource,
    Map<String, Object?> extraMetadata = const <String, Object?>{},
  }) async {
    if (hlsSource.isEmpty) {
      return null;
    }
    final refreshedVariants = await _loadVariants(
      hlsSource: hlsSource,
      referer: referer,
    );
    final masterPlaylistContent =
        refreshedVariants?.masterPlaylistContent ?? '';
    return (
      detail: _copyDetailWithHlsSource(
        detail: detail,
        hlsSource: hlsSource,
        masterPlaylistContent: masterPlaylistContent,
        extraMetadata: extraMetadata,
      ),
      variants: refreshedVariants?.variants ?? const <ChaturbateHlsVariant>[],
      masterPlaylistContent: masterPlaylistContent,
    );
  }

  LiveRoomDetail _copyDetailWithHlsSource({
    required LiveRoomDetail detail,
    required String hlsSource,
    required String masterPlaylistContent,
    Map<String, Object?> extraMetadata = const <String, Object?>{},
  }) {
    return LiveRoomDetail(
      providerId: detail.providerId,
      roomId: detail.roomId,
      title: detail.title,
      streamerName: detail.streamerName,
      streamerAvatarUrl: detail.streamerAvatarUrl,
      coverUrl: detail.coverUrl,
      keyframeUrl: detail.keyframeUrl,
      areaName: detail.areaName,
      description: detail.description,
      sourceUrl: detail.sourceUrl,
      startedAt: detail.startedAt,
      isLive: detail.isLive,
      viewerCount: detail.viewerCount,
      danmakuToken: detail.danmakuToken,
      metadata: {
        ...?detail.metadata,
        ...extraMetadata,
        'hlsSource': hlsSource,
        if (masterPlaylistContent.trim().isNotEmpty)
          'hlsMasterPlaylistContent': masterPlaylistContent,
      },
    );
  }

  void _diagnostic(String message) {
    _diagnostics?.call('chaturbate data source: $message');
  }
}
