import 'dart:convert';

import 'package:live_core/live_core.dart';

import '../provider_json.dart';

class HuyaMapper {
  const HuyaMapper._();

  static PagedResponse<LiveRoom> mapSearchResponse(
    String responseText, {
    required int page,
  }) {
    final response = _decodeMap(responseText, context: 'search response');
    final docs = _asList(_asMap(_asMap(response['response'])['3'])['docs']);
    final numFound =
        _asInt(_asMap(_asMap(response['response'])['3'])['numFound']) ?? 0;
    final items = docs
        .map((item) => mapSearchRoom(_asMap(item)))
        .toList(growable: false);
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
      providerId: ProviderId.huya,
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
    // SlotSun: status comes from TT_ROOM_DATA only
    // (state == ON && !isReplay). Offline rooms often lack a usable stream
    // blob — that must still resolve as isLive=false for follow chips.
    final roomDataJson = _extractJsonObject(html, 'var TT_ROOM_DATA');
    if (roomDataJson == null) {
      throw ProviderParseException(
        providerId: ProviderId.huya,
        message: 'Huya room detail HTML did not contain TT_ROOM_DATA.',
      );
    }

    final roomData = _decodeMap(roomDataJson, context: 'room data');
    final isLive =
        roomData['state'] == 'ON' && roomData['isReplay'] != true;
    final streamJsonRaw = _extractJsonObject(html, 'stream:');

    Map<String, dynamic> liveInfo = const {};
    Map<String, dynamic> streamDataJson = const {};
    var streamJson = const <String, dynamic>{};
    if (streamJsonRaw != null) {
      try {
        streamJson = _decodeMap(streamJsonRaw, context: 'stream data');
        streamDataJson = _asMap(_asList(streamJson['data']).firstOrNull);
        liveInfo = _asMap(streamDataJson['gameLiveInfo']);
      } catch (_) {
        // Offline pages may ship truncated / empty stream payloads.
        if (isLive) {
          rethrow;
        }
      }
    }

    if (isLive && (liveInfo.isEmpty || streamDataJson.isEmpty)) {
      throw ProviderParseException(
        providerId: ProviderId.huya,
        message: 'Huya live room detail payload was empty or invalid.',
      );
    }

    final streamInfoList = _asList(streamDataJson['gameStreamInfoList']);
    final firstStreamInfo = _asMap(streamInfoList.firstOrNull);
    final topSid = _asInt(firstStreamInfo['lChannelId']);
    final subSid = _asInt(firstStreamInfo['lSubChannelId']);
    final yySid = _asInt(liveInfo['yyid']);
    final lines = <Map<String, Object?>>[];
    final bitRates = <Map<String, Object?>>[];

    if (isLive) {
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

    if (isLive && lines.isEmpty) {
      throw ProviderParseException(
        providerId: ProviderId.huya,
        message: 'Huya room detail did not contain playable stream lines.',
      );
    }

    // Prefer stream liveInfo when present; offline may only have roomData.
    final nick = liveInfo['nick']?.toString() ??
        roomData['nick']?.toString() ??
        '';
    final introduction = liveInfo['introduction']?.toString() ??
        roomData['introduction']?.toString() ??
        '';
    final screenshot = liveInfo['screenshot']?.toString() ??
        roomData['screenshot']?.toString();
    final avatar = liveInfo['avatar180']?.toString() ??
        roomData['avatar180']?.toString();
    final gameName = liveInfo['gameFullName']?.toString() ??
        roomData['gameFullName']?.toString() ??
        '';

    return LiveRoomDetail(
      providerId: ProviderId.huya,
      roomId: requestedRoomId,
      title: normalizeDisplayText(introduction),
      streamerName: normalizeDisplayText(nick),
      streamerAvatarUrl: avatar,
      coverUrl: isLive ? screenshot : null,
      keyframeUrl: isLive ? screenshot : null,
      areaName: normalizeDisplayText(gameName),
      description: normalizeDisplayText(introduction),
      sourceUrl: 'https://www.huya.com/$requestedRoomId',
      isLive: isLive,
      viewerCount: isLive ? _asInt(liveInfo['totalCount']) : null,
      danmakuToken: isLive
          ? HuyaDanmakuToken(
              ayyuid: yySid ?? 0,
              topSid: topSid ?? 0,
              subSid: subSid ?? 0,
            )
          : null,
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
    final qualities =
        bitRates
            .map((item) => _asMap(item))
            .map((item) {
              final bitRate = _asInt(item['bitRate']) ?? 0;
              return LivePlayQuality(
                id: bitRate.toString(),
                label: item['name']?.toString() ?? '未知清晰度',
                isDefault: bitRate == 0,
                sortOrder: bitRate == 0 ? 1 << 30 : bitRate,
                metadata: {'bitRate': bitRate, 'lines': lines},
              );
            })
            .toList(growable: false)
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
    if (depth > 0) {
      throw ProviderParseException(
        providerId: ProviderId.huya,
        message: 'Huya $marker JSON payload was truncated.',
      );
    }
    return null;
  }

  static Map<String, dynamic> _asMap(Object? value) {
    return ProviderJson.asMap(value);
  }

  static List<dynamic> _asList(Object? value) {
    return ProviderJson.asList(value);
  }

  static int? _asInt(Object? value) {
    return ProviderJson.asInt(value);
  }

  static Map<String, dynamic> _decodeMap(
    String source, {
    required String context,
  }) {
    final decoded = jsonDecode(source);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.cast<String, dynamic>();
    }
    throw ProviderParseException(
      providerId: ProviderId.huya,
      message: 'Huya $context payload type was ${decoded.runtimeType}.',
    );
  }
}

extension on List<dynamic> {
  Object? get firstOrNull => isEmpty ? null : first;
}
