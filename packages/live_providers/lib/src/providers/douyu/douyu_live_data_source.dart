import 'package:live_core/live_core.dart';
import 'package:meta/meta.dart';

import '../provider_json.dart';
import 'douyu_data_source.dart';
import 'douyu_mapper.dart';
import 'douyu_sign_service.dart';
import 'douyu_transport.dart';

/// Classification of non-zero getH5Play `error` codes.
enum DouyuH5PlayErrorKind {
  /// Room not broadcasting / offline.
  offline,

  /// Rate limit / frequency control.
  rateLimited,

  /// Sign / auth / encryption failure.
  authFailed,

  /// Other temporary or unknown API failures.
  temporary,
}

/// Maps Douyu getH5Play error code + msg to a recovery-oriented kind.
@visibleForTesting
DouyuH5PlayErrorKind classifyDouyuH5PlayError(int errorCode, String? msg) {
  if (errorCode == -5) {
    return DouyuH5PlayErrorKind.offline;
  }
  final m = (msg ?? '').toLowerCase();
  if (m.contains('未开播') ||
      m.contains('不在线') ||
      m.contains('offline') ||
      m.contains('not live') ||
      m.contains('房间关闭')) {
    return DouyuH5PlayErrorKind.offline;
  }
  if (errorCode == 429 ||
      m.contains('频繁') ||
      m.contains('rate') ||
      m.contains('limit') ||
      m.contains('too many')) {
    return DouyuH5PlayErrorKind.rateLimited;
  }
  if (m.contains('鉴权') ||
      m.contains('签名') ||
      m.contains('sign') ||
      m.contains('auth') ||
      m.contains('encrypt') ||
      errorCode == -1 && m.contains('参数')) {
    return DouyuH5PlayErrorKind.authFailed;
  }
  return DouyuH5PlayErrorKind.temporary;
}

class DouyuLiveDataSource implements DouyuDataSource {
  static const int _recommendPageSize = 40;
  static const int _playRequestMaxAttempts = 2;
  static const Duration _playRequestRetryBackoff = Duration(milliseconds: 1);

