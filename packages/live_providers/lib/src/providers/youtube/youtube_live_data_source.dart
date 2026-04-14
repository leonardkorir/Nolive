import 'dart:convert';

import 'package:live_core/live_core.dart';

import 'youtube_api_client.dart';
import 'youtube_data_source.dart';
import 'youtube_hls_master_playlist_parser.dart';
import 'youtube_mapper.dart';
import 'youtube_page_parser.dart';

class YouTubeLiveDataSource implements YouTubeDataSource {
  YouTubeLiveDataSource({
    required YouTubeApiClient apiClient,
    YouTubePageParser pageParser = const YouTubePageParser(),
    YouTubeHlsMasterPlaylistParser hlsMasterPlaylistParser =
        const YouTubeHlsMasterPlaylistParser(),
  })  : _apiClient = apiClient,
        _pageParser = pageParser,
        _hlsMasterPlaylistParser = hlsMasterPlaylistParser;

  final YouTubeApiClient _apiClient;
  final YouTubePageParser _pageParser;
  final YouTubeHlsMasterPlaylistParser _hlsMasterPlaylistParser;
  final Map<String, List<YouTubeHlsVariant>> _hlsVariantCache =
      <String, List<YouTubeHlsVariant>>{};
  final Map<String, bool> _hlsUsabilityCache = <String, bool>{};
  static const List<YouTubePlayerClientProfile> _playbackProfiles = [
    YouTubePlayerClientProfile.webSafari,
    YouTubePlayerClientProfile.mweb,
    YouTubePlayerClientProfile.ios,
    YouTubePlayerClientProfile.web,
  ];
  static const String _playbackSourcesMetadataKey = 'playbackSources';
  static const String _playbackAudioSourcesMetadataKey = 'playbackAudioSources';
  static const List<_YouTubeLiveCategoryDefinition> _categoryDefinitions = [
    _YouTubeLiveCategoryDefinition(
      id: 'news',
      groupId: 'content',
      groupName: '内容分类',
      name: '新闻',
      queries: [
        'live news',
        'breaking news live',
        'world news live',
        'politics live',
        'financial news live',
      ],
    ),
    _YouTubeLiveCategoryDefinition(
      id: 'gaming',
      groupId: 'content',
      groupName: '内容分类',
      name: '游戏',
      queries: [
        'gaming live',
        'esports live',
        'valorant live',
        'league of legends live',
        'minecraft live',
      ],
    ),
    _YouTubeLiveCategoryDefinition(
      id: 'music',
      groupId: 'content',
      groupName: '内容分类',
      name: '音乐',
      queries: [
        'music live',
        'live concert',
        'dj live',
        'lofi live',
        'radio live',
      ],
    ),
    _YouTubeLiveCategoryDefinition(
      id: 'entertainment',
      groupId: 'content',
      groupName: '内容分类',
      name: '娱乐',
      queries: [
        'entertainment live',
        'talk show live',
        'reaction live',
        'variety show live',
        'vtuber live',
      ],
    ),
    _YouTubeLiveCategoryDefinition(
      id: 'sports',
      groupId: 'content',
      groupName: '内容分类',
      name: '体育',
      queries: [
        'sports live',
        'football live',
        'basketball live',
        'baseball live',
        'mma live',
      ],
    ),
    _YouTubeLiveCategoryDefinition(
      id: 'podcast',
      groupId: 'content',
      groupName: '内容分类',
      name: '播客',
      queries: [
        'podcast live',
        'talk podcast live',
        'interview live',
        'debate live',
        'talk radio live',
      ],
    ),
  ];
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

