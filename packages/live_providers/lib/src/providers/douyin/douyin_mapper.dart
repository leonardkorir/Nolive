import 'dart:convert';

import 'package:live_core/live_core.dart';

class DouyinMapper {
  const DouyinMapper._();

  static PagedResponse<LiveRoom> mapSearchResponse(
    Map<String, dynamic> response, {
    required int page,
  }) {
    final items = _asList(response['data'])
        .map((item) => _asMap(item))
        .map((item) =>
            _asMap(jsonDecode(item['lives']?['rawdata']?.toString() ?? '{}')))
        .where((item) => item.isNotEmpty)
        .map(mapSearchRoom)
        .toList(growable: false);
    return PagedResponse(items: items, hasMore: items.length >= 10, page: page);
  }

  static LiveRoom mapSearchRoom(Map<String, dynamic> item) {
    final owner = _asMap(item['owner']);
    return LiveRoom(
      providerId: ProviderId.douyin.value,
      roomId: owner['web_rid']?.toString() ?? '',
      title: normalizeDisplayText(item['title']?.toString()),
      streamerName: normalizeDisplayText(owner['nickname']?.toString()),
      coverUrl: _firstUrl(_asMap(item['cover'])),
      keyframeUrl: _firstUrl(_asMap(item['cover'])),
      areaName: '',
      streamerAvatarUrl: _firstUrl(_asMap(owner['avatar_medium'])),
      viewerCount: _asInt(_asMap(item['stats'])['total_user']),
      isLive: true,
    );
  }

  static LiveRoomDetail mapRoomDetailFromApi(
    Map<String, dynamic> data, {
    required String webRid,
    required String cookie,
  }) {
    final roomData = _asMap(_asList(data['data']).firstOrNull);
    final userData = _asMap(data['user']);
    final owner = _asMap(roomData['owner']);
    final roomStatus = (_asInt(roomData['status']) ?? 0) == 2;
    final partitionRoadMap = _asMap(data['partition_road_map']);
    final partitionTitle =
        _asMap(partitionRoadMap['partition'])['title']?.toString();
    final subPartitionTitle =
        _asMap(_asMap(partitionRoadMap['sub_partition'])['partition'])['title']
            ?.toString();
    final areaName = (partitionTitle != null && partitionTitle.isNotEmpty)
        ? partitionTitle
        : (subPartitionTitle ?? '');

    return LiveRoomDetail(
      providerId: ProviderId.douyin.value,
      roomId: webRid,
      title: normalizeDisplayText(roomData['title']?.toString()),
      streamerName: roomStatus
          ? normalizeDisplayText(owner['nickname']?.toString())
          : normalizeDisplayText(userData['nickname']?.toString()),
      streamerAvatarUrl: roomStatus
          ? _firstUrl(_asMap(owner['avatar_thumb']))
          : _firstUrl(_asMap(userData['avatar_thumb'])),
      coverUrl: roomStatus ? _firstUrl(_asMap(roomData['cover'])) : null,
      keyframeUrl: roomStatus ? _firstUrl(_asMap(roomData['cover'])) : null,
      areaName: normalizeDisplayText(areaName),
      description: normalizeDisplayText(owner['signature']?.toString()),
      sourceUrl: 'https://live.douyin.com/$webRid',
      isLive: roomStatus,
      viewerCount: roomStatus
          ? _asInt(_asMap(roomData['room_view_stats'])['display_value'])
          : 0,
      danmakuToken: {
        'webRid': webRid,
        'roomId': roomData['id_str']?.toString() ?? '',
        'cookie': cookie,
        'userUniqueId': _userUniqueIdFromApi(data, roomData),
      },
      metadata: {
        'streamUrl': roomStatus
            ? _asMap(roomData['stream_url'])
            : const <String, Object?>{},
      },
    );
  }

