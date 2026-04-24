import 'dart:convert';
import 'dart:async';

import 'package:live_core/live_core.dart';

import 'douyin_data_source.dart';
import 'douyin_mapper.dart';
import 'douyin_sign_service.dart';
import 'douyin_transport.dart';

class DouyinLiveDataSource implements DouyinDataSource {
  static const int _kCategoryPageSize = 15;
  static const int _kCategorySparsePageLookahead = 2;

  DouyinLiveDataSource({
    required DouyinTransport transport,
    required DouyinSignService signService,
    Duration roomDetailApiTimeout = const Duration(seconds: 4),
    Duration roomDetailHtmlTimeout = const Duration(seconds: 4),
  })  : _transport = transport,
        _signService = signService,
        _roomDetailApiTimeout = roomDetailApiTimeout,
        _roomDetailHtmlTimeout = roomDetailHtmlTimeout;

  final DouyinTransport _transport;
  final DouyinSignService _signService;
  final Duration _roomDetailApiTimeout;
  final Duration _roomDetailHtmlTimeout;

  static final RegExp _kRiskControlStatusPattern =
      RegExp(r'status (444|403|429)');

  Future<_DouyinRequestResult<T>> _requestWithRetry<T>({
    required Future<T> Function(Map<String, String> headers) request,
    String? refererPath,
    Map<String, String> headerOverrides = const {},
  }) async {
    var baseHeaders = await _signService.buildHeaders(refererPath: refererPath);
    var headers = {...baseHeaders, ...headerOverrides};

    try {
      final data = await request(headers);
      return _DouyinRequestResult(data: data, headers: headers);
    } on ProviderParseException catch (error) {
      if (!_kRiskControlStatusPattern.hasMatch(error.message)) {
        rethrow;
      }

      await Future<void>.delayed(const Duration(milliseconds: 600));
      baseHeaders = await _signService.buildHeaders(
        refererPath: refererPath,
        forceRefreshCookie: true,
      );
      headers = {...baseHeaders, ...headerOverrides};
      final data = await request(headers);
      return _DouyinRequestResult(data: data, headers: headers);
    }
  }

