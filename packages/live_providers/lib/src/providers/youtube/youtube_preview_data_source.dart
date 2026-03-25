import 'package:live_core/live_core.dart';

import 'youtube_data_source.dart';
import 'youtube_hls_master_playlist_parser.dart';
import 'youtube_mapper.dart';

class YouTubePreviewDataSource implements YouTubeDataSource {
  const YouTubePreviewDataSource();

  static const List<LiveCategory> _categories = [
    LiveCategory(
      id: 'content',
      name: '内容分类',
      children: [
        LiveSubCategory(id: 'news', parentId: 'content', name: '新闻'),
        LiveSubCategory(id: 'gaming', parentId: 'content', name: '游戏'),
        LiveSubCategory(id: 'music', parentId: 'content', name: '音乐'),
      ],
    ),
  ];

  static const Map<String, String> _playHeaders = {
    'referer': 'https://www.youtube.com/watch?v=Z3eFGbFcaXs',
    'user-agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36',
  };

  static const List<LiveRoom> _rooms = [
    LiveRoom(
      providerId: 'youtube',
      roomId: '@ChinaStreetObserver/live',
      title: 'China Street Observer Live',
      streamerName: 'China Street Observer',
      coverUrl: 'https://i.ytimg.com/vi/Z3eFGbFcaXs/maxresdefault_live.jpg',
      areaName: '新闻',
      viewerCount: 12034,
      isLive: true,
    ),
    LiveRoom(
      providerId: 'youtube',
      roomId: '@WenzelTCG/live',
      title: 'WENZ VAULT!',
      streamerName: 'Wenzel TCG',
      coverUrl: 'https://i.ytimg.com/vi/Z3eFGbFcaXs/hqdefault_live.jpg',
      areaName: '游戏',
      viewerCount: 4821,
      isLive: true,
    ),
    LiveRoom(
      providerId: 'youtube',
      roomId: '@lofigirl/live',
      title: 'lofi hip hop radio',
      streamerName: 'Lofi Girl',
      coverUrl: 'https://i.ytimg.com/vi/jfKfPfyJRdk/hqdefault_live.jpg',
      areaName: '音乐',
      viewerCount: 35687,
      isLive: true,
    ),
  ];

  static const Map<String, LiveRoomDetail> _details = {
    '@ChinaStreetObserver/live': LiveRoomDetail(
      providerId: 'youtube',
      roomId: '@ChinaStreetObserver/live',
      title: 'China Street Observer Live',
      streamerName: 'China Street Observer',
      coverUrl: 'https://i.ytimg.com/vi/Z3eFGbFcaXs/maxresdefault_live.jpg',
      areaName: 'News',
      sourceUrl: 'https://www.youtube.com/watch?v=Z3eFGbFcaXs',
      isLive: true,
      viewerCount: 12034,
      danmakuToken: {
        'mode': 'preview',
      },
      metadata: {
        'resolvedVideoId': 'Z3eFGbFcaXs',
        'hlsManifestUrl':
            'https://manifest.googlevideo.com/api/manifest/hls_variant/fixture/Z3eFGbFcaXs/index.m3u8',
      },
    ),
    'Z3eFGbFcaXs': LiveRoomDetail(
      providerId: 'youtube',
      roomId: '@ChinaStreetObserver/live',
      title: 'China Street Observer Live',
      streamerName: 'China Street Observer',
      coverUrl: 'https://i.ytimg.com/vi/Z3eFGbFcaXs/maxresdefault_live.jpg',
      areaName: 'News',
      sourceUrl: 'https://www.youtube.com/watch?v=Z3eFGbFcaXs',
      isLive: true,
      viewerCount: 12034,
      danmakuToken: {
        'mode': 'preview',
      },
      metadata: {
        'resolvedVideoId': 'Z3eFGbFcaXs',
        'hlsManifestUrl':
            'https://manifest.googlevideo.com/api/manifest/hls_variant/fixture/Z3eFGbFcaXs/index.m3u8',
      },
    ),
    '@WenzelTCG/live': LiveRoomDetail(
      providerId: 'youtube',
      roomId: '@WenzelTCG/live',
      title: 'WENZ VAULT!',
      streamerName: 'Wenzel TCG',
      coverUrl: 'https://i.ytimg.com/vi/Z3eFGbFcaXs/hqdefault_live.jpg',
      areaName: 'Gaming',
      sourceUrl: 'https://www.youtube.com/watch?v=Z3eFGbFcaXs',
      isLive: true,
      viewerCount: 4821,
      danmakuToken: {
        'mode': 'preview',
      },
      metadata: {
        'resolvedVideoId': 'Z3eFGbFcaXs',
        'hlsManifestUrl':
            'https://manifest.googlevideo.com/api/manifest/hls_variant/fixture/Z3eFGbFcaXs/index.m3u8',
      },
    ),
    '@lofigirl/live': LiveRoomDetail(
      providerId: 'youtube',
      roomId: '@lofigirl/live',
      title: 'lofi hip hop radio',
      streamerName: 'Lofi Girl',
      coverUrl: 'https://i.ytimg.com/vi/jfKfPfyJRdk/hqdefault_live.jpg',
      areaName: 'Music',
      sourceUrl: 'https://www.youtube.com/watch?v=jfKfPfyJRdk',
      isLive: true,
      viewerCount: 35687,
      danmakuToken: {
        'mode': 'preview',
      },
      metadata: {
        'resolvedVideoId': 'jfKfPfyJRdk',
        'hlsManifestUrl':
            'https://manifest.googlevideo.com/api/manifest/hls_variant/fixture/jfKfPfyJRdk/index.m3u8',
      },
    ),
  };

