import 'package:live_core/live_core.dart';

import 'chaturbate_hls_master_playlist_parser.dart';
import 'chaturbate_room_page_parser.dart';

class ChaturbateMapper {
  const ChaturbateMapper._();

  static const String categoriesRootId = 'genders';
  static const List<LiveCategory> categories = [
    LiveCategory(
      id: categoriesRootId,
      name: 'Genders',
      children: [
        LiveSubCategory(
            id: 'female', parentId: categoriesRootId, name: 'Female'),
        LiveSubCategory(id: 'male', parentId: categoriesRootId, name: 'Male'),
        LiveSubCategory(
            id: 'couple', parentId: categoriesRootId, name: 'Couple'),
        LiveSubCategory(id: 'trans', parentId: categoriesRootId, name: 'Trans'),
      ],
    ),
  ];

  static LiveRoom mapRecommendRoom(Map<String, dynamic> payload) {
    return _mapRoom(
      payload,
      roomId: _firstNonEmpty([
        payload['room']?.toString(),
        payload['username']?.toString(),
      ]),
      viewerCount: _asInt(payload['viewers']),
    );
  }

  static LiveRoom mapSearchRoom(Map<String, dynamic> payload) {
    return _mapRoom(
      payload,
      roomId: _firstNonEmpty([
        payload['username']?.toString(),
        payload['room']?.toString(),
      ]),
      viewerCount: _asInt(payload['num_users']) ?? _asInt(payload['viewers']),
    );
  }

  static LiveRoom _mapRoom(
    Map<String, dynamic> payload, {
    required String roomId,
    required int? viewerCount,
  }) {
    final title = _firstNonEmpty([
      normalizeDisplayText(payload['room_subject']?.toString()),
      normalizeDisplayText(payload['subject']?.toString()),
      roomId,
    ]);

    return LiveRoom(
      providerId: ProviderId.chaturbate.value,
      roomId: roomId,
      title: title,
      streamerName: roomId,
      coverUrl: _nonEmptyString(payload['img']),
      areaName: _genderLabel(payload['gender']),
      viewerCount: viewerCount,
      isLive: true,
    );
  }

  static LiveRoomDetail mapRoomDetail(Map<String, dynamic> dossier) {
    return _mapRoomDetail(
      dossier: dossier,
      csrfToken: '',
      pushService: const {},
    );
  }

  static LiveRoomDetail mapRoomDetailFromPageContext(
    ChaturbateRoomPageContext context,
  ) {
    return _mapRoomDetail(
      dossier: context.dossier,
      csrfToken: context.csrfToken,
      pushService: context.primaryPushService,
    );
  }

  static LiveRoomDetail _mapRoomDetail({
    required Map<String, dynamic> dossier,
    required String csrfToken,
    required Map<String, dynamic> pushService,
  }) {
    final roomId = dossier['broadcaster_username']?.toString() ?? '';
    final broadcasterUid = dossier['broadcaster_uid']?.toString() ?? '';
    final roomUid = dossier['room_uid']?.toString() ?? '';
    final roomStatus = dossier['room_status']?.toString() ?? '';
    final edgeRegion = dossier['edge_region']?.toString() ?? '';
    final hlsSource = dossier['hls_source']?.toString() ?? '';
    final metadata = <String, Object?>{
      'roomStatus': roomStatus,
      'roomUid': roomUid,
      'broadcasterUid': broadcasterUid,
      'edgeRegion': edgeRegion,
      'allowPrivateShows': dossier['allow_private_shows'],
      'privateShowPrice': _asInt(dossier['private_show_price']),
      'spyPrivateShowPrice': _asInt(dossier['spy_private_show_price']),
      'hlsSource': hlsSource,
    };

    return LiveRoomDetail(
      providerId: ProviderId.chaturbate.value,
      roomId: roomId,
      title: _firstNonEmpty([
        normalizeDisplayText(dossier['room_title']?.toString()),
        roomId,
      ]),
      streamerName: roomId,
      areaName: _genderLabel(dossier['broadcaster_gender']),
      sourceUrl:
          roomId.isEmpty ? null : 'https://chaturbate.com/${roomId.trim()}/',
      isLive: roomStatus == 'public',
      viewerCount: _asInt(dossier['num_viewers']),
      danmakuToken: _buildDanmakuToken(
        roomId: roomId,
        broadcasterUid: broadcasterUid,
        roomUid: roomUid,
        csrfToken: csrfToken,
        pushService: pushService,
      ),
      metadata: metadata,
    );
  }

