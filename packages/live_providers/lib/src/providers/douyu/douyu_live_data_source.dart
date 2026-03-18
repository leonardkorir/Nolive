import 'package:live_core/live_core.dart';

import 'douyu_data_source.dart';
import 'douyu_mapper.dart';
import 'douyu_sign_service.dart';
import 'douyu_transport.dart';

class DouyuLiveDataSource implements DouyuDataSource {
  DouyuLiveDataSource({
    required DouyuTransport transport,
    required DouyuSignService signService,
  })  : _transport = transport,
        _signService = signService;

  final DouyuTransport _transport;
  final DouyuSignService _signService;

  @override
  Future<List<LiveCategory>> fetchCategories() async {
    final response = await _transport.getJson(
      'https://m.douyu.com/api/cate/list',
    );
    final data = _asMap(response['data']);
    final subCategories = _asList(data['cate2Info']);
    final categories = _asList(data['cate1Info']).map((item) {
      final category = _asMap(item);
      final categoryId = category['cate1Id']?.toString() ?? '';
      final children = subCategories
          .map((subItem) => _asMap(subItem))
          .where((subItem) => subItem['cate1Id']?.toString() == categoryId)
          .map(
            (subItem) => LiveSubCategory(
              id: subItem['cate2Id']?.toString() ?? '',
              parentId: categoryId,
              name: subItem['cate2Name']?.toString() ?? '',
              pic: subItem['smallIcon']?.toString() ??
                  subItem['icon']?.toString() ??
                  subItem['pic']?.toString(),
            ),
          )
          .where((item) => item.id.isNotEmpty && item.name.isNotEmpty)
          .toList(growable: false);
      return LiveCategory(
        id: categoryId,
        name: category['cate1Name']?.toString() ?? '',
        children: children,
      );
    }).where((item) {
      return item.id.isNotEmpty && item.name.isNotEmpty;
    }).toList(growable: false)
      ..sort((left, right) {
        return (int.tryParse(left.id) ?? 0)
            .compareTo(int.tryParse(right.id) ?? 0);
      });
    return categories;
  }

  @override
  Future<PagedResponse<LiveRoom>> fetchCategoryRooms(
    LiveSubCategory category, {
    int page = 1,
  }) async {
    final response = await _transport.getJson(
      'https://www.douyu.com/gapi/rkc/directory/mixList/2_${category.id}/$page',
    );
    final data = _asMap(response['data']);
    final items = _asList(data['rl'])
        .map((item) => _asMap(item))
        .where((item) => item['type'] == 1)
        .map(_mapCategoryRoom)
        .where((item) => item.roomId.isNotEmpty)
        .toList(growable: false);

    return PagedResponse(
      items: items,
      hasMore: page < (_asInt(data['pgcnt']) ?? page),
      page: page,
    );
  }

  @override
  Future<PagedResponse<LiveRoom>> fetchRecommendRooms({int page = 1}) async {
    final response = await _transport.getJson(
      'https://www.douyu.com/japi/weblist/apinc/allpage/6/$page',
    );
    final data = _asMap(response['data']);
    final items = _asList(data['rl'])
        .map((item) => _asMap(item))
        .where((item) => item['type'] == 1)
        .map(_mapCategoryRoom)
        .where((item) => item.roomId.isNotEmpty)
        .toList(growable: false);
    return PagedResponse(
      items: items,
      hasMore: page < (_asInt(data['pgcnt']) ?? page),
      page: page,
    );
  }

  @override
  Future<PagedResponse<LiveRoom>> searchRooms(
    String query, {
    int page = 1,
  }) async {
    final response = await _transport.getJson(
      'https://www.douyu.com/japi/search/api/searchShow',
      queryParameters: {
        'kw': query,
        'page': page.toString(),
        'pageSize': '20',
      },
      headers: _signService.buildSearchHeaders(),
    );

    final errorCode = _asInt(response['error']) ?? 0;
    if (errorCode != 0) {
      throw ProviderParseException(
        providerId: ProviderId.douyu,
        message: response['msg']?.toString() ?? 'Douyu search request failed.',
      );
    }

    return DouyuMapper.mapSearchResponse(response, page: page);
  }

