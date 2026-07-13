import 'dart:async';

import 'package:live_core/live_core.dart';

import '../provider_json.dart';
import '../provider_runtime_support.dart';
import 'youtube_api_client.dart';
import 'youtube_category_definitions.dart';
import 'youtube_mapper.dart';
import 'youtube_page_parser.dart';
import 'youtube_playback_data_source.dart';

class YouTubeBrowseDataSource {
  YouTubeBrowseDataSource({
    required YouTubeApiClient apiClient,
    required YouTubePlaybackDataSource playbackDataSource,
    YouTubePageParser pageParser = const YouTubePageParser(),
    Future<PagedResponse<LiveRoom>> Function(String query, {int page})?
    searchRoomsDelegate,
  }) : _apiClient = apiClient,
       _playbackDataSource = playbackDataSource,
       _pageParser = pageParser,
       _searchRoomsDelegate = searchRoomsDelegate;

  final YouTubeApiClient _apiClient;
  final YouTubePlaybackDataSource _playbackDataSource;
  final YouTubePageParser _pageParser;
  final Future<PagedResponse<LiveRoom>> Function(String query, {int page})?
  _searchRoomsDelegate;

  static const List<String> _recommendQueries = [
    'live news',
    'gaming live',
    'music live',
    'sports live',
    'podcast live',
  ];
  static const String _liveSearchFilter = 'EgJAAQ==';
  static const int _categoryPageSize = 30;
  static const int _recommendQueryBatchSize = 5;
  static final List<String> _recommendQueryPool = _buildRecommendQueryPool();

  static const String _playbackSourcesMetadataKey = 'playbackSources';
  static const String _playbackAudioSourcesMetadataKey = 'playbackAudioSources';

  Future<List<LiveCategory>> fetchCategories() async {
    final groups = <String, List<YouTubeLiveCategoryDefinition>>{};
    for (final definition in youtubeCategoryDefinitions) {
      groups.putIfAbsent(definition.groupId, () => []).add(definition);
    }
    return groups.entries
        .map(
          (entry) => LiveCategory(
            id: entry.key,
            name: entry.value.first.groupName,
            children: entry.value
                .map(
                  (definition) => LiveSubCategory(
                    id: definition.id,
                    parentId: definition.groupId,
                    name: definition.name,
                  ),
                )
                .toList(growable: false),
          ),
        )
        .toList(growable: false);
  }

  Future<PagedResponse<LiveRoom>> fetchCategoryRooms(
    LiveSubCategory category, {
    int page = 1,
  }) async {
    YouTubeLiveCategoryDefinition? definition;
    for (final item in youtubeCategoryDefinitions) {
      if (item.id == category.id) {
        definition = item;
        break;
      }
    }
    if (definition == null || page <= 0) {
      return PagedResponse(items: const [], hasMore: false, page: page);
    }
    final queryResults = await Future.wait(
      definition.queries.map(_loadCategoryQueryRooms),
    );
    final seen = <String>{};
    final rooms = <LiveRoom>[];
    ProviderParseException? firstError;
    for (final result in queryResults) {
      firstError ??= result.error;
      for (final room in result.rooms) {
        if (!seen.add(room.roomId)) {
          continue;
        }
        rooms.add(
          LiveRoom(
            providerId: room.providerId,
            roomId: room.roomId,
            title: room.title,
            streamerName: room.streamerName,
            coverUrl: room.coverUrl,
            keyframeUrl: room.keyframeUrl,
            areaName: definition.name,
            streamerAvatarUrl: room.streamerAvatarUrl,
            viewerCount: room.viewerCount,
            isLive: room.isLive,
          ),
        );
      }
    }
    if (rooms.isEmpty && firstError != null) {
      throw ProviderParseException(
        providerId: ProviderId.youtube,
        message: 'YouTube 分类 ${definition.name} 房间加载失败：${firstError.message}',
      );
    }
    rooms.sort((left, right) {
      final viewerCompare = (right.viewerCount ?? -1).compareTo(
        left.viewerCount ?? -1,
      );
      if (viewerCompare != 0) {
        return viewerCompare;
      }
      return left.roomId.compareTo(right.roomId);
    });
    final startIndex = (page - 1) * _categoryPageSize;
    final items = rooms
        .skip(startIndex)
        .take(_categoryPageSize)
        .toList(growable: false);
    return PagedResponse(
      items: items,
      hasMore: startIndex + _categoryPageSize < rooms.length,
      page: page,
    );
  }