  DouyuLiveDataSource({
    required DouyuTransport transport,
    required DouyuSignService signService,
  }) : _transport = transport,
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
    final categories =
        _asList(data['cate1Info'])
            .map((item) {
              final category = _asMap(item);
              final categoryId = category['cate1Id']?.toString() ?? '';
              final children = subCategories
                  .map((subItem) => _asMap(subItem))
                  .where(
                    (subItem) => subItem['cate1Id']?.toString() == categoryId,
                  )
                  .map(
                    (subItem) => LiveSubCategory(
                      id: subItem['cate2Id']?.toString() ?? '',
                      parentId: categoryId,
                      name: subItem['cate2Name']?.toString() ?? '',
                      pic: _resolveCategoryImage(subItem),
                    ),
                  )
                  .where((item) => item.id.isNotEmpty && item.name.isNotEmpty)
                  .toList(growable: false);
              return LiveCategory(
                id: categoryId,
                name: category['cate1Name']?.toString() ?? '',
                children: children,
              );
            })
            .where((item) {
              return item.id.isNotEmpty && item.name.isNotEmpty;
            })
            .toList(growable: false)
          ..sort((left, right) {
            return (int.tryParse(left.id) ?? 0).compareTo(
              int.tryParse(right.id) ?? 0,
            );
          });
    return categories;
  }

  String? _resolveCategoryImage(Map<String, dynamic> payload) {
    for (final candidate in [
      payload['icon'],
      payload['pic'],
      payload['smallIcon'],
    ]) {
      final value = candidate?.toString().trim() ?? '';
      if (value.isEmpty) {
        continue;
      }
      if (value.startsWith('//')) {
        return 'https:$value';
      }
      return value;
    }
    return null;
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
    final rawItems = _asList(data['rl']);
    final items = rawItems
        .map((item) => _asMap(item))
        .where((item) => item['type'] == 1)
        .map(_mapCategoryRoom)
        .where((item) => item.roomId.isNotEmpty)
        .toList(growable: false);
    final totalPages = _asInt(data['pgcnt']) ?? 0;
    final hasMore = totalPages > 0
        ? page < totalPages
        : rawItems.length >= _recommendPageSize;
    return PagedResponse(items: items, hasMore: hasMore, page: page);
  }

  @override
  Future<PagedResponse<LiveRoom>> searchRooms(
    String query, {
    int page = 1,
  }) async {
    final response = await _transport.getJson(
      'https://www.douyu.com/japi/search/api/searchShow',
      queryParameters: {'kw': query, 'page': page.toString(), 'pageSize': '20'},
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
    // SlotSun getRoomDetail: betard only (no sign). Sign happens at play time.
    final roomResponse = await _transport.getJson(
      'https://www.douyu.com/betard/$roomId',
      headers: _signService.buildRoomHeaders(roomId),
    );
    final roomInfo = DouyuMapper.extractRoomInfo(roomResponse);
    final sign = _signService;
    final resolvedDeviceId = sign is HttpDouyuSignService
        ? sign.deviceId
        : DouyuDeviceId.legacyShared;
    return DouyuMapper.mapRoomDetail(
      roomInfo: roomInfo,
      requestedRoomId: roomId,
      playContext: DouyuSignedPlayContext(
        body: '',
        deviceId: resolvedDeviceId,
        timestamp: 0,
      ),
    );
  }

  @override
  Future<List<LivePlayQuality>> fetchPlayQualities(
    LiveRoomDetail detail,
  ) async {
    // SlotSun: DouyuUtils.sign(rid) then POST getH5PlayV1 (fresh body every time).
    final body = await _runPlayRequestWithRetry(
      () => _signService.buildSignedPlayBody(detail.roomId),
    );
    final response = await _runPlayRequestWithRetry(
      () => _transport.postJson(
        'https://www.douyu.com/lapi/live/getH5PlayV1/${detail.roomId}',
        body: body,
        headers: _signService.buildPlayHeaders(detail.roomId),
      ),
    );

    final errorCode = _asInt(response['error']) ?? 0;
    if (errorCode != 0) {
      final msg = response['msg']?.toString();
      final kind = classifyDouyuH5PlayError(errorCode, msg);
      // Offline → empty ladder so UI can show "未开播" without thrashing.
      if (kind == DouyuH5PlayErrorKind.offline) {
        return const [];
      }
      // Sign / rate-limit / temporary: surface so room recovery can retry.
      throw ProviderParseException(
        providerId: ProviderId.douyu,
        message:
            'Douyu getH5Play failed ($kind, error=$errorCode): '
            '${msg ?? 'unknown'}',
      );
    }
    final data = response['data'];
    if (data is! Map) {
      return const [];
    }
    return DouyuMapper.mapPlayQualities(response);
  }

  @override
  Future<List<LivePlayUrl>> fetchPlayUrls({
    required LiveRoomDetail detail,
    required LivePlayQuality quality,
  }) async {
    // SlotSun: for each CDN, DouyuUtils.sign(rid, rate:, cdn:) then getH5Play.
    final rate = (quality.metadata?['rate'] ?? quality.id).toString();
    final cdns = _extractCdns(quality);
    final urls = <LivePlayUrl>[];
    // SlotSun plays bare URL — no stream headers.
    final streamHeaders = _signService.buildStreamHeaders(detail.roomId);
    DouyuH5PlayErrorKind? lastNonOfflineKind;
    String? lastNonOfflineMsg;
    var lastNonOfflineCode = 0;

    for (final cdn in cdns) {
      final body = await _runPlayRequestWithRetry(
        () => _signService.buildSignedPlayBody(
          detail.roomId,
          cdn: cdn,
          rate: rate,
        ),
      );
      final response = await _runPlayRequestWithRetry(
        () => _transport.postJson(
          'https://www.douyu.com/lapi/live/getH5PlayV1/${detail.roomId}',
          body: body,
          headers: _signService.buildPlayHeaders(detail.roomId),
        ),
      );
      final errorCode = _asInt(response['error']) ?? 0;
      if (errorCode != 0) {
        final msg = response['msg']?.toString();
        final kind = classifyDouyuH5PlayError(errorCode, msg);
        if (kind != DouyuH5PlayErrorKind.offline) {
          lastNonOfflineKind = kind;
          lastNonOfflineMsg = msg;
          lastNonOfflineCode = errorCode;
        }
        continue;
      }
      final data = response['data'];
      if (data is! Map) {
        continue;
      }
      urls.addAll(
        DouyuMapper.mapPlayUrls(
          response,
          headers: streamHeaders,
          lineLabel: cdn,
        ),
      );
    }

    if (urls.isEmpty && lastNonOfflineKind != null) {
      throw ProviderParseException(
        providerId: ProviderId.douyu,
        message:
            'Douyu getH5Play urls failed ($lastNonOfflineKind, '
            'error=$lastNonOfflineCode): ${lastNonOfflineMsg ?? 'unknown'}',
      );
    }

    final unique = <String, LivePlayUrl>{};
    for (final item in urls) {
      unique.putIfAbsent(item.url, () => item);
    }
    // Prefer reliable hosts first; still bare-URL like SlotSun.
    return DouyuMapper.preferReliableDouyuPlayUrls(
      unique.values.toList(growable: false),
    );
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

  Future<T> _runPlayRequestWithRetry<T>(Future<T> Function() operation) async {
    Object? lastError;
    StackTrace? lastStackTrace;
    for (var attempt = 0; attempt < _playRequestMaxAttempts; attempt += 1) {
      try {
        return await operation();
      } catch (error, stackTrace) {
        lastError = error;
        lastStackTrace = stackTrace;
        if (attempt + 1 >= _playRequestMaxAttempts) {
          rethrow;
        }
        await Future<void>.delayed(_playRequestRetryBackoff);
      }
    }
    Error.throwWithStackTrace(lastError!, lastStackTrace!);
  }

  LiveRoom _mapCategoryRoom(Map<String, dynamic> item) {
    return LiveRoom(
      providerId: ProviderId.douyu,
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
    return ProviderJson.asMap(value);
  }

  List<dynamic> _asList(Object? value) {
    return ProviderJson.asList(value);
  }

  int? _asInt(Object? value) {
    return ProviderJson.asInt(value);
  }
}
