import 'package:live_core/live_core.dart';

import 'twitch_data_source.dart';
import 'twitch_hls_master_playlist_parser.dart';
import 'twitch_mapper.dart';

class TwitchPreviewDataSource implements TwitchDataSource {
  const TwitchPreviewDataSource();

  static const List<LiveCategory> _categories = [
    LiveCategory(
      id: 'popular',
      name: '热门分类',
      children: [
        LiveSubCategory(
          id: 'just_chatting',
          parentId: 'popular',
          name: 'Just Chatting',
        ),
        LiveSubCategory(
          id: 'talk_shows',
          parentId: 'popular',
          name: 'Talk Shows',
        ),
      ],
    ),
  ];

  static const Map<String, String> _playHeaders = {
    'user-agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36',
    'referer': 'https://www.twitch.tv/xqc',
  };

  static const List<LiveRoom> _rooms = [
    LiveRoom(
      providerId: 'twitch',
      roomId: 'xqc',
      title: 'LIVE REACT DRAMA NEWS VIDEOS GAMES',
      streamerName: 'xQc',
      coverUrl:
          'https://static-cdn.jtvnw.net/previews-ttv/live_user_xqc-214x120.jpg',
      streamerAvatarUrl:
          'https://static-cdn.jtvnw.net/jtv_user_pictures/xqc-profile_image-9298dca608632101-150x150.jpeg',
      areaName: 'Just Chatting',
      viewerCount: 22089,
      isLive: true,
    ),
    LiveRoom(
      providerId: 'twitch',
      roomId: 'arky',
      title: 'LAST DANCE PARTY',
      streamerName: 'arky',
      coverUrl:
          'https://static-cdn.jtvnw.net/previews-ttv/live_user_arky-214x120.jpg',
      streamerAvatarUrl:
          'https://static-cdn.jtvnw.net/jtv_user_pictures/1ed0e0c7-2714-41c3-9848-5eb1696db74a-profile_image-70x70.png',
      areaName: 'Just Chatting',
      viewerCount: 7944,
      isLive: true,
    ),
    LiveRoom(
      providerId: 'twitch',
      roomId: 'zackrawrr',
      title: 'Offline preview room',
      streamerName: 'zackrawrr',
      streamerAvatarUrl:
          'https://static-cdn.jtvnw.net/jtv_user_pictures/a9ce83ba-c0bd-49cc-83bd-9d17647a211a-profile_image-70x70.png',
      areaName: 'Talk Shows',
      isLive: false,
    ),
  ];

  static const Map<String, LiveRoomDetail> _details = {
    'xqc': LiveRoomDetail(
      providerId: 'twitch',
      roomId: 'xqc',
      title: 'LIVE REACT DRAMA NEWS VIDEOS GAMES',
      streamerName: 'xQc',
      streamerAvatarUrl:
          'https://static-cdn.jtvnw.net/jtv_user_pictures/xqc-profile_image-9298dca608632101-70x70.jpeg',
      coverUrl:
          'https://static-cdn.jtvnw.net/jtv_user_pictures/xqc-profile_banner-480.png',
      areaName: 'RISK: The Game of Global Domination',
      sourceUrl: 'https://www.twitch.tv/xqc',
      isLive: true,
      viewerCount: 22089,
      danmakuToken: {'mode': 'preview'},
      metadata: {
        'masterPlaylistUrl':
            'https://usher.ttvnw.net/api/v2/channel/hls/xqc.m3u8',
      },
    ),
    'arky': LiveRoomDetail(
      providerId: 'twitch',
      roomId: 'arky',
      title: 'LAST DANCE PARTY',
      streamerName: 'arky',
      streamerAvatarUrl:
          'https://static-cdn.jtvnw.net/jtv_user_pictures/1ed0e0c7-2714-41c3-9848-5eb1696db74a-profile_image-70x70.png',
      coverUrl:
          'https://static-cdn.jtvnw.net/jtv_user_pictures/arky-banner-480.png',
      areaName: 'Just Chatting',
      sourceUrl: 'https://www.twitch.tv/arky',
      isLive: true,
      viewerCount: 7944,
      danmakuToken: {'mode': 'preview'},
      metadata: {
        'masterPlaylistUrl':
            'https://usher.ttvnw.net/api/v2/channel/hls/arky.m3u8',
      },
    ),
    'zackrawrr': LiveRoomDetail(
      providerId: 'twitch',
      roomId: 'zackrawrr',
      title: 'Offline preview room',
      streamerName: 'zackrawrr',
      streamerAvatarUrl:
          'https://static-cdn.jtvnw.net/jtv_user_pictures/a9ce83ba-c0bd-49cc-83bd-9d17647a211a-profile_image-70x70.png',
      sourceUrl: 'https://www.twitch.tv/zackrawrr',
      isLive: false,
      danmakuToken: {'mode': 'preview'},
      metadata: {
        'masterPlaylistUrl':
            'https://usher.ttvnw.net/api/v2/channel/hls/zackrawrr.m3u8',
      },
    ),
  };

  static const List<TwitchHlsVariant> _variants = [
    TwitchHlsVariant(
      url:
          'https://d1m7jfoe9zdc1j.cloudfront.net/fixture/xqc/chunked/index-dvr.m3u8',
      bandwidth: 7925994,
      label: '1080p60',
      stableVariantId: '1080p60',
      source: 'source',
      width: 1920,
      height: 1080,
      frameRate: 60,
    ),
    TwitchHlsVariant(
      url:
          'https://d1m7jfoe9zdc1j.cloudfront.net/fixture/xqc/720p60/index-dvr.m3u8',
      bandwidth: 3145142,
      label: '720p60',
      stableVariantId: '720p60',
      source: 'transcode',
      width: 1280,
      height: 720,
      frameRate: 60,
    ),
    TwitchHlsVariant(
      url:
          'https://d1m7jfoe9zdc1j.cloudfront.net/fixture/xqc/480p30/index-dvr.m3u8',
      bandwidth: 1425635,
      label: '480p',
      stableVariantId: '480p30',
      source: 'transcode',
      width: 852,
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
        .where(
          (room) =>
              _normalizeCategoryKey(room.areaName) ==
              _normalizeCategoryKey(category.name),
        )
        .toList(growable: false);
    return PagedResponse(items: items, hasMore: false, page: page);
  }

  @override
  Future<PagedResponse<LiveRoom>> fetchRecommendRooms({int page = 1}) async {
    if (page != 1) {
      return PagedResponse(items: const [], hasMore: false, page: page);
    }
    return PagedResponse(items: _rooms, hasMore: false, page: page);
  }

  @override
  Future<PagedResponse<LiveRoom>> searchRooms(
    String query, {
    int page = 1,
  }) async {
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
        providerId: ProviderId.twitch,
        message: 'Preview Twitch room detail for roomId=$roomId was not found.',
      );
    }
    return detail;
  }

  @override
  Future<List<LivePlayQuality>> fetchPlayQualities(
    LiveRoomDetail detail,
  ) async {
    final masterPlaylistUrl =
        detail.metadata?['masterPlaylistUrl']?.toString().trim() ?? '';
    return TwitchMapper.mapPlayQualitiesFromVariants(
      variants: _variants,
      masterPlaylistUrl: masterPlaylistUrl,
      headers: _playHeaders,
    );
  }

  @override
  Future<List<LivePlayUrl>> fetchPlayUrls({
    required LiveRoomDetail detail,
    required LivePlayQuality quality,
  }) async {
    return TwitchMapper.mapPlayUrls(detail, quality);
  }
}

String _normalizeCategoryKey(String? value) {
  return (value ?? '')
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-');
}