  @override
  Future<List<LiveCategory>> fetchCategories() async {
    final groups = <String, List<_YouTubeLiveCategoryDefinition>>{};
    for (final definition in _categoryDefinitions) {
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

  @override
  Future<PagedResponse<LiveRoom>> fetchCategoryRooms(
    LiveSubCategory category, {
    int page = 1,
  }) async {
    _YouTubeLiveCategoryDefinition? definition;
    for (final item in _categoryDefinitions) {
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
      final viewerCompare =
          (right.viewerCount ?? -1).compareTo(left.viewerCount ?? -1);
      if (viewerCompare != 0) {
        return viewerCompare;
      }
      return left.roomId.compareTo(right.roomId);
    });
    final startIndex = (page - 1) * _categoryPageSize;
    final items =
        rooms.skip(startIndex).take(_categoryPageSize).toList(growable: false);
    return PagedResponse(
      items: items,
      hasMore: startIndex + _categoryPageSize < rooms.length,
      page: page,
    );
  }

  @override
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

  @override
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

  Future<_YouTubeCategoryQueryResult> _loadCategoryQueryRooms(
    String query,
  ) async {
    try {
      final response = await searchRooms(query, page: 1);
      return _YouTubeCategoryQueryResult(
        query: query,
        rooms: response.items,
      );
    } on ProviderParseException catch (error) {
      return _YouTubeCategoryQueryResult(
        query: query,
        error: error,
      );
    } catch (error) {
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
      final viewerCompare =
          (right.viewerCount ?? -1).compareTo(left.viewerCount ?? -1);
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
      for (final definition in _categoryDefinitions) ...definition.queries,
    ];
    for (final query in queryCandidates) {
      if (seen.add(query)) {
        pool.add(query);
      }
    }
    return List<String>.unmodifiable(pool);
  }

  @override
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
    final playbackBundle = await _loadPlaybackBundle(
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
      },
    );
  }

  @override
  Future<List<LivePlayQuality>> fetchPlayQualities(
    LiveRoomDetail detail,
  ) async {
    final playbackSources = _readPlaybackSources(detail);
    final allHlsSources = playbackSources.where((item) => item.isHls).toList();
    final hlsSources = await _selectUsableHlsSources(allHlsSources);
    for (final source in hlsSources) {
      try {
        final variants = await _loadHlsVariants(source);
        if (variants.isEmpty) {
          continue;
        }
        return YouTubeMapper.mapPlayQualitiesFromVariants(
          variants: variants,
          manifestUrl: source.url,
          headers: source.headers,
        );
      } catch (_) {
        continue;
      }
    }

    final directQualities = _buildDirectPlayQualities(
      playbackSources.where((item) => item.isDirect).toList(),
    );
    if (directQualities.isNotEmpty) {
      return directQualities;
    }

    final dashSources = playbackSources.where((item) => item.isDash).toList();
    if (dashSources.isNotEmpty) {
      return const [
        LivePlayQuality(
          id: 'auto',
          label: 'Auto',
          isDefault: true,
          metadata: {'playbackMode': 'dash'},
        ),
      ];
    }

    for (final source in allHlsSources) {
      try {
        final variants = await _loadHlsVariants(source);
        if (variants.isEmpty) {
          continue;
        }
        return YouTubeMapper.mapPlayQualitiesFromVariants(
          variants: variants,
          manifestUrl: source.url,
          headers: source.headers,
        );
      } catch (_) {
        continue;
      }
    }

    final manifestUrl = await _resolveManifestUrl(detail);
    if (manifestUrl.isEmpty) {
      return const [];
    }
    final sourcePageUrl =
        detail.metadata?['sourcePageUrl']?.toString().trim() ??
            detail.sourceUrl?.trim() ??
            'https://www.youtube.com/';
    final headers = _buildLegacyPlaybackHeaders(sourcePageUrl);
    final playlistText = await _apiClient.fetchText(
      manifestUrl,
      headers: headers,
    );
    final variants = _hlsMasterPlaylistParser.parse(
      playlistUrl: manifestUrl,
      source: playlistText,
    );
    return YouTubeMapper.mapPlayQualitiesFromVariants(
      variants: variants,
      manifestUrl: manifestUrl,
      headers: headers,
    );
  }

  @override
  Future<List<LivePlayUrl>> fetchPlayUrls({
    required LiveRoomDetail detail,
    required LivePlayQuality quality,
  }) async {
    final playbackSources = _readPlaybackSources(detail);
    final playbackAudioSources = _readPlaybackAudioSources(detail);
    if (playbackSources.isEmpty) {
      return YouTubeMapper.mapPlayUrls(detail, quality);
    }

    final mode = quality.metadata?['playbackMode']?.toString().trim() ?? '';
    final urls = <LivePlayUrl>[];
    final seen = <String>{};
    final allHlsSources = playbackSources.where((item) => item.isHls).toList();
    final usableHlsSources = await _selectUsableHlsSources(allHlsSources);
    final hasAlternativeSources =
        playbackSources.any((item) => item.isDirect || item.isDash);
    final hlsSources = usableHlsSources.isNotEmpty
        ? usableHlsSources
        : hasAlternativeSources
            ? const <_YouTubePlaybackSource>[]
            : allHlsSources;

    if (mode != 'direct' && mode != 'dash') {
      if (quality.id == 'auto') {
        for (final source in hlsSources) {
          final hlsAudioMetadata = await _buildHlsAutoAudioMetadata(
            source: source,
            audioSources: playbackAudioSources,
          );
          _appendPlayUrl(
            urls,
            seen: seen,
            candidate: LivePlayUrl(
              url: source.url,
              headers: source.headers,
              lineLabel: source.lineLabel,
              metadata: {
                ...source.toMetadata(),
                ...hlsAudioMetadata,
              },
            ),
          );
        }
      } else {
        for (final source in hlsSources) {
          try {
            final variant = await _selectHlsVariantForQuality(
              source: source,
              quality: quality,
            );
            if (variant == null) {
              continue;
            }
            final hlsAudioMetadata = _buildResolvedHlsVariantAudioMetadata(
              source: source,
              variant: variant,
              audioSources: playbackAudioSources,
            );
            _appendPlayUrl(
              urls,
              seen: seen,
              candidate: LivePlayUrl(
                url: variant.url,
                headers: source.headers,
                lineLabel: source.lineLabel,
                metadata: {
                  ...source.toMetadata(),
                  'qualityId': quality.id,
                  'qualityLabel': quality.label,
                  'resolvedVariantLabel': variant.label,
                  ...hlsAudioMetadata,
                },
              ),
            );
          } catch (_) {
            continue;
          }
        }
      }
    }

    final directSources =
        playbackSources.where((item) => item.isDirect).toList();
    for (final source in _selectDirectSourcesForQuality(
      sources: directSources,
      quality: quality,
    )) {
      _appendPlayUrl(
        urls,
        seen: seen,
        candidate: LivePlayUrl(
          url: source.url,
          headers: source.headers,
          lineLabel: source.lineLabel,
          metadata: source.toMetadata(),
        ),
      );
    }

    for (final source in playbackSources.where((item) => item.isDash)) {
      _appendPlayUrl(
        urls,
        seen: seen,
        candidate: LivePlayUrl(
          url: source.url,
          headers: source.headers,
          lineLabel: source.lineLabel,
          metadata: source.toMetadata(),
        ),
      );
    }
    _debugLog(
      'fetchPlayUrls room=${detail.roomId} '
      'quality=${quality.id}/${quality.label} '
      'sources=${playbackSources.length} '
      'audioSources=${playbackAudioSources.length} '
      'emitted=${urls.length} '
      'emittedAudio=${urls.where((item) => item.metadata?['audioUrl'] != null).length}',
    );
    return urls;
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

  Map<String, String> _buildLegacyPlaybackHeaders(String referer) {
    return {
      'accept': 'application/x-mpegURL, application/vnd.apple.mpegurl, '
          'application/json, text/plain',
      'accept-language': 'en-US,en;q=0.9',
      'referer': referer,
      'user-agent': YouTubeApiClient.browserUserAgent,
    };
  }

  Map<String, String> _buildPlaybackHeaders({
    required YouTubePlayerClientProfile clientProfile,
    required String sourcePageUrl,
  }) {
    return {
      'accept': 'application/x-mpegURL, application/vnd.apple.mpegurl, '
          'application/json, text/plain',
      'accept-language': 'en-US,en;q=0.9',
      'origin': clientProfile.origin,
      'referer': clientProfile.rewriteOriginalUrl(sourcePageUrl),
      'user-agent': clientProfile.userAgent,
    };
  }

  Future<String> _resolveManifestUrl(LiveRoomDetail detail) async {
    final playbackSources = _readPlaybackSources(detail);
    final hlsSource =
        playbackSources.cast<_YouTubePlaybackSource?>().firstWhere(
              (item) => item?.isHls == true,
              orElse: () => null,
            );
    if (hlsSource != null) {
      return hlsSource.url;
    }
    final direct = detail.metadata?['hlsManifestUrl']?.toString().trim() ?? '';
    if (direct.isNotEmpty) {
      return direct;
    }
    if (!detail.isLive) {
      return '';
    }
    final apiKey = detail.metadata?['apiKey']?.toString().trim() ?? '';
    final resolvedVideoId =
        detail.metadata?['resolvedVideoId']?.toString().trim() ?? '';
    final sourcePageUrl =
        detail.metadata?['sourcePageUrl']?.toString().trim() ??
            detail.sourceUrl?.trim() ??
            '';
    if (apiKey.isEmpty || resolvedVideoId.isEmpty || sourcePageUrl.isEmpty) {
      return '';
    }
    final playerResponse = await _apiClient.postPlayer(
      apiKey: apiKey,
      videoId: resolvedVideoId,
      originalUrl: sourcePageUrl,
      innertubeContext: _asMap(detail.metadata?['playerClientContext']),
      rolloutToken: detail.metadata?['playerRolloutToken']?.toString() ?? '',
      poToken: detail.metadata?['playerPoToken']?.toString() ?? '',
      clientProfile: _readPlayerClientProfile(detail),
    );
    return _asMap(playerResponse['streamingData'])['hlsManifestUrl']
            ?.toString()
            .trim() ??
        '';
  }

  Future<_YouTubePlaybackBundle> _loadPlaybackBundle({
    required YouTubePageBootstrap bootstrap,
    required String resolvedVideoId,
    required String sourcePageUrl,
  }) async {
    final pageResponse = _asMap(bootstrap.initialPlayerResponse);
    final baseClientContext = _extractPlayerClientContext(bootstrap);
    final candidates = <_YouTubePlayerResponseCandidate>[];
    Object? firstError;

    for (final profile in _playbackProfiles) {
      try {
        final apiResponse = await _apiClient.postPlayer(
          apiKey: bootstrap.apiKey,
          videoId: resolvedVideoId,
          originalUrl: sourcePageUrl,
          innertubeContext: baseClientContext,
          rolloutToken: bootstrap.rolloutToken ?? '',
          poToken: bootstrap.poToken ?? '',
          clientProfile: profile,
        );
        final merged = pageResponse.isEmpty
            ? apiResponse
            : _mergeMaps(pageResponse, apiResponse);
        if (merged.isEmpty) {
          continue;
        }
        candidates.add(
          _YouTubePlayerResponseCandidate(
            profile: profile,
            sourcePageUrl: profile.rewriteOriginalUrl(sourcePageUrl),
            playerResponse: merged,
            requestClientContext: _buildPlayerClientContext(
              baseContext: baseClientContext,
              clientProfile: profile,
              sourcePageUrl: sourcePageUrl,
            ),
          ),
        );
      } catch (error) {
        firstError ??= error;
      }
    }

    if (candidates.isEmpty && pageResponse.isNotEmpty) {
      final profile = YouTubePlayerClientProfile.web;
      candidates.add(
        _YouTubePlayerResponseCandidate(
          profile: profile,
          sourcePageUrl: sourcePageUrl,
          playerResponse: pageResponse,
          requestClientContext: _buildPlayerClientContext(
            baseContext: baseClientContext,
            clientProfile: profile,
            sourcePageUrl: sourcePageUrl,
          ),
        ),
      );
    }
    if (candidates.isEmpty) {
      if (firstError != null) {
        throw firstError;
      }
      throw ProviderParseException(
        providerId: ProviderId.youtube,
        message: 'YouTube 当前未返回可用播放器响应。',
      );
    }

    final hlsSources = <_YouTubePlaybackSource>[];
    final directSources = <_YouTubePlaybackSource>[];
    final dashSources = <_YouTubePlaybackSource>[];
    final audioSources = <_YouTubePlaybackAudioSource>[];
    final seenSourceKeys = <String>{};
    final seenAudioSourceKeys = <String>{};
    _YouTubePlayerResponseCandidate? primaryCandidate;

    for (final candidate in candidates) {
      final candidateHls = _extractHlsSources(candidate);
      final candidateDirect = _extractDirectSources(candidate);
      final candidateDash = _extractDashSources(candidate);
      final candidateAudio = _extractAudioSources(candidate);
      _debugLog(
        'playback bundle profile=${candidate.profile.id} '
        'hls=${candidateHls.length} '
        'direct=${candidateDirect.length} '
        'dash=${candidateDash.length} '
        'audio=${candidateAudio.length}',
      );
      if (primaryCandidate == null && candidateHls.isNotEmpty) {
        primaryCandidate = candidate;
      } else if (primaryCandidate == null && candidateDirect.isNotEmpty) {
        primaryCandidate = candidate;
      } else if (primaryCandidate == null && candidateDash.isNotEmpty) {
        primaryCandidate = candidate;
      }
      _appendUniqueSources(hlsSources, candidateHls, seenSourceKeys);
      _appendUniqueSources(directSources, candidateDirect, seenSourceKeys);
      _appendUniqueSources(dashSources, candidateDash, seenSourceKeys);
      _appendUniqueAudioSources(
        audioSources,
        candidateAudio,
        seenAudioSourceKeys,
      );
    }
    primaryCandidate ??= candidates.first;

    return _YouTubePlaybackBundle(
      detailPlayerResponse: primaryCandidate.playerResponse,
      playerClientContext: primaryCandidate.requestClientContext,
      playbackAudioSources: audioSources,
      playbackSources: [
        ...hlsSources,
        ...directSources,
        ...dashSources,
      ],
      primarySource: hlsSources.isNotEmpty
          ? hlsSources.first
          : directSources.isNotEmpty
              ? directSources.first
              : dashSources.isNotEmpty
                  ? dashSources.first
                  : null,
    );
  }

  Map<String, dynamic> _extractPlayerClientContext(
    YouTubePageBootstrap bootstrap,
  ) {
    final context = _asMap(bootstrap.innertubeContext);
    final clientContext = _asMap(context['client']);
    if (clientContext.isNotEmpty) {
      return clientContext;
    }
    return context;
  }

  Map<String, dynamic> _mergeMaps(
    Map<String, dynamic> base,
    Map<String, dynamic> overlay,
  ) {
    final merged = <String, dynamic>{...base};
    for (final entry in overlay.entries) {
      final baseValue = merged[entry.key];
      final overlayValue = entry.value;
      if (baseValue is Map && overlayValue is Map) {
        merged[entry.key] = _mergeMaps(
          _asMap(baseValue),
          _asMap(overlayValue),
        );
        continue;
      }
      merged[entry.key] = overlayValue;
    }
    return merged;
  }

  Map<String, dynamic> _buildPlayerClientContext({
    required Map<String, dynamic> baseContext,
    required YouTubePlayerClientProfile clientProfile,
    required String sourcePageUrl,
  }) {
    final visitorData = baseContext['visitorData']?.toString().trim() ?? '';
    return {
      'clientName': clientProfile.clientName,
      'clientVersion': clientProfile.clientVersion,
      'platform': clientProfile.platform,
      'hl': baseContext['hl']?.toString().trim().isNotEmpty == true
          ? baseContext['hl']!.toString().trim()
          : 'en',
      'gl': baseContext['gl']?.toString().trim().isNotEmpty == true
          ? baseContext['gl']!.toString().trim()
          : 'US',
      'originalUrl': clientProfile.rewriteOriginalUrl(sourcePageUrl),
      'clientScreen':
          baseContext['clientScreen']?.toString().trim().isNotEmpty == true
              ? baseContext['clientScreen']!.toString().trim()
              : 'WATCH',
      'clientFormFactor': clientProfile.clientFormFactor,
      'userAgent': clientProfile.userAgent,
      'osName': clientProfile.osName,
      'osVersion': clientProfile.osVersion,
      if (visitorData.isNotEmpty) 'visitorData': visitorData,
      if ((clientProfile.browserName?.isNotEmpty ?? false))
        'browserName': clientProfile.browserName,
      if ((clientProfile.browserVersion?.isNotEmpty ?? false))
        'browserVersion': clientProfile.browserVersion,
      if ((clientProfile.deviceMake?.isNotEmpty ?? false))
        'deviceMake': clientProfile.deviceMake,
      if ((clientProfile.deviceModel?.isNotEmpty ?? false))
        'deviceModel': clientProfile.deviceModel,
    };
  }

  List<_YouTubePlaybackSource> _extractHlsSources(
    _YouTubePlayerResponseCandidate candidate,
  ) {
    final manifestUrl =
        _asMap(candidate.playerResponse['streamingData'])['hlsManifestUrl']
                ?.toString()
                .trim() ??
            '';
    if (manifestUrl.isEmpty) {
      return const [];
    }
    return [
      _YouTubePlaybackSource(
        strategy: 'hls',
        clientProfile: candidate.profile,
        lineLabel: '${candidate.profile.lineLabel} HLS',
        url: manifestUrl,
        headers: _buildPlaybackHeaders(
          clientProfile: candidate.profile,
          sourcePageUrl: candidate.sourcePageUrl,
        ),
      ),
    ];
  }

  List<_YouTubePlaybackSource> _extractDashSources(
    _YouTubePlayerResponseCandidate candidate,
  ) {
    final manifestUrl =
        _asMap(candidate.playerResponse['streamingData'])['dashManifestUrl']
                ?.toString()
                .trim() ??
            '';
    if (manifestUrl.isEmpty) {
      return const [];
    }
    return [
      _YouTubePlaybackSource(
        strategy: 'dash',
        clientProfile: candidate.profile,
        lineLabel: '${candidate.profile.lineLabel} DASH',
        url: manifestUrl,
        headers: _buildPlaybackHeaders(
          clientProfile: candidate.profile,
          sourcePageUrl: candidate.sourcePageUrl,
        ),
      ),
    ];
  }

  List<_YouTubePlaybackSource> _extractDirectSources(
    _YouTubePlayerResponseCandidate candidate,
  ) {
    final streamingData = _asMap(candidate.playerResponse['streamingData']);
    final selectedByQuality = <String, Map<String, dynamic>>{};
    for (final item in _asList(streamingData['formats'])) {
      final format = _asMap(item);
      final url = format['url']?.toString().trim() ?? '';
      final mimeType = format['mimeType']?.toString().trim() ?? '';
      if (url.isEmpty || mimeType.isEmpty || !mimeType.startsWith('video/')) {
        continue;
      }
      final qualityId = _formatQualityId(format);
      final existing = selectedByQuality[qualityId];
      if (existing == null ||
          _directFormatScore(format) > _directFormatScore(existing)) {
        selectedByQuality[qualityId] = format;
      }
    }
    final sources = selectedByQuality.values
        .map(
          (format) => _YouTubePlaybackSource(
            strategy: 'direct',
            clientProfile: candidate.profile,
            lineLabel: '${candidate.profile.lineLabel} Direct',
            url: format['url']!.toString(),
            headers: _buildPlaybackHeaders(
              clientProfile: candidate.profile,
              sourcePageUrl: candidate.sourcePageUrl,
            ),
            qualityId: _formatQualityId(format),
            qualityLabel: _formatQualityLabel(format),
            sortOrder: _formatSortOrder(format),
            mimeType: format['mimeType']?.toString(),
          ),
        )
        .toList(growable: false);
    sources.sort((left, right) => right.sortOrder.compareTo(left.sortOrder));
    return sources;
  }

  List<_YouTubePlaybackAudioSource> _extractAudioSources(
    _YouTubePlayerResponseCandidate candidate,
  ) {
    final streamingData = _asMap(candidate.playerResponse['streamingData']);
    _YouTubePlaybackAudioSource? best;
    var audioFormatCount = 0;
    var directUrlCount = 0;
    var cipherCount = 0;
    for (final item in _asList(streamingData['adaptiveFormats'])) {
      final format = _asMap(item);
      final mimeType = format['mimeType']?.toString().trim() ?? '';
      if (mimeType.isEmpty || !mimeType.startsWith('audio/')) {
        continue;
      }
      audioFormatCount += 1;
      final url = format['url']?.toString().trim() ?? '';
      if (url.isEmpty) {
        final cipher = format['signatureCipher']?.toString().trim() ??
            format['cipher']?.toString().trim() ??
            '';
        if (cipher.isNotEmpty) {
          cipherCount += 1;
        }
        continue;
      }
      directUrlCount += 1;
      final candidateSource = _YouTubePlaybackAudioSource(
        clientProfile: candidate.profile,
        lineLabel: '${candidate.profile.lineLabel} Audio',
        url: url,
        headers: _buildPlaybackHeaders(
          clientProfile: candidate.profile,
          sourcePageUrl: candidate.sourcePageUrl,
        ),
        bitrate:
            _asInt(format['bitrate']) ?? _asInt(format['averageBitrate']) ?? 0,
        mimeType: mimeType,
      );
      if (best == null || candidateSource.score > best.score) {
        best = candidateSource;
      }
    }
    if (best == null) {
      _debugLog(
        'audio sources profile=${candidate.profile.id} '
        'audioFormats=$audioFormatCount direct=$directUrlCount cipher=$cipherCount '
        'selected=-',
      );
      return const [];
    }
    _debugLog(
      'audio sources profile=${candidate.profile.id} '
      'audioFormats=$audioFormatCount direct=$directUrlCount cipher=$cipherCount '
      'selected=${Uri.tryParse(best.url)?.host ?? '-'}${Uri.tryParse(best.url)?.path ?? ''} '
      'bitrate=${best.bitrate}',
    );
    return [best];
  }

  Future<List<YouTubeHlsVariant>> _loadHlsVariants(
    _YouTubePlaybackSource source,
  ) async {
    final cached = _hlsVariantCache[source.url];
    if (cached != null) {
      return cached;
    }
    final playlistText = await _apiClient.fetchText(
      source.url,
      headers: source.headers,
    );
    final variants = _hlsMasterPlaylistParser.parse(
      playlistUrl: source.url,
      source: playlistText,
    );
    _hlsVariantCache[source.url] = variants;
    return variants;
  }

  Future<List<_YouTubePlaybackSource>> _selectUsableHlsSources(
    List<_YouTubePlaybackSource> sources,
  ) async {
    if (sources.isEmpty) {
      return const [];
    }
    final usable = await Future.wait(
      sources.map((source) async {
        return await _isHlsSourceUsable(source) ? source : null;
      }),
    );
    return usable.whereType<_YouTubePlaybackSource>().toList(growable: false);
  }

  Future<bool> _isHlsSourceUsable(_YouTubePlaybackSource source) async {
    final cached = _hlsUsabilityCache[source.url];
    if (cached != null) {
      return cached;
    }
    try {
      final variants = await _loadHlsVariants(source);
      if (variants.isEmpty) {
        _hlsUsabilityCache[source.url] = false;
        return false;
      }
      final mediaPlaylistUrl = variants.first.url;
      final mediaPlaylist = await _apiClient.fetchText(
        mediaPlaylistUrl,
        headers: source.headers,
      );
      final segmentUrl = _extractFirstHlsSegmentUrl(
        playlistUrl: mediaPlaylistUrl,
        source: mediaPlaylist,
      );
      if (segmentUrl.isEmpty) {
        _hlsUsabilityCache[source.url] = false;
        return false;
      }
      final status = await _apiClient.probeStatus(
        segmentUrl,
        headers: source.headers,
      );
      final usable = status >= 200 && status < 300;
      _hlsUsabilityCache[source.url] = usable;
      return usable;
    } catch (_) {
      _hlsUsabilityCache[source.url] = false;
      return false;
    }
  }

  String _extractFirstHlsSegmentUrl({
    required String playlistUrl,
    required String source,
  }) {
    final playlistUri = Uri.tryParse(playlistUrl);
    if (playlistUri == null) {
      return '';
    }
    for (final rawLine in const LineSplitter().convert(source)) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) {
        continue;
      }
      return playlistUri.resolve(line).toString();
    }
    return '';
  }

  Future<YouTubeHlsVariant?> _selectHlsVariantForQuality({
    required _YouTubePlaybackSource source,
    required LivePlayQuality quality,
  }) async {
    final variants = await _loadHlsVariants(source);
    if (variants.isEmpty) {
      return null;
    }
    final requestedRank = _parseQualityRank(
      quality.id,
      fallbackLabel: quality.label,
    );
    if (requestedRank == null) {
      return variants.first;
    }
    final exact = variants.firstWhere(
      (item) =>
          item.height?.toString() == quality.id ||
          item.label.trim().toLowerCase() == quality.label.trim().toLowerCase(),
      orElse: () => const YouTubeHlsVariant(
        url: '',
        bandwidth: 0,
        label: '',
      ),
    );
    if (exact.url.isNotEmpty) {
      return exact;
    }
    final sorted = [...variants]..sort((left, right) {
        final leftRank = left.height ?? left.bandwidth;
        final rightRank = right.height ?? right.bandwidth;
        final diff = (leftRank - requestedRank).abs().compareTo(
              (rightRank - requestedRank).abs(),
            );
        if (diff != 0) {
          return diff;
        }
        return right.sortOrder.compareTo(left.sortOrder);
      });
    return sorted.first;
  }

  List<LivePlayQuality> _buildDirectPlayQualities(
    List<_YouTubePlaybackSource> sources,
  ) {
    if (sources.isEmpty) {
      return const [];
    }
    final bestByQuality = <String, _YouTubePlaybackSource>{};
    for (final source in sources) {
      final qualityId = source.qualityId;
      if (qualityId == null || qualityId.isEmpty) {
        continue;
      }
      final existing = bestByQuality[qualityId];
      if (existing == null || source.sortOrder > existing.sortOrder) {
        bestByQuality[qualityId] = source;
      }
    }
    final ordered = bestByQuality.values.toList(growable: false)
      ..sort((left, right) => right.sortOrder.compareTo(left.sortOrder));
    if (ordered.isEmpty) {
      return const [];
    }
    return [
      for (var index = 0; index < ordered.length; index += 1)
        LivePlayQuality(
          id: ordered[index].qualityId!,
          label: ordered[index].qualityLabel ?? ordered[index].qualityId!,
          isDefault: index == 0,
          sortOrder: ordered[index].sortOrder,
          metadata: const {'playbackMode': 'direct'},
        ),
    ];
  }

  List<_YouTubePlaybackSource> _selectDirectSourcesForQuality({
    required List<_YouTubePlaybackSource> sources,
    required LivePlayQuality quality,
  }) {
    if (sources.isEmpty) {
      return const [];
    }
    final requestedRank = _parseQualityRank(
      quality.id,
      fallbackLabel: quality.label,
    );
    final grouped =
        <YouTubePlayerClientProfile, List<_YouTubePlaybackSource>>{};
    for (final source in sources) {
      grouped.putIfAbsent(source.clientProfile, () => []).add(source);
    }
    final selected = <_YouTubePlaybackSource>[];
    for (final group in grouped.values) {
      final ordered = [...group]
        ..sort((left, right) => right.sortOrder.compareTo(left.sortOrder));
      if (ordered.isEmpty) {
        continue;
      }
      if (quality.id == 'auto' || requestedRank == null) {
        selected.add(ordered.first);
        continue;
      }
      final exact = ordered.where((item) => item.qualityId == quality.id);
      if (exact.isNotEmpty) {
        selected.add(exact.first);
        continue;
      }
      final nearest = [...ordered]..sort((left, right) {
          final leftRank = left.sortOrder;
          final rightRank = right.sortOrder;
          final diff = (leftRank - requestedRank).abs().compareTo(
                (rightRank - requestedRank).abs(),
              );
          if (diff != 0) {
            return diff;
          }
          return right.sortOrder.compareTo(left.sortOrder);
        });
      selected.add(nearest.first);
    }
    selected.sort((left, right) {
      final profileCompare =
          _playbackProfiles.indexOf(left.clientProfile).compareTo(
                _playbackProfiles.indexOf(right.clientProfile),
              );
      if (profileCompare != 0) {
        return profileCompare;
      }
      return right.sortOrder.compareTo(left.sortOrder);
    });
    return selected;
  }

  void _appendUniqueSources(
    List<_YouTubePlaybackSource> target,
    List<_YouTubePlaybackSource> candidates,
    Set<String> seenSourceKeys,
  ) {
    for (final source in candidates) {
      final key = '${source.strategy}|${source.clientProfile.id}|${source.url}|'
          '${source.qualityId ?? ''}';
      if (!seenSourceKeys.add(key)) {
        continue;
      }
      target.add(source);
    }
  }

  void _appendUniqueAudioSources(
    List<_YouTubePlaybackAudioSource> target,
    List<_YouTubePlaybackAudioSource> candidates,
    Set<String> seenAudioSourceKeys,
  ) {
    for (final source in candidates) {
      final key = '${source.clientProfile.id}|${source.url}';
      if (!seenAudioSourceKeys.add(key)) {
        continue;
      }
      target.add(source);
    }
  }

  void _appendPlayUrl(
    List<LivePlayUrl> target, {
    required Set<String> seen,
    required LivePlayUrl candidate,
  }) {
    final key =
        '${candidate.url}|${candidate.lineLabel ?? ''}|${candidate.metadata?['strategy'] ?? ''}';
    if (!seen.add(key)) {
      return;
    }
    target.add(candidate);
  }

  List<_YouTubePlaybackSource> _readPlaybackSources(LiveRoomDetail detail) {
    final raw = detail.metadata?[_playbackSourcesMetadataKey];
    if (raw is! List) {
      return const [];
    }
    return raw
        .map(_asMap)
        .where((item) => item.isNotEmpty)
        .map(_YouTubePlaybackSource.fromMetadata)
        .toList(growable: false);
  }

  List<_YouTubePlaybackAudioSource> _readPlaybackAudioSources(
    LiveRoomDetail detail,
  ) {
    final raw = detail.metadata?[_playbackAudioSourcesMetadataKey];
    if (raw is! List) {
      return const [];
    }
    return raw
        .map(_asMap)
        .where((item) => item.isNotEmpty)
        .map(_YouTubePlaybackAudioSource.fromMetadata)
        .toList(growable: false);
  }

  YouTubePlayerClientProfile _readPlayerClientProfile(LiveRoomDetail detail) {
    final raw =
        detail.metadata?['playerClientProfile']?.toString().trim() ?? '';
    for (final profile in YouTubePlayerClientProfile.values) {
      if (profile.id == raw) {
        return profile;
      }
    }
    return YouTubePlayerClientProfile.web;
  }

  int _directFormatScore(Map<String, dynamic> format) {
    final mimeType = format['mimeType']?.toString().toLowerCase() ?? '';
    final audioBonus =
        (format['audioQuality']?.toString().trim().isNotEmpty ?? false)
            ? 10
            : 0;
    final mimeBonus = mimeType.contains('mp4') ? 20 : 0;
    return _formatSortOrder(format) + audioBonus + mimeBonus;
  }

  Future<Map<String, Object?>> _buildHlsAutoAudioMetadata({
    required _YouTubePlaybackSource source,
    required List<_YouTubePlaybackAudioSource> audioSources,
  }) async {
    final variants = await _loadHlsVariants(source);
    final hasMasterAudioRendition = variants.any(
      (item) => item.audioUrl?.isNotEmpty == true,
    );
    if (hasMasterAudioRendition) {
      _debugLog(
        'hls auto audio profile=${source.clientProfile.id} '
        'line=${source.lineLabel} '
        'selected=master-audio-rendition',
      );
      return const {};
    }
    return _fallbackExternalAudioMetadataForHls(
      source: source,
      audioSources: audioSources,
    );
  }

  Map<String, Object?> _buildHlsVariantAudioMetadata({
    required _YouTubePlaybackSource source,
    required YouTubeHlsVariant variant,
  }) {
    final audioUrl = variant.audioUrl?.trim() ?? '';
    if (audioUrl.isNotEmpty) {
      _debugLog(
        'hls variant audio profile=${source.clientProfile.id} '
        'line=${source.lineLabel} '
        'group=${variant.audioGroupId ?? '-'} '
        'selected=${Uri.tryParse(audioUrl)?.host ?? '-'}${Uri.tryParse(audioUrl)?.path ?? ''}',
      );
      return {
        'audioUrl': audioUrl,
        'audioHeaders': source.headers,
        'audioLineLabel': '${source.lineLabel} Audio',
        'audioClientProfile': source.clientProfile.id,
        'audioSource': 'hls-rendition',
        'audioGroupId': variant.audioGroupId,
        'audioMimeType': 'application/x-mpegURL',
      };
    }
    return const {};
  }

  Map<String, Object?> _buildResolvedHlsVariantAudioMetadata({
    required _YouTubePlaybackSource source,
    required YouTubeHlsVariant variant,
    required List<_YouTubePlaybackAudioSource> audioSources,
  }) {
    final hlsAudioMetadata = _buildHlsVariantAudioMetadata(
      source: source,
      variant: variant,
    );
    if (hlsAudioMetadata.isNotEmpty) {
      return hlsAudioMetadata;
    }
    return _fallbackExternalAudioMetadataForHls(
      source: source,
      audioSources: audioSources,
    );
  }

  Map<String, Object?> _fallbackExternalAudioMetadataForHls({
    required _YouTubePlaybackSource source,
    required List<_YouTubePlaybackAudioSource> audioSources,
  }) {
    final audioSource =
        audioSources.cast<_YouTubePlaybackAudioSource?>().firstWhere(
              (item) => item?.clientProfile == source.clientProfile,
              orElse: () => null,
            );
    if (audioSource == null) {
      _debugLog(
        'hls fallback audio profile=${source.clientProfile.id} '
        'line=${source.lineLabel} selected=-',
      );
      return const {};
    }
    _debugLog(
      'hls fallback audio profile=${source.clientProfile.id} '
      'line=${source.lineLabel} '
      'selected=${Uri.tryParse(audioSource.url)?.host ?? '-'}${Uri.tryParse(audioSource.url)?.path ?? ''}',
    );
    return audioSource.toPlaybackMetadata();
  }

  String _formatQualityId(Map<String, dynamic> format) {
    final qualityLabel = format['qualityLabel']?.toString().trim() ?? '';
    final fromLabel = _parseQualityRank(qualityLabel);
    if (fromLabel != null) {
      return fromLabel.toString();
    }
    final height = _asInt(format['height']);
    if (height != null && height > 0) {
      return height.toString();
    }
    final bitrate =
        _asInt(format['bitrate']) ?? _asInt(format['averageBitrate']);
    if (bitrate != null && bitrate > 0) {
      return bitrate.toString();
    }
    return 'auto';
  }

  String _formatQualityLabel(Map<String, dynamic> format) {
    final qualityLabel = format['qualityLabel']?.toString().trim() ?? '';
    if (qualityLabel.isNotEmpty) {
      return qualityLabel;
    }
    final height = _asInt(format['height']);
    if (height != null && height > 0) {
      return '${height}p';
    }
    return 'Direct';
  }

  int _formatSortOrder(Map<String, dynamic> format) {
    return _asInt(format['height']) ??
        _asInt(format['bitrate']) ??
        _asInt(format['averageBitrate']) ??
        0;
  }

  int? _parseQualityRank(String raw, {String? fallbackLabel}) {
    final normalized =
        raw.trim().isEmpty ? (fallbackLabel ?? '').trim() : raw.trim();
    if (normalized.isEmpty) {
      return null;
    }
    final heightMatch =
        RegExp(r'(\d{3,4})p', caseSensitive: false).firstMatch(normalized);
    if (heightMatch != null) {
      return int.tryParse(heightMatch.group(1)!);
    }
    return int.tryParse(normalized);
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

  List<dynamic> _asList(Object? value) {
    if (value is List) {
      return value;
    }
    return const [];
  }

  void _debugLog(String message) {
    assert(() {
      print('[YouTubeLiveDataSource] $message');
      return true;
    }());
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
    } catch (_) {
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

  Map<String, dynamic> _asMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.cast<String, dynamic>();
    }
    return const {};
  }
}

