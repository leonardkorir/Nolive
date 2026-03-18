import 'package:live_core/live_core.dart';

class BilibiliMapper {
  const BilibiliMapper._();

  static PagedResponse<LiveRoom> mapSearchResponse(
    Map<String, dynamic> response, {
    required int page,
  }) {
    final data = _asMap(response['data']);
    final result = _asMap(data['result']);
    final rooms = _asList(result['live_room']);
    final items = rooms
        .map((item) => mapSearchRoom(_asMap(item)))
        .toList(growable: false);
    final pageInfo = _asMap(data['pageinfo']);
    final liveRoomInfo = _asMap(pageInfo['live_room']);
    final numPages = _asInt(liveRoomInfo['numPages']) ?? 1;

    return PagedResponse(
      items: items,
      hasMore: page < numPages,
      page: page,
    );
  }

  static LiveRoom mapSearchRoom(Map<String, dynamic> item) {
    return LiveRoom(
      providerId: ProviderId.bilibili.value,
      roomId: item['roomid'].toString(),
      title: _stripHighlight(item['title']?.toString()),
      streamerName: item['uname']?.toString() ?? '',
      coverUrl: _normalizeAssetUrl(item['user_cover']?.toString()),
      keyframeUrl: _normalizeAssetUrl(item['cover']?.toString()),
      areaName: _stripHighlight(item['cate_name']?.toString()),
      streamerAvatarUrl: _normalizeAssetUrl(item['uface']?.toString()),
      viewerCount: _asInt(item['online']),
      isLive: (_asInt(item['live_status']) ?? 0) == 1,
    );
  }

  static LiveRoomDetail mapRoomDetail({
    required Map<String, dynamic> roomInfoData,
    required Map<String, dynamic> danmakuInfoData,
    required String requestedRoomId,
    required String buvid3,
    required String cookie,
    required int userId,
  }) {
    final roomInfo = _asMap(roomInfoData['room_info']);
    final anchorInfo = _asMap(roomInfoData['anchor_info']);
    final anchorBaseInfo = _asMap(anchorInfo['base_info']);
    final serverHosts = _asList(danmakuInfoData['host_list'])
        .map((item) => _asMap(item)['host']?.toString() ?? '')
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    final realRoomId = roomInfo['room_id']?.toString() ?? requestedRoomId;
    final liveStartTime = _asInt(roomInfo['live_start_time']);

    return LiveRoomDetail(
      providerId: ProviderId.bilibili.value,
      roomId: realRoomId,
      title: roomInfo['title']?.toString() ?? '',
      streamerName: anchorBaseInfo['uname']?.toString() ?? '',
      streamerAvatarUrl: _normalizeAssetUrl(anchorBaseInfo['face']?.toString()),
      coverUrl: roomInfo['cover']?.toString(),
      keyframeUrl: roomInfo['keyframe']?.toString(),
      areaName: roomInfo['area_name']?.toString(),
      description: roomInfo['description']?.toString(),
      sourceUrl: 'https://live.bilibili.com/$requestedRoomId',
      startedAt: liveStartTime == null || liveStartTime <= 0
          ? null
          : DateTime.fromMillisecondsSinceEpoch(liveStartTime * 1000),
      isLive: (_asInt(roomInfo['live_status']) ?? 0) == 1,
      viewerCount: _asInt(roomInfo['online']),
      danmakuToken: {
        'roomId': _asInt(realRoomId) ?? 0,
        'uid': userId,
        'token': danmakuInfoData['token']?.toString() ?? '',
        'serverHost': serverHosts.isNotEmpty
            ? serverHosts.first
            : 'broadcastlv.chat.bilibili.com',
        'buvid': buvid3,
        'cookie': cookie,
      },
      metadata: {
        'requestedRoomId': requestedRoomId,
        'shortId': roomInfo['short_id']?.toString(),
      },
    );
  }

  static List<LivePlayQuality> mapPlayQualities(Map<String, dynamic> response) {
    final playUrl = _playUrlPayload(response);
    final currentQn = _asInt(playUrl['current_qn']);
    final qualityMap = <int, String>{
      for (final item in _asList(playUrl['g_qn_desc']))
        _asInt(_asMap(item)['qn']) ?? 0:
            _asMap(item)['desc']?.toString() ?? '未知清晰度',
    };

    final firstCodec = _firstCodec(playUrl);
    final acceptQn = _asList(firstCodec['accept_qn']);
    final qualities = acceptQn
        .map((item) => _asInt(item) ?? 0)
        .where((item) => item > 0)
        .map(
          (item) => LivePlayQuality(
            id: item.toString(),
            label: qualityMap[item] ?? '未知清晰度',
            isDefault: item == currentQn,
            sortOrder: item,
            metadata: {
              'qn': item,
              'qualityMap': qualityMap,
            },
          ),
        )
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

  static List<LivePlayUrl> mapPlayUrls(Map<String, dynamic> response) {
    final playUrl = _playUrlPayload(response);
    final urls = <({String url, String lineLabel})>[];

    for (final stream in _asList(playUrl['stream'])) {
      for (final format in _asList(_asMap(stream)['format'])) {
        for (final codec in _asList(_asMap(format)['codec'])) {
          final codecMap = _asMap(codec);
          final baseUrl = codecMap['base_url']?.toString() ?? '';
          for (final urlInfo in _asList(codecMap['url_info'])) {
            final urlInfoMap = _asMap(urlInfo);
            final host = urlInfoMap['host']?.toString() ?? '';
            final extra = urlInfoMap['extra']?.toString() ?? '';
            final fullUrl = '$host$baseUrl$extra';
            if (fullUrl.isEmpty) {
              continue;
            }
            urls.add(
                (url: fullUrl, lineLabel: Uri.tryParse(host)?.host ?? host));
          }
        }
      }
    }

    final uniqueUrls = <String, String>{};
    for (final item in urls) {
      uniqueUrls.putIfAbsent(item.url, () => item.lineLabel);
    }

    final sorted = uniqueUrls.entries.toList(growable: false)
      ..sort((a, b) {
        final leftPenalty = a.key.contains('mcdn') ? 1 : 0;
        final rightPenalty = b.key.contains('mcdn') ? 1 : 0;
        return leftPenalty.compareTo(rightPenalty);
      });

    return sorted
        .map(
          (entry) => LivePlayUrl(
            url: entry.key,
            headers: const {
              'referer': 'https://live.bilibili.com',
              'user-agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                      '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36 '
                      'Edg/126.0.0.0',
            },
            lineLabel: entry.value,
          ),
        )
        .toList(growable: false);
  }

  static Map<String, dynamic> _playUrlPayload(Map<String, dynamic> response) {
    final data = _asMap(response['data']);
    final playurlInfo = _asMap(data['playurl_info']);
    return _asMap(playurlInfo['playurl']);
  }

  static Map<String, dynamic> _firstCodec(Map<String, dynamic> playUrl) {
    final streams = _asList(playUrl['stream']);
    final stream =
        streams.isEmpty ? const <String, dynamic>{} : _asMap(streams.first);
    final formats = _asList(stream['format']);
    final format =
        formats.isEmpty ? const <String, dynamic>{} : _asMap(formats.first);
    final codecs = _asList(format['codec']);
    return codecs.isEmpty ? const <String, dynamic>{} : _asMap(codecs.first);
  }

  static String _stripHighlight(String? value) {
    return (value ?? '').replaceAll(RegExp(r'<.*?em.*?>'), '');
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
