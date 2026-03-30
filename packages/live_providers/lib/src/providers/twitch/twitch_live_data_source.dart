import 'dart:async';
import 'dart:math';

import 'package:live_core/live_core.dart';

import 'twitch_api_client.dart';
import 'twitch_data_source.dart';
import 'twitch_hls_master_playlist_parser.dart';
import 'twitch_mapper.dart';
import 'twitch_playback_bootstrap.dart';
import 'twitch_playback_manifest.dart';

class TwitchLiveDataSource implements TwitchDataSource {
  TwitchLiveDataSource({
    required TwitchApiClient apiClient,
    TwitchHlsMasterPlaylistParser hlsMasterPlaylistParser =
        const TwitchHlsMasterPlaylistParser(),
    String clientIntegrity = '',
    TwitchPlaybackBootstrapResolver? playbackBootstrapResolver,
    Duration requestTimeout = const Duration(seconds: 12),
    Duration alternateSurfaceTimeout = const Duration(seconds: 4),
    Duration bootstrapResolverTimeout = const Duration(seconds: 6),
    Duration bootstrapResolverGraceTimeout = const Duration(milliseconds: 1500),
    String supportedCodecs = 'h264',
  })  : _apiClient = apiClient,
        _hlsMasterPlaylistParser = hlsMasterPlaylistParser,
        _clientIntegrity = clientIntegrity.trim(),
        _playbackBootstrapResolver = playbackBootstrapResolver,
        _requestTimeout = requestTimeout,
        _alternateSurfaceTimeout = alternateSurfaceTimeout,
        _bootstrapResolverTimeout = bootstrapResolverTimeout,
        _bootstrapResolverGraceTimeout = bootstrapResolverGraceTimeout,
        _supportedCodecs =
            supportedCodecs.trim().isEmpty ? 'h264' : supportedCodecs.trim();

  static const String _sideNavOperationHash =
      '3d96d9a885e7761ccd4bab5d19f66eb6e1a0005cb94700afa8309676ca3052a5';
  static const String _browsePopularOperationHash =
      'fb60a7f9b2fe8f9c9a080f41585bd4564bea9d3030f4d7cb8ab7f9e99b1cee67';
  static const String _browseAllDirectoriesOperationHash =
      '2f67f71ba89f3c0ed26a141ec00da1defecb2303595f5cda4298169549783d9e';
  static const String _directoryPageGameOperationHash =
      '76cb069d835b8a02914c08dc42c421d0dafda8af5b113a3f19141824b901402f';
  static const String _searchOperationHash =
      'a7c600111acc4d1b294eafa364600556227939e2ff88505faa73035b57a83b22';
  static const String _channelShellHash =
      'fea4573a7bf2644f5b3f2cbbdcbee0d17312e48d2e55f080589d053aad353f11';
  static const String _streamMetadataHash =
      'ad022ca32220d5523d03a23cbcb5beaa1e0999889c1f8f78f9f2520dafb5cae6';
  static const String _useViewCountHash =
      'e28de6b91c2ac736882f4960e7de60ca4a4eeebc06affdc45d6408b19318cef7';
  static const String _useLiveBroadcastHash =
      '0b47cc6d8c182acd2e78b81c8ba5414a5a38057f2089b1bbcfa6046aae248bd2';
  static const String _playbackAccessTokenQuery =
      'query PlaybackAccessToken_Template('
      r'$login: String!, $isLive: Boolean!, $vodID: ID!, $isVod: Boolean!, '
      r'$playerType: String!, $platform: String!) {'
      '  streamPlaybackAccessToken('
      'channelName: \$login, '
      'params: {platform: \$platform, playerBackend: "mediaplayer", '
      'playerType: \$playerType}'
      '  ) @include(if: \$isLive) {'
      '    value'
      '    signature'
      '    authorization { isForbidden forbiddenReasonCode }'
      '    __typename'
      '  }'
      '  videoPlaybackAccessToken('
      'id: \$vodID, '
      'params: {platform: \$platform, playerBackend: "mediaplayer", '
      'playerType: \$playerType}'
      '  ) @include(if: \$isVod) {'
      '    value'
      '    signature'
      '    __typename'
      '  }'
      '}';
  static const String _defaultAcmb =
      'eyJBcHBWZXJzaW9uIjoiNTZiZDRjMDAtNTk1Ny00ODc3LThlNzQtNGQxOTM0NDZi'
      'MjBiIiwiQ2xpZW50QXBwIjoid2ViIn0=';
  static const int _directoryCategoryImageWidth = 144;
  static const int _directoryCategoryImageHeight = 192;
  static const int _browsePageSize = 30;
  static const int _categoryPageSize = 30;
  static const int _maxDirectoryCategoryLimit = 100;
  static const int _maxCategoryRoomLimit = 100;
  static const int _maxCategoryRoomWindows =
      (_maxCategoryRoomLimit + _categoryPageSize - 1) ~/ _categoryPageSize;
  static const List<_TwitchPlayerSurface> _playerSurfaces = [
    _TwitchPlayerSurface(
      playerType: 'embed',
      platform: 'web',
      priority: 2,
      lineLabel: '备用 Embed',
    ),
    _TwitchPlayerSurface(
      playerType: 'site',
      platform: 'web',
      priority: 1,
      lineLabel: '备用 Site',
    ),
    _TwitchPlayerSurface(
      playerType: 'popout',
      platform: 'web',
      priority: 0,
      lineLabel: '默认 Popout',
    ),
    _TwitchPlayerSurface(
      playerType: 'autoplay',
      platform: 'android',
      priority: 3,
      lineLabel: '备用 Autoplay',
    ),
  ];

