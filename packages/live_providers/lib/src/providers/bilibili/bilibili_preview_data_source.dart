import 'package:live_core/live_core.dart';

import 'bilibili_data_source.dart';

class BilibiliPreviewDataSource implements BilibiliDataSource {
  const BilibiliPreviewDataSource();

  static const List<LiveCategory> _categories = [
    LiveCategory(
      id: '1',
      name: '知识',
      children: [
        LiveSubCategory(id: '101', parentId: '1', name: '知识区'),
        LiveSubCategory(id: '102', parentId: '1', name: '测试区'),
      ],
    ),
    LiveCategory(
      id: '2',
      name: '娱乐',
      children: [
        LiveSubCategory(id: '201', parentId: '2', name: '聊天互动'),
      ],
    ),
  ];

  static const List<LiveRoom> _rooms = [
    LiveRoom(
      providerId: 'bilibili',
      roomId: '6',
      title: '新项目参考直播间',
      streamerName: '系统演示主播',
      coverUrl: 'https://i0.hdslb.com/bfs/live/mock-cover-1.png',
      keyframeUrl: 'https://i0.hdslb.com/bfs/live/mock-keyframe-1.webp',
      areaName: '知识区',
      streamerAvatarUrl: 'https://i0.hdslb.com/bfs/face/mock-avatar-1.png',
      viewerCount: 1024,
    ),
    LiveRoom(
      providerId: 'bilibili',
      roomId: '66666',
      title: '架构迁移验证房间',
      streamerName: '迁移样例主播',
      coverUrl: 'https://i0.hdslb.com/bfs/live/mock-cover-2.png',
      keyframeUrl: 'https://i0.hdslb.com/bfs/live/mock-keyframe-2.webp',
      areaName: '测试区',
      streamerAvatarUrl: 'https://i0.hdslb.com/bfs/face/mock-avatar-2.png',
      viewerCount: 2048,
    ),
  ];

  static const Map<String, LiveRoomDetail> _details = {
    '6': LiveRoomDetail(
      providerId: 'bilibili',
      roomId: '6',
      title: '新项目参考直播间',
      streamerName: '系统演示主播',
      streamerAvatarUrl: 'https://i0.hdslb.com/bfs/face/mock-avatar-1.png',
      coverUrl: 'https://i0.hdslb.com/bfs/live/mock-cover-1.png',
      keyframeUrl: 'https://i0.hdslb.com/bfs/live/mock-keyframe-1.webp',
      areaName: '知识区',
      description: '用于验证新架构接线的预览房间。',
      sourceUrl: 'https://live.bilibili.com/6',
      isLive: true,
      viewerCount: 1024,
      danmakuToken: {'mode': 'preview'},
    ),
    '66666': LiveRoomDetail(
      providerId: 'bilibili',
      roomId: '66666',
      title: '架构迁移验证房间',
      streamerName: '迁移样例主播',
      streamerAvatarUrl: 'https://i0.hdslb.com/bfs/face/mock-avatar-2.png',
      coverUrl: 'https://i0.hdslb.com/bfs/live/mock-cover-2.png',
      keyframeUrl: 'https://i0.hdslb.com/bfs/live/mock-keyframe-2.webp',
      areaName: '测试区',
      description: '用于演示 provider runtime foundation 的 deterministic preview。',
      sourceUrl: 'https://live.bilibili.com/66666',
      isLive: true,
      viewerCount: 2048,
      danmakuToken: {'mode': 'preview'},
    ),
  };

  static const List<LivePlayQuality> _qualities = [
    LivePlayQuality(
      id: '80',
      label: '流畅',
      isDefault: true,
      sortOrder: 80,
      metadata: {'qn': 80},
    ),
    LivePlayQuality(
      id: '150',
      label: '高清',
      sortOrder: 150,
      metadata: {'qn': 150},
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
        providerId: ProviderId.bilibili,
        message:
            'Preview bilibili room detail for roomId=$roomId was not found.',
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
        url:
            'https://mock.bilibili.local/live/${detail.roomId}/${quality.id}.m3u8',
        headers: const {
          'referer': 'https://live.bilibili.com',
          'user-agent': 'simplelive-migration-preview',
        },
        lineLabel: 'mock-primary',
      ),
    ];
  }
}
