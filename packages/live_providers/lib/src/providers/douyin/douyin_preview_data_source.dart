import 'package:live_core/live_core.dart';

import 'douyin_data_source.dart';
import 'douyin_mapper.dart';

class DouyinPreviewDataSource implements DouyinDataSource {
  const DouyinPreviewDataSource();

  static const List<LiveCategory> _categories = [
    LiveCategory(
      id: '720,1',
      name: '娱乐',
      children: [
        LiveSubCategory(id: '720,1', parentId: '720,1', name: '热门'),
        LiveSubCategory(id: '721,1', parentId: '720,1', name: '生活'),
      ],
    ),
    LiveCategory(
      id: '730,1',
      name: '知识',
      children: [
        LiveSubCategory(id: '730,1', parentId: '730,1', name: '知识'),
      ],
    ),
  ];

  static const List<LiveRoom> _rooms = [
    LiveRoom(
      providerId: 'douyin',
      roomId: '416144012050',
      title: '抖音架构演示房间',
      streamerName: '抖音样例主播',
      coverUrl: 'https://p3-pc-weblive.douyinpic.com/mock-cover-1.jpeg',
      keyframeUrl: 'https://p3-pc-weblive.douyinpic.com/mock-keyframe-1.jpeg',
      areaName: '生活',
      streamerAvatarUrl: 'https://p3.douyinpic.com/mock-avatar-1.jpeg',
      viewerCount: 32100,
    ),
    LiveRoom(
      providerId: 'douyin',
      roomId: '512300998877',
      title: '抖音迁移验证房间',
      streamerName: '迁移样例主播',
      coverUrl: 'https://p3-pc-weblive.douyinpic.com/mock-cover-2.jpeg',
      keyframeUrl: 'https://p3-pc-weblive.douyinpic.com/mock-keyframe-2.jpeg',
      areaName: '知识',
      streamerAvatarUrl: 'https://p3.douyinpic.com/mock-avatar-2.jpeg',
      viewerCount: 45600,
    ),
  ];

  static const Map<String, LiveRoomDetail> _details = {
    '416144012050': LiveRoomDetail(
      providerId: 'douyin',
      roomId: '416144012050',
      title: '抖音架构演示房间',
      streamerName: '抖音样例主播',
      streamerAvatarUrl: 'https://p3.douyinpic.com/mock-avatar-1.jpeg',
      coverUrl: 'https://p3-pc-weblive.douyinpic.com/mock-cover-1.jpeg',
      keyframeUrl: 'https://p3-pc-weblive.douyinpic.com/mock-keyframe-1.jpeg',
      areaName: '生活',
      description: '用于验证 douyin provider preview runtime。',
      sourceUrl: 'https://live.douyin.com/416144012050',
      isLive: true,
      viewerCount: 32100,
      danmakuToken: {'mode': 'preview'},
      metadata: {
        'streamUrl': {
          'flv_pull_url': {
            'FULL_HD1': 'https://mock.douyin.local/live/416144012050/flv'
          },
          'hls_pull_url_map': {
            'FULL_HD1': 'https://mock.douyin.local/live/416144012050/hls.m3u8'
          },
        },
      },
    ),
    '512300998877': LiveRoomDetail(
      providerId: 'douyin',
      roomId: '512300998877',
      title: '抖音迁移验证房间',
      streamerName: '迁移样例主播',
      streamerAvatarUrl: 'https://p3.douyinpic.com/mock-avatar-2.jpeg',
      coverUrl: 'https://p3-pc-weblive.douyinpic.com/mock-cover-2.jpeg',
      keyframeUrl: 'https://p3-pc-weblive.douyinpic.com/mock-keyframe-2.jpeg',
      areaName: '知识',
      description: '用于演示 douyin provider preview/live 双 runtime。',
      sourceUrl: 'https://live.douyin.com/512300998877',
      isLive: true,
      viewerCount: 45600,
      danmakuToken: {'mode': 'preview'},
      metadata: {
        'streamUrl': {
          'flv_pull_url': {
            'FULL_HD1': 'https://mock.douyin.local/live/512300998877/flv'
          },
          'hls_pull_url_map': {
            'FULL_HD1': 'https://mock.douyin.local/live/512300998877/hls.m3u8'
          },
        },
      },
    ),
  };

  static const List<LivePlayQuality> _qualities = [
    LivePlayQuality(
      id: '0',
      label: '流畅',
      sortOrder: 0,
      metadata: {
        'rate': 0,
        'urls': [
          'https://mock.douyin.local/live/default/flv',
          'https://mock.douyin.local/live/default/hls.m3u8',
        ],
      },
    ),
    LivePlayQuality(
      id: '4',
      label: '蓝光',
      isDefault: true,
      sortOrder: 4,
      metadata: {
        'rate': 4,
        'urls': [
          'https://mock.douyin.local/live/default/blu-ray.flv',
          'https://mock.douyin.local/live/default/blu-ray.m3u8',
        ],
      },
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
        .where(
            (room) => room.areaName == category.name || category.name == '热门')
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
        providerId: ProviderId.douyin,
        message: 'Preview douyin room detail for roomId=$roomId was not found.',
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
    return DouyinMapper.mapPlayUrls(quality);
  }
}
