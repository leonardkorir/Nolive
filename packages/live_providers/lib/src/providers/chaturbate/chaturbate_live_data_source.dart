import 'package:live_core/live_core.dart';

import 'chaturbate_api_client.dart';
import 'chaturbate_data_source.dart';
import 'chaturbate_hls_master_playlist_parser.dart';
import 'chaturbate_mapper.dart';
import 'chaturbate_room_page_parser.dart';

class ChaturbateLiveDataSource implements ChaturbateDataSource {
  ChaturbateLiveDataSource({
    required ChaturbateApiClient apiClient,
    ChaturbateRoomPageParser roomPageParser = const ChaturbateRoomPageParser(),
    ChaturbateHlsMasterPlaylistParser hlsMasterPlaylistParser =
        const ChaturbateHlsMasterPlaylistParser(),
    List<String>? recommendCarouselIds,
  })  : _apiClient = apiClient,
        _roomPageParser = roomPageParser,
        _hlsMasterPlaylistParser = hlsMasterPlaylistParser,
        _recommendCarouselIds = List.unmodifiable(
          recommendCarouselIds ??
              ChaturbateApiClient.defaultRecommendCarouselIds,
        );

  final ChaturbateApiClient _apiClient;
  final ChaturbateRoomPageParser _roomPageParser;
  final ChaturbateHlsMasterPlaylistParser _hlsMasterPlaylistParser;
  final List<String> _recommendCarouselIds;

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
    final html = await _apiClient.fetchRoomPage(roomId);
    final context = _roomPageParser.parsePageContext(html);
    return ChaturbateMapper.mapRoomDetailFromPageContext(context);
  }

  @override
  Future<List<LivePlayQuality>> fetchPlayQualities(
    LiveRoomDetail detail,
  ) async {
    final fallbackQualities = ChaturbateMapper.mapPlayQualities(detail);
    final metadata = detail.metadata ?? const <String, Object?>{};
    final hlsSource = metadata['hlsSource']?.toString().trim() ?? '';
    if (hlsSource.isEmpty) {
      return fallbackQualities;
    }
    try {
      final playlistText = await _apiClient.fetchHlsPlaylist(
        hlsSource,
        referer: detail.sourceUrl,
      );
      final variants = _hlsMasterPlaylistParser.parse(
        playlistUrl: hlsSource,
        source: playlistText,
      );
      if (variants.isEmpty) {
        return fallbackQualities;
      }
      return ChaturbateMapper.mapPlayQualitiesFromVariants(
        variants: variants,
      );
    } catch (_) {
      return fallbackQualities;
    }
  }

  @override
  Future<List<LivePlayUrl>> fetchPlayUrls({
    required LiveRoomDetail detail,
    required LivePlayQuality quality,
  }) async {
    return ChaturbateMapper.mapPlayUrls(detail, quality);
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
}
