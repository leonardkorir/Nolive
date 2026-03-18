import 'package:live_core/live_core.dart';

import 'douyu_data_source.dart';

class DouyuPreviewDataSource implements DouyuDataSource {
  const DouyuPreviewDataSource();

  static const List<LiveCategory> _categories = [
    LiveCategory(
      id: '1',
      name: '技术',
      children: [
        LiveSubCategory(id: '11', parentId: '1', name: '技术杂谈'),
        LiveSubCategory(id: '12', parentId: '1', name: '测试专区'),
      ],
    ),
    LiveCategory(
      id: '2',
      name: '游戏',
      children: [
        LiveSubCategory(id: '21', parentId: '2', name: '王者荣耀'),
      ],
    ),
  ];

  static const List<LiveRoom> _rooms = [
    LiveRoom(
      providerId: 'douyu',
      roomId: '3125893',
      title: '斗鱼架构演示房间',
      streamerName: '斗鱼样例主播',
      coverUrl: 'https://apic.douyucdn.cn/upload/mock-cover-1.jpg',
      keyframeUrl: 'https://apic.douyucdn.cn/upload/mock-keyframe-1.jpg',
      areaName: '技术杂谈',
      streamerAvatarUrl: 'https://apic.douyucdn.cn/upload/mock-avatar-1.jpg',
      viewerCount: 12345,
    ),
    LiveRoom(
      providerId: 'douyu',
      roomId: '9123456',
      title: '斗鱼迁移验证房间',
      streamerName: '迁移样例主播',
      coverUrl: 'https://apic.douyucdn.cn/upload/mock-cover-2.jpg',
      keyframeUrl: 'https://apic.douyucdn.cn/upload/mock-keyframe-2.jpg',
      areaName: '测试专区',
      streamerAvatarUrl: 'https://apic.douyucdn.cn/upload/mock-avatar-2.jpg',
      viewerCount: 45678,
    ),
  ];

  static const Map<String, LiveRoomDetail> _details = {
    '3125893': LiveRoomDetail(
      providerId: 'douyu',
      roomId: '3125893',
      title: '斗鱼架构演示房间',
      streamerName: '斗鱼样例主播',
      streamerAvatarUrl: 'https://apic.douyucdn.cn/upload/mock-avatar-1.jpg',
      coverUrl: 'https://apic.douyucdn.cn/upload/mock-cover-1.jpg',
      keyframeUrl: 'https://apic.douyucdn.cn/upload/mock-keyframe-1.jpg',
      areaName: '技术杂谈',
      description: '用于验证 douyu provider preview runtime。',
      sourceUrl: 'https://www.douyu.com/3125893',
      isLive: true,
      viewerCount: 12345,
      danmakuToken: {'mode': 'preview'},
      metadata: {'playContext': 'preview'},
    ),
    '9123456': LiveRoomDetail(
      providerId: 'douyu',
      roomId: '9123456',
      title: '斗鱼迁移验证房间',
      streamerName: '迁移样例主播',
      streamerAvatarUrl: 'https://apic.douyucdn.cn/upload/mock-avatar-2.jpg',
      coverUrl: 'https://apic.douyucdn.cn/upload/mock-cover-2.jpg',
      keyframeUrl: 'https://apic.douyucdn.cn/upload/mock-keyframe-2.jpg',
      areaName: '测试专区',
      description: '用于演示 douyu provider preview/live 双 runtime。',
      sourceUrl: 'https://www.douyu.com/9123456',
      isLive: true,
      viewerCount: 45678,
      danmakuToken: {'mode': 'preview'},
      metadata: {'playContext': 'preview'},
    ),
  };

  static const List<LivePlayQuality> _qualities = [
    LivePlayQuality(
      id: '0',
      label: '流畅',
      isDefault: true,
      sortOrder: 0,
      metadata: {'rate': 0},
    ),
    LivePlayQuality(
      id: '4',
      label: '蓝光',
      sortOrder: 4,
      metadata: {'rate': 4},
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
  Future<PagedResponse<LiveRoom>> searchRooms(
    String query, {
    int page = 1,
  }) async {
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
        providerId: ProviderId.douyu,
        message: 'Preview douyu room detail for roomId=$roomId was not found.',
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
    return [
      LivePlayUrl(
        url:
            'https://mock.douyu.local/live/${detail.roomId}/${quality.id}.m3u8',
        headers: {
          'referer': 'https://www.douyu.com/${detail.roomId}',
          'user-agent': 'simplelive-migration-preview',
        },
        lineLabel: 'mock-primary',
      ),
    ];
  }
}