  @override
  Future<List<LiveCategory>> fetchCategories() async {
    final htmlResult = await _requestWithRetry(
      request: (headers) => _transport.getText(
        'https://live.douyin.com/',
        headers: headers,
      ),
    );
    final html = htmlResult.data;
    final renderData = RegExp(r'\{\\"pathname\\":\\"/\\",\\"categoryData.*?\],')
            .firstMatch(html)
            ?.group(0) ??
        '';
    if (renderData.isEmpty) {
      throw ProviderParseException(
        providerId: ProviderId.douyin,
        message: 'Unable to parse Douyin categories from homepage payload.',
      );
    }
    final decoded = jsonDecode(
      renderData
          .trim()
          .replaceAll('\\"', '"')
          .replaceAll(r'\\', r'\')
          .replaceAll('],', ''),
    ) as Map<String, dynamic>;

    return _asList(decoded['categoryData']).map((item) {
      final category = _asMap(item);
      final partition = _asMap(category['partition']);
      final categoryId =
          '${partition['id_str']?.toString() ?? ''},${partition['type']?.toString() ?? ''}';
      final children = _extractLeafSubCategories(
        _asList(category['sub_partition']),
        parentId: categoryId,
      ).toList(growable: true);
      final resolvedName = partition['title']?.toString() ?? '';
      if (categoryId.isNotEmpty && resolvedName.isNotEmpty) {
        children.insert(
          0,
          LiveSubCategory(
            id: categoryId,
            parentId: categoryId,
            name: resolvedName,
            pic: _partitionIconUrl(partition),
          ),
        );
      }
      return LiveCategory(
        id: categoryId,
        name: resolvedName,
        children: children.toList(growable: false),
      );
    }).where((item) {
      return item.id.isNotEmpty && item.name.isNotEmpty;
    }).toList(growable: false);
  }

  @override
  Future<PagedResponse<LiveRoom>> fetchRecommendRooms({int page = 1}) {
    return fetchCategoryRooms(
      const LiveSubCategory(id: '720,1', parentId: '720,1', name: '热门'),
      page: page,
    );
  }

  @override
  Future<PagedResponse<LiveRoom>> fetchCategoryRooms(
    LiveSubCategory category, {
    int page = 1,
  }) async {
    final normalizedPage = page < 1 ? 1 : page;
    var resolvedPage = await _fetchCategoryRoomsPage(
      category,
      requestOffset: (normalizedPage - 1) * _kCategoryPageSize,
    );
    for (var attempt = 0;
        attempt < _kCategorySparsePageLookahead &&
            resolvedPage.items.isEmpty &&
            resolvedPage.nextOffset > resolvedPage.requestOffset;
        attempt += 1) {
      resolvedPage = await _fetchCategoryRoomsPage(
        category,
        requestOffset: resolvedPage.nextOffset,
      );
    }
    return PagedResponse(
      items: resolvedPage.items,
      hasMore: resolvedPage.hasMore,
      page: (resolvedPage.requestOffset ~/ _kCategoryPageSize) + 1,
    );
  }

  Future<_DouyinCategoryRoomsPage> _fetchCategoryRoomsPage(
    LiveSubCategory category, {
    required int requestOffset,
  }) async {
    final ids = category.id.split(',');
    final partitionId = ids.isNotEmpty ? ids.first : category.id;
    final partitionType = ids.length > 1 ? ids[1] : '1';
    final requestUrl = _signService.buildSignedUrl(
      'https://live.douyin.com/webcast/web/partition/detail/room/v2/',
      {
        'aid': '6383',
        'app_name': 'douyin_web',
        'live_id': '1',
        'device_platform': 'web',
        'language': 'zh-CN',
        'enter_from': 'link_share',
        'cookie_enabled': 'true',
        'screen_width': '1980',
        'screen_height': '1080',
        'browser_language': 'zh-CN',
        'browser_platform': 'Win32',
        'browser_name': 'Edge',
        'browser_version': '125.0.0.0',
        'browser_online': 'true',
        'count': '$_kCategoryPageSize',
        'offset': '$requestOffset',
        'partition': partitionId,
        'partition_type': partitionType,
        'req_from': '2',
      },
    );
    final responseResult = await _requestWithRetry(
      request: (headers) => _transport.getJson(
        requestUrl,
        headers: headers,
      ),
    );
    final response = responseResult.data;
    final data = _asMap(response['data']);
    final itemsRaw = _asList(data['data']);
    final items = itemsRaw
        .map((item) => _mapCategoryRoom(_asMap(item)))
        .where((item) => item.roomId.isNotEmpty)
        .toList(growable: false);
    return _DouyinCategoryRoomsPage(
      requestOffset: requestOffset,
      nextOffset: _asInt(data['offset']) ?? requestOffset,
      items: items,
      hasMore: itemsRaw.length >= _kCategoryPageSize,
    );
  }

  @override
  Future<PagedResponse<LiveRoom>> searchRooms(String query,
      {int page = 1}) async {
    final requestUrl = _signService.buildSignedUrl(
      'https://www.douyin.com/aweme/v1/web/live/search/',
      {
        'device_platform': 'webapp',
        'aid': '6383',
        'channel': 'channel_pc_web',
        'search_channel': 'aweme_live',
        'keyword': query,
        'search_source': 'switch_tab',
        'query_correct_type': '1',
        'is_filter_search': '0',
        'from_group_id': '',
        'offset': '${(page - 1) * 10}',
        'count': '10',
        'pc_client_type': '1',
        'version_code': '170400',
        'version_name': '17.4.0',
        'cookie_enabled': 'true',
        'screen_width': '1980',
        'screen_height': '1080',
        'browser_language': 'zh-CN',
        'browser_platform': 'Win32',
        'browser_name': 'Edge',
        'browser_version': '125.0.0.0',
        'browser_online': 'true',
        'engine_name': 'Blink',
        'engine_version': '125.0.0.0',
        'os_name': 'Windows',
        'os_version': '10',
        'cpu_core_num': '12',
        'device_memory': '8',
        'platform': 'PC',
        'downlink': '10',
        'effective_type': '4g',
        'round_trip_time': '100',
        'webid': '7382872326016435738',
      },
    );
    final responseResult = await _requestWithRetry(
      headerOverrides: {
        'referer':
            'https://www.douyin.com/search/${Uri.encodeComponent(query)}?type=live',
      },
      request: (headers) => _transport.getJson(
        requestUrl,
        headers: headers,
      ),
    );
    final response = responseResult.data;
    if (_asInt(response['status_code']) != 0) {
      throw ProviderParseException(
        providerId: ProviderId.douyin,
        message: response['status_msg']?.toString() ??
            'Douyin search request failed.',
      );
    }
    final mapped = DouyinMapper.mapSearchResponse(response, page: page);
    if (mapped.items.isNotEmpty) {
      return mapped;
    }
    return _searchRoomsFromFeed(query, page: page);
  }

  Future<PagedResponse<LiveRoom>> _searchRoomsFromFeed(
    String query, {
    required int page,
  }) async {
    const pageSize = 10;
    const fetchBatchSize = 50;

    final responseResult = await _requestWithRetry(
      request: (headers) => _transport.getJson(
        'https://live.douyin.com/webcast/feed/',
        queryParameters: const {
          'aid': '6383',
          'app_name': 'douyin_web',
          'need_map': '1',
          'is_draw': '1',
          'inner_from_drawer': '0',
          'enter_source': 'web_homepage_hot_web_live_card',
          'source_key': 'web_homepage_hot_web_live_card',
          'count': '$fetchBatchSize',
        },
        headers: headers,
      ),
    );
    final response = responseResult.data;
    final rawItems = _asList(response['data']);
    final rooms = rawItems
        .map((item) {
          final data = _asMap(_asMap(item)['data']);
          final owner = _asMap(data['owner']);
          final cover = _asMap(data['cover']);
          return LiveRoom(
            providerId: ProviderId.douyin.value,
            roomId: owner['web_rid']?.toString() ?? '',
            title: normalizeDisplayText(data['title']?.toString()),
            streamerName: normalizeDisplayText(owner['nickname']?.toString()),
            coverUrl: _firstUrl(cover),
            keyframeUrl: _firstUrl(cover),
            areaName: '',
            streamerAvatarUrl: _firstUrl(_asMap(owner['avatar_thumb'])),
            viewerCount:
                _asInt(_asMap(data['room_view_stats'])['display_value']),
            isLive: true,
          );
        })
        .where((item) => item.roomId.isNotEmpty)
        .toList(growable: false);

    final normalized = query.trim().toLowerCase();
    final filtered = normalized.isEmpty
        ? rooms
        : rooms.where((room) {
            return room.title.toLowerCase().contains(normalized) ||
                room.streamerName.toLowerCase().contains(normalized);
          }).toList(growable: false);

    final start = (page - 1) * pageSize;
    final end = start + pageSize;
    final resolved = start >= filtered.length
        ? const <LiveRoom>[]
        : filtered.sublist(
            start, end > filtered.length ? filtered.length : end);
    return PagedResponse(
      items: resolved,
      hasMore: filtered.length > end,
      page: page,
    );
  }

  @override
  Future<LiveRoomDetail> fetchRoomDetail(String roomId) async {
    if (roomId.length > 16) {
      return _fetchRoomDetailByRoomId(roomId);
    }
    return _fetchRoomDetailByWebRid(roomId);
  }

  Future<LiveRoomDetail> _fetchRoomDetailByRoomId(String roomId) async {
    final responseResult = await _requestWithRetry(
      request: (headers) => _transport.getJson(
        'https://webcast.amemv.com/webcast/room/reflow/info/',
        queryParameters: {
          'type_id': '0',
          'live_id': '1',
          'room_id': roomId,
          'sec_user_id': '',
          'version_code': '99.99.99',
          'app_id': '6383',
        },
        headers: headers,
      ),
    );
    final response = responseResult.data;
    final headers = responseResult.headers;
    final room = _asMap(_asMap(response['data'])['room']);
    final owner = _asMap(room['owner']);
    final webRid = owner['web_rid']?.toString() ?? roomId;
    return DouyinMapper.mapRoomDetailFromApi(
      {
        'data': [room],
        'user': _asMap(_asMap(response['data'])['owner']),
        'partition_road_map': const {},
      },
      webRid: webRid,
      cookie: headers['cookie'] ?? '',
    );
  }

  Future<LiveRoomDetail> _fetchRoomDetailByWebRid(String webRid) async {
    LiveRoomDetail? apiDetail;
    Object? apiError;
    try {
      apiDetail = await _fetchRoomDetailByWebRidViaApi(webRid)
          .timeout(_roomDetailApiTimeout);
      if (_hasUsablePlaybackMetadata(apiDetail)) {
        return apiDetail;
      }
    } catch (error) {
      apiError = error;
    }

    try {
      final htmlDetail = await _fetchRoomDetailByWebRidViaHtml(webRid)
          .timeout(_roomDetailHtmlTimeout);
      if (_hasUsablePlaybackMetadata(htmlDetail)) {
        return htmlDetail;
      }
      return apiDetail ?? htmlDetail;
    } catch (htmlError) {
      if (apiDetail != null) {
        return apiDetail;
      }
      if (apiError != null) {
        Error.throwWithStackTrace(
          _wrapRoomDetailError(apiError, webRid: webRid, stage: 'web-enter'),
          StackTrace.current,
        );
      }
      Error.throwWithStackTrace(
        _wrapRoomDetailError(htmlError, webRid: webRid, stage: 'html'),
        StackTrace.current,
      );
    }
  }

  Future<LiveRoomDetail> _fetchRoomDetailByWebRidViaApi(String webRid) async {
    final requestUrl = _signService.buildSignedUrl(
      'https://live.douyin.com/webcast/room/web/enter/',
      {
        'app_name': 'douyin_web',
        'enter_from': 'web_live',
        'live_id': '1',
        'web_rid': webRid,
        'is_need_double_stream': 'false',
      },
    );
    final responseResult = await _requestWithRetry(
      refererPath: webRid,
      request: (headers) => _transport.getJson(
        requestUrl,
        headers: headers,
      ),
    );
    return DouyinMapper.mapRoomDetailFromApi(
      _asMap(responseResult.data['data']),
      webRid: webRid,
      cookie: responseResult.headers['cookie'] ?? '',
    );
  }

  Future<LiveRoomDetail> _fetchRoomDetailByWebRidViaHtml(String webRid) async {
    final htmlResult = await _requestWithRetry(
      refererPath: webRid,
      request: (headers) => _transport.getText(
        'https://live.douyin.com/$webRid',
        headers: headers,
      ),
    );
    final state = DouyinMapper.parseHtmlState(htmlResult.data);
    return DouyinMapper.mapRoomDetailFromHtml(
      state,
      webRid: webRid,
      cookie: htmlResult.headers['cookie'] ?? '',
    );
  }

  bool _hasUsablePlaybackMetadata(LiveRoomDetail detail) {
    if (!detail.isLive) {
      return true;
    }
    return _asMap(detail.metadata?['streamUrl']).isNotEmpty;
  }

  ProviderParseException _wrapRoomDetailError(
    Object error, {
    required String webRid,
    required String stage,
  }) {
    if (error is ProviderParseException) {
      return error;
    }
    if (error is TimeoutException) {
      return ProviderParseException(
        providerId: ProviderId.douyin,
        message:
            'Douyin room detail request timed out at $stage for web_rid=$webRid.',
      );
    }
    return ProviderParseException(
      providerId: ProviderId.douyin,
      message: 'Douyin room detail request failed at $stage for web_rid=$webRid: $error',
    );
  }

  @override
  Future<List<LivePlayQuality>> fetchPlayQualities(
      LiveRoomDetail detail) async {
    return DouyinMapper.mapPlayQualities(detail);
  }

  @override
  Future<List<LivePlayUrl>> fetchPlayUrls({
    required LiveRoomDetail detail,
    required LivePlayQuality quality,
  }) async {
    return DouyinMapper.mapPlayUrls(quality);
  }

  LiveRoom _mapCategoryRoom(Map<String, dynamic> item) {
    final room = _asMap(item['room']);
    final owner = _asMap(room['owner']);
    return LiveRoom(
      providerId: ProviderId.douyin.value,
      roomId: item['web_rid']?.toString() ?? owner['web_rid']?.toString() ?? '',
      title: normalizeDisplayText(room['title']?.toString()),
      streamerName: normalizeDisplayText(owner['nickname']?.toString()),
      coverUrl: _firstUrl(_asMap(room['cover'])),
      keyframeUrl: _firstUrl(_asMap(room['cover'])),
      areaName: normalizeDisplayText(
        item['tag_name']?.toString() ?? categoryNameFromRoom(room),
      ),
      streamerAvatarUrl: _firstUrl(_asMap(owner['avatar_medium'])),
      viewerCount: _asInt(_asMap(room['room_view_stats'])['display_value']),
      isLive: true,
    );
  }

  String categoryNameFromRoom(Map<String, dynamic> room) {
    final partitionRoadMap = _asMap(room['partition_road_map']);
    return normalizeDisplayText(
      _asMap(partitionRoadMap['partition'])['title']?.toString(),
    );
  }

  List<LiveSubCategory> _extractLeafSubCategories(
    List<dynamic> rawItems, {
    required String parentId,
  }) {
    final items = <LiveSubCategory>[];
    final seen = <String>{};

    void visit(Object? raw) {
      final item = _asMap(raw);
      if (item.isEmpty) {
        return;
      }
      final partition = _asMap(item['partition']);
      final nested = _asList(item['sub_partition']);
      if (nested.isNotEmpty) {
        for (final child in nested) {
          visit(child);
        }
        return;
      }
      final id =
          '${partition['id_str']?.toString() ?? ''},${partition['type']?.toString() ?? ''}';
      final name = partition['title']?.toString() ?? '';
      if (id.isEmpty || name.isEmpty || !seen.add(id)) {
        return;
      }
      items.add(
        LiveSubCategory(
          id: id,
          parentId: parentId,
          name: name,
          pic: _partitionIconUrl(partition),
        ),
      );
    }

    for (final raw in rawItems) {
      visit(raw);
    }
    return items;
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

  int? _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is double) {
      return value.round();
    }
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) {
      return null;
    }
    final normalized = raw.replaceAll(',', '');
    final match =
        RegExp(r'^([0-9]+(?:\.[0-9]+)?)([万亿]?)$').firstMatch(normalized);
    if (match != null) {
      final number = double.tryParse(match.group(1) ?? '');
      if (number == null) {
        return null;
      }
      final unit = match.group(2);
      final multiplier = switch (unit) {
        '万' => 10000,
        '亿' => 100000000,
        _ => 1,
      };
      return (number * multiplier).round();
    }
    return int.tryParse(normalized);
  }

  List<dynamic> _asList(Object? value) {
    if (value is List) {
      return value;
    }
    return const [];
  }

  String? _firstUrl(Map<String, dynamic> value) {
    final list = _asList(value['url_list']);
    if (list.isEmpty) {
      return null;
    }
    return list.first?.toString();
  }

  String? _partitionIconUrl(Map<String, dynamic> partition) {
    final icon = _asMap(partition['icon']);
    final nested = _firstUrl(icon);
    if (nested != null && nested.isNotEmpty) {
      return nested;
    }
    final directUrl = icon['url']?.toString().trim();
    if (directUrl != null && directUrl.isNotEmpty) {
      return directUrl;
    }
    final directUri = icon['uri']?.toString().trim();
    if (directUri != null && directUri.isNotEmpty) {
      return directUri;
    }
    final raw = partition['icon']?.toString().trim();
    if (raw == null || raw.isEmpty || raw == '{}') {
      return null;
    }
    return raw;
  }
}

class _DouyinRequestResult<T> {
  const _DouyinRequestResult({required this.data, required this.headers});

  final T data;
  final Map<String, String> headers;
}

class _DouyinCategoryRoomsPage {
  const _DouyinCategoryRoomsPage({
    required this.requestOffset,
    required this.nextOffset,
    required this.items,
    required this.hasMore,
  });

  final int requestOffset;
  final int nextOffset;
  final List<LiveRoom> items;
  final bool hasMore;
}
