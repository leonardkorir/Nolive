import 'package:live_core/live_core.dart';

import 'bilibili_auth_context.dart';
import 'bilibili_data_source.dart';
import 'bilibili_mapper.dart';
import 'bilibili_sign_service.dart';
import 'bilibili_transport.dart';

class BilibiliLiveDataSource implements BilibiliDataSource {
  BilibiliLiveDataSource({
    required BilibiliTransport transport,
    required BilibiliSignService signService,
    required BilibiliAuthContext authContext,
  })  : _transport = transport,
        _signService = signService,
        _authContext = authContext;

  final BilibiliTransport _transport;
  final BilibiliSignService _signService;
  final BilibiliAuthContext _authContext;

  @override
  Future<List<LiveCategory>> fetchCategories() async {
    final response = await _transport.getJson(
      'https://api.live.bilibili.com/room/v1/Area/getList',
      queryParameters: const {
        'need_entrance': '1',
        'parent_id': '0',
      },
      headers: await _signService.buildHeaders(),
    );

    return _asList(response['data']).map((item) {
      final category = _asMap(item);
      final id = category['id']?.toString() ?? '';
      final children = _asList(category['list'])
          .map((subItem) {
            final subCategory = _asMap(subItem);
            return LiveSubCategory(
              id: subCategory['id']?.toString() ?? '',
              parentId: subCategory['parent_id']?.toString() ?? id,
              name: subCategory['name']?.toString() ?? '',
              pic: subCategory['pic']?.toString(),
            );
          })
          .where((item) => item.id.isNotEmpty && item.name.isNotEmpty)
          .toList(growable: false);
      return LiveCategory(
        id: id,
        name: category['name']?.toString() ?? '',
        children: children,
      );
    }).where((item) {
      return item.id.isNotEmpty && item.name.isNotEmpty;
    }).toList(growable: false);
  }

  @override
  Future<PagedResponse<LiveRoom>> fetchCategoryRooms(
    LiveSubCategory category, {
    int page = 1,
  }) async {
    const baseUrl =
        'https://api.live.bilibili.com/xlive/web-interface/v1/second/getList';
    final accessId = await _signService.getAccessId();
    final signedUrl = StringBuffer(
      '$baseUrl?platform=web&parent_area_id=${category.parentId}&area_id=${category.id}&sort_type=&page=$page',
    );
    if (accessId.isNotEmpty) {
      signedUrl.write('&w_webid=$accessId');
    }
    final queryParameters = await _signService.signUrl(signedUrl.toString());
    final response = await _transport.getJson(
      baseUrl,
      queryParameters: queryParameters,
      headers: await _signService.buildHeaders(),
    );

    final data = _asMap(response['data']);
    final items = _asList(data['list'])
        .map((item) => _mapCategoryRoom(_asMap(item)))
        .where((item) => item.roomId.isNotEmpty)
        .toList(growable: false);
    final responseCode = _asInt(response['code']) ?? 0;

    if (responseCode == -352 || items.isEmpty) {
      return _fallbackCategoryRooms(category, page: page);
    }

    return PagedResponse(
      items: items,
      hasMore: (_asInt(data['has_more']) ?? 0) == 1,
      page: page,
    );
  }

  @override
  Future<PagedResponse<LiveRoom>> fetchRecommendRooms({int page = 1}) async {
    const baseUrl =
        'https://api.live.bilibili.com/xlive/web-interface/v1/second/getListByArea';
    final queryParameters = await _signService.signUrl(
      '$baseUrl?platform=web&sort=online&page_size=30&page=$page',
    );
    final response = await _transport.getJson(
      baseUrl,
      queryParameters: queryParameters,
      headers: await _signService.buildHeaders(),
    );
    final data = _asMap(response['data']);
    final items = _asList(data['list'])
        .map((item) => _mapCategoryRoom(_asMap(item)))
        .where((item) => item.roomId.isNotEmpty)
        .toList(growable: false);
    return PagedResponse(
      items: items,
      hasMore: items.isNotEmpty,
      page: page,
    );
  }

  @override
  Future<PagedResponse<LiveRoom>> searchRooms(String query,
      {int page = 1}) async {
    final response = await _transport.getJson(
      'https://api.bilibili.com/x/web-interface/search/type',
      queryParameters: {
        'context': '',
        'search_type': 'live',
        'cover_type': 'user_cover',
        'order': '',
        'keyword': query,
        'category_id': '',
        '__refresh__': '',
        '_extra': '',
        'highlight': '0',
        'single_column': '0',
        'page': page.toString(),
      },
      headers: await _signService.buildHeaders(),
    );

    return BilibiliMapper.mapSearchResponse(response, page: page);
  }