  static String _userUniqueIdFromApi(
    Map<String, dynamic> apiData,
    Map<String, dynamic> roomData,
  ) {
    final user = _asMap(apiData['user']);
    final direct = user['user_unique_id']?.toString() ?? '';
    if (direct.isNotEmpty) {
      return direct;
    }
    final owner = _asMap(roomData['owner']);
    final ownerUid = owner['user_unique_id']?.toString() ?? '';
    if (ownerUid.isNotEmpty) {
      return ownerUid;
    }
    final digits =
        (roomData['id_str']?.toString() ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.isNotEmpty) {
      return digits.padRight(12, '0').substring(0, 12);
    }
    final fallback = DateTime.now().millisecondsSinceEpoch.toString();
    return fallback.substring(fallback.length - 12);
  }

  static LiveRoomDetail mapRoomDetailFromHtml(
    Map<String, dynamic> state, {
    required String webRid,
    required String cookie,
  }) {
    final roomStore = _asMap(state['roomStore']);
    final roomInfo = _asMap(roomStore['roomInfo']);
    final room = _asMap(roomInfo['room']);
    final owner = _asMap(room['owner']);
    final anchor = _asMap(roomInfo['anchor']);
    final userStore = _asMap(state['userStore']);
    final odin = _asMap(userStore['odin']);
    final roomStatus = (_asInt(room['status']) ?? 0) == 2;

    return LiveRoomDetail(
      providerId: ProviderId.douyin.value,
      roomId: webRid,
      title: normalizeDisplayText(room['title']?.toString()),
      streamerName: roomStatus
          ? normalizeDisplayText(owner['nickname']?.toString())
          : normalizeDisplayText(anchor['nickname']?.toString()),
      streamerAvatarUrl: roomStatus
          ? _firstUrl(_asMap(owner['avatar_thumb']))
          : _firstUrl(_asMap(anchor['avatar_thumb'])),
      coverUrl: roomStatus ? _firstUrl(_asMap(room['cover'])) : null,
      keyframeUrl: roomStatus ? _firstUrl(_asMap(room['cover'])) : null,
      areaName: '',
      description: normalizeDisplayText(owner['signature']?.toString()),
      sourceUrl: 'https://live.douyin.com/$webRid',
      isLive: roomStatus,
      viewerCount: roomStatus
          ? _asInt(_asMap(room['room_view_stats'])['display_value'])
          : 0,
      danmakuToken: {
        'webRid': webRid,
        'roomId': room['id_str']?.toString() ?? '',
        'cookie': cookie,
        'userUniqueId': odin['user_unique_id']?.toString() ?? '',
      },
      metadata: {
        'streamUrl':
            roomStatus ? _asMap(room['stream_url']) : const <String, Object?>{},
      },
    );
  }