class _YouTubePlaybackBundle {
  const _YouTubePlaybackBundle({
    required this.detailPlayerResponse,
    required this.playerClientContext,
    required this.playbackAudioSources,
    required this.playbackSources,
    required this.primarySource,
  });

  final Map<String, dynamic> detailPlayerResponse;
  final Map<String, dynamic> playerClientContext;
  final List<_YouTubePlaybackAudioSource> playbackAudioSources;
  final List<_YouTubePlaybackSource> playbackSources;
  final _YouTubePlaybackSource? primarySource;
}

class _YouTubePlayerResponseCandidate {
  const _YouTubePlayerResponseCandidate({
    required this.profile,
    required this.sourcePageUrl,
    required this.playerResponse,
    required this.requestClientContext,
  });

  final YouTubePlayerClientProfile profile;
  final String sourcePageUrl;
  final Map<String, dynamic> playerResponse;
  final Map<String, dynamic> requestClientContext;
}

class _YouTubePlaybackAudioSource {
  const _YouTubePlaybackAudioSource({
    required this.clientProfile,
    required this.lineLabel,
    required this.url,
    required this.headers,
    required this.bitrate,
    this.mimeType,
  });

  final YouTubePlayerClientProfile clientProfile;
  final String lineLabel;
  final String url;
  final Map<String, String> headers;
  final int bitrate;
  final String? mimeType;

