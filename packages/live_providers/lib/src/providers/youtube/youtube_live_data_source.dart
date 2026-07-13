import 'package:live_core/live_core.dart';

import 'youtube_api_client.dart';
import 'youtube_browse_data_source.dart';
import 'youtube_data_source.dart';
import 'youtube_decipher_service.dart';
import 'youtube_hls_master_playlist_parser.dart';
import 'youtube_page_parser.dart';
import 'youtube_playback_data_source.dart';
import 'youtube_playback_extractor.dart';

class YouTubeLiveDataSource implements YouTubeDataSource {
  YouTubeLiveDataSource({
    required YouTubeApiClient apiClient,
    YouTubePageParser pageParser = const YouTubePageParser(),
    YouTubeHlsMasterPlaylistParser hlsMasterPlaylistParser =
        const YouTubeHlsMasterPlaylistParser(),
    YouTubeNSigSolver? nSigSolver,
  }) : this._internal(
         playbackDataSource: YouTubePlaybackDataSource(
           apiClient: apiClient,
           hlsMasterPlaylistParser: hlsMasterPlaylistParser,
           nSigSolver: nSigSolver,
         ),
         apiClient: apiClient,
         pageParser: pageParser,
       );

  YouTubeLiveDataSource._internal({
    required YouTubePlaybackDataSource playbackDataSource,
    required YouTubeApiClient apiClient,
    required YouTubePageParser pageParser,
  }) : _playbackDataSource = playbackDataSource {
    _browseDataSource = YouTubeBrowseDataSource(
      apiClient: apiClient,
      playbackDataSource: playbackDataSource,
      pageParser: pageParser,
      searchRoomsDelegate: (query, {page = 1}) =>
          searchRooms(query, page: page),
    );
  }

  final YouTubePlaybackDataSource _playbackDataSource;
  late final YouTubeBrowseDataSource _browseDataSource;

  @override
  Future<List<LiveCategory>> fetchCategories() =>
      _browseDataSource.fetchCategories();

  @override
  Future<PagedResponse<LiveRoom>> fetchCategoryRooms(
    LiveSubCategory category, {
    int page = 1,
  }) => _browseDataSource.fetchCategoryRooms(category, page: page);

  @override
  Future<PagedResponse<LiveRoom>> fetchRecommendRooms({int page = 1}) =>
      _browseDataSource.fetchRecommendRooms(page: page);

  @override
  Future<PagedResponse<LiveRoom>> searchRooms(String query, {int page = 1}) =>
      _browseDataSource.searchRooms(query, page: page);

  @override
  Future<LiveRoomDetail> fetchRoomDetail(String roomId) =>
      _browseDataSource.fetchRoomDetail(roomId);

  @override
  Future<List<LivePlayQuality>> fetchPlayQualities(LiveRoomDetail detail) =>
      _playbackDataSource.fetchPlayQualities(detail);

  @override
  Future<List<LivePlayUrl>> fetchPlayUrls({
    required LiveRoomDetail detail,
    required LivePlayQuality quality,
  }) => _playbackDataSource.fetchPlayUrls(detail: detail, quality: quality);

  int get debugHlsVariantCacheSize =>
      _playbackDataSource.debugHlsVariantCacheSize;

  int get debugHlsUsabilityCacheSize =>
      _playbackDataSource.debugHlsUsabilityCacheSize;

  void debugRememberHlsVariantCache(
    String url,
    List<YouTubeHlsVariant> variants,
  ) => _playbackDataSource.debugRememberHlsVariantCache(url, variants);

  void debugRememberHlsUsabilityCache(String url, bool usable) =>
      _playbackDataSource.debugRememberHlsUsabilityCache(url, usable);

  Map<String, dynamic> debugMergeContextMaps(
    Map<String, dynamic> base,
    Map<String, dynamic> overlay,
  ) => YouTubePlaybackExtractor.mergeMaps(base, overlay);
}
