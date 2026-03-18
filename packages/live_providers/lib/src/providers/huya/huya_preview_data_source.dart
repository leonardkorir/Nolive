import 'package:live_core/live_core.dart';

import 'huya_data_source.dart';
import 'huya_sign_service.dart';

class HuyaPreviewDataSource implements HuyaDataSource {
  const HuyaPreviewDataSource();

  static const List<LiveCategory> _categories = [
    LiveCategory(
      id: '1',
      name: '网游',
      children: [
        LiveSubCategory(id: '100', parentId: '1', name: '英雄联盟'),
        LiveSubCategory(id: '101', parentId: '1', name: '王者荣耀'),
      ],
    ),
    LiveCategory(
      id: '8',
      name: '娱乐',
      children: [
        LiveSubCategory(id: '800', parentId: '8', name: '聊天互动'),
      ],
    ),
  ];

  static const List<LiveRoom> _rooms = [
    LiveRoom(
      providerId: 'huya',
      roomId: 'yy/880123',
      title: '虎牙架构演示房间',
      streamerName: '虎牙样例主播',
      coverUrl: 'https://huyaimg.msstatic.com/cdnimage/mock-cover-1.jpg',
      keyframeUrl: 'https://huyaimg.msstatic.com/cdnimage/mock-keyframe-1.jpg',
      areaName: '英雄联盟',
      streamerAvatarUrl: 'https://huyaimg.msstatic.com/avatar/mock-1.jpg',
      viewerCount: 54321,
    ),
    LiveRoom(
      providerId: 'huya',
      roomId: 'yy/990456',
      title: '虎牙迁移验证房间',
      streamerName: '迁移样例主播',
      coverUrl: 'https://huyaimg.msstatic.com/cdnimage/mock-cover-2.jpg',
      keyframeUrl: 'https://huyaimg.msstatic.com/cdnimage/mock-keyframe-2.jpg',
      areaName: '王者荣耀',
      streamerAvatarUrl: 'https://huyaimg.msstatic.com/avatar/mock-2.jpg',
      viewerCount: 65432,
    ),
  ];

  static const Map<String, LiveRoomDetail> _details = {
    'yy/880123': LiveRoomDetail(
      providerId: 'huya',
      roomId: 'yy/880123',
      title: '虎牙架构演示房间',
      streamerName: '虎牙样例主播',
      streamerAvatarUrl: 'https://huyaimg.msstatic.com/avatar/mock-1.jpg',
      coverUrl: 'https://huyaimg.msstatic.com/cdnimage/mock-cover-1.jpg',
      keyframeUrl: 'https://huyaimg.msstatic.com/cdnimage/mock-keyframe-1.jpg',
      areaName: '英雄联盟',
      description: '用于验证 huya provider 迁移骨架的 deterministic preview。',
      sourceUrl: 'https://www.huya.com/yy/880123',
      isLive: true,
      viewerCount: 54321,
      danmakuToken: {'mode': 'preview'},
    ),
    'yy/990456': LiveRoomDetail(
      providerId: 'huya',
      roomId: 'yy/990456',
      title: '虎牙迁移验证房间',
      streamerName: '迁移样例主播',
      streamerAvatarUrl: 'https://huyaimg.msstatic.com/avatar/mock-2.jpg',
      coverUrl: 'https://huyaimg.msstatic.com/cdnimage/mock-cover-2.jpg',
      keyframeUrl: 'https://huyaimg.msstatic.com/cdnimage/mock-keyframe-2.jpg',
      areaName: '王者荣耀',
      description: '用于演示 huya provider preview/live 双 runtime 结构。',
      sourceUrl: 'https://www.huya.com/yy/990456',
      isLive: true,
      viewerCount: 65432,
      danmakuToken: {'mode': 'preview'},
    ),
  };

  static const List<LivePlayQuality> _qualities = [
    LivePlayQuality(id: '0', label: '原画', isDefault: true, sortOrder: 0),
    LivePlayQuality(id: '2000', label: '高清', sortOrder: 2000),
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
    final items = _rooms
        .where((room) => room.areaName == category.name)
        .toList(growable: false);
    return PagedResponse(items: items, hasMore: false, page: page);
  }

  @override
  Future<PagedResponse<LiveRoom>> fetchRecommendRooms({int page = 1}) async {
    final items = [..._rooms]..sort((left, right) {
        final compare =
            (right.viewerCount ?? -1).compareTo(left.viewerCount ?? -1);
        if (compare != 0) {
          return compare;
        }
        return left.roomId.compareTo(right.roomId);
      });
    return PagedResponse(items: items, hasMore: false, page: page);
  }

  @override
  Future<PagedResponse<LiveRoom>> searchRooms(String query,
      {int page = 1}) async {
    final normalizedQuery = query.trim().toLowerCase();
    final filtered = _rooms.where((room) {
      if (normalizedQuery.isEmpty) {
        return true;
      }
      return room.title.toLowerCase().contains(normalizedQuery) ||
          room.streamerName.toLowerCase().contains(normalizedQuery);
    }).toList(growable: false);
    return PagedResponse(items: filtered, hasMore: false, page: page);
  }

  @override
  Future<LiveRoomDetail> fetchRoomDetail(String roomId) async {
    final detail = _details[roomId];
    if (detail == null) {
      throw ProviderParseException(
        providerId: ProviderId.huya,
        message: 'Preview huya room detail for roomId=$roomId was not found.',
      );
    }
    return detail;
  }

  @override
  Future<List<LivePlayQuality>> fetchPlayQualities(
      LiveRoomDetail detail) async {
    return _qualities;
  }

  @override
  Future<List<LivePlayUrl>> fetchPlayUrls({
    required LiveRoomDetail detail,
    required LivePlayQuality quality,
  }) async {
    return [
      LivePlayUrl(
        url: 'https://mock.huya.local/live/${detail.roomId}/${quality.id}.m3u8',
        headers: const {'user-agent': HttpHuyaSignService.playerUserAgent},
        lineLabel: 'mock-primary',
      ),
    ];
  }
}
