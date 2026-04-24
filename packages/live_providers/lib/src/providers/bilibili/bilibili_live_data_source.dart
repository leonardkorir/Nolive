import 'package:live_core/live_core.dart';

import 'bilibili_auth_context.dart';
import 'bilibili_data_source.dart';
import 'bilibili_mapper.dart';
import 'bilibili_sign_service.dart';
import 'bilibili_transport.dart';

class BilibiliLiveDataSource implements BilibiliDataSource {
  static const int _recommendFallbackCategoryProbeLimit = 6;
  static const int _recommendFallbackRoomTarget = 30;
  static const String _roomPlayInfoWebLocation = '444.8';

  BilibiliLiveDataSource({
    required BilibiliTransport transport,
    required BilibiliSignService signService,
    required BilibiliAuthContext authContext,
  })  : _transport = transport,
        _signService = signService;

  final BilibiliTransport _transport;
  final BilibiliSignService _signService;

  @override
  Future<List<LiveCategory>> fetchCategories() async {
    final response = ensureBilibiliSuccess(
      await _transport.getJson(
        'https://api.live.bilibili.com/room/v1/Area/getList',
        queryParameters: const {
          'need_entrance': '1',
          'parent_id': '0',
        },
        headers: await _signService.buildHeaders(),
      ),
      operation: 'fetch categories',
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
              name: normalizeDisplayText(subCategory['name']?.toString()),
              pic: subCategory['pic']?.toString(),
            );
          })
          .where((item) => item.id.isNotEmpty && item.name.isNotEmpty)
          .toList(growable: false);
      return LiveCategory(
        id: id,
        name: normalizeDisplayText(category['name']?.toString()),
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
    try {
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

      if (responseCode == -352 || (responseCode == 0 && items.isEmpty)) {
        return _fallbackCategoryRooms(category, page: page);
      }
      ensureBilibiliSuccess(response, operation: 'fetch category rooms');

      return PagedResponse(
        items: items,
        hasMore: (_asInt(data['has_more']) ?? 0) == 1,
        page: page,
      );
    } on ProviderParseException catch (error) {
      if (!_shouldFallbackSignedRoomLists(error)) {
        rethrow;
      }
      return _fallbackCategoryRooms(category, page: page);
    }
  }

  @override
  Future<PagedResponse<LiveRoom>> fetchRecommendRooms({int page = 1}) async {
    try {
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
      final responseCode = bilibiliResponseCode(response);
      final items = _asList(data['list'])
          .map((item) => _mapCategoryRoom(_asMap(item)))
          .where((item) => item.roomId.isNotEmpty)
          .toList(growable: false);
      if (responseCode == -352 || (responseCode == 0 && items.isEmpty)) {
        return _fallbackRecommendRooms(page: page);
      }
      ensureBilibiliSuccess(response, operation: 'fetch recommend rooms');
      return PagedResponse(
        items: items,
        hasMore: items.isNotEmpty,
        page: page,
      );
    } on ProviderParseException catch (error) {
      if (!_shouldFallbackSignedRoomLists(error)) {
        rethrow;
      }
      return _fallbackRecommendRooms(page: page);
    }
  }

  @override
  Future<PagedResponse<LiveRoom>> searchRooms(String query,
      {int page = 1}) async {
    final response = ensureBilibiliSuccess(
      await _transport.getJson(
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
      ),
      operation: 'search rooms',
    );

    return BilibiliMapper.mapSearchResponse(response, page: page);
  }

  Future<PagedResponse<LiveRoom>> _fallbackRecommendRooms({
    required int page,
  }) async {
    final merged = <String, LiveRoom>{};
    var hasMore = false;
    try {
      final categories = await fetchCategories();
      final candidates = categories
          .expand((item) => item.children)
          .where((item) => item.id.isNotEmpty && item.parentId.isNotEmpty)
          .take(_recommendFallbackCategoryProbeLimit);
      for (final category in candidates) {
        try {
          final response = await fetchCategoryRooms(category, page: page);
          hasMore = hasMore || response.hasMore;
          for (final room in response.items) {
            merged.putIfAbsent('${room.providerId}:${room.roomId}', () => room);
          }
          if (merged.length >= _recommendFallbackRoomTarget) {
            break;
          }
        } catch (_) {
          continue;
        }
      }
    } catch (_) {
      // Ignore and continue to the final search fallback below.
    }

    if (merged.isNotEmpty) {
      final items = merged.values.toList(growable: false)
        ..sort((left, right) {
          final popularity =
              (right.viewerCount ?? -1).compareTo(left.viewerCount ?? -1);
          if (popularity != 0) {
            return popularity;
          }
          return left.roomId.compareTo(right.roomId);
        });
      return PagedResponse(
        items: items,
        hasMore: hasMore,
        page: page,
      );
    }

    const searchQueries = <String>['热门', '直播'];
    for (final query in searchQueries) {
      try {
        final response = await searchRooms(query, page: page);
        if (response.items.isNotEmpty) {
          return response;
        }
      } catch (_) {
        continue;
      }
    }
    return PagedResponse(items: const [], hasMore: false, page: page);
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
    final roomInfoHeaders = await _signService.buildHeaders();

    const roomInfoBaseUrl =
        'https://api.live.bilibili.com/xlive/web-room/v1/index/getInfoByRoom';
    final roomInfoResponse = ensureBilibiliSuccess(
      await _transport.getJson(
        roomInfoBaseUrl,
        queryParameters:
            await _signService.signUrl('$roomInfoBaseUrl?room_id=$roomId'),
        headers: roomInfoHeaders,
      ),
      operation: 'fetch room detail',
    );
    final roomInfoData =
        (roomInfoResponse['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    final realRoomId =
        (roomInfoData['room_info'] as Map?)?['room_id']?.toString() ?? roomId;

    Map<String, dynamic> danmakuData;
    try {
      danmakuData = await _fetchDanmakuInfo(realRoomId);
    } catch (error) {
      danmakuData = {
        'mode': 'unavailable',
        'reason': '哔哩哔哩当前房间暂未拿到可用弹幕连接参数，请稍后刷新重试。',
        'cause': error.toString(),
      };
    }

    return BilibiliMapper.mapRoomDetail(
      roomInfoData: roomInfoData,
      danmakuInfoData: danmakuData,
      requestedRoomId: roomId,
      buvid3: _signService.buvid3,
      cookie: _signService.cookie,
      userId: _signService.userId,
    );
  }

  @override
  Future<List<LivePlayQuality>> fetchPlayQualities(
      LiveRoomDetail detail) async {
    final response = await _fetchRoomPlayInfo(
      detail: detail,
      operation: 'fetch play qualities',
    );

    return BilibiliMapper.mapPlayQualities(response);
  }

  @override
  Future<List<LivePlayUrl>> fetchPlayUrls({
    required LiveRoomDetail detail,
    required LivePlayQuality quality,
  }) async {
    final response = await _fetchRoomPlayInfo(
      detail: detail,
      qualityId: quality.id,
      operation: 'fetch play urls',
    );

    return BilibiliMapper.mapPlayUrls(response);
  }

  Future<Map<String, dynamic>> _fetchRoomPlayInfo({
    required LiveRoomDetail detail,
    required String operation,
    String? qualityId,
  }) async {
    const endpoint =
        'https://api.live.bilibili.com/xlive/web-room/v2/index/getRoomPlayInfo';
    final requestedQn = int.tryParse(qualityId ?? '');
    final queryCandidates = _buildRoomPlayInfoQueryCandidates(
      roomId: detail.roomId,
      qualityId: qualityId,
    );
    Map<String, dynamic>? fallbackResponse;
    var fallbackQn = -1;
    var allowAccountHeaders = _signService.cookie.trim().isNotEmpty;

    for (final queryParameters in queryCandidates) {
      final result = await _requestRoomPlayInfo(
        endpoint: endpoint,
        operation: operation,
        queryParameters: queryParameters,
        allowAccountHeaders: allowAccountHeaders,
      );
      allowAccountHeaders = allowAccountHeaders && !result.authRejected;
      if (requestedQn == null ||
          _responseHasExactRequestedQn(result.response, requestedQn)) {
        return result.response;
      }
      final bestReturnedQn = _bestReturnedPlayInfoQn(result.response);
      if (fallbackResponse == null || bestReturnedQn > fallbackQn) {
        fallbackResponse = result.response;
        fallbackQn = bestReturnedQn;
      }
    }

    return fallbackResponse ?? const <String, dynamic>{};
  }

  LiveRoom _mapCategoryRoom(Map<String, dynamic> item) {
    return LiveRoom(
      providerId: ProviderId.bilibili.value,
      roomId: item['roomid']?.toString() ?? '',
      title: normalizeDisplayText(item['title']?.toString()),
      streamerName: normalizeDisplayText(item['uname']?.toString()),
      coverUrl: item['cover']?.toString(),
      keyframeUrl: item['system_cover']?.toString(),
      areaName: normalizeDisplayText(item['area_name']?.toString()),
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

  bool _shouldFallbackSignedRoomLists(ProviderParseException error) {
    final message = error.message.toLowerCase();
    return message.contains('load wbi keys failed') ||
        message.contains('load buvid failed') ||
        message.contains('fetch recommend rooms failed') ||
        message.contains('fetch category rooms failed');
  }

  bool _shouldRetryPlayInfoAnonymously(ProviderParseException error) {
    final message = error.message.toLowerCase();
    return message.contains('code -101') ||
        message.contains('账号未登录') ||
        message.contains('not login');
  }

  Future<Map<String, dynamic>> _fetchDanmakuInfo(String roomId) async {
    const endpoint =
        'https://api.live.bilibili.com/xlive/web-room/v1/index/getDanmuInfo';
    final queryParameters = await _signService.signUrl('$endpoint?id=$roomId');

    if (_signService.cookie.trim().isNotEmpty) {
      try {
        final response = ensureBilibiliSuccess(
          await _transport.getJson(
            endpoint,
            queryParameters: queryParameters,
            headers: await _signService.buildAccountHeaders(),
          ),
          operation: 'fetch danmaku info',
        );
        return _asMap(response['data']);
      } on ProviderParseException catch (error) {
        if (!_shouldRetryDanmakuInfoAnonymously(error)) {
          rethrow;
        }
      }
    }

    final response = ensureBilibiliSuccess(
      await _transport.getJson(
        endpoint,
        queryParameters: queryParameters,
        headers: await _signService.buildHeaders(),
      ),
      operation: 'fetch danmaku info',
    );
    return _asMap(response['data']);
  }

  List<Map<String, String>> _buildRoomPlayInfoQueryCandidates({
    required String roomId,
    String? qualityId,
  }) {
    final broadHtml5 = <String, String>{
      'room_id': roomId,
      'protocol': '0,1',
      'format': '0,1,2',
      'codec': '0,1',
      'platform': 'html5',
      'dolby': '5',
      'web_location': _roomPlayInfoWebLocation,
      if (qualityId != null) 'qn': qualityId,
    };
    if (qualityId == null) {
      return [broadHtml5];
    }
    return [
      broadHtml5,
      <String, String>{
        'room_id': roomId,
        'protocol': '0,1',
        'format': '0,1,2',
        'codec': '0,1',
        'platform': 'web',
        'dolby': '5',
        'web_location': _roomPlayInfoWebLocation,
        'qn': qualityId,
      },
      <String, String>{
        'room_id': roomId,
        'protocol': '0,1',
        'format': '0,2',
        'codec': '0',
        'platform': 'web',
        'qn': qualityId,
      },
    ];
  }

  Future<({Map<String, dynamic> response, bool authRejected})>
      _requestRoomPlayInfo({
    required String endpoint,
    required String operation,
    required Map<String, String> queryParameters,
    required bool allowAccountHeaders,
  }) async {
    if (allowAccountHeaders) {
      try {
        final response = ensureBilibiliSuccess(
          await _transport.getJson(
            endpoint,
            queryParameters: queryParameters,
            headers: await _signService.buildAccountHeaders(),
          ),
          operation: operation,
        );
        return (response: response, authRejected: false);
      } on ProviderParseException catch (error) {
        if (!_shouldRetryPlayInfoAnonymously(error)) {
          rethrow;
        }
      }
    }

    final response = ensureBilibiliSuccess(
      await _transport.getJson(
        endpoint,
        queryParameters: queryParameters,
        headers: await _signService.buildHeaders(),
      ),
      operation: operation,
    );
    return (response: response, authRejected: allowAccountHeaders);
  }

  bool _responseHasExactRequestedQn(
    Map<String, dynamic> response,
    int requestedQn,
  ) {
    for (final item in BilibiliMapper.mapPlayUrls(response)) {
      final effectiveQn =
          _asInt(item.metadata?['expectedQn']) ?? _asInt(item.metadata?['qn']);
      if (effectiveQn == requestedQn) {
        return true;
      }
    }
    return false;
  }

  int _bestReturnedPlayInfoQn(Map<String, dynamic> response) {
    var best = -1;
    for (final item in BilibiliMapper.mapPlayUrls(response)) {
      final effectiveQn =
          _asInt(item.metadata?['expectedQn']) ?? _asInt(item.metadata?['qn']);
      if (effectiveQn != null && effectiveQn > best) {
        best = effectiveQn;
      }
    }
    return best;
  }

  bool _shouldRetryDanmakuInfoAnonymously(ProviderParseException error) {
    final message = error.message.toLowerCase();
    return message.contains('code -101') ||
        message.contains('账号未登录') ||
        message.contains('not login');
  }
}