  static List<LivePlayQuality> mapPlayQualities(LiveRoomDetail detail) {
    final streamUrl = _asMap(detail.metadata?['streamUrl']);
    final liveCoreSdkData = _asMap(streamUrl['live_core_sdk_data']);
    final pullData = _asMap(liveCoreSdkData['pull_data']);
    final qualityList = _asList(_asMap(pullData['options'])['qualities']);
    final streamData = pullData['stream_data']?.toString() ?? '';

    final qualities = <LivePlayQuality>[];
    if (!streamData.startsWith('{')) {
      final flvEntries =
          _asMap(streamUrl['flv_pull_url']).entries.toList(growable: false);
      final hlsEntries =
          _asMap(streamUrl['hls_pull_url_map']).entries.toList(growable: false);
      for (final rawQuality in qualityList) {
        final quality = _asMap(rawQuality);
        final level = _asInt(quality['level']) ?? 0;
        final sdkKey = quality['sdk_key']?.toString() ?? '';
        final label = quality['name']?.toString() ?? '未知清晰度';
        final urls = <String>[];
        urls.addAll(_matchLegacyQualityUrls(
          entries: flvEntries,
          level: level,
          sdkKey: sdkKey,
          label: label,
        ));
        urls.addAll(_matchLegacyQualityUrls(
          entries: hlsEntries,
          level: level,
          sdkKey: sdkKey,
          label: label,
        ));
        if (urls.isEmpty) {
          continue;
        }
        qualities.add(
          LivePlayQuality(
            id: level.toString(),
            label: label,
            isDefault: level == 0,
            sortOrder: level,
            metadata: {'urls': urls},
          ),
        );
      }
    } else {
      final qualityData = _asMap(jsonDecode(streamData)['data']);
      for (final rawQuality in qualityList) {
        final quality = _asMap(rawQuality);
        final sdkKey = quality['sdk_key']?.toString() ?? '';
        final main = _asMap(_asMap(qualityData[sdkKey])['main']);
        final urls = <String>[];
        final flvUrl = main['flv']?.toString();
        if (flvUrl != null && flvUrl.isNotEmpty) {
          urls.add(flvUrl);
        }
        final hlsUrl = main['hls']?.toString();
        if (hlsUrl != null && hlsUrl.isNotEmpty) {
          urls.add(hlsUrl);
        }
        if (urls.isEmpty) {
          continue;
        }
        qualities.add(
          LivePlayQuality(
            id: (_asInt(quality['level']) ?? 0).toString(),
            label: quality['name']?.toString() ?? '未知清晰度',
            isDefault: (_asInt(quality['level']) ?? 0) == 0,
            sortOrder: _asInt(quality['level']) ?? 0,
            metadata: {'urls': urls},
          ),
        );
      }
    }
    qualities.sort((a, b) => b.sortOrder.compareTo(a.sortOrder));
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

  static List<LivePlayUrl> mapPlayUrls(LivePlayQuality quality) {
    final urls = quality.metadata?['urls'];
    final entries = urls is List ? urls : const [];
    return entries
        .map((item) => item?.toString() ?? '')
        .where((item) => item.isNotEmpty)
        .map(
          (item) => LivePlayUrl(
            url: item,
            headers: const {},
            lineLabel: item.contains('.m3u8') ? 'hls' : 'flv',
          ),
        )
        .toList(growable: false);
  }

  static List<String> _matchLegacyQualityUrls({
    required List<MapEntry<String, dynamic>> entries,
    required int level,
    required String sdkKey,
    required String label,
  }) {
    final normalizedSdkKey = sdkKey.toLowerCase();
    final normalizedLabel = label.toLowerCase();
    final matched = entries
        .where((entry) {
          final key = entry.key.toLowerCase();
          return (normalizedSdkKey.isNotEmpty &&
                  key.contains(normalizedSdkKey)) ||
              (normalizedLabel.isNotEmpty && key.contains(normalizedLabel));
        })
        .map((entry) => entry.value?.toString() ?? '')
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (matched.isNotEmpty) {
      return matched;
    }

    final index = entries.length - 1 - level;
    if (index < 0 || index >= entries.length) {
      return const [];
    }
    final url = entries[index].value?.toString() ?? '';
    return url.isEmpty ? const [] : [url];
  }

  static Map<String, dynamic> parseHtmlState(String html) {
    final matched = RegExp(r'\{\\"state\\":\{\\"appStore.*?\]\\n')
            .firstMatch(html)
            ?.group(0) ??
        '';
    final normalized = matched
        .trim()
        .replaceAll('\\"', '"')
        .replaceAll(r'\\', r'\')
        .replaceAll(']\\n', '');
    if (normalized.isEmpty) {
      throw ProviderParseException(
        providerId: ProviderId.douyin,
        message: 'Douyin HTML did not contain expected room state payload.',
      );
    }
    final decoded = jsonDecode(normalized) as Map<String, dynamic>;
    return _asMap(decoded['state']);
  }

  static String? _firstUrl(Map<String, dynamic> value) {
    final list = _asList(value['url_list']);
    if (list.isEmpty) {
      return null;
    }
    return list.first?.toString();
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
}

extension on List<dynamic> {
  Object? get firstOrNull => isEmpty ? null : first;
}
