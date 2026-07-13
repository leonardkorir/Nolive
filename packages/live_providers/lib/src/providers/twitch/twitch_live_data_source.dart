import 'dart:async';

import 'package:live_core/live_core.dart';

import '../provider_runtime_support.dart';

import '../provider_json.dart';
import 'twitch_api_client.dart';
import 'twitch_bootstrap_resolver.dart';
import 'twitch_data_source.dart';
import 'twitch_graphql_client.dart';
import 'twitch_hls_master_playlist_parser.dart';
import 'twitch_mapper.dart';
import 'twitch_playback_bootstrap.dart';
import 'twitch_playback_manifest.dart';
import 'twitch_playback_surface_manager.dart';

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
    ProviderBrowserProfile browserProfile =
        ProviderBrowserProfile.chromiumDesktop,
  }) : _clientIntegrity = clientIntegrity.trim() {
    _graphQlClient = TwitchGraphQlClient(
      apiClient: apiClient,
      requestTimeout: requestTimeout,
    );
    _bootstrapResolverImpl = TwitchPlaybackBootstrapResolverImpl(
      graphQlClient: _graphQlClient,
      customResolver: playbackBootstrapResolver,
      bootstrapResolverTimeout: bootstrapResolverTimeout,
      bootstrapResolverGraceTimeout: bootstrapResolverGraceTimeout,
      clientIntegrity: _clientIntegrity,
    );
    _playbackSurfaceManager = TwitchPlaybackSurfaceManager(
      apiClient: apiClient,
      graphQlClient: _graphQlClient,
      hlsMasterPlaylistParser: hlsMasterPlaylistParser,
      alternateSurfaceTimeout: alternateSurfaceTimeout,
      browserProfile: browserProfile,
      supportedCodecs: supportedCodecs.trim().isEmpty
          ? 'h264'
          : supportedCodecs.trim(),
      clientIntegrity: _clientIntegrity,
    );
  }

  static const int _directoryCategoryImageWidth = 144;
  static const int _directoryCategoryImageHeight = 192;
  static const int _browsePageSize = 30;
  static const int _categoryPageSize = 30;
  static const int _maxDirectoryCategoryLimit = 100;
  static const int _maxCategoryRoomLimit = 100;
  static const int _maxCategoryRoomWindows =
      (_maxCategoryRoomLimit + _categoryPageSize - 1) ~/ _categoryPageSize;

  final String _clientIntegrity;
  late final TwitchGraphQlClient _graphQlClient;
  late final TwitchPlaybackBootstrapResolverImpl _bootstrapResolverImpl;
  late final TwitchPlaybackSurfaceManager _playbackSurfaceManager;
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
    final payload = await _graphQlClient.fetchSideNav();
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
    final payload = await _graphQlClient.search(normalizedQuery);
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
    final payload = await _graphQlClient.fetchRoomDetailBatch(
      login: normalizedRoomId,
    );
    final channelShell = _graphQlClient.findOperationResponse(
      payload,
      'ChannelShell',
    );
    final userOrError = _asMap(
      _asMap(_asMap(channelShell['data'])['userOrError']),
    );
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
      streamMetadata: _graphQlClient.findOperationResponse(
        payload,
        'StreamMetadata',
      ),
      viewCount: _graphQlClient.findOperationResponse(payload, 'UseViewCount'),
      liveBroadcast: _graphQlClient.findOperationResponse(
        payload,
        'UseLiveBroadcast',
      ),
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

    final bootstrap = await _bootstrapResolverImpl.resolvePlaybackBootstrap(
      detail,
    );
    if (bootstrap == null || !bootstrap.isUsable) {
      throw ProviderParseException(
        providerId: ProviderId.twitch,
        message: 'Twitch 当前未能获得可用播放 bootstrap。',
      );
    }
    final playbackSurfaces = await _playbackSurfaceManager
        .loadPlaybackSurfaceCandidates(roomId: roomId, bootstrap: bootstrap);
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
    final groups = _playbackSurfaceManager.mergeQualityGroups(playbackSurfaces);
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

  @override
  Future<List<LivePlayUrl>> fetchPlayUrls({
    required LiveRoomDetail detail,
    required LivePlayQuality quality,
  }) async {
    return TwitchMapper.mapPlayUrls(detail, quality);
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
    final raw =
        payload['avatarURL']?.toString().trim() ??
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
      payload = await _graphQlClient.fetchBrowsePopular(
        cursor: cursor,
        limit: _browsePageSize,
      );
      final edges = _asList(
        _asMap(_asMap(payload['data'])['streams'])['edges'],
      );
      if (currentPage == page) {
        final items = edges
            .map(
              (edge) =>
                  TwitchMapper.mapBrowseRoom(_asMap(_asMap(edge)['node'])),
            )
            .where((room) => room.roomId.isNotEmpty)
            .toList(growable: false);
        return PagedResponse(
          items: items,
          hasMore:
              _asMap(
                _asMap(payload['data'])['streams'],
              )['pageInfo']['hasNextPage'] ==
              true,
          page: page,
        );
      }
      if (_asMap(
            _asMap(payload['data'])['streams'],
          )['pageInfo']['hasNextPage'] !=
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
    final payload = await _graphQlClient.fetchBrowseAllDirectories(
      limit: _maxDirectoryCategoryLimit,
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
    final requestedLimit = (_categoryPageSize * page).clamp(
      _categoryPageSize,
      _maxCategoryRoomLimit,
    );
    final payload = await _graphQlClient.fetchDirectoryPageGame(
      slug: category.id,
      limit: requestedLimit,
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
      return (items: const <LiveRoom>[], hasMore: false, page: page);
    }
    final endIndex = startIndex + _categoryPageSize;
    final pageItems = allItems
        .skip(startIndex)
        .take(_categoryPageSize)
        .toList(growable: false);
    final canGrowWindow =
        requestedLimit < _maxCategoryRoomLimit &&
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

  Map<String, dynamic> _asMap(Object? value) {
    return ProviderJson.asMap(value);
  }

  List<dynamic> _asList(Object? value) {
    return ProviderJson.asList(value);
  }
}