  int get score {
    final mimeBonus =
        (mimeType?.toLowerCase().contains('mp4') ?? false) ? 1000 : 0;
    return bitrate + mimeBonus;
  }

  Map<String, Object?> toMetadata() {
    return {
      'clientProfile': clientProfile.id,
      'lineLabel': lineLabel,
      'url': url,
      'headers': headers,
      if (bitrate > 0) 'bitrate': bitrate,
      if (mimeType != null) 'mimeType': mimeType,
    };
  }

  Map<String, Object?> toPlaybackMetadata() {
    return {
      'audioUrl': url,
      'audioHeaders': headers,
      'audioLineLabel': lineLabel,
      'audioClientProfile': clientProfile.id,
      if (bitrate > 0) 'audioBitrate': bitrate,
      if (mimeType != null) 'audioMimeType': mimeType,
    };
  }

  static _YouTubePlaybackAudioSource fromMetadata(Map<String, dynamic> raw) {
    final clientId = raw['clientProfile']?.toString().trim() ?? '';
    final clientProfile = YouTubePlayerClientProfile.values.firstWhere(
      (item) => item.id == clientId,
      orElse: () => YouTubePlayerClientProfile.web,
    );
    final headers = <String, String>{};
    final rawHeaders = raw['headers'];
    if (rawHeaders is Map) {
      for (final entry in rawHeaders.entries) {
        final key = entry.key.toString().trim();
        final value = entry.value?.toString().trim() ?? '';
        if (key.isEmpty || value.isEmpty) {
          continue;
        }
        headers[key] = value;
      }
    }
    return _YouTubePlaybackAudioSource(
      clientProfile: clientProfile,
      lineLabel: raw['lineLabel']?.toString().trim() ?? clientProfile.lineLabel,
      url: raw['url']?.toString().trim() ?? '',
      headers: headers,
      bitrate: int.tryParse(raw['bitrate']?.toString() ?? '') ?? 0,
      mimeType: raw['mimeType']?.toString().trim(),
    );
  }
}