  @override
  Future<LiveRoomDetail> fetchRoomDetail(String roomId) async {
    final roomResponse = await _transport.getJson(
      'https://www.douyu.com/betard/$roomId',
      headers: _signService.buildRoomHeaders(roomId),
    );
    final roomInfo = DouyuMapper.extractRoomInfo(roomResponse);
    final realRoomId = roomInfo['room_id']?.toString() ?? roomId;
    final playContext = await _signService.buildPlayContext(realRoomId);

    return DouyuMapper.mapRoomDetail(
      roomInfo: roomInfo,
      requestedRoomId: roomId,
      playContext: playContext,
    );
  }

  @override
  Future<List<LivePlayQuality>> fetchPlayQualities(
    LiveRoomDetail detail,
  ) async {
    final playContext = await _resolvePlayContext(detail);
    final response = await _transport.postJson(
      'https://www.douyu.com/lapi/live/getH5Play/${detail.roomId}',
      body: _signService.extendPlayBody(
        playContext.body,
        cdn: '',
        rate: '-1',
      ),
      headers: _signService.buildPlayHeaders(
        detail.roomId,
        deviceId: playContext.deviceId,
      ),
    );

    return DouyuMapper.mapPlayQualities(response);
  }

  @override
  Future<List<LivePlayUrl>> fetchPlayUrls({
    required LiveRoomDetail detail,
    required LivePlayQuality quality,
  }) async {
    final playContext = await _resolvePlayContext(detail);
    final rate = (quality.metadata?['rate'] ?? quality.id).toString();
    final cdns = _extractCdns(quality);
    final urls = <LivePlayUrl>[];
    final headers = _signService.buildPlayHeaders(
      detail.roomId,
      deviceId: playContext.deviceId,
    );

    for (final cdn in cdns) {
      final response = await _transport.postJson(
        'https://www.douyu.com/lapi/live/getH5Play/${detail.roomId}',
        body: _signService.extendPlayBody(
          playContext.body,
          cdn: cdn,
          rate: rate,
        ),
        headers: headers,
      );
      urls.addAll(
        DouyuMapper.mapPlayUrls(
          response,
          headers: headers,
          lineLabel: cdn,
        ),
      );
    }

    final unique = <String, LivePlayUrl>{};
    for (final item in urls) {
      unique[item.url] = item;
    }
    return unique.values.toList(growable: false);
  }

  Future<DouyuSignedPlayContext> _resolvePlayContext(
    LiveRoomDetail detail,
  ) async {
    final metadata = detail.metadata ?? const <String, Object?>{};
    final body = metadata['playBody']?.toString() ?? '';
    final deviceId = metadata['deviceId']?.toString() ?? '';
    final timestamp = _asInt(metadata['signatureTimestamp']);
    if (body.isNotEmpty && deviceId.isNotEmpty) {
      return DouyuSignedPlayContext(
        body: body,
        deviceId: deviceId,
        timestamp: timestamp ?? 0,
        script: metadata['signScript']?.toString() ?? '',
      );
    }
    return _signService.buildPlayContext(detail.roomId);
  }

  List<String> _extractCdns(LivePlayQuality quality) {
    final raw = quality.metadata?['cdns'];
    if (raw is List) {
      return raw
          .map((item) => item?.toString() ?? '')
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }
    return const [''];
  }

  LiveRoom _mapCategoryRoom(Map<String, dynamic> item) {
    return LiveRoom(
      providerId: ProviderId.douyu.value,
      roomId: item['rid']?.toString() ?? '',
      title: normalizeDisplayText(item['rn']?.toString()),
      streamerName: normalizeDisplayText(item['nn']?.toString()),
      coverUrl: item['rs16']?.toString(),
      keyframeUrl: item['rs16']?.toString(),
      areaName: normalizeDisplayText(item['c2name_display']?.toString()),
      streamerAvatarUrl: _normalizeAvatarUrl(item['av']?.toString()),
      viewerCount: DouyuMapper.parseHotCount(item['ol']),
      isLive: true,
    );
  }

  String? _normalizeAvatarUrl(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    return 'https://apic.douyucdn.cn/upload/${value}_middle.jpg';
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
