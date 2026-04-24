import 'dart:async';

import 'package:live_core/live_core.dart';

import 'chaturbate_api_client.dart';
import 'chaturbate_data_source.dart';
import 'chaturbate_hls_master_playlist_parser.dart';
import 'chaturbate_mapper.dart';
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

class ChaturbateLiveDataSource implements ChaturbateDataSource {
  ChaturbateLiveDataSource({
    required ChaturbateApiClient apiClient,
    ChaturbateRoomPageParser roomPageParser = const ChaturbateRoomPageParser(),
    ChaturbateHlsMasterPlaylistParser hlsMasterPlaylistParser =
        const ChaturbateHlsMasterPlaylistParser(),
    List<String>? recommendCarouselIds,
    Duration roomPageRequestTimeout = const Duration(seconds: 6),
    Duration roomContextRequestTimeout = const Duration(seconds: 3),
    Duration hlsPlaylistRequestTimeout = const Duration(seconds: 4),
  })  : _apiClient = apiClient,
        _roomPageParser = roomPageParser,
        _hlsMasterPlaylistParser = hlsMasterPlaylistParser,
        _roomPageRequestTimeout = roomPageRequestTimeout,
        _roomContextRequestTimeout = roomContextRequestTimeout,
        _hlsPlaylistRequestTimeout = hlsPlaylistRequestTimeout,
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
    final response = await _apiClient.fetchRoomList(
      query: normalizedQuery,
      offset: offset,
      limit: ChaturbateApiClient.searchPageSize,
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
    final normalizedRoomId = roomId.trim();
    if (normalizedRoomId.isNotEmpty) {
      _primeRoomPlaybackBootstrap(
        roomId: normalizedRoomId,
        referer: 'https://chaturbate.com/$normalizedRoomId/',
      );
    }
    final html =
        await _apiClient.fetchRoomPage(roomId).timeout(_roomPageRequestTimeout);
    final context = _roomPageParser.parsePageContext(html);
    var detail = ChaturbateMapper.mapRoomDetailFromPageContext(context);
    final bootstrap = normalizedRoomId.isEmpty
        ? null
        : _roomPlaybackBootstrapCache[normalizedRoomId];
    if (bootstrap != null) {
      detail = _applyPlaybackBootstrap(
        detail: detail,
        bootstrap: bootstrap,
      );
    }
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
      metadata: {
        ...?detail.metadata,
        'requestCookie': requestCookie,
      },
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

    final initialVariants = preloadedVariants ??
        await _loadVariants(
          hlsSource: initialHlsSource,
          referer: referer,
        );
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
          fallbackPlaylistUrl:
              refreshed.detail.metadata?['hlsSource']?.toString().trim(),
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
    final uniqueRooms = <String, LiveRoom>{};
    var successfulCarouselCount = 0;
    Object? lastError;
    for (final carouselId in _recommendCarouselIds) {
      if (_isExcludedCarouselId(carouselId)) {
        continue;
      }

      Map<String, dynamic> response;
      try {
        response = await _fetchCarouselWithRetry(
          carouselId,
          genders: genders,
        );
        successfulCarouselCount += 1;
      } catch (error) {
        lastError = error;
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
    }

    final items = uniqueRooms.values.toList(growable: false)
      ..sort((left, right) {
        final compare =
            (right.viewerCount ?? -1).compareTo(left.viewerCount ?? -1);
        if (compare != 0) {
          return compare;
        }
        return left.roomId.compareTo(right.roomId);
      });
    if (successfulCarouselCount == 0 && lastError != null) {
      throw lastError;
    }
    return items;
  }

  Future<Map<String, dynamic>> _fetchCarouselWithRetry(
    String carouselId, {
    required String genders,
  }) async {
    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt += 1) {
      try {
        return await _apiClient.fetchDiscoverCarousel(
          carouselId,
          genders: genders,
        );
      } catch (error) {
        lastError = error;
      }
    }
    if (lastError != null) {
      throw lastError;
    }
    throw StateError(
      'Unexpected empty retry result for carousel=$carouselId genders=$genders',
    );
  }

  List<dynamic> _asList(Object? value) {
    if (value is List) {
      return value;
    }
    return const [];
  }

