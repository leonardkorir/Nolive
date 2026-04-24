import 'package:live_core/live_core.dart';

import 'huya_data_source.dart';
import 'huya_mapper.dart';
import 'huya_sign_service.dart';
import 'huya_transport.dart';

class HuyaLiveDataSource implements HuyaDataSource {
  HuyaLiveDataSource({
    required HuyaTransport transport,
    required HuyaSignService signService,
  })  : _transport = transport,
        _signService = signService;

  final HuyaTransport _transport;
  final HuyaSignService _signService;

  static const List<({String id, String name})> _rootCategories = [
    (id: '1', name: '网游'),
    (id: '2', name: '单机'),
    (id: '8', name: '娱乐'),
    (id: '3', name: '手游'),
  ];

  @override
  Future<List<LiveCategory>> fetchCategories() async {
    final categories = <LiveCategory>[];
    for (final item in _rootCategories) {
      final children = await _fetchSubCategories(item.id);
      categories.add(
        LiveCategory(
          id: item.id,
          name: item.name,
          children: children,
        ),
      );
    }
    return categories;
  }

  @override
  Future<PagedResponse<LiveRoom>> fetchCategoryRooms(
    LiveSubCategory category, {
    int page = 1,
  }) async {
    final response = await _transport.getJson(
      'https://www.huya.com/cache.php',
      queryParameters: {
        'm': 'LiveList',
        'do': 'getLiveListByPage',
        'tagAll': '0',
        'gameId': category.id,
        'page': page.toString(),
      },
    );
    final data = _asMap(response['data']);
    final items = _asList(data['datas'])
        .map((item) => _mapCategoryRoom(_asMap(item)))
        .where((item) => item.roomId.isNotEmpty)
        .toList(growable: false);
    return PagedResponse(
      items: items,
      hasMore: (_asInt(data['page']) ?? 1) < (_asInt(data['totalPage']) ?? 1),
      page: page,
    );
  }

  @override
  Future<PagedResponse<LiveRoom>> fetchRecommendRooms({int page = 1}) async {
    final response = await _transport.getJson(
      'https://www.huya.com/cache.php',
      queryParameters: {
        'm': 'LiveList',
        'do': 'getLiveListByPage',
        'tagAll': '0',
        'page': page.toString(),
      },
    );
    final data = _asMap(response['data']);
    final items = _asList(data['datas'])
        .map((item) => _mapCategoryRoom(_asMap(item)))
        .where((item) => item.roomId.isNotEmpty)
        .toList(growable: false);
    return PagedResponse(
      items: items,
      hasMore: (_asInt(data['page']) ?? 1) < (_asInt(data['totalPage']) ?? 1),
      page: page,
    );
  }

  @override
  Future<PagedResponse<LiveRoom>> searchRooms(String query,
      {int page = 1}) async {
    final text = await _transport.getText(
      'https://search.cdn.huya.com/',
      queryParameters: {
        'm': 'Search',
        'do': 'getSearchContent',
        'q': query,
        'uid': '0',
        'v': '4',
        'typ': '-5',
        'livestate': '0',
        'rows': '20',
        'start': '${(page - 1) * 20}',
      },
    );
    return HuyaMapper.mapSearchResponse(text, page: page);
  }

  @override
  Future<LiveRoomDetail> fetchRoomDetail(String roomId) async {
    final html = await _transport.getText(
      'https://www.huya.com/$roomId',
      headers: {'user-agent': HttpHuyaSignService.playerUserAgent},
    );
    return HuyaMapper.mapRoomDetail(html, requestedRoomId: roomId);
  }

  @override
  Future<List<LivePlayQuality>> fetchPlayQualities(
      LiveRoomDetail detail) async {
    return HuyaMapper.mapPlayQualities(detail);
  }

  @override
  Future<List<LivePlayUrl>> fetchPlayUrls({
    required LiveRoomDetail detail,
    required LivePlayQuality quality,
  }) async {
    final linesRaw = quality.metadata?['lines'];
    final lines = linesRaw is List ? linesRaw : const [];
    final urls = <LivePlayUrl>[];
    final bitRate = int.tryParse(quality.id) ?? 0;
    for (final item in lines) {
      final line = item is Map<String, Object?>
          ? item
          : item is Map
              ? item.cast<String, Object?>()
              : const <String, Object?>{};
      if (line.isEmpty) {
        continue;
      }
      urls.add(
        LivePlayUrl(
          url: _signService.buildUrl(line: line, bitRate: bitRate),
          headers: const {'user-agent': HttpHuyaSignService.playerUserAgent},
          lineLabel: line['cdnType']?.toString(),
        ),
      );
    }
    return urls;
  }

  Future<List<LiveSubCategory>> _fetchSubCategories(String categoryId) async {
    final response = await _transport.getJson(
      'https://live.cdn.huya.com/liveconfig/game/bussLive',
      queryParameters: {'bussType': categoryId},
    );
    return _asList(response['data']).map((item) {
      final data = _asMap(item);
      final gameId = _resolveGameId(data['gid']);
      return LiveSubCategory(
        id: gameId,
        parentId: categoryId,
        name: normalizeDisplayText(data['gameFullName']?.toString()),
        pic: gameId.isEmpty
            ? null
            : 'https://huyaimg.msstatic.com/cdnimage/game/$gameId-MS.jpg',
      );
    }).where((item) {
      return item.id.isNotEmpty && item.name.isNotEmpty;
    }).toList(growable: false);
  }

  LiveRoom _mapCategoryRoom(Map<String, dynamic> item) {
    var cover = item['screenshot']?.toString();
    if (cover != null && cover.isNotEmpty && !cover.contains('?')) {
      cover = '$cover?x-oss-process=style/w338_h190&';
    }
    final title = (item['introduction']?.toString().isNotEmpty ?? false)
        ? item['introduction'].toString()
        : item['roomName']?.toString() ?? '';
    return LiveRoom(
      providerId: ProviderId.huya.value,
      roomId: item['profileRoom']?.toString() ?? '',
      title: normalizeDisplayText(title),
      streamerName: normalizeDisplayText(item['nick']?.toString()),
      coverUrl: cover,
      keyframeUrl: cover,
      areaName: normalizeDisplayText(item['gameFullName']?.toString()),
      streamerAvatarUrl: item['avatar180']?.toString(),
      viewerCount: _asInt(item['totalCount']),
      isLive: true,
    );
  }

  String _resolveGameId(Object? value) {
    if (value is Map) {
      final raw = value['value']?.toString() ?? '';
      return raw.split(',').first;
    }
    if (value is double) {
      return value.toInt().toString();
    }
    return value?.toString() ?? '';
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