  static const List<YouTubeHlsVariant> _variants = [
    YouTubeHlsVariant(
      url:
          'https://manifest.googlevideo.com/api/manifest/hls_variant/fixture/Z3eFGbFcaXs/1080p60.m3u8',
      bandwidth: 6200000,
      label: '1080p60',
      width: 1920,
      height: 1080,
      frameRate: 60,
    ),
    YouTubeHlsVariant(
      url:
          'https://manifest.googlevideo.com/api/manifest/hls_variant/fixture/Z3eFGbFcaXs/720p60.m3u8',
      bandwidth: 3200000,
      label: '720p60',
      width: 1280,
      height: 720,
      frameRate: 60,
    ),
    YouTubeHlsVariant(
      url:
          'https://manifest.googlevideo.com/api/manifest/hls_variant/fixture/Z3eFGbFcaXs/480p30.m3u8',
      bandwidth: 1500000,
      label: '480p',
      width: 854,
      height: 480,
      frameRate: 30,
    ),
  ];

  @override
  Future<List<LiveCategory>> fetchCategories() async {
    return _categories;
  }

  @override
  Future<PagedResponse<LiveRoom>> fetchCategoryRooms(
    LiveSubCategory category, {
    int page = 1,
  }) async {
    if (page != 1) {
      return PagedResponse(items: const [], hasMore: false, page: page);
    }
    final items = _rooms
        .where((room) => room.areaName == category.name)
        .toList(growable: false);
    return PagedResponse(items: items, hasMore: false, page: page);
  }

  @override
  Future<PagedResponse<LiveRoom>> fetchRecommendRooms({int page = 1}) async {
    if (page != 1) {
      return PagedResponse(items: const [], hasMore: false, page: page);
    }
    return PagedResponse(
      items: _rooms,
      hasMore: false,
      page: page,
    );
  }

  @override
  Future<PagedResponse<LiveRoom>> searchRooms(
    String query, {
    int page = 1,
  }) async {
    if (page != 1) {
      return PagedResponse(items: const [], hasMore: false, page: page);
    }
    final normalized = query.trim().toLowerCase();
    final items = _rooms.where((room) {
      if (normalized.isEmpty) {
        return true;
      }
      return room.roomId.toLowerCase().contains(normalized) ||
          room.streamerName.toLowerCase().contains(normalized) ||
          room.title.toLowerCase().contains(normalized);
    }).toList(growable: false);
    return PagedResponse(items: items, hasMore: false, page: page);
  }

  @override
  Future<LiveRoomDetail> fetchRoomDetail(String roomId) async {
    final detail = _details[roomId];
    if (detail == null) {
      throw ProviderParseException(
        providerId: ProviderId.youtube,
        message:
            'Preview YouTube room detail for roomId=$roomId was not found.',
      );
    }
    return detail;
  }

  @override
  Future<List<LivePlayQuality>> fetchPlayQualities(
    LiveRoomDetail detail,
  ) async {
    final manifestUrl =
        detail.metadata?['hlsManifestUrl']?.toString().trim() ?? '';
    if (manifestUrl.isEmpty) {
      return const [];
    }
    return YouTubeMapper.mapPlayQualitiesFromVariants(
      variants: _variants,
      manifestUrl: manifestUrl,
      headers: _playHeaders,
    );
  }

  @override
  Future<List<LivePlayUrl>> fetchPlayUrls({
    required LiveRoomDetail detail,
    required LivePlayQuality quality,
  }) async {
    return YouTubeMapper.mapPlayUrls(detail, quality);
  }
}
