import 'dart:convert';
import 'dart:developer' as developer;

import 'package:live_core/live_core.dart';
import 'package:live_storage/live_storage.dart';

import 'sync_snapshot.dart';

class SyncSnapshotJsonCodec {
  const SyncSnapshotJsonCodec._();

  static const int currentFormatVersion = 3;

  static String encode(SyncSnapshot snapshot) {
    return jsonEncode(_toJson(snapshot));
  }

  static SyncSnapshot decode(String rawJson) {
    final decoded = jsonDecode(rawJson);
    if (decoded is! Map) {
      throw const FormatException('Sync snapshot JSON must be an object.');
    }
    final json = decoded is Map<String, dynamic>
        ? decoded
        : decoded.map((key, value) => MapEntry(key.toString(), value));
    _validateFormatVersion(json['format_version']);
    if (!_looksLikeSnapshotJson(json)) {
      throw const FormatException(
        'Sync snapshot JSON must include at least one snapshot section.',
      );
    }
    return _fromJson(json);
  }

  static Map<String, Object?> _toJson(SyncSnapshot snapshot) {
    return {
      'format_version': currentFormatVersion,
      'settings': snapshot.settings,
      'blocked_keywords': snapshot.blockedKeywords,
      'tags': snapshot.tags,
      'history': [
        for (final item in snapshot.history)
          {
            'provider_id': item.providerId.value,
            'room_id': item.roomId,
            'title': item.title,
            'streamer_name': item.streamerName,
            'viewed_at': item.viewedAt.toIso8601String(),
            'watch_duration_sec': item.watchDurationSec,
            'sync_duration_sec': item.syncDurationSec,
            if (item.updatedAt != null)
              'updated_at': item.updatedAt!.toIso8601String(),
          },
      ],
      'follows': [
        for (final item in snapshot.follows)
          {
            'provider_id': item.providerId.value,
            'room_id': item.roomId,
            'streamer_name': item.streamerName,
            'streamer_avatar_url': item.streamerAvatarUrl,
            'last_title': item.lastTitle,
            'last_area_name': item.lastAreaName,
            'last_cover_url': item.lastCoverUrl,
            'last_keyframe_url': item.lastKeyframeUrl,
            'tags': item.tags,
            if (item.remark != null) 'remark': item.remark,
            'deleted': item.deleted,
            if (item.addedAt != null)
              'added_at': item.addedAt!.toIso8601String(),
            if (item.updatedAt != null)
              'updated_at': item.updatedAt!.toIso8601String(),
            'watch_duration_sec': item.watchDurationSec,
            'sync_duration_sec': item.syncDurationSec,
            if (item.lastLiveStatus != null)
              'last_live_status': item.lastLiveStatus,
            if (item.lastOnline != null) 'last_online': item.lastOnline,
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

    final records = <HistoryRecord>[];
    var droppedCount = 0;
    for (final item in raw) {
      if (item is! Map) {
        droppedCount++;
        continue;
      }
      try {
        final viewedAtRaw = item['viewed_at']?.toString();
        final viewedAt = viewedAtRaw == null || viewedAtRaw.isEmpty
            ? null
            : DateTime.tryParse(viewedAtRaw);
        if (viewedAt == null) {
          throw FormatException(
            'Invalid history viewed_at timestamp: ${viewedAtRaw ?? '<missing>'}',
          );
        }
        final providerId = item['provider_id']?.toString() ?? '';
        final roomId = item['room_id']?.toString() ?? '';
        if (providerId.isEmpty || roomId.isEmpty) {
          throw FormatException('Missing provider_id or room_id');
        }
        records.add(
          HistoryRecord(
            providerId: ProviderId.from(providerId),
            roomId: roomId,
            title: item['title']?.toString() ?? '',
            streamerName: item['streamer_name']?.toString() ?? '',
            viewedAt: viewedAt,
            watchDurationSec: _decodeInt(item['watch_duration_sec']),
            syncDurationSec: _decodeInt(item['sync_duration_sec']),
            updatedAt: DateTime.tryParse(item['updated_at']?.toString() ?? ''),
          ),
        );
      } catch (error, stackTrace) {
        droppedCount++;
        developer.log(
          'Skipping corrupt history record.',
          name: 'live_sync.codec',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
    if (droppedCount > 0) {
      developer.log(
        'Dropped $droppedCount corrupt history records during sync snapshot decode.',
        name: 'live_sync.codec',
      );
    }
    return List<HistoryRecord>.unmodifiable(records);
  }

  static void _validateFormatVersion(Object? rawVersion) {
    if (rawVersion == null) {
      return;
    }
    final version = switch (rawVersion) {
      int value => value,
      num value => value.toInt(),
      _ => int.tryParse(rawVersion.toString()),
    };
    if (version == null || version <= 0) {
      throw const FormatException('Sync snapshot format_version is invalid.');
    }
    if (version > currentFormatVersion) {
      throw FormatException(
        'Sync snapshot format_version $version is newer than supported version $currentFormatVersion.',
      );
    }
  }

  static List<FollowRecord> _decodeFollows(Object? raw) {
    if (raw is! List) {
      return const <FollowRecord>[];
    }

    return raw
        .whereType<Map>()
        .map((item) {
          return FollowRecord(
            providerId: ProviderId.from(item['provider_id']),
            roomId: item['room_id']?.toString() ?? '',
            streamerName: item['streamer_name']?.toString() ?? '',
            streamerAvatarUrl: _optionalString(item['streamer_avatar_url']),
            lastTitle: _optionalString(item['last_title']),
            lastAreaName: _optionalString(item['last_area_name']),
            lastCoverUrl: _optionalString(item['last_cover_url']),
            lastKeyframeUrl: _optionalString(item['last_keyframe_url']),
            tags: _stringList(item['tags']),
            remark: _optionalString(item['remark']),
            deleted: item['deleted'] == true,
            addedAt: DateTime.tryParse(item['added_at']?.toString() ?? ''),
            updatedAt: DateTime.tryParse(item['updated_at']?.toString() ?? ''),
            watchDurationSec: _decodeInt(item['watch_duration_sec']),
            syncDurationSec: _decodeInt(item['sync_duration_sec']),
            lastLiveStatus: _decodeNullableInt(item['last_live_status']),
            lastOnline: _decodeNullableInt(item['last_online']),
          );
        })
        .where((item) {
          return item.providerId.isNotEmpty && item.roomId.isNotEmpty;
        })
        .toList(growable: false);
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

  static int _decodeInt(Object? raw, {int fallback = 0}) {
    if (raw is int) {
      return raw;
    }
    if (raw is num) {
      return raw.toInt();
    }
    return int.tryParse(raw?.toString() ?? '') ?? fallback;
  }

  static int? _decodeNullableInt(Object? raw) {
    if (raw == null) {
      return null;
    }
    if (raw is int) {
      return raw;
    }
    if (raw is num) {
      return raw.toInt();
    }
    return int.tryParse(raw.toString());
  }

  static bool _looksLikeSnapshotJson(Map<String, dynamic> json) {
    return json.containsKey('settings') ||
        json.containsKey('blocked_keywords') ||
        json.containsKey('tags') ||
        json.containsKey('history') ||
        json.containsKey('follows');
  }
}