  static List<LivePlayQuality> mapPlayQualities(LiveRoomDetail detail) {
    return const [
      LivePlayQuality(
        id: 'auto',
        label: 'Auto',
        isDefault: true,
      ),
    ];
  }

  static List<LivePlayQuality> mapPlayQualitiesFromVariants({
    required List<ChaturbateHlsVariant> variants,
  }) {
    final qualities = <LivePlayQuality>[
      const LivePlayQuality(
        id: 'auto',
        label: 'Auto',
        isDefault: true,
      ),
    ];
    for (final variant in variants) {
      qualities.add(
        LivePlayQuality(
          id: variant.bandwidth.toString(),
          label: variant.label,
          sortOrder: variant.sortOrder,
          metadata: {
            'playlistUrl': variant.url,
            'bandwidth': variant.bandwidth,
            'width': variant.width,
            'height': variant.height,
          },
        ),
      );
    }
    return qualities;
  }

  static List<LivePlayUrl> mapPlayUrls(
    LiveRoomDetail detail,
    LivePlayQuality quality,
  ) {
    final metadata = detail.metadata ?? const <String, Object?>{};
    final selectedUrl = _firstNonEmpty([
      quality.metadata?['playlistUrl']?.toString(),
      metadata['hlsSource']?.toString(),
    ]);
    if (selectedUrl.isEmpty) {
      return const [];
    }

    final edgeRegion = metadata['edgeRegion']?.toString() ?? '';
    return [
      LivePlayUrl(
        url: selectedUrl,
        lineLabel: edgeRegion.isEmpty ? null : edgeRegion,
        metadata: quality.metadata,
      ),
    ];
  }

  static String? genderQueryForCategory(LiveSubCategory category) {
    return switch (category.id.trim().toLowerCase()) {
      'female' => 'f',
      'male' => 'm',
      'couple' => 'c',
      'trans' => 't',
      _ => null,
    };
  }

  static LiveMessage? mapDanmakuPayload(Map<String, dynamic> payload) {
    final topic = _resolveTopic(payload);
    final event = _unwrapEvent(payload);
    final timestamp = _asDateTime(event['pub_ts'] ?? event['ts']);
    switch (topic) {
      case 'RoomMessageTopic':
        final content = normalizeDisplayText(event['message']?.toString());
        if (content.isEmpty) {
          return null;
        }
        final fromUser = _asMap(event['from_user']);
        final userName = _nonEmptyString(
          _firstNonEmpty([
            fromUser['username']?.toString(),
            event['from_username']?.toString(),
          ]),
        );
        return LiveMessage(
          type: LiveMessageType.chat,
          userName: userName,
          content: content,
          timestamp: timestamp,
          payload: event,
        );
      case 'RoomTipAlertTopic':
        final amount = _asInt(event['amount']);
        final note = normalizeDisplayText(event['message']?.toString());
        final content = note.isEmpty
            ? amount == null
                ? '送出打赏'
                : '送出 $amount tokens'
            : amount == null
                ? '送出打赏 · $note'
                : '送出 $amount tokens · $note';
        return LiveMessage(
          type: LiveMessageType.gift,
          userName: _nonEmptyString(event['from_username']),
          content: content,
          timestamp: timestamp,
          payload: event,
        );
      case 'RoomNoticeTopic':
        final messages = _asList(event['messages'])
            .map((item) => normalizeDisplayText(item?.toString()))
            .where((item) => item.isNotEmpty)
            .toList(growable: false);
        final content = messages.isNotEmpty
            ? messages.join(' ')
            : normalizeDisplayText(event['message']?.toString());
        if (content.isEmpty) {
          return null;
        }
        return LiveMessage(
          type: LiveMessageType.notice,
          content: content,
          timestamp: timestamp,
          payload: event,
        );
      case 'RoomFanClubJoinedTopic':
        final userName = _nonEmptyString(event['from_username']);
        return LiveMessage(
          type: LiveMessageType.member,
          userName: userName,
          content: userName == null ? '有用户加入粉丝团' : '$userName 加入了粉丝团',
          timestamp: timestamp,
          payload: event,
        );
      case 'RoomPurchaseTopic':
        final userName = _nonEmptyString(event['from_username']);
        final content = _firstNonEmpty([
          normalizeDisplayText(event['message']?.toString()),
          '购买了房间内容',
        ]);
        return LiveMessage(
          type: LiveMessageType.notice,
          userName: userName,
          content: content,
          timestamp: timestamp,
          payload: event,
        );
      default:
        final content = _firstNonEmpty([
          normalizeDisplayText(event['message']?.toString()),
          normalizeDisplayText(_asList(event['messages']).join(' ')),
        ]);
        if (content.isEmpty) {
          return null;
        }
        return LiveMessage(
          type: LiveMessageType.notice,
          content: content,
          timestamp: timestamp,
          payload: event,
        );
    }
  }