  final TwitchApiClient _apiClient;
  final TwitchHlsMasterPlaylistParser _hlsMasterPlaylistParser;
  final String _clientIntegrity;
  final TwitchPlaybackBootstrapResolver? _playbackBootstrapResolver;
  final Duration _requestTimeout;
  final Duration _alternateSurfaceTimeout;
  final Duration _bootstrapResolverTimeout;
  final Duration _bootstrapResolverGraceTimeout;
  final String _supportedCodecs;
  Future<List<LiveSubCategory>>? _topDirectoryCategoriesFuture;

  @override
  Future<List<LiveCategory>> fetchCategories() async {
    final children = await _loadTopDirectoryCategories();
    if (children.isEmpty) {
      return const [];
    }
    return [
      LiveCategory(
        id: 'popular',
        name: '热门分类',
        children: children
            .map(
              (item) => LiveSubCategory(
                id: item.id,
                parentId: 'popular',
                name: item.name,
                pic: item.pic,
              ),
            )
            .toList(growable: false),
      ),
    ];
  }

  @override
  Future<PagedResponse<LiveRoom>> fetchCategoryRooms(
    LiveSubCategory category, {
    int page = 1,
  }) async {
    if (page <= 0) {
      return const PagedResponse(items: [], hasMore: false, page: 1);
    }
    if (page > _maxCategoryRoomWindows) {
      return PagedResponse(items: const [], hasMore: false, page: page);
    }
    final window = await _fetchDirectoryCategoryWindow(
      category: category,
      page: page,
    );
    return PagedResponse(
      items: window.items,
      hasMore: window.hasMore,
      page: window.page,
    );
  }

  @override
  Future<PagedResponse<LiveRoom>> fetchRecommendRooms({int page = 1}) async {
    if (page <= 0) {
      return const PagedResponse(items: [], hasMore: false, page: 1);
    }
    if (page > 1) {
      return _fetchRecommendRoomsFromDirectoryWindows(page: page);
    }
    final rooms = <String, LiveRoom>{};
    final browse = await _fetchBrowsePopularRooms(page: 1);
    for (final room in browse.items) {
      rooms.putIfAbsent(room.roomId, () => room);
    }
    final payload = await _requireMap(
      _withRequestTimeout(
        _apiClient.postGraphQl(_buildSideNavQuery()),
        context: 'side nav response',
      ),
      context: 'side nav response',
    );
    final sections = _asList(
      _asMap(_asMap(_asMap(payload['data'])['sideNav'])['sections'])['edges'],
    );
    for (final section in sections) {
      final contentEdges = _asList(
        _asMap(_asMap(_asMap(section)['node'])['content'])['edges'],
      );
      for (final edge in contentEdges) {
        final room = TwitchMapper.mapRecommendRoom(
          _asMap(_asMap(edge)['node']),
        );
        if (room.roomId.isEmpty) {
          continue;
        }
        rooms.putIfAbsent(room.roomId, () => room);
      }
    }
    return PagedResponse(
      items: rooms.values.toList(growable: false),
      hasMore: browse.hasMore,
      page: 1,
    );
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
    if (page != 1) {
      return PagedResponse(items: const [], hasMore: false, page: page);
    }
    final payload = await _requireMap(
      _withRequestTimeout(
        _apiClient.postGraphQl(_buildSearchQuery(normalizedQuery)),
        context: 'search response',
      ),
      context: 'search response',
    );
    final edges = _asList(
      _asMap(_asMap(_asMap(payload['data'])['searchFor'])['channels'])['edges'],
    );
    final items = edges
        .map((edge) => TwitchMapper.mapSearchRoom(_asMap(_asMap(edge)['item'])))
        .where((room) => room.roomId.isNotEmpty)
        .toList(growable: false);
    return PagedResponse(items: items, hasMore: false, page: page);
  }

  @override
  Future<LiveRoomDetail> fetchRoomDetail(String roomId) async {
    final normalizedRoomId = roomId.trim().toLowerCase();
    if (normalizedRoomId.isEmpty) {
      throw ProviderParseException(
        providerId: ProviderId.twitch,
        message: 'Twitch 房间号不能为空。',
      );
    }
    final payload = await _requireList(
      _withRequestTimeout(
        _apiClient.postGraphQl([
          _buildPersistedQuery(
            operationName: 'ChannelShell',
            sha256Hash: _channelShellHash,
            variables: {'login': normalizedRoomId},
          ),
          _buildPersistedQuery(
            operationName: 'StreamMetadata',
            sha256Hash: _streamMetadataHash,
            variables: {'channelLogin': normalizedRoomId},
          ),
          _buildPersistedQuery(
            operationName: 'UseViewCount',
            sha256Hash: _useViewCountHash,
            variables: {'channelLogin': normalizedRoomId},
          ),
          _buildPersistedQuery(
            operationName: 'UseLiveBroadcast',
            sha256Hash: _useLiveBroadcastHash,
            variables: {'channelLogin': normalizedRoomId},
          ),
        ]),
        context: 'detail batch response',
      ),
      context: 'detail batch response',
    );
    final channelShell = _findOperationResponse(payload, 'ChannelShell');
    final userOrError =
        _asMap(_asMap(_asMap(channelShell['data'])['userOrError']));
    if (userOrError.isEmpty ||
        (userOrError['__typename']?.toString() ?? 'User') != 'User') {
      throw ProviderParseException(
        providerId: ProviderId.twitch,
        message: 'Twitch 当前未找到频道 $normalizedRoomId。',
      );
    }
    return TwitchMapper.mapRoomDetail(
      login: normalizedRoomId,
      channelShell: channelShell,
      streamMetadata: _findOperationResponse(payload, 'StreamMetadata'),
      viewCount: _findOperationResponse(payload, 'UseViewCount'),
      liveBroadcast: _findOperationResponse(payload, 'UseLiveBroadcast'),
    );
  }