  Future<PagedResponse<LiveRoom>> fetchRecommendRooms({int page = 1}) async {
    if (page <= 0) {
      return PagedResponse(items: const [], hasMore: false, page: page);
    }
    final startIndex = (page - 1) * _recommendQueryBatchSize;
    if (startIndex >= _recommendQueryPool.length) {
      return PagedResponse(items: const [], hasMore: false, page: page);
    }
    final queryBatch = _recommendQueryPool
        .skip(startIndex)
        .take(_recommendQueryBatchSize)
        .toList(growable: false);
    final queryResults = await Future.wait(
      queryBatch.map(_loadCategoryQueryRooms),
    );
    final seen = <String>{};
    final items = <LiveRoom>[];
    ProviderParseException? firstError;
    for (final result in queryResults) {
      firstError ??= result.error;
      for (final room in result.rooms) {
        if (!seen.add(room.roomId)) {
          continue;
        }
        items.add(room);
      }
    }
    if (items.isEmpty && firstError != null) {
      throw ProviderParseException(
        providerId: ProviderId.youtube,
        message: 'YouTube 首页推荐加载失败：${firstError.message}',
      );
    }
    _sortRoomsByPopularity(items);
    return PagedResponse(
      items: items,
      hasMore:
          startIndex + _recommendQueryBatchSize < _recommendQueryPool.length,
      page: page,
    );
  }

  Future<PagedResponse<LiveRoom>> searchRooms(
    String query, {
    int page = 1,
  }) async {
    final normalizedQuery = query.trim();
    if (page != 1 || normalizedQuery.isEmpty) {
      return PagedResponse(items: const [], hasMore: false, page: page);
    }
    final url = Uri.https('www.youtube.com', '/results', {
      'search_query': normalizedQuery,
      'sp': _liveSearchFilter,
    }).toString();
    final html = await _apiClient.fetchText(
      url,
      headers: _buildPageHeaders(referer: 'https://www.youtube.com/'),
    );
    final items = _pageParser
        .parseSearchCandidates(html)
        .map(YouTubeMapper.mapSearchRoom)
        .toList(growable: false);
    return PagedResponse(items: items, hasMore: false, page: page);
  }

  Future<LiveRoomDetail> fetchRoomDetail(String roomId) async {
    final normalizedRoomId = roomId.trim().replaceFirst(RegExp(r'^/+'), '');
    if (normalizedRoomId.isEmpty) {
      throw ProviderParseException(
        providerId: ProviderId.youtube,
        message: 'YouTube 房间号不能为空。',
      );
    }
    final sourcePageUrl = _buildSourcePageUrl(normalizedRoomId);
    final html = await _apiClient.fetchText(
      sourcePageUrl,
      headers: _buildPageHeaders(referer: 'https://www.youtube.com/'),
    );
    final bootstrap = _pageParser.parsePage(
      requestedRoomId: normalizedRoomId,
      html: html,
    );
    final resolvedVideoId = bootstrap.videoId?.trim() ?? '';
    if (resolvedVideoId.isEmpty) {
      throw ProviderParseException(
        providerId: ProviderId.youtube,
        message: 'YouTube 当前未能从页面解析到可用视频 ID。',
      );
    }
    final playbackBundle = await _playbackDataSource.loadPlaybackBundle(
      bootstrap: bootstrap,
      resolvedVideoId: resolvedVideoId,
      sourcePageUrl: sourcePageUrl,
    );
    final pageCandidate = _pageParser.findLiveCandidateByVideoId(
      initialData: bootstrap.initialData,
      videoId: resolvedVideoId,
    );
    final playerResponse = playbackBundle.detailPlayerResponse;
    final liveChatBootstrap = _isLivePlayerResponse(playerResponse)
        ? await _tryResolveLiveChatBootstrap(
            videoId: resolvedVideoId,
            sourcePageUrl: sourcePageUrl,
            fallbackApiKey: bootstrap.apiKey,
          )
        : null;
    return YouTubeMapper.mapRoomDetail(
      requestedRoomId: normalizedRoomId,
      resolvedVideoId: resolvedVideoId,
      playerResponse: playerResponse,
      sourcePageUrl: sourcePageUrl,
      apiKey: bootstrap.apiKey,
      pageCandidate: pageCandidate,
      playerClientContext: playbackBundle.playerClientContext,
      playerRolloutToken: bootstrap.rolloutToken,
      playerPoToken: bootstrap.poToken,
      liveChatBootstrap: liveChatBootstrap,
      additionalMetadata: {
        if (bootstrap.playerJsUrl != null && bootstrap.playerJsUrl!.isNotEmpty)
          'playerJsUrl': bootstrap.playerJsUrl,
        if (playbackBundle.playbackSources.isNotEmpty)
          _playbackSourcesMetadataKey: playbackBundle.playbackSources
              .map((item) => item.toMetadata())
              .toList(growable: false),
        if (playbackBundle.playbackAudioSources.isNotEmpty)
          _playbackAudioSourcesMetadataKey: playbackBundle.playbackAudioSources
              .map((item) => item.toMetadata())
              .toList(growable: false),
        if (playbackBundle.primarySource != null) ...{
          'playerClientProfile': playbackBundle.primarySource!.clientProfile.id,
          'playerPlaybackStrategy': playbackBundle.primarySource!.strategy,
        },
        if (playbackBundle.playbackUnavailableReason != null)
          'playbackUnavailableReason': playbackBundle.playbackUnavailableReason,
        if (playbackBundle.playbackDiagnostics.isNotEmpty)
          'playbackDiagnostics': playbackBundle.playbackDiagnostics,
      },
    );
  }