class _YouTubePlaybackSource {
  const _YouTubePlaybackSource({
    required this.strategy,
    required this.clientProfile,
    required this.lineLabel,
    required this.url,
    required this.headers,
    this.qualityId,
    this.qualityLabel,
    this.sortOrder = 0,
    this.mimeType,
  });

  final String strategy;
  final YouTubePlayerClientProfile clientProfile;
  final String lineLabel;
  final String url;
  final Map<String, String> headers;
  final String? qualityId;
  final String? qualityLabel;
  final int sortOrder;
  final String? mimeType;

  bool get isHls => strategy == 'hls';
  bool get isDirect => strategy == 'direct';
  bool get isDash => strategy == 'dash';

  Map<String, Object?> toMetadata() {
    return {
      'strategy': strategy,
      'clientProfile': clientProfile.id,
      'lineLabel': lineLabel,
      'url': url,
      'headers': headers,
      if (qualityId != null) 'qualityId': qualityId,
      if (qualityLabel != null) 'qualityLabel': qualityLabel,
      if (sortOrder > 0) 'sortOrder': sortOrder,
      if (mimeType != null) 'mimeType': mimeType,
    };
  }

  static _YouTubePlaybackSource fromMetadata(Map<String, dynamic> raw) {
    final clientId = raw['clientProfile']?.toString().trim() ?? '';
    final clientProfile = YouTubePlayerClientProfile.values.firstWhere(
      (item) => item.id == clientId,
      orElse: () => YouTubePlayerClientProfile.web,
    );
    final headers = <String, String>{};
    final rawHeaders = raw['headers'];
    if (rawHeaders is Map) {
      for (final entry in rawHeaders.entries) {
        final key = entry.key.toString().trim();
        final value = entry.value?.toString().trim() ?? '';
        if (key.isEmpty || value.isEmpty) {
          continue;
        }
        headers[key] = value;
      }
    }
    return _YouTubePlaybackSource(
      strategy: raw['strategy']?.toString().trim() ?? '',
      clientProfile: clientProfile,
      lineLabel: raw['lineLabel']?.toString().trim() ?? clientProfile.lineLabel,
      url: raw['url']?.toString().trim() ?? '',
      headers: headers,
      qualityId: raw['qualityId']?.toString().trim(),
      qualityLabel: raw['qualityLabel']?.toString().trim(),
      sortOrder: int.tryParse(raw['sortOrder']?.toString() ?? '') ?? 0,
      mimeType: raw['mimeType']?.toString().trim(),
    );
  }
}

class _YouTubeLiveCategoryDefinition {
  const _YouTubeLiveCategoryDefinition({
    required this.id,
    required this.groupId,
    required this.groupName,
    required this.name,
    required this.queries,
  });

  final String id;
  final String groupId;
  final String groupName;
  final String name;
  final List<String> queries;
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