  Map<String, dynamic> _asMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.cast<String, dynamic>();
    }
    return const {};
  }

  int? _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '');
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
          .fetchHlsPlaylist(
            hlsSource,
            referer: referer,
            cookie: '',
          )
          .timeout(_hlsPlaylistRequestTimeout);
      return (
        variants: _hlsMasterPlaylistParser.parse(
          playlistUrl: hlsSource,
          source: playlistText,
        ),
        masterPlaylistContent: playlistText,
      );
    } catch (_) {
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

    final inlineVariants = _readVariantsFromMetadata(
          metadata: metadata,
          hlsSource: currentHlsSource,
        ) ??
        await _loadVariants(
          hlsSource: currentHlsSource,
          referer: referer,
        );
    if (inlineVariants != null && inlineVariants.variants.isNotEmpty) {
      final refreshedQuality = ChaturbateMapper.mapPlayQualitiesFromVariants(
        variants: inlineVariants.variants,
        fallbackPlaylistUrl: currentHlsSource,
        masterPlaylistContent: inlineVariants.masterPlaylistContent,
      ).firstWhere(
        (item) => item.id == quality.id,
        orElse: () => quality,
      );
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
    ).firstWhere(
      (item) => item.id == quality.id,
      orElse: () => quality,
    );
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
    final future = _loadRoomPlaybackBootstrap(
      roomId: roomId,
      referer: referer,
    );
    _roomPlaybackBootstrapFutures[roomId] = future;
    unawaited(() async {
      try {
        final bootstrap = await future;
        if (bootstrap != null) {
          _roomPlaybackBootstrapCache[roomId] = bootstrap;
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
      return cached;
    }
    _primeRoomPlaybackBootstrap(
      roomId: roomId,
      referer: referer,
    );
    final future = _roomPlaybackBootstrapFutures[roomId];
    if (future == null) {
      return null;
    }
    final bootstrap = await future;
    if (bootstrap != null) {
      _roomPlaybackBootstrapCache[roomId] = bootstrap;
    }
    return bootstrap;
  }

  Future<_ChaturbatePlaybackBootstrap?> _loadRoomPlaybackBootstrap({
    required String roomId,
    required String? referer,
  }) async {
    try {
      final roomContext = await _apiClient
          .fetchRoomContext(
            roomId,
            cookie: '',
          )
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
    } catch (_) {
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
    return _applyPlaybackBootstrap(
      detail: detail,
      bootstrap: bootstrap,
    );
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
      })?> _refreshPlaybackDetail({
    required LiveRoomDetail detail,
    required String? referer,
  }) async {
    final results = await Future.wait([
      _refreshPlaybackDetailFromRoomContext(
        detail: detail,
        referer: referer,
      ),
      _refreshPlaybackDetailFromRoomPage(
        detail: detail,
        referer: referer,
      ),
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
      })?> _refreshPlaybackDetailFromRoomContext({
    required LiveRoomDetail detail,
    required String? referer,
  }) async {
    final roomId = detail.roomId.trim();
    if (roomId.isEmpty) {
      return null;
    }
    try {
      final roomContext = await _apiClient
          .fetchRoomContext(
            roomId,
            cookie: '',
          )
          .timeout(_roomContextRequestTimeout);
      final refreshedHlsSource =
          roomContext['hls_source']?.toString().trim() ?? '';
      return _buildPlaybackRefreshResult(
        detail: detail,
        referer: referer,
        hlsSource: refreshedHlsSource,
      );
    } catch (_) {
      return null;
    }
  }

  Future<
      ({
        LiveRoomDetail detail,
        List<ChaturbateHlsVariant> variants,
        String masterPlaylistContent,
      })?> _refreshPlaybackDetailFromRoomPage({
    required LiveRoomDetail detail,
    required String? referer,
  }) async {
    final roomId = detail.roomId.trim();
    if (roomId.isEmpty) {
      return null;
    }
    try {
      final html = await _apiClient
          .fetchRoomPage(roomId)
          .timeout(_roomPageRequestTimeout);
      final context = _roomPageParser.parsePageContext(html);
      final refreshedDetail =
          ChaturbateMapper.mapRoomDetailFromPageContext(context);
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
    } catch (_) {
      return null;
    }
  }

  Future<
      ({
        LiveRoomDetail detail,
        List<ChaturbateHlsVariant> variants,
        String masterPlaylistContent,
      })?> _buildPlaybackRefreshResult({
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
}
