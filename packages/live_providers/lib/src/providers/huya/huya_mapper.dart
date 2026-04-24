import 'dart:convert';

import 'package:live_core/live_core.dart';

class HuyaMapper {
  const HuyaMapper._();

  static PagedResponse<LiveRoom> mapSearchResponse(
    String responseText, {
    required int page,
  }) {
    final response = jsonDecode(responseText) as Map<String, dynamic>;
    final docs = _asList(_asMap(_asMap(response['response'])['3'])['docs']);
    final numFound =
        _asInt(_asMap(_asMap(response['response'])['3'])['numFound']) ?? 0;
    final items =
        docs.map((item) => mapSearchRoom(_asMap(item))).toList(growable: false);
    return PagedResponse(
      items: items,
      hasMore: numFound > page * 20,
      page: page,
    );
  }

  static LiveRoom mapSearchRoom(Map<String, dynamic> item) {
    var cover = item['game_screenshot']?.toString();
    if (cover != null && !cover.contains('?')) {
      cover += '?x-oss-process=style/w338_h190&';
    }
    final title = (item['game_introduction']?.toString().isNotEmpty ?? false)
        ? item['game_introduction'].toString()
        : item['game_roomName']?.toString() ?? '';
    return LiveRoom(
      providerId: ProviderId.huya.value,
      roomId: 'yy/${item['yyid']}',
      title: normalizeDisplayText(title),
      streamerName: normalizeDisplayText(item['game_nick']?.toString()),
      coverUrl: cover,
      keyframeUrl: cover,
      areaName: normalizeDisplayText(item['gameName']?.toString()),
      streamerAvatarUrl: item['game_imgUrl']?.toString(),
      viewerCount: _asInt(item['game_total_count']),
      isLive: true,
    );
  }

  static LiveRoomDetail mapRoomDetail(
    String html, {
    required String requestedRoomId,
  }) {
    final roomDataJson = _extractJsonObject(html, 'var TT_ROOM_DATA');
    final streamJsonRaw = _extractJsonObject(html, 'stream:');
    if (roomDataJson == null || streamJsonRaw == null) {
      throw ProviderParseException(
        providerId: ProviderId.huya,
        message:
            'Huya room detail HTML did not contain expected room payloads.',
      );
    }

    final roomData = jsonDecode(roomDataJson) as Map<String, dynamic>;
    final streamJson = jsonDecode(streamJsonRaw) as Map<String, dynamic>;
    final streamDataJson = _asMap(_asList(streamJson['data']).firstOrNull);
    final liveInfo = _asMap(streamDataJson['gameLiveInfo']);
    final streamInfoList = _asList(streamDataJson['gameStreamInfoList']);
    if (liveInfo.isEmpty || streamDataJson.isEmpty) {
      throw ProviderParseException(
        providerId: ProviderId.huya,
        message: 'Huya room detail payload was empty or invalid.',
      );
    }
    final status = roomData['state'] == 'ON' && roomData['isReplay'] != true;
    final firstStreamInfo = _asMap(streamInfoList.firstOrNull);
    final topSid = _asInt(firstStreamInfo['lChannelId']);
    final subSid = _asInt(firstStreamInfo['lSubChannelId']);
    final yySid = _asInt(liveInfo['yyid']);
    final lines = <Map<String, Object?>>[];
    final bitRates = <Map<String, Object?>>[];

    if (status) {
      for (final item in streamInfoList) {
        final lineMap = _asMap(item);
        if ((lineMap['sFlvUrl']?.toString().isNotEmpty ?? false)) {
          lines.add({
            'line': lineMap['sFlvUrl']?.toString() ?? '',
            'lineType': 'flv',
            'antiCode': lineMap['sFlvAntiCode']?.toString() ?? '',
            'streamName': lineMap['sStreamName']?.toString() ?? '',
            'cdnType': lineMap['sCdnType']?.toString() ?? '',
            'presenterUid': topSid ?? 0,
          });
        }
        if ((lineMap['sHlsUrl']?.toString().isNotEmpty ?? false)) {
          lines.add({
            'line': lineMap['sHlsUrl']?.toString() ?? '',
            'lineType': 'hls',
            'antiCode': lineMap['sHlsAntiCode']?.toString() ?? '',
            'streamName': lineMap['sStreamName']?.toString() ?? '',
            'cdnType': lineMap['sCdnType']?.toString() ?? '',
            'presenterUid': topSid ?? 0,
          });
        }
      }
      for (final item in _asList(streamJson['vMultiStreamInfo'])) {
        final bitrate = _asMap(item);
        final name = bitrate['sDisplayName']?.toString() ?? '';
        if (name.contains('HDR')) {
          continue;
        }
        bitRates.add({
          'name': name,
          'bitRate': _asInt(bitrate['iBitRate']) ?? 0,
        });
      }
    }

    if (status && lines.isEmpty) {
      throw ProviderParseException(
        providerId: ProviderId.huya,
        message: 'Huya room detail did not contain playable stream lines.',
      );
    }

    return LiveRoomDetail(
      providerId: ProviderId.huya.value,
      roomId: requestedRoomId,
      title: normalizeDisplayText(liveInfo['introduction']?.toString()),
      streamerName: normalizeDisplayText(liveInfo['nick']?.toString()),
      streamerAvatarUrl: liveInfo['avatar180']?.toString(),
      coverUrl: liveInfo['screenshot']?.toString(),
      keyframeUrl: liveInfo['screenshot']?.toString(),
      areaName: normalizeDisplayText(liveInfo['gameFullName']?.toString()),
      description: normalizeDisplayText(liveInfo['introduction']?.toString()),
      sourceUrl: 'https://www.huya.com/$requestedRoomId',
      isLive: status,
      viewerCount: _asInt(liveInfo['totalCount']),
      danmakuToken: {
        'ayyuid': yySid ?? 0,
        'topSid': topSid ?? 0,
        'subSid': subSid ?? 0,
      },
      metadata: {
        'isReplay': roomData['isReplay'] == true,
        'lines': lines,
        'bitrates': bitRates,
      },
    );
  }