  @override
  Future<List<LivePlayQuality>> fetchPlayQualities(
    LiveRoomDetail detail,
  ) async {
    if (!detail.isLive) {
      return const [];
    }
    final roomId = detail.roomId.trim().toLowerCase();
    if (roomId.isEmpty) {
      throw ProviderParseException(
        providerId: ProviderId.twitch,
        message: 'Twitch 房间号不能为空。',
      );
    }

    final bootstrap = await _resolvePlaybackBootstrap(detail);
    if (bootstrap == null || !bootstrap.isUsable) {
      throw ProviderParseException(
        providerId: ProviderId.twitch,
        message: 'Twitch 当前未能获得可用播放 bootstrap。',
      );
    }
    final playbackSurfaces = await _loadPlaybackSurfaceCandidates(
      roomId: roomId,
      bootstrap: bootstrap,
    );
    if (playbackSurfaces.isEmpty) {
      throw ProviderParseException(
        providerId: ProviderId.twitch,
        message: 'Twitch 当前未能加载可用播放面。',
      );
    }
    final primarySurface = playbackSurfaces.firstWhere(
      (surface) => surface.variants.isNotEmpty,
      orElse: () => playbackSurfaces.first,
    );
    final groups = _mergeQualityGroups(playbackSurfaces);
    return TwitchMapper.mapPlayQualitiesFromVariants(
      variants: primarySurface.variants,
      masterPlaylistUrl: primarySurface.masterPlaylistUrl,
      headers: primarySurface.headers,
      masterCandidates: playbackSurfaces
          .map(
            (surface) => TwitchPlaybackCandidate(
              playlistUrl: surface.masterPlaylistUrl,
              headers: surface.headers,
              playerType: surface.playerType,
              platform: surface.platform,
              lineLabel: surface.lineLabel,
            ),
          )
          .toList(growable: false),
      candidateGroups: groups,
    );
  }

  Future<List<_TwitchPlaybackSurfaceCandidate>> _loadPlaybackSurfaceCandidates({
    required String roomId,
    required TwitchPlaybackBootstrap bootstrap,
  }) async {
    final preferredRoomId = bootstrap.roomId.trim().isNotEmpty
        ? bootstrap.roomId.trim().toLowerCase()
        : roomId;
    final preferredHeaders = _buildPlaybackHeaders(
      roomId: preferredRoomId,
      sourceUrl: bootstrap.sourceUrl,
      cookie: bootstrap.cookie,
      userAgent: bootstrap.userAgent,
    );
    final preferredSessionId = bootstrap.clientSessionId.trim().isNotEmpty
        ? bootstrap.clientSessionId.trim()
        : _randomHex(32);
    final preferredMasterPlaylistUrl =
        bootstrap.masterPlaylistUrl.trim().isNotEmpty
            ? bootstrap.masterPlaylistUrl.trim()
            : _buildHlsPlaylistUrl(
                roomId: preferredRoomId,
                sessionId: preferredSessionId,
                signature: bootstrap.signature,
                tokenValue: bootstrap.tokenValue,
                platform: 'web',
              );
    final futures = <Future<_TwitchPlaybackSurfaceCandidate?>>[
      _loadPlaybackSurfaceCandidate(
        roomId: preferredRoomId,
        surface: _playerSurfaces[0],
        contextBootstrap: bootstrap,
      ).timeout(_alternateSurfaceTimeout, onTimeout: () => null),
      _loadPlaybackSurfaceCandidate(
        roomId: preferredRoomId,
        surface: _playerSurfaces[1],
        contextBootstrap: bootstrap,
      ).timeout(_alternateSurfaceTimeout, onTimeout: () => null),
      _loadPlaybackSurfaceCandidate(
        roomId: preferredRoomId,
        surface: _playerSurfaces[3],
        contextBootstrap: bootstrap,
      ).timeout(_alternateSurfaceTimeout, onTimeout: () => null),
    ];
    final preferredVariants = _hlsMasterPlaylistParser.parse(
      playlistUrl: preferredMasterPlaylistUrl,
      source: await _withRequestTimeout(
        _apiClient.fetchText(
          preferredMasterPlaylistUrl,
          headers: preferredHeaders,
        ),
        context: 'preferred playback playlist',
      ),
    );
    final candidates = <_TwitchPlaybackSurfaceCandidate>[
      if (preferredVariants.isNotEmpty)
        _TwitchPlaybackSurfaceCandidate(
          playerType: 'popout',
          platform: 'web',
          lineLabel: _playerSurfaces[2].lineLabel,
          masterPlaylistUrl: preferredMasterPlaylistUrl,
          headers: preferredHeaders,
          variants: preferredVariants,
        ),
    ];
    final alternates = await Future.wait(futures);
    for (final item in alternates) {
      if (item == null || item.variants.isEmpty) {
        continue;
      }
      candidates.add(item);
    }
    candidates.sort((left, right) => left.priority.compareTo(right.priority));
    return candidates;
  }

