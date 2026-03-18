import 'package:live_core/live_core.dart';

import 'chaturbate_data_source.dart';
import 'chaturbate_mapper.dart';

class ChaturbatePreviewDataSource implements ChaturbateDataSource {
  const ChaturbatePreviewDataSource();

  static const List<LiveRoom> _rooms = [
    LiveRoom(
      providerId: 'chaturbate',
      roomId: 'kittengirlxo',
      title: 'kittengirlxo',
      streamerName: 'kittengirlxo',
      coverUrl: 'https://thumb.live.mmcdn.com/riw/kittengirlxo.jpg?1773558480',
      areaName: 'Female',
      viewerCount: 9775,
    ),
    LiveRoom(
      providerId: 'chaturbate',
      roomId: 'emilygrey_',
      title: 'Hiya! | /tipmenu | #lovense #lush',
      streamerName: 'emilygrey_',
      coverUrl: 'https://thumb.live.mmcdn.com/riw/emilygrey_.jpg?1773558480',
      areaName: 'Female',
      viewerCount: 8910,
    ),
    LiveRoom(
      providerId: 'chaturbate',
      roomId: 'sladkoesolnishko',
      title: 'Couple preview room',
      streamerName: 'sladkoesolnishko',
      coverUrl:
          'https://thumb.live.mmcdn.com/riw/sladkoesolnishko.jpg?1773558480',
      areaName: 'Couple',
      viewerCount: 4210,
    ),
    LiveRoom(
      providerId: 'chaturbate',
      roomId: 'cutie_lilliana',
      title: 'Trans preview room',
      streamerName: 'cutie_lilliana',
      coverUrl:
          'https://thumb.live.mmcdn.com/riw/cutie_lilliana.jpg?1773558480',
      areaName: 'Trans',
      viewerCount: 506,
    ),
  ];

  static const Map<String, LiveRoomDetail> _details = {
    'kittengirlxo': LiveRoomDetail(
      providerId: 'chaturbate',
      roomId: 'kittengirlxo',
      title: "Kittengirlxo's room",
      streamerName: 'kittengirlxo',
      areaName: 'Female',
      sourceUrl: 'https://chaturbate.com/kittengirlxo/',
      isLive: true,
      viewerCount: 9627,
      danmakuToken: {'mode': 'preview'},
      metadata: {
        'roomStatus': 'public',
        'edgeRegion': 'AUS',
        'allowPrivateShows': false,
        'privateShowPrice': 60,
        'spyPrivateShowPrice': 6,
        'hlsSource':
            'https://edge7-aus.live.mmcdn.com/live-hls/amlst:kittengirlxo-sd-preview/playlist.m3u8',
      },
    ),
    'emilygrey_': LiveRoomDetail(
      providerId: 'chaturbate',
      roomId: 'emilygrey_',
      title: 'Hiya! | /tipmenu | #lovense #lush',
      streamerName: 'emilygrey_',
      areaName: 'Female',
      sourceUrl: 'https://chaturbate.com/emilygrey_/',
      isLive: true,
      viewerCount: 8910,
      danmakuToken: {'mode': 'preview'},
      metadata: {
        'roomStatus': 'public',
        'edgeRegion': 'AUS',
        'hlsSource':
            'https://edge7-aus.live.mmcdn.com/live-hls/amlst:emilygrey_-sd-preview/playlist.m3u8',
      },
    ),
    'sladkoesolnishko': LiveRoomDetail(
      providerId: 'chaturbate',
      roomId: 'sladkoesolnishko',
      title: 'Couple preview room',
      streamerName: 'sladkoesolnishko',
      areaName: 'Couple',
      sourceUrl: 'https://chaturbate.com/sladkoesolnishko/',
      isLive: true,
      viewerCount: 4210,
      danmakuToken: {'mode': 'preview'},
      metadata: {
        'roomStatus': 'public',
        'edgeRegion': 'AMS',
        'hlsSource':
            'https://edge7-ams.live.mmcdn.com/live-hls/amlst:sladkoesolnishko-sd-preview/playlist.m3u8',
      },
    ),
    'cutie_lilliana': LiveRoomDetail(
      providerId: 'chaturbate',
      roomId: 'cutie_lilliana',
      title: 'Trans preview room',
      streamerName: 'cutie_lilliana',
      areaName: 'Trans',
      sourceUrl: 'https://chaturbate.com/cutie_lilliana/',
      isLive: true,
      viewerCount: 506,
      danmakuToken: {'mode': 'preview'},
      metadata: {
        'roomStatus': 'public',
        'edgeRegion': 'IAD',
        'hlsSource':
            'https://edge7-iad.live.mmcdn.com/live-hls/amlst:cutie_lilliana-sd-preview/playlist.m3u8',
      },
    ),
  };

  static const List<LivePlayQuality> _qualities = [
    LivePlayQuality(
      id: 'auto',
      label: 'Auto',
      isDefault: true,
    ),
  ];

  @override
  Future<List<LiveCategory>> fetchCategories() async {
    return ChaturbateMapper.categories;
  }

  @override
  Future<PagedResponse<LiveRoom>> fetchCategoryRooms(
    LiveSubCategory category, {
    int page = 1,
  }) async {
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
    return PagedResponse(items: _rooms, hasMore: false, page: page);
  }

  @override
  Future<PagedResponse<LiveRoom>> searchRooms(
    String query, {
    int page = 1,
  }) async {
    final normalizedQuery = query.trim().toLowerCase();
    final items = _rooms.where((room) {
      if (normalizedQuery.isEmpty) {
        return true;
      }
      return room.roomId.toLowerCase().contains(normalizedQuery) ||
          room.title.toLowerCase().contains(normalizedQuery) ||
          room.streamerName.toLowerCase().contains(normalizedQuery);
    }).toList(growable: false);
    return PagedResponse(items: items, hasMore: false, page: page);
  }

  @override
  Future<LiveRoomDetail> fetchRoomDetail(String roomId) async {
    final detail = _details[roomId];
    if (detail == null) {
      throw ProviderParseException(
        providerId: ProviderId.chaturbate,
        message:
            'Preview chaturbate room detail for roomId=$roomId was not found.',
      );
    }
    return detail;
  }

  @override
  Future<List<LivePlayQuality>> fetchPlayQualities(
    LiveRoomDetail detail,
  ) async {
    return _qualities;
  }

  @override
  Future<List<LivePlayUrl>> fetchPlayUrls({
    required LiveRoomDetail detail,
    required LivePlayQuality quality,
  }) async {
    return ChaturbateMapper.mapPlayUrls(detail, quality);
  }
}
