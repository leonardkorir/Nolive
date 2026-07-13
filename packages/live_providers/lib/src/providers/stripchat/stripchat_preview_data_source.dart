import 'package:live_core/live_core.dart';

import 'stripchat_data_source.dart';

class StripchatPreviewDataSource implements StripchatDataSource {
  const StripchatPreviewDataSource();

  static const List<LiveCategory> _categories = [
    LiveCategory(
      id: 'country-asia_pacific',
      name: '亚洲 & 太平洋',
      children: [
        LiveSubCategory(
          id: 'tagLanguageChinese',
          parentId: 'country-asia_pacific',
          name: '中文',
        ),
        LiveSubCategory(
          id: 'tagLanguageIndian',
          parentId: 'country-asia_pacific',
          name: '印度人',
        ),
      ],
    ),
    LiveCategory(
      id: 'country-north_america',
      name: '北美',
      children: [
        LiveSubCategory(
          id: 'tagLanguageUSModels',
          parentId: 'country-north_america',
          name: '美国人',
        ),
      ],
    ),
    LiveCategory(
      id: 'ethnicity',
      name: '种族',
      children: [
        LiveSubCategory(
          id: 'ethnicityAsian',
          parentId: 'ethnicity',
          name: '亚洲人',
        ),
        LiveSubCategory(
          id: 'ethnicityLatina',
          parentId: 'ethnicity',
          name: '拉丁人',
        ),
        LiveSubCategory(
          id: 'ethnicityWhite',
          parentId: 'ethnicity',
          name: '白人',
        ),
      ],
    ),
  ];

  static const List<LiveRoom> _rooms = [
    LiveRoom(
      providerId: ProviderId.stripchat,
      roomId: 'alice_demo',
      title: '',
      streamerName: 'alice_demo',
      coverUrl: 'https://static-proxy.strpst.com/previews/mock-alice-small.jpg',
      areaName: 'China',
      streamerAvatarUrl:
          'https://static-proxy.strpst.com/avatars/mock-alice.jpg',
      viewerCount: 1200,
    ),
    LiveRoom(
      providerId: ProviderId.stripchat,
      roomId: 'bob_live',
      title: '',
      streamerName: 'bob_live',
      coverUrl: 'https://static-proxy.strpst.com/previews/mock-bob-small.jpg',
      areaName: 'United States',
      streamerAvatarUrl: 'https://static-proxy.strpst.com/avatars/mock-bob.jpg',
      viewerCount: 800,
    ),
    LiveRoom(
      providerId: ProviderId.stripchat,
      roomId: 'carol_show',
      title: '',
      streamerName: 'carol_show',
      coverUrl: 'https://static-proxy.strpst.com/previews/mock-carol-small.jpg',
      areaName: 'Korea',
      streamerAvatarUrl:
          'https://static-proxy.strpst.com/avatars/mock-carol.jpg',
      viewerCount: 2500,
    ),
    LiveRoom(
      providerId: ProviderId.stripchat,
      roomId: 'dave_music',
      title: '',
      streamerName: 'dave_music',
      coverUrl: 'https://static-proxy.strpst.com/previews/mock-dave-small.jpg',
      areaName: 'Japan',
      streamerAvatarUrl:
          'https://static-proxy.strpst.com/avatars/mock-dave.jpg',
      viewerCount: 600,
    ),
  ];

  static final Map<String, LiveRoomDetail> _details = {
    for (final room in _rooms)
      room.roomId: LiveRoomDetail(
        providerId: ProviderId.stripchat,
        roomId: room.roomId,
        title: '${room.streamerName} Room',
        streamerName: room.streamerName,
        streamerAvatarUrl: room.streamerAvatarUrl,
        coverUrl: room.coverUrl,
        areaName: room.areaName,
        description: 'Welcome to ${room.streamerName} preview room.',
        sourceUrl: 'https://zh.stripchat.com/${room.roomId}',
        isLive: true,
        viewerCount: room.viewerCount,
        danmakuToken: const PreviewDanmakuToken(),
        metadata: {
          'modelId': room.roomId,
          'streamName': room.roomId,
          'cdnDomains': ['doppiocdn.net'],
        },
      ),
  };

  static final List<LivePlayQuality> _qualities = List.unmodifiable([
    LivePlayQuality(id: 'auto', label: 'Auto', isDefault: true, sortOrder: 0),
    LivePlayQuality(id: '720p', label: '720P', sortOrder: 720),
    LivePlayQuality(id: '480p', label: '480P', sortOrder: 480),
    LivePlayQuality(id: '240p', label: '240P', sortOrder: 240),
    LivePlayQuality(id: '160p', label: '160P', sortOrder: 160),
  ]);

  @override
  Future<List<LiveCategory>> fetchCategories() async {
    return _categories;
  }

  @override
  Future<PagedResponse<LiveRoom>> fetchCategoryRooms(
    LiveSubCategory category, {
    int page = 1,
  }) async {
    final filtered = _rooms
        .where((room) {
          return switch (category.id) {
            'tagLanguageChinese' => room.areaName == 'China',
            'tagLanguageUSModels' => room.areaName == 'United States',
            _ => true,
          };
        })
        .toList(growable: false);
    return PagedResponse(items: filtered, hasMore: false, page: page);
  }

  @override
  Future<PagedResponse<LiveRoom>> fetchRecommendRooms({int page = 1}) async {
    final items = [..._rooms]
      ..sort(
        (left, right) =>
            (right.viewerCount ?? 0).compareTo(left.viewerCount ?? 0),
      );
    return PagedResponse(items: items, hasMore: false, page: page);
  }

  @override
  Future<PagedResponse<LiveRoom>> searchRooms(
    String query, {
    int page = 1,
  }) async {
    final normalizedQuery = query.trim().toLowerCase();
    final filtered = _rooms
        .where((room) {
          if (normalizedQuery.isEmpty) {
            return true;
          }
          return room.streamerName.toLowerCase().contains(normalizedQuery) ||
              room.roomId.toLowerCase().contains(normalizedQuery);
        })
        .toList(growable: false);
    return PagedResponse(items: filtered, hasMore: false, page: page);
  }

  @override
  Future<LiveRoomDetail> fetchRoomDetail(String roomId) async {
    final detail = _details[roomId];
    if (detail == null) {
      throw ProviderParseException(
        providerId: ProviderId.stripchat,
        message: 'Preview stripchat room detail not found for $roomId.',
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
    final streamName = detail.metadata?['streamName']?.toString() ?? '100001';
    return [
      LivePlayUrl(
        url:
            'https://edge-hls.doppiocdn.com/hls/$streamName/master/${streamName}_${quality.id}.m3u8?minHeight=240&playlistType=lowLatency',
        headers: const {'referer': 'https://zh.stripchat.com/'},
        lineLabel: 'HLS ${quality.id}',
      ),
    ];
  }

  @override
  void close() {}
}