  static String? dedupeKeyForDanmakuPayload(Map<String, dynamic> payload) {
    final event = _unwrapEvent(payload);
    return _nonEmptyString(
      _firstNonEmpty([
        event['tid']?.toString(),
        event['id']?.toString(),
      ]),
    );
  }

  static Map<String, Object?>? _buildDanmakuToken({
    required String roomId,
    required String broadcasterUid,
    required String roomUid,
    required String csrfToken,
    required Map<String, dynamic> pushService,
  }) {
    if (roomId.isEmpty || broadcasterUid.isEmpty || csrfToken.isEmpty) {
      return null;
    }
    return {
      'roomId': roomId,
      'roomUid': roomUid,
      'broadcasterUid': broadcasterUid,
      'csrfToken': csrfToken,
      'backend': _firstNonEmpty([
        pushService['backend']?.toString(),
        'a',
      ]),
      'host': _nonEmptyString(pushService['host']),
      'restHost': _nonEmptyString(pushService['rest_host']),
      'fallbackHosts': _asList(pushService['fallback_hosts'])
          .map((item) => item?.toString() ?? '')
          .where((item) => item.isNotEmpty)
          .toList(growable: false),
    };
  }

  static String _resolveTopic(Map<String, dynamic> payload) {
    final event = _unwrapEvent(payload);
    final topic = event['_topic']?.toString().trim() ?? '';
    if (topic.isNotEmpty) {
      return topic;
    }
    if (payload.length == 1) {
      final key = payload.keys.single;
      return key.split('#').first;
    }
    return '';
  }

  static Map<String, dynamic> _unwrapEvent(Map<String, dynamic> payload) {
    if (payload.length == 1) {
      final entry = payload.entries.single;
      final value = _asMap(entry.value);
      if (value.isNotEmpty) {
        return value;
      }
    }
    return payload;
  }

  static String _firstNonEmpty(List<String?> values) {
    for (final value in values) {
      final trimmed = value?.trim() ?? '';
      if (trimmed.isNotEmpty) {
        return trimmed;
      }
    }
    return '';
  }

  static String? _genderLabel(Object? rawGender) {
    final value = rawGender?.toString().trim().toLowerCase() ?? '';
    return switch (value) {
      'f' || 'female' => 'Female',
      'm' || 'male' => 'Male',
      'c' || 'couple' => 'Couple',
      's' || 'trans' => 'Trans',
      _ => null,
    };
  }

  static String? _nonEmptyString(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  static List<dynamic> _asList(Object? value) {
    if (value is List) {
      return value;
    }
    return const [];
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

  static int? _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '');
  }

  static DateTime? _asDateTime(Object? value) {
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch((value * 1000).round());
    }
    final parsed = num.tryParse(value?.toString() ?? '');
    if (parsed == null) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch((parsed * 1000).round());
  }
}