  Future<PagedResponse<LiveRoom>> _fallbackCategoryRooms(
    LiveSubCategory category, {
    required int page,
  }) async {
    final queries = <String>[category.name, '热门', ''];
    PagedResponse<LiveRoom>? genericCandidate;

    for (final query in queries) {
      try {
        final response = await searchRooms(query, page: page);
        if (response.items.isEmpty) {
          continue;
        }
        final filtered = _filterRoomsForCategory(response.items, category);
        if (filtered.isNotEmpty) {
          return PagedResponse(
            items: filtered,
            hasMore: response.hasMore,
            page: response.page,
          );
        }
        if (query == category.name) {
          return response;
        }
        genericCandidate ??= response;
      } catch (_) {
        continue;
      }
    }

    return genericCandidate ??
        PagedResponse(items: const [], hasMore: false, page: page);
  }

  List<LiveRoom> _filterRoomsForCategory(
    List<LiveRoom> rooms,
    LiveSubCategory category,
  ) {
    final keyword = _normalizeCategoryKeyword(category.name);
    if (keyword.isEmpty) {
      return const [];
    }
    return rooms.where((room) {
      final haystack = _normalizeCategoryKeyword(
        '${room.areaName ?? ''} ${room.title} ${room.streamerName}',
      );
      return haystack.contains(keyword);
    }).toList(growable: false);
  }

  String _normalizeCategoryKeyword(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[\s：:·•/\_\-]'), '');
  }

  @override
  Future<LiveRoomDetail> fetchRoomDetail(String roomId) async {
    final headers = await _signService.buildHeaders();

    const roomInfoBaseUrl =
        'https://api.live.bilibili.com/xlive/web-room/v1/index/getInfoByRoom';
    final roomInfoResponse = await _transport.getJson(
      roomInfoBaseUrl,
      queryParameters:
          await _signService.signUrl('$roomInfoBaseUrl?room_id=$roomId'),
      headers: headers,
    );
    final roomInfoData =
        (roomInfoResponse['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    final realRoomId =
        (roomInfoData['room_info'] as Map?)?['room_id']?.toString() ?? roomId;

    const danmakuBaseUrl =
        'https://api.live.bilibili.com/xlive/web-room/v1/index/getDanmuInfo';
    final danmakuResponse = await _transport.getJson(
      danmakuBaseUrl,
      queryParameters:
          await _signService.signUrl('$danmakuBaseUrl?id=$realRoomId'),
      headers: headers,
    );
    final danmakuData =
        (danmakuResponse['data'] as Map?)?.cast<String, dynamic>() ?? const {};

    return BilibiliMapper.mapRoomDetail(
      roomInfoData: roomInfoData,
      danmakuInfoData: danmakuData,
      requestedRoomId: roomId,
      buvid3: _signService.buvid3,
      cookie: _signService.cookie,
      userId: _authContext.userId,
    );
  }

  @override
  Future<List<LivePlayQuality>> fetchPlayQualities(
      LiveRoomDetail detail) async {
    final response = await _transport.getJson(
      'https://api.live.bilibili.com/xlive/web-room/v2/index/getRoomPlayInfo',
      queryParameters: {
        'room_id': detail.roomId,
        'protocol': '0,1',
        'format': '0,1,2',
        'codec': '0,1',
        'platform': 'web',
      },
      headers: await _signService.buildHeaders(),
    );

    return BilibiliMapper.mapPlayQualities(response);
  }

  @override
  Future<List<LivePlayUrl>> fetchPlayUrls({
    required LiveRoomDetail detail,
    required LivePlayQuality quality,
  }) async {
    final response = await _transport.getJson(
      'https://api.live.bilibili.com/xlive/web-room/v2/index/getRoomPlayInfo',
      queryParameters: {
        'room_id': detail.roomId,
        'protocol': '0,1',
        'format': '0,2',
        'codec': '0',
        'platform': 'web',
        'qn': quality.id,
      },
      headers: await _signService.buildHeaders(),
    );

    return BilibiliMapper.mapPlayUrls(response);
  }

  LiveRoom _mapCategoryRoom(Map<String, dynamic> item) {
    return LiveRoom(
      providerId: ProviderId.bilibili.value,
      roomId: item['roomid']?.toString() ?? '',
      title: item['title']?.toString() ?? '',
      streamerName: item['uname']?.toString() ?? '',
      coverUrl: item['cover']?.toString(),
      keyframeUrl: item['system_cover']?.toString(),
      areaName: item['area_name']?.toString(),
      streamerAvatarUrl: item['face']?.toString(),
      viewerCount: _asInt(item['online']),
      isLive: (_asInt(item['live_status']) ?? 1) == 1,
    );
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

  List<dynamic> _asList(Object? value) {
    if (value is List) {
      return value;
    }
    return const [];
  }

  int? _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    return int.tryParse(value?.toString() ?? '');
  }
}