  Future<_YouTubeCategoryQueryResult> _loadCategoryQueryRooms(
    String query,
  ) async {
    try {
      final response =
          await (_searchRoomsDelegate?.call(query, page: 1) ??
              searchRooms(query, page: 1));
      return _YouTubeCategoryQueryResult(query: query, rooms: response.items);
    } on ProviderParseException catch (error, stackTrace) {
      reportProviderDiagnostic(
        providerId: ProviderId.youtube,
        scope: 'youtube category query load',
        message: 'search failed for query="$query"',
        error: error,
        stackTrace: stackTrace,
      );
      return _YouTubeCategoryQueryResult(query: query, error: error);
    } catch (error, stackTrace) {
      reportProviderDiagnostic(
        providerId: ProviderId.youtube,
        scope: 'youtube category query load',
        message: 'unexpected search failure for query="$query"',
        error: error,
        stackTrace: stackTrace,
      );
      return _YouTubeCategoryQueryResult(
        query: query,
        error: ProviderParseException(
          providerId: ProviderId.youtube,
          message: 'YouTube 搜索 "$query" 失败：$error',
        ),
      );
    }
  }

  void _sortRoomsByPopularity(List<LiveRoom> rooms) {
    rooms.sort((left, right) {
      final viewerCompare = (right.viewerCount ?? -1).compareTo(
        left.viewerCount ?? -1,
      );
      if (viewerCompare != 0) {
        return viewerCompare;
      }
      return left.roomId.compareTo(right.roomId);
    });
  }

  static List<String> _buildRecommendQueryPool() {
    final pool = <String>[];
    final seen = <String>{};
    final queryCandidates = <String>[
      ..._recommendQueries,
      for (final definition in youtubeCategoryDefinitions)
        ...definition.queries,
    ];
    for (final query in queryCandidates) {
      if (seen.add(query)) {
        pool.add(query);
      }
    }
    return List<String>.unmodifiable(pool);
  }

  Future<YouTubeLiveChatBootstrap?> _tryResolveLiveChatBootstrap({
    required String videoId,
    required String sourcePageUrl,
    required String fallbackApiKey,
  }) async {
    try {
      final pageUrl = _buildLiveChatPageUrl(videoId);
      final html = await _apiClient.fetchText(
        pageUrl,
        headers: _buildPageHeaders(referer: sourcePageUrl),
      );
      return _pageParser.tryParseLiveChatBootstrap(
        html: html,
        fallbackApiKey: fallbackApiKey,
      );
    } catch (error, stackTrace) {
      reportProviderDiagnostic(
        providerId: ProviderId.youtube,
        scope: 'youtube live chat bootstrap',
        message: 'failed for videoId=$videoId',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  bool _isLivePlayerResponse(Map<String, dynamic> playerResponse) {
    final videoDetails = _asMap(playerResponse['videoDetails']);
    final microformat = _asMap(
      _asMap(playerResponse['microformat'])['playerMicroformatRenderer'],
    );
    final liveBroadcastDetails = _asMap(microformat['liveBroadcastDetails']);
    return liveBroadcastDetails['isLiveNow'] == true ||
        videoDetails['isLive'] == true ||
        videoDetails['isLiveContent'] == true;
  }

  String _buildSourcePageUrl(String roomId) {
    if (RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(roomId)) {
      return 'https://www.youtube.com/watch?v=$roomId';
    }
    return 'https://www.youtube.com/$roomId';
  }

  String _buildLiveChatPageUrl(String videoId) {
    return Uri.https('www.youtube.com', '/live_chat', {
      'is_popout': '1',
      'v': videoId,
    }).toString();
  }

  Map<String, String> _buildPageHeaders({required String referer}) {
    return {
      'accept-language': 'en-US,en;q=0.9',
      'referer': referer,
      'user-agent': YouTubeApiClient.browserUserAgent,
    };
  }

  Map<String, dynamic> _asMap(Object? value) {
    return ProviderJson.asMap(value);
  }
}

class _YouTubeCategoryQueryResult {
  const _YouTubeCategoryQueryResult({
    required this.query,
    this.rooms = const [],
    this.error,
  });

  final String query;
  final List<LiveRoom> rooms;
  final ProviderParseException? error;
}
