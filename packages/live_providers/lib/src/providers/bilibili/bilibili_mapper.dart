import 'package:live_core/live_core.dart';

import '../provider_json.dart';
import 'bilibili_sign_service.dart';

class BilibiliMapper {
  const BilibiliMapper._();

  static PagedResponse<LiveRoom> mapSearchResponse(
    Map<String, dynamic> response, {
    required int page,
  }) {
    final data = ProviderJson.asMap(response['data']);
    final result = ProviderJson.asMap(data['result']);
    final rooms = ProviderJson.asList(result['live_room']);
    final items = rooms
        .map((item) => _tryMapSearchRoom(ProviderJson.asMap(item)))
        .whereType<LiveRoom>()
        .toList(growable: false);
    final pageInfo = ProviderJson.asMap(data['pageinfo']);
    final liveRoomInfo = ProviderJson.asMap(pageInfo['live_room']);
    final numPages = ProviderJson.asInt(liveRoomInfo['numPages']) ?? 1;

    return PagedResponse(
      items: items,
      hasMore: page < numPages,
      page: page,
    );
  }

  static LiveRoom mapSearchRoom(Map<String, dynamic> item) {
    final roomId = _normalizeRoomId(item['roomid']);
    if (roomId == null) {
      throw ProviderParseException(
        providerId: ProviderId.bilibili,
        message: 'Bilibili 搜索结果缺少有效 roomid。',
      );
    }
    return LiveRoom(
      providerId: ProviderId.bilibili.value,
      roomId: roomId,
      title: _stripHighlight(item['title']?.toString()),
      streamerName: normalizeDisplayText(item['uname']?.toString()),
      coverUrl: _normalizeAssetUrl(item['user_cover']?.toString()),
      keyframeUrl: _normalizeAssetUrl(item['cover']?.toString()),
      areaName: _stripHighlight(item['cate_name']?.toString()),
      streamerAvatarUrl: _normalizeAssetUrl(item['uface']?.toString()),
      viewerCount: ProviderJson.asInt(item['online']),
      isLive: (ProviderJson.asInt(item['live_status']) ?? 0) == 1,
    );
  }

  static LiveRoom? _tryMapSearchRoom(Map<String, dynamic> item) {
    if (_normalizeRoomId(item['roomid']) == null) {
      return null;
    }
    return mapSearchRoom(item);
  }

  static String? _normalizeRoomId(Object? value) {
    final roomId = value?.toString().trim() ?? '';
    if (roomId.isEmpty || roomId == 'null') {
      return null;
    }
    return roomId;
  }

  static LiveRoomDetail mapRoomDetail({
    required Map<String, dynamic> roomInfoData,
    required Map<String, dynamic> danmakuInfoData,
    required String requestedRoomId,
    required String buvid3,
    required String cookie,
    required int userId,
  }) {
    final roomInfo = ProviderJson.asMap(roomInfoData['room_info']);
    final anchorInfo = ProviderJson.asMap(roomInfoData['anchor_info']);
    final anchorBaseInfo = ProviderJson.asMap(anchorInfo['base_info']);
    final serverHosts = ProviderJson.asList(danmakuInfoData['host_list'])
        .map((item) => ProviderJson.asMap(item)['host']?.toString() ?? '')
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    final realRoomId = roomInfo['room_id']?.toString() ?? requestedRoomId;
    final liveStartTime = ProviderJson.asInt(roomInfo['live_start_time']);
    final danmakuMode = danmakuInfoData['mode']?.toString() ?? '';
    final danmakuToken = danmakuMode == 'unavailable'
        ? UnavailableDanmakuToken(
            reason: danmakuInfoData['reason']?.toString() ??
                '哔哩哔哩当前房间暂未拿到可用弹幕连接参数，请稍后刷新重试。',
            cause: danmakuInfoData['cause']?.toString(),
          )
        : BilibiliDanmakuToken(
            roomId: ProviderJson.asInt(realRoomId) ?? 0,
            uid: userId,
            token: danmakuInfoData['token']?.toString() ?? '',
            serverHost: serverHosts.isNotEmpty
                ? serverHosts.first
                : 'broadcastlv.chat.bilibili.com',
            buvid: buvid3,
            cookie: cookie,
          );

    return LiveRoomDetail(
      providerId: ProviderId.bilibili.value,
      roomId: realRoomId,
      title: normalizeDisplayText(roomInfo['title']?.toString()),
      streamerName: normalizeDisplayText(anchorBaseInfo['uname']?.toString()),
      streamerAvatarUrl: _normalizeAssetUrl(anchorBaseInfo['face']?.toString()),
      coverUrl: roomInfo['cover']?.toString(),
      keyframeUrl: roomInfo['keyframe']?.toString(),
      areaName: normalizeDisplayText(roomInfo['area_name']?.toString()),
      description: normalizeDisplayText(roomInfo['description']?.toString()),
      sourceUrl: 'https://live.bilibili.com/$requestedRoomId',
      startedAt: liveStartTime == null || liveStartTime <= 0
          ? null
          : DateTime.fromMillisecondsSinceEpoch(liveStartTime * 1000),
      isLive: (ProviderJson.asInt(roomInfo['live_status']) ?? 0) == 1,
      viewerCount: ProviderJson.asInt(roomInfo['online']),
      danmakuToken: danmakuToken,
      metadata: {
        'requestedRoomId': requestedRoomId,
        'shortId': roomInfo['short_id']?.toString(),
      },
    );
  }

