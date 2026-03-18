import 'dart:convert';

import 'package:live_storage/live_storage.dart';

import 'sync_snapshot.dart';

class SyncSnapshotJsonCodec {
  const SyncSnapshotJsonCodec._();

  static String encode(SyncSnapshot snapshot) {
    return jsonEncode(_toJson(snapshot));
  }

  static SyncSnapshot decode(String rawJson) {
    final decoded = jsonDecode(rawJson);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Sync snapshot JSON must be an object.');
    }
    if (!_looksLikeSnapshotJson(decoded)) {
      throw const FormatException(
        'Sync snapshot JSON must include at least one snapshot section.',
      );
    }
    return _fromJson(decoded);
  }

  static Map<String, Object?> _toJson(SyncSnapshot snapshot) {
    return {
      'settings': snapshot.settings,
      'blocked_keywords': snapshot.blockedKeywords,
      'tags': snapshot.tags,
      'history': [
        for (final item in snapshot.history)
          {
            'provider_id': item.providerId,
            'room_id': item.roomId,
            'title': item.title,
            'streamer_name': item.streamerName,
            'viewed_at': item.viewedAt.toIso8601String(),
          },
      ],
      'follows': [
        for (final item in snapshot.follows)
          {
            'provider_id': item.providerId,
            'room_id': item.roomId,
            'streamer_name': item.streamerName,
            'streamer_avatar_url': item.streamerAvatarUrl,
            'last_title': item.lastTitle,
            'last_area_name': item.lastAreaName,
            'last_cover_url': item.lastCoverUrl,
            'last_keyframe_url': item.lastKeyframeUrl,
            'tags': item.tags,
          },
      ],
    };
  }

  static SyncSnapshot _fromJson(Map<String, dynamic> json) {
    final settings = <String, Object?>{};
    final settingsJson = json['settings'];
    if (settingsJson is Map) {
      for (final entry in settingsJson.entries) {
        if (entry.key is String) {
          settings[entry.key as String] = entry.value;
        }
      }
    }

    final blockedKeywords = _stringList(json['blocked_keywords']);
    final tags = _stringList(json['tags']);

    return SyncSnapshot(
      settings: settings,
      blockedKeywords: blockedKeywords,
      tags: tags,
      history: _decodeHistory(json['history']),
      follows: _decodeFollows(json['follows']),
    );
  }

  static List<HistoryRecord> _decodeHistory(Object? raw) {
    if (raw is! List) {
      return const <HistoryRecord>[];
    }

    return raw.whereType<Map>().map((item) {
      final viewedAtRaw = item['viewed_at']?.toString();
      final viewedAt = viewedAtRaw == null
          ? DateTime.fromMillisecondsSinceEpoch(0)
          : DateTime.tryParse(viewedAtRaw) ??
              DateTime.fromMillisecondsSinceEpoch(0);
      return HistoryRecord(
        providerId: item['provider_id']?.toString() ?? '',
        roomId: item['room_id']?.toString() ?? '',
        title: item['title']?.toString() ?? '',
        streamerName: item['streamer_name']?.toString() ?? '',
        viewedAt: viewedAt,
      );
    }).where((item) {
      return item.providerId.isNotEmpty && item.roomId.isNotEmpty;
    }).toList(growable: false);
  }

  static List<FollowRecord> _decodeFollows(Object? raw) {
    if (raw is! List) {
      return const <FollowRecord>[];
    }

    return raw.whereType<Map>().map((item) {
      return FollowRecord(
        providerId: item['provider_id']?.toString() ?? '',
        roomId: item['room_id']?.toString() ?? '',
        streamerName: item['streamer_name']?.toString() ?? '',
        streamerAvatarUrl: _optionalString(item['streamer_avatar_url']),
        lastTitle: _optionalString(item['last_title']),
        lastAreaName: _optionalString(item['last_area_name']),
        lastCoverUrl: _optionalString(item['last_cover_url']),
        lastKeyframeUrl: _optionalString(item['last_keyframe_url']),
        tags: _stringList(item['tags']),
      );
    }).where((item) {
      return item.providerId.isNotEmpty && item.roomId.isNotEmpty;
    }).toList(growable: false);
  }

  static List<String> _stringList(Object? raw) {
    if (raw is! List) {
      return const <String>[];
    }
    return raw
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList(growable: false)
      ..sort();
  }

  static String? _optionalString(Object? raw) {
    final value = raw?.toString().trim() ?? '';
    return value.isEmpty ? null : value;
  }

  static bool _looksLikeSnapshotJson(Map<String, dynamic> json) {
    return json.containsKey('settings') ||
        json.containsKey('blocked_keywords') ||
        json.containsKey('tags') ||
        json.containsKey('history') ||
        json.containsKey('follows');
  }
}