  static List<LivePlayQuality> mapPlayQualities(LiveRoomDetail detail) {
    final metadata = detail.metadata ?? const <String, Object?>{};
    final lines = _asList(metadata['lines']);
    var bitRates = _asList(metadata['bitrates']);
    if (lines.isEmpty) {
      return const [];
    }
    if (bitRates.isEmpty) {
      bitRates = const [
        {'name': '原画', 'bitRate': 0},
      ];
    }
    final qualities = bitRates.map((item) => _asMap(item)).map(
      (item) {
        final bitRate = _asInt(item['bitRate']) ?? 0;
        return LivePlayQuality(
          id: bitRate.toString(),
          label: item['name']?.toString() ?? '未知清晰度',
          isDefault: bitRate == 0,
          sortOrder: bitRate == 0 ? 1 << 30 : bitRate,
          metadata: {
            'bitRate': bitRate,
            'lines': lines,
          },
        );
      },
    ).toList(growable: false)
      ..sort((a, b) => b.sortOrder.compareTo(a.sortOrder));
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

  static String? _extractJsonObject(String source, String marker) {
    final markerIndex = source.indexOf(marker);
    if (markerIndex < 0) {
      return null;
    }
    final startIndex = source.indexOf('{', markerIndex);
    if (startIndex < 0) {
      return null;
    }
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var index = startIndex; index < source.length; index += 1) {
      final char = source[index];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (char == '\\') {
        escaped = true;
        continue;
      }
      if (char == '"') {
        inString = !inString;
        continue;
      }
      if (inString) {
        continue;
      }
      if (char == '{') {
        depth += 1;
      } else if (char == '}') {
        depth -= 1;
        if (depth == 0) {
          return source.substring(startIndex, index + 1);
        }
      }
    }
    return null;
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

extension on List<dynamic> {
  Object? get firstOrNull => isEmpty ? null : first;
}
