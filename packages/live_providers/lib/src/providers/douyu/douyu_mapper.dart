import 'package:live_core/live_core.dart';

import 'douyu_sign_service.dart';

class DouyuMapper {
  const DouyuMapper._();

  static PagedResponse<LiveRoom> mapSearchResponse(
    Map<String, dynamic> response, {
    required int page,
    int pageSize = 20,
  }) {
    final data = _asMap(response['data']);
    final rooms = _asList(data['relateShow']);
    final items = rooms
        .map((item) => mapSearchRoom(_asMap(item)))
        .toList(growable: false);
    final pageCount = _asInt(data['pageCount']) ??
        _asInt(data['pgcnt']) ??
        _asInt(data['totalPage']);

    return PagedResponse(
      items: items,
      hasMore: pageCount != null ? page < pageCount : items.length >= pageSize,
      page: page,
    );
  }

  static LiveRoom mapSearchRoom(Map<String, dynamic> item) {
    final avatar = item['avatar']?.toString();
    return LiveRoom(
      providerId: ProviderId.douyu.value,
      roomId: item['rid']?.toString() ?? '',
      title:
          normalizeDisplayText(_stripHighlight(item['roomName']?.toString())),
      streamerName: normalizeDisplayText(item['nickName']?.toString()),
      coverUrl: _normalizeAssetUrl(item['roomSrc']?.toString()),
      keyframeUrl: _normalizeAssetUrl(item['roomSrc']?.toString()),
      areaName:
          normalizeDisplayText(_stripHighlight(item['cateName']?.toString())),
      streamerAvatarUrl: _normalizeAvatarUrl(avatar),
      viewerCount: parseHotCount(item['hot']),
      isLive: true,
    );
  }

  static Map<String, dynamic> extractRoomInfo(Map<String, dynamic> response) {
    return _asMap(response['room']);
  }

  static LiveRoomDetail mapRoomDetail({
    required Map<String, dynamic> roomInfo,
    required String requestedRoomId,
    required DouyuSignedPlayContext playContext,
  }) {
    final roomBiz = _asMap(roomInfo['room_biz_all']);
    final title = roomInfo['room_name']?.toString() ?? '';
    final roomId = roomInfo['room_id']?.toString() ?? requestedRoomId;
    final isRecord =
        (_asInt(roomInfo['videoLoop']) ?? 0) == 1 || title.startsWith('【回放】');
    final isLive = (_asInt(roomInfo['show_status']) ?? 0) == 1 && !isRecord;

    return LiveRoomDetail(
      providerId: ProviderId.douyu.value,
      roomId: roomId,
      title: normalizeDisplayText(title),
      streamerName: normalizeDisplayText(roomInfo['owner_name']?.toString()),
      streamerAvatarUrl: _normalizeAvatarUrl(
        roomInfo['owner_avatar']?.toString(),
      ),
      coverUrl: _normalizeAssetUrl(roomInfo['room_pic']?.toString()),
      keyframeUrl: _normalizeAssetUrl(roomInfo['room_pic']?.toString()),
      areaName: normalizeDisplayText(roomInfo['second_lvl_name']?.toString()),
      description: normalizeDisplayText(roomInfo['show_details']?.toString()),
      sourceUrl: 'https://www.douyu.com/$requestedRoomId',
      isLive: isLive,
      viewerCount: parseHotCount(roomBiz['hot']),
      danmakuToken: {'roomId': roomId, 'mode': 'migration-pending'},
      metadata: {
        'requestedRoomId': requestedRoomId,
        'playBody': playContext.body,
        'deviceId': playContext.deviceId,
        'signatureTimestamp': playContext.timestamp,
        'signScript': playContext.script,
      },
    );
  }

  static List<LivePlayQuality> mapPlayQualities(Map<String, dynamic> response) {
    final data = _asMap(response['data']);
    final cdns = _sortedCdns(
      _asList(data['cdnsWithName'])
          .map((item) => _asMap(item)['cdn']?.toString() ?? '')
          .where((item) => item.isNotEmpty)
          .toList(growable: false),
    );
    final currentRate = _asInt(data['rate']);
    final multirates = _asList(data['multirates']);
    final qualityMap = <String, Object?>{};
    final qualities = <LivePlayQuality>[];

    for (var index = 0; index < multirates.length; index += 1) {
      final item = _asMap(multirates[index]);
      final rate = _asInt(item['rate']) ?? 0;
      final label = item['name']?.toString() ?? '未知清晰度';
      final sortOrder = _resolveSortOrder(
        rate: rate,
        label: label,
        bitRate: _asInt(item['bit']),
        index: index,
        total: multirates.length,
      );
      qualityMap[rate.toString()] = label;
      qualities.add(
        LivePlayQuality(
          id: rate.toString(),
          label: label,
          isDefault: rate == currentRate,
          sortOrder: sortOrder,
          metadata: {
            'rate': rate,
            'bit': _asInt(item['bit']),
            'cdns': cdns,
            'qualityMap': qualityMap,
          },
        ),
      );
    }

    if (qualities.isNotEmpty && !qualities.any((item) => item.isDefault)) {
      final first = qualities.first;
      qualities[0] = LivePlayQuality(
        id: first.id,
        label: first.label,
        isDefault: true,
        sortOrder: first.sortOrder,
        metadata: first.metadata,
      );
    }

    return qualities;
  }