  static List<LivePlayQuality> mapPlayQualities(Map<String, dynamic> response) {
    final playUrl = _playUrlPayload(response);
    final currentQn = ProviderJson.asInt(playUrl['current_qn']);
    final qualityMap = <int, String>{
      for (final item in ProviderJson.asList(playUrl['g_qn_desc']))
        ProviderJson.asInt(ProviderJson.asMap(item)['qn']) ?? 0:
            ProviderJson.asMap(item)['desc']?.toString() ?? '未知清晰度',
    };

    final firstCodec = _firstCodec(playUrl);
    final acceptQn = ProviderJson.asList(firstCodec['accept_qn']);
    final qualities = acceptQn
        .map((item) => ProviderJson.asInt(item) ?? 0)
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
    final urls = <({
      String url,
      String lineLabel,
      Map<String, Object?> metadata,
    })>[];

    for (final stream in ProviderJson.asList(playUrl['stream'])) {
      for (final format in ProviderJson.asList(
        ProviderJson.asMap(stream)['format'],
      )) {
        for (final codec in ProviderJson.asList(
          ProviderJson.asMap(format)['codec'],
        )) {
          final codecMap = ProviderJson.asMap(codec);
          final baseUrl = codecMap['base_url']?.toString() ?? '';
          for (final urlInfo in ProviderJson.asList(codecMap['url_info'])) {
            final urlInfoMap = ProviderJson.asMap(urlInfo);
            final host = urlInfoMap['host']?.toString() ?? '';
            final extra = urlInfoMap['extra']?.toString() ?? '';
            final fullUrl = '$host$baseUrl$extra';
            if (fullUrl.isEmpty) {
              continue;
            }
            final uri = Uri.tryParse(fullUrl);
            final qn = ProviderJson.asInt(codecMap['current_qn']) ??
                ProviderJson.asInt(playUrl['current_qn']) ??
                ProviderJson.asInt(uri?.queryParameters['qn']);
            final expectedQn = ProviderJson.asInt(
                  uri?.queryParameters['expected_qn'],
                ) ??
                qn;
            urls.add(
              (
                url: fullUrl,
                lineLabel: Uri.tryParse(host)?.host ?? host,
                metadata: <String, Object?>{
                  if (qn != null) 'qn': qn,
                  if (expectedQn != null) 'expectedQn': expectedQn,
                },
              ),
            );
          }
        }
      }
    }

    final uniqueUrls =
        <String, ({String lineLabel, Map<String, Object?> metadata})>{};
    for (final item in urls) {
      uniqueUrls.putIfAbsent(
        item.url,
        () => (lineLabel: item.lineLabel, metadata: item.metadata),
      );
    }

    final sorted = uniqueUrls.entries.toList(growable: false)
      ..sort((a, b) {
        final leftQn = ProviderJson.asInt(a.value.metadata['expectedQn']) ??
            ProviderJson.asInt(a.value.metadata['qn']) ??
            0;
        final rightQn = ProviderJson.asInt(b.value.metadata['expectedQn']) ??
            ProviderJson.asInt(b.value.metadata['qn']) ??
            0;
        final qualityCompare = rightQn.compareTo(leftQn);
        if (qualityCompare != 0) {
          return qualityCompare;
        }
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
              'user-agent': BilibiliSignService.defaultUserAgent,
            },
            lineLabel: entry.value.lineLabel,
            metadata: entry.value.metadata,
          ),
        )
        .toList(growable: false);
  }

  static Map<String, dynamic> _playUrlPayload(Map<String, dynamic> response) {
    final data = ProviderJson.asMap(response['data']);
    final playurlInfo = ProviderJson.asMap(data['playurl_info']);
    return ProviderJson.asMap(playurlInfo['playurl']);
  }

  static Map<String, dynamic> _firstCodec(Map<String, dynamic> playUrl) {
    final streams = ProviderJson.asList(playUrl['stream']);
    final stream = streams.isEmpty
        ? const <String, dynamic>{}
        : ProviderJson.asMap(streams.first);
    final formats = ProviderJson.asList(stream['format']);
    final format = formats.isEmpty
        ? const <String, dynamic>{}
        : ProviderJson.asMap(formats.first);
    final codecs = ProviderJson.asList(format['codec']);
    return codecs.isEmpty
        ? const <String, dynamic>{}
        : ProviderJson.asMap(codecs.first);
  }

  static String _stripHighlight(String? value) {
    return normalizeDisplayText(
      (value ?? '').replaceAll(RegExp(r'<.*?em.*?>'), ''),
    );
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
}