  Future<_TwitchPlaybackSurfaceCandidate?> _loadPlaybackSurfaceCandidate({
    required String roomId,
    required _TwitchPlayerSurface surface,
    required TwitchPlaybackBootstrap contextBootstrap,
  }) async {
    try {
      final bootstrap = await _requestPlaybackBootstrap(
        roomId,
        playerType: surface.playerType,
        platform: surface.platform,
        contextBootstrap: contextBootstrap,
      );
      final resolvedRoomId = bootstrap.roomId.trim().isNotEmpty
          ? bootstrap.roomId.trim().toLowerCase()
          : roomId;
      final sessionId = bootstrap.clientSessionId.trim().isNotEmpty
          ? bootstrap.clientSessionId.trim()
          : _randomHex(32);
      final masterPlaylistUrl = _buildHlsPlaylistUrl(
        roomId: resolvedRoomId,
        sessionId: sessionId,
        signature: bootstrap.signature,
        tokenValue: bootstrap.tokenValue,
        platform: surface.platform,
      );
      final headers = _buildPlaybackHeaders(
        roomId: resolvedRoomId,
        sourceUrl: bootstrap.sourceUrl,
        cookie: bootstrap.cookie,
        userAgent: bootstrap.userAgent,
      );
      final playlistText = await _withRequestTimeout(
        _apiClient.fetchText(
          masterPlaylistUrl,
          headers: headers,
        ),
        context: '${surface.playerType} playback playlist',
      );
      return _TwitchPlaybackSurfaceCandidate(
        playerType: surface.playerType,
        platform: surface.platform,
        lineLabel: surface.lineLabel,
        masterPlaylistUrl: masterPlaylistUrl,
        headers: headers,
        variants: _hlsMasterPlaylistParser.parse(
          playlistUrl: masterPlaylistUrl,
          source: playlistText,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  List<TwitchPlaybackQualityGroup> _mergeQualityGroups(
    List<_TwitchPlaybackSurfaceCandidate> playbackSurfaces,
  ) {
    final groups = <String, _TwitchPlaybackGroupAccumulator>{};
    for (final surface in playbackSurfaces) {
      for (final variant in surface.variants) {
        final key = _groupKeyForVariant(variant);
        final group = groups.putIfAbsent(
          key,
          () => _TwitchPlaybackGroupAccumulator(
            id: key,
            label: variant.label,
            sortOrder: variant.sortOrder,
            bandwidth: variant.bandwidth,
            width: variant.width,
            height: variant.height,
            frameRate: variant.frameRate,
            codecs: variant.codecs,
          ),
        );
        final candidate = TwitchPlaybackCandidate(
          playlistUrl: variant.url,
          headers: surface.headers,
          playerType: surface.playerType,
          platform: surface.platform,
          lineLabel: surface.lineLabel,
          source: variant.source,
          bandwidth: variant.bandwidth,
          width: variant.width,
          height: variant.height,
          frameRate: variant.frameRate,
          codecs: variant.codecs,
        );
        if (!group.candidates.any(
          (item) =>
              item.playlistUrl == candidate.playlistUrl &&
              item.playerType == candidate.playerType,
        )) {
          group.candidates.add(candidate);
        }
      }
    }
    final results = groups.values
        .map(
          (group) => TwitchPlaybackQualityGroup(
            id: group.id,
            label: group.label,
            sortOrder: group.sortOrder,
            bandwidth: group.bandwidth,
            width: group.width,
            height: group.height,
            frameRate: group.frameRate,
            codecs: group.codecs,
            candidates: group.candidates,
          ),
        )
        .toList(growable: false);
    results.sort((left, right) => right.sortOrder.compareTo(left.sortOrder));
    return results;
  }

  @override
  Future<List<LivePlayUrl>> fetchPlayUrls({
    required LiveRoomDetail detail,
    required LivePlayQuality quality,
  }) async {
    return TwitchMapper.mapPlayUrls(detail, quality);
  }

  Map<String, dynamic> _buildSideNavQuery() {
    return _buildPersistedQuery(
      operationName: 'SideNav',
      sha256Hash: _sideNavOperationHash,
      variables: {
        'input': {
          'recommendationContext': {
            'platform': 'web',
            'clientApp': 'twilight',
            'location': 'search_results',
            'referrerDomain': 'www.twitch.tv',
            'viewportHeight': 1609,
            'viewportWidth': 2291,
            'channelName': null,
            'categorySlug': null,
            'lastChannelName': null,
            'lastCategorySlug': null,
            'pageviewContent': null,
            'pageviewContentType': null,
            'pageviewLocation': 'search_results',
            'pageviewMedium': 'search',
            'previousPageviewContent': null,
            'previousPageviewContentType': null,
            'previousPageviewLocation': null,
            'previousPageviewMedium': null,
          },
        },
        'creatorAnniversariesFeature': false,
        'withFreeformTags': false,
      },
    );
  }

  Map<String, dynamic> _buildSearchQuery(String query) {
    return _buildPersistedQuery(
      operationName: 'SearchResultsPage_SearchResults',
      sha256Hash: _searchOperationHash,
      variables: {
        'platform': 'web',
        'query': query,
        'options': {
          'targets': null,
          'shouldSkipDiscoveryControl': false,
        },
        'requestID': _randomHex(32),
      },
    );
  }

  Map<String, dynamic> _buildBrowsePopularQuery({
    String? cursor,
    int limit = _browsePageSize,
  }) {
    return _buildPersistedQuery(
      operationName: 'BrowsePage_Popular',
      sha256Hash: _browsePopularOperationHash,
      variables: {
        'imageWidth': 50,
        'limit': limit,
        'platformType': 'all',
        if (cursor != null && cursor.trim().isNotEmpty) 'cursor': cursor.trim(),
        'options': {
          'sort': 'VIEWER_COUNT',
          'freeformTags': null,
          'tags': [],
          'recommendationsContext': {
            'platform': 'web',
          },
          'requestID': 'JIRA-VXP-2397',
          'broadcasterLanguages': [],
        },
        'sortTypeIsRecency': false,
        'includeCostreaming': true,
      },
    );
  }

  Map<String, dynamic> _buildBrowseAllDirectoriesQuery({
    String? cursor,
    int limit = _maxDirectoryCategoryLimit,
  }) {
    return _buildPersistedQuery(
      operationName: 'BrowsePage_AllDirectories',
      sha256Hash: _browseAllDirectoriesOperationHash,
      variables: {
        'limit': limit,
        'options': {
          'sort': 'VIEWER_COUNT',
          'recommendationsContext': {
            'platform': 'web',
          },
          'requestID': 'JIRA-VXP-2397',
          'tags': [],
        },
        if (cursor != null && cursor.trim().isNotEmpty) 'cursor': cursor.trim(),
      },
    );
  }

  Map<String, dynamic> _buildDirectoryPageGameQuery({
    required String slug,
    required int limit,
  }) {
    return _buildPersistedQuery(
      operationName: 'DirectoryPage_Game',
      sha256Hash: _directoryPageGameOperationHash,
      variables: {
        'imageWidth': 50,
        'slug': slug,
        'options': {
          'sort': 'VIEWER_COUNT',
          'requestID': 'JIRA-VXP-2397',
          'freeformTags': null,
          'tags': [],
          'recommendationsContext': {
            'platform': 'web',
          },
          'broadcasterLanguages': [],
          'systemFilters': [],
        },
        'sortTypeIsRecency': false,
        'limit': limit,
        'includeCostreaming': true,
      },
    );
  }

  String _readDirectoryCategorySlug(Map<String, dynamic> payload) {
    return payload['slug']?.toString().trim() ?? '';
  }

  String _readDirectoryCategoryName(Map<String, dynamic> payload) {
    return [
      normalizeDisplayText(payload['displayName']?.toString()),
      normalizeDisplayText(payload['name']?.toString()),
    ].firstWhere((item) => item.trim().isNotEmpty, orElse: () => '');
  }

  String? _readDirectoryCategoryPic(Map<String, dynamic> payload) {
    final raw = payload['avatarURL']?.toString().trim() ??
        payload['boxArtURL']?.toString().trim() ??
        payload['boxArtUrl']?.toString().trim() ??
        '';
    if (raw.isEmpty) {
      return null;
    }
    return raw
        .replaceAll('{width}', '$_directoryCategoryImageWidth')
        .replaceAll('{height}', '$_directoryCategoryImageHeight');
  }

  Future<PagedResponse<LiveRoom>> _fetchBrowsePopularRooms({
    required int page,
  }) async {
    if (page <= 0) {
      return const PagedResponse(items: [], hasMore: false, page: 1);
    }
    String? cursor;
    Map<String, dynamic> payload = const {};
    for (var currentPage = 1; currentPage <= page; currentPage += 1) {
      payload = await _requireMap(
        _withRequestTimeout(
          _apiClient.postGraphQl(
            _buildBrowsePopularQuery(cursor: cursor),
          ),
          context: 'browse popular response',
        ),
        context: 'browse popular response',
      );
      final edges = _asList(
        _asMap(_asMap(payload['data'])['streams'])['edges'],
      );
      if (currentPage == page) {
        final items = edges
            .map((edge) =>
                TwitchMapper.mapBrowseRoom(_asMap(_asMap(edge)['node'])))
            .where((room) => room.roomId.isNotEmpty)
            .toList(growable: false);
        return PagedResponse(
          items: items,
          hasMore: _asMap(_asMap(payload['data'])['streams'])['pageInfo']
                  ['hasNextPage'] ==
              true,
          page: page,
        );
      }
      if (_asMap(_asMap(payload['data'])['streams'])['pageInfo']
              ['hasNextPage'] !=
          true) {
        break;
      }
      cursor = edges.isEmpty ? null : _asMap(edges.last)['cursor']?.toString();
      if (cursor == null || cursor.isEmpty) {
        break;
      }
    }
    return PagedResponse(items: const [], hasMore: false, page: page);
  }

  Future<List<LiveSubCategory>> _loadTopDirectoryCategories() {
    final cached = _topDirectoryCategoriesFuture;
    if (cached != null) {
      return cached;
    }
    final future = _fetchTopDirectoryCategories();
    _topDirectoryCategoriesFuture = future;
    return future;
  }

  Future<List<LiveSubCategory>> _fetchTopDirectoryCategories() async {
    final children = <LiveSubCategory>[];
    final seen = <String>{};
    final payload = await _requireMap(
      _withRequestTimeout(
        _apiClient.postGraphQl(
          _buildBrowseAllDirectoriesQuery(
            limit: _maxDirectoryCategoryLimit,
          ),
        ),
        context: 'browse directories response',
      ),
      context: 'browse directories response',
    );
    final directories = _asMap(_asMap(payload['data'])['directoriesWithTags']);
    final edges = _asList(directories['edges']);
    for (final edge in edges) {
      final node = _asMap(_asMap(edge)['node']);
      final slug = _readDirectoryCategorySlug(node);
      final name = _readDirectoryCategoryName(node);
      if (slug.isEmpty || name.isEmpty || !seen.add(slug)) {
        continue;
      }
      children.add(
        LiveSubCategory(
          id: slug,
          parentId: 'popular',
          name: name,
          pic: _readDirectoryCategoryPic(node),
        ),
      );
    }
    return children;
  }

  Future<({List<LiveRoom> items, bool hasMore, int page})>
      _fetchDirectoryCategoryWindow({
    required LiveSubCategory category,
    required int page,
  }) async {
    final requestedLimit = (_categoryPageSize * page)
        .clamp(_categoryPageSize, _maxCategoryRoomLimit);
    final payload = await _requireMap(
      _withRequestTimeout(
        _apiClient.postGraphQl(
          _buildDirectoryPageGameQuery(
            slug: category.id,
            limit: requestedLimit,
          ),
        ),
        context: 'directory page game response',
      ),
      context: 'directory page game response',
    );
    final game = _asMap(_asMap(payload['data'])['game']);
    if (game.isEmpty) {
      return (items: const <LiveRoom>[], hasMore: false, page: page);
    }
    final streams = _asMap(game['streams']);
    final allItems = _asList(streams['edges'])
        .map((edge) => TwitchMapper.mapBrowseRoom(_asMap(_asMap(edge)['node'])))
        .where((room) => room.roomId.isNotEmpty)
        .toList(growable: false);
    final startIndex = (page - 1) * _categoryPageSize;
    if (startIndex >= allItems.length) {
      return (
        items: const <LiveRoom>[],
        hasMore: false,
        page: page,
      );
    }
    final endIndex = startIndex + _categoryPageSize;
    final pageItems = allItems
        .skip(startIndex)
        .take(_categoryPageSize)
        .toList(growable: false);
    final canGrowWindow = requestedLimit < _maxCategoryRoomLimit &&
        _asMap(streams['pageInfo'])['hasNextPage'] == true;
    return (
      items: pageItems,
      hasMore: endIndex < allItems.length || canGrowWindow,
      page: page,
    );
  }

  Future<PagedResponse<LiveRoom>> _fetchRecommendRoomsFromDirectoryWindows({
    required int page,
  }) async {
    final categories = await _loadTopDirectoryCategories();
    if (categories.isEmpty) {
      return PagedResponse(items: const [], hasMore: false, page: page);
    }
    var windowIndex = page - 2;
    final totalWindows = categories.length * _maxCategoryRoomWindows;
    while (windowIndex >= 0 && windowIndex < totalWindows) {
      final sliceIndex = windowIndex ~/ categories.length;
      final categoryIndex = windowIndex % categories.length;
      final window = await _fetchDirectoryCategoryWindow(
        category: categories[categoryIndex],
        page: sliceIndex + 1,
      );
      if (window.items.isNotEmpty) {
        final resolvedPage = windowIndex + 2;
        return PagedResponse(
          items: window.items,
          hasMore: windowIndex < totalWindows - 1,
          page: resolvedPage,
        );
      }
      windowIndex += 1;
    }
    return PagedResponse(items: const [], hasMore: false, page: page);
  }

  Map<String, dynamic> _buildPersistedQuery({
    required String operationName,
    required String sha256Hash,
    required Map<String, Object?> variables,
  }) {
    return {
      'operationName': operationName,
      'variables': variables,
      'extensions': {
        'persistedQuery': {
          'version': 1,
          'sha256Hash': sha256Hash,
        },
      },
    };
  }

  String _buildHlsPlaylistUrl({
    required String roomId,
    required String sessionId,
    required String signature,
    required String tokenValue,
    String platform = 'web',
  }) {
    return Uri.https(
      'usher.ttvnw.net',
      '/api/v2/channel/hls/$roomId.m3u8',
      {
        'acmb': _defaultAcmb,
        'allow_source': 'true',
        'browser_family': 'chrome',
        'browser_version': '146.0',
        'cdm': 'wv',
        'enable_score': 'true',
        'fast_bread': 'true',
        'include_unavailable': 'true',
        'lang': 'zh-cn',
        'multigroup_video': 'false',
        'os_name': 'Linux',
        'os_version': 'undefined',
        'p': '${Random().nextInt(900000) + 100000}',
        'platform': platform,
        'play_session_id': sessionId,
        'player_backend': 'mediaplayer',
        'player_version': '1.50.0-rc.4',
        'playlist_include_framerate': 'true',
        'reassignments_supported': 'true',
        'sig': signature,
        'supported_codecs': _supportedCodecs,
        'token': tokenValue,
        'transcode_mode': 'cbr_v1',
      },
    ).toString();
  }

  Map<String, String> _buildPlaybackHeaders({
    required String roomId,
    String? sourceUrl,
    String? cookie,
    String? userAgent,
  }) {
    final headers = <String, String>{
      'accept': 'application/x-mpegURL, application/vnd.apple.mpegurl, '
          'application/json, text/plain',
      'referer': sourceUrl?.trim().isNotEmpty == true
          ? sourceUrl!.trim()
          : 'https://www.twitch.tv/$roomId',
      'user-agent': userAgent?.trim().isNotEmpty == true
          ? userAgent!.trim()
          : TwitchApiClient.browserUserAgent,
    };
    final normalizedCookie = cookie?.trim() ?? '';
    if (normalizedCookie.isNotEmpty) {
      headers['cookie'] = normalizedCookie;
    }
    return headers;
  }

  Future<TwitchPlaybackBootstrap?> _resolvePlaybackBootstrap(
    LiveRoomDetail detail,
  ) async {
    final metadataBootstrap = _bootstrapFromMetadata(detail);
    if (metadataBootstrap?.isUsable == true) {
      return metadataBootstrap;
    }

    final directFuture = _resolveDirectPlaybackBootstrap(detail.roomId);

    final resolver = _playbackBootstrapResolver;
    if (resolver == null) {
      return await directFuture;
    }

    final resolverFuture = _resolvePlaybackBootstrapFromResolver(
      resolver,
      detail,
    );
    final firstResolved = await Future.any<
        ({String source, TwitchPlaybackBootstrap? bootstrap})>([
      directFuture.then(
        (bootstrap) => (
          source: 'direct',
          bootstrap: bootstrap,
        ),
      ),
      resolverFuture.then(
        (bootstrap) => (
          source: 'resolver',
          bootstrap: bootstrap,
        ),
      ),
    ]);
    if (firstResolved.source == 'resolver' &&
        firstResolved.bootstrap?.isUsable == true) {
      return firstResolved.bootstrap;
    }
    if (firstResolved.source == 'direct' &&
        firstResolved.bootstrap?.isUsable == true) {
      final resolverBootstrap = await resolverFuture.timeout(
        _bootstrapResolverGraceTimeout,
        onTimeout: () => null,
      );
      if (_shouldPreferResolverBootstrap(
        directBootstrap: firstResolved.bootstrap!,
        resolverBootstrap: resolverBootstrap,
      )) {
        return resolverBootstrap;
      }
      return firstResolved.bootstrap;
    }

    return firstResolved.source == 'direct'
        ? await resolverFuture
        : await directFuture;
  }

  bool _shouldPreferResolverBootstrap({
    required TwitchPlaybackBootstrap directBootstrap,
    required TwitchPlaybackBootstrap? resolverBootstrap,
  }) {
    if (resolverBootstrap?.isUsable != true) {
      return false;
    }
    return _bootstrapRichnessScore(resolverBootstrap!) >=
        _bootstrapRichnessScore(directBootstrap);
  }

  int _bootstrapRichnessScore(TwitchPlaybackBootstrap bootstrap) {
    var score = 0;
    if (bootstrap.clientIntegrity.trim().isNotEmpty) {
      score += 3;
    }
    if (bootstrap.cookie.trim().isNotEmpty) {
      score += 2;
    }
    if (bootstrap.masterPlaylistUrl.trim().isNotEmpty) {
      score += 2;
    }
    if (bootstrap.userAgent.trim().isNotEmpty) {
      score += 1;
    }
    if (bootstrap.sourceUrl.trim().isNotEmpty) {
      score += 1;
    }
    return score;
  }

  Future<TwitchPlaybackBootstrap?> _resolveDirectPlaybackBootstrap(
    String roomId,
  ) async {
    try {
      final bootstrap = await _requestPlaybackBootstrap(roomId);
      return bootstrap.isUsable ? bootstrap : null;
    } catch (_) {
      return null;
    }
  }

  Future<TwitchPlaybackBootstrap?> _resolvePlaybackBootstrapFromResolver(
    TwitchPlaybackBootstrapResolver resolver,
    LiveRoomDetail detail,
  ) async {
    try {
      final bootstrap = await resolver(detail).timeout(
        _bootstrapResolverTimeout,
      );
      return bootstrap?.isUsable == true ? bootstrap : null;
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<TwitchPlaybackBootstrap> _requestPlaybackBootstrap(
    String roomId, {
    String playerType = 'popout',
    String platform = 'web',
    TwitchPlaybackBootstrap? contextBootstrap,
  }) async {
    final normalizedRoomId = roomId.trim().toLowerCase();
    final deviceId = contextBootstrap?.deviceId.trim().isNotEmpty == true
        ? contextBootstrap!.deviceId.trim()
        : _randomHex(32);
    final sessionId =
        contextBootstrap?.clientSessionId.trim().isNotEmpty == true
            ? contextBootstrap!.clientSessionId.trim()
            : _randomHex(32);
    final sourceUrl = contextBootstrap?.sourceUrl.trim().isNotEmpty == true
        ? contextBootstrap!.sourceUrl.trim()
        : 'https://www.twitch.tv/$normalizedRoomId';
    final payload = await _requireMap(
      _withRequestTimeout(
        _apiClient.postGraphQl(
          {
            'operationName': 'PlaybackAccessToken_Template',
            'query': _playbackAccessTokenQuery,
            'variables': {
              'isLive': true,
              'login': normalizedRoomId,
              'isVod': false,
              'vodID': '',
              'playerType': playerType,
              'platform': platform,
            },
          },
          deviceId: deviceId,
          clientSessionId: sessionId,
          clientIntegrity:
              contextBootstrap?.clientIntegrity.trim().isNotEmpty == true
                  ? contextBootstrap!.clientIntegrity.trim()
                  : _clientIntegrity,
        ),
        context: 'playback access token response',
      ),
      context: 'playback access token response',
    );
    final token = _asMap(_asMap(payload['data'])['streamPlaybackAccessToken']);
    final authorization = _asMap(token['authorization']);
    if (authorization['isForbidden'] == true) {
      final reason = authorization['forbiddenReasonCode']?.toString().trim();
      throw ProviderParseException(
        providerId: ProviderId.twitch,
        message: reason?.isNotEmpty == true
            ? 'Twitch 拒绝返回播放 token：$reason'
            : 'Twitch 拒绝返回播放 token。',
      );
    }
    final signature = token['signature']?.toString().trim() ?? '';
    final tokenValue = token['value']?.toString().trim() ?? '';
    if (signature.isEmpty || tokenValue.isEmpty) {
      throw ProviderParseException(
        providerId: ProviderId.twitch,
        message: 'Twitch 当前未返回可用播放 token。',
      );
    }
    return TwitchPlaybackBootstrap(
      roomId: normalizedRoomId,
      signature: signature,
      tokenValue: tokenValue,
      deviceId: deviceId,
      clientSessionId: sessionId,
      clientIntegrity:
          contextBootstrap?.clientIntegrity.trim().isNotEmpty == true
              ? contextBootstrap!.clientIntegrity.trim()
              : _clientIntegrity,
      sourceUrl: sourceUrl,
      cookie: contextBootstrap?.cookie ?? '',
      userAgent: contextBootstrap?.userAgent ?? '',
    );
  }

  TwitchPlaybackBootstrap? _bootstrapFromMetadata(LiveRoomDetail detail) {
    final metadata = detail.metadata;
    if (metadata == null || metadata.isEmpty) {
      return null;
    }
    final roomId =
        metadata['playbackRoomId']?.toString().trim() ?? detail.roomId.trim();
    final signature =
        metadata['playbackAccessTokenSignature']?.toString().trim() ?? '';
    final tokenValue =
        metadata['playbackAccessTokenValue']?.toString().trim() ?? '';
    if (roomId.isEmpty || signature.isEmpty || tokenValue.isEmpty) {
      return null;
    }
    return TwitchPlaybackBootstrap(
      roomId: roomId,
      signature: signature,
      tokenValue: tokenValue,
      deviceId: metadata['playbackDeviceId']?.toString().trim() ?? '',
      clientSessionId:
          metadata['playbackClientSessionId']?.toString().trim() ?? '',
      clientIntegrity:
          metadata['playbackClientIntegrity']?.toString().trim() ?? '',
      sourceUrl: metadata['playbackSourceUrl']?.toString().trim() ??
          detail.sourceUrl?.trim() ??
          '',
      masterPlaylistUrl:
          metadata['playbackMasterPlaylistUrl']?.toString().trim() ?? '',
      cookie: metadata['playbackCookie']?.toString().trim() ?? '',
      userAgent: metadata['playbackUserAgent']?.toString().trim() ?? '',
    );
  }

  Future<Map<String, dynamic>> _requireMap(
    Future<Object?> future, {
    required String context,
  }) async {
    final resolved = await future;
    if (resolved is Map<String, dynamic>) {
      return resolved;
    }
    if (resolved is Map) {
      return resolved.cast<String, dynamic>();
    }
    throw ProviderParseException(
      providerId: ProviderId.twitch,
      message:
          'Unexpected Twitch $context payload type: ${resolved.runtimeType}.',
    );
  }

  Future<List<Map<String, dynamic>>> _requireList(
    Future<Object?> future, {
    required String context,
  }) async {
    final resolved = await future;
    if (resolved is! List) {
      throw ProviderParseException(
        providerId: ProviderId.twitch,
        message:
            'Unexpected Twitch $context payload type: ${resolved.runtimeType}.',
      );
    }
    return resolved
        .map((item) => _asMap(item))
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  Map<String, dynamic> _findOperationResponse(
    List<Map<String, dynamic>> payload,
    String operationName,
  ) {
    for (final item in payload) {
      final extensions = _asMap(item['extensions']);
      if (extensions['operationName']?.toString() == operationName) {
        return item;
      }
    }
    throw ProviderParseException(
      providerId: ProviderId.twitch,
      message: 'Twitch 当前缺少 $operationName 响应。',
    );
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

  List<dynamic> _asList(Object? value) {
    if (value is List) {
      return value;
    }
    return const [];
  }

  String _randomHex(int length) {
    final buffer = StringBuffer();
    final random = Random();
    while (buffer.length < length) {
      buffer.write(random.nextInt(16).toRadixString(16));
    }
    return buffer.toString().substring(0, length);
  }

  Future<T> _withRequestTimeout<T>(
    Future<T> future, {
    required String context,
  }) async {
    try {
      return await future.timeout(_requestTimeout);
    } on TimeoutException {
      throw ProviderParseException(
        providerId: ProviderId.twitch,
        message: 'Twitch $context 请求超时。',
      );
    }
  }
}

class _TwitchPlayerSurface {
  const _TwitchPlayerSurface({
    required this.playerType,
    required this.platform,
    required this.priority,
    required this.lineLabel,
  });

  final String playerType;
  final String platform;
  final int priority;
  final String lineLabel;
}

class _TwitchPlaybackSurfaceCandidate {
  const _TwitchPlaybackSurfaceCandidate({
    required this.playerType,
    required this.platform,
    required this.lineLabel,
    required this.masterPlaylistUrl,
    required this.headers,
    required this.variants,
  });

  final String playerType;
  final String platform;
  final String lineLabel;
  final String masterPlaylistUrl;
  final Map<String, String> headers;
  final List<TwitchHlsVariant> variants;

  int get priority {
    final surface = TwitchLiveDataSource._playerSurfaces.firstWhere(
      (item) => item.playerType == playerType && item.platform == platform,
      orElse: () => TwitchLiveDataSource._playerSurfaces[2],
    );
    return surface.priority;
  }
}

class _TwitchPlaybackGroupAccumulator {
  _TwitchPlaybackGroupAccumulator({
    required this.id,
    required this.label,
    required this.sortOrder,
    required this.bandwidth,
    required this.width,
    required this.height,
    required this.frameRate,
    required this.codecs,
  });

  final String id;
  final String label;
  final int sortOrder;
  final int bandwidth;
  final int? width;
  final int? height;
  final double? frameRate;
  final String? codecs;
  final List<TwitchPlaybackCandidate> candidates = <TwitchPlaybackCandidate>[];
}

String _groupKeyForVariant(TwitchHlsVariant variant) {
  final stableVariantId = variant.stableVariantId?.trim() ?? '';
  if (stableVariantId.isNotEmpty) {
    return stableVariantId;
  }
  final height = variant.height;
  if (height != null && height > 0) {
    final roundedFrameRate = variant.frameRate?.round() ?? 0;
    return roundedFrameRate > 0 ? '${height}p$roundedFrameRate' : '${height}p';
  }
  return variant.label.trim().isNotEmpty
      ? variant.label.trim()
      : variant.bandwidth.toString();
}