  static List<LivePlayUrl> mapPlayUrls(
    Map<String, dynamic> response, {
    required Map<String, String> headers,
    String? lineLabel,
  }) {
    final data = _asMap(response['data']);
    final rtmpUrl = data['rtmp_url']?.toString() ?? '';
    final livePath = _decodeHtml(data['rtmp_live']?.toString() ?? '');
    if (rtmpUrl.isEmpty || livePath.isEmpty) {
      return const [];
    }

    final actualRate = _asInt(data['rate']);
    final resolvedLineLabel = lineLabel ?? data['cdn']?.toString();

    return [
      LivePlayUrl(
        url: '$rtmpUrl/$livePath',
        headers: headers,
        lineLabel: resolvedLineLabel,
        metadata: {
          if (actualRate != null) 'rate': actualRate,
          if (resolvedLineLabel != null && resolvedLineLabel.isNotEmpty)
            'cdn': resolvedLineLabel,
        },
      ),
    ];
  }

  static int _resolveSortOrder({
    required int rate,
    required String label,
    required int? bitRate,
    required int index,
    required int total,
  }) {
    if (bitRate != null && bitRate > 0) {
      return bitRate;
    }

    final normalized = label.toLowerCase();
    if (rate == 0 &&
        (normalized.contains('原画') ||
            normalized.contains('1080') ||
            normalized.contains('蓝光'))) {
      return 100000;
    }
    if (normalized.contains('原画')) {
      return 100000;
    }
    if (normalized.contains('蓝光')) {
      return 80000;
    }
    if (normalized.contains('超清')) {
      return 60000;
    }
    if (normalized.contains('高清')) {
      return 40000;
    }
    if (normalized.contains('流畅') || normalized.contains('标清')) {
      return 20000;
    }
    return total - index;
  }

  static int? parseHotCount(Object? value) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) {
      return null;
    }

    final normalized = text.replaceAll(',', '').toUpperCase();
    if (normalized.endsWith('万')) {
      final number =
          double.tryParse(normalized.substring(0, normalized.length - 1));
      return number == null ? null : (number * 10000).round();
    }
    if (normalized.endsWith('W')) {
      final number =
          double.tryParse(normalized.substring(0, normalized.length - 1));
      return number == null ? null : (number * 10000).round();
    }
    if (normalized.endsWith('K')) {
      final number =
          double.tryParse(normalized.substring(0, normalized.length - 1));
      return number == null ? null : (number * 1000).round();
    }
    return int.tryParse(normalized);
  }

  static List<String> _sortedCdns(List<String> cdns) {
    final items = List<String>.from(cdns);
    items.sort((left, right) {
      final leftIsScdn = left.startsWith('scdn');
      final rightIsScdn = right.startsWith('scdn');
      if (leftIsScdn == rightIsScdn) {
        return 0;
      }
      return leftIsScdn ? 1 : -1;
    });
    return items;
  }

  static String _stripHighlight(String? value) {
    return (value ?? '').replaceAll(RegExp(r'<[^>]+>'), '');
  }

  static String _decodeHtml(String value) {
    return value
        .replaceAll('&amp;', '&')
        .replaceAll('&#38;', '&')
        .replaceAll('&#x2F;', '/')
        .replaceAll('&quot;', '"');
  }

  static String? _normalizeAssetUrl(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    if (value.startsWith('//')) {
      return 'https:$value';
    }
    return value;
  }

  static String? _normalizeAvatarUrl(String? value) {
    final normalized = _normalizeAssetUrl(value);
    if (normalized == null || normalized.isEmpty) {
      return normalized;
    }
    if (normalized.startsWith('http://') || normalized.startsWith('https://')) {
      return normalized;
    }
    return 'https://apic.douyucdn.cn/upload/${normalized}_middle.jpg';
  }

  static Map<String, dynamic> _asMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.cast<String, dynamic>();
    }
    return const {};
  }

  static List<dynamic> _asList(Object? value) {
    if (value is List) {
      return value;
    }
    return const [];
  }

  static int? _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    return int.tryParse(value?.toString() ?? '');
  }
}
