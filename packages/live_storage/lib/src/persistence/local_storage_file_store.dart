import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/follow_record.dart';
import '../models/history_record.dart';

class LocalStorageFileStore {
  LocalStorageFileStore._({required this.file});

  final File file;

  static Future<LocalStorageFileStore> open({required File file}) async {
    final store = LocalStorageFileStore._(file: file);
    await store._ensureLoaded();
    return store;
  }

  FileStorageSnapshot _snapshot = const FileStorageSnapshot();
  Future<void> _pending = Future<void>.value();
  bool _loaded = false;

  Map<String, Object?> settingsSnapshot() {
    return _cloneSettingsMap(_snapshot.settings);
  }

  Future<T> read<T>(T Function(FileStorageSnapshot snapshot) reader) async {
    await _pending;
    await _ensureLoaded();
    return reader(_snapshot.clone());
  }

  Future<T> update<T>(T Function(FileStorageSnapshot snapshot) updater) {
    final completer = Completer<T>();
    _pending = _pending.then((_) async {
      await _ensureLoaded();
      final next = _snapshot.clone();
      final result = updater(next);
      _snapshot = next.clone();
      await _persistSnapshot(_snapshot);
      completer.complete(result);
    }).catchError((Object error, StackTrace stackTrace) {
      if (!completer.isCompleted) {
        completer.completeError(error, stackTrace);
      }
      throw error;
    });
    return completer.future;
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) {
      return;
    }
    await file.parent.create(recursive: true);
    if (!await file.exists()) {
      _snapshot = const FileStorageSnapshot();
      await _persistSnapshot(_snapshot);
      _loaded = true;
      return;
    }

    try {
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) {
        _snapshot = const FileStorageSnapshot();
      } else {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          _snapshot = FileStorageSnapshot.fromJson(decoded);
        } else if (decoded is Map) {
          _snapshot = FileStorageSnapshot.fromJson(
            decoded.map(
              (key, value) => MapEntry(key.toString(), value),
            ),
          );
        } else {
          _snapshot = const FileStorageSnapshot();
        }
      }
    } on FormatException {
      _snapshot = const FileStorageSnapshot();
    }
    _loaded = true;
  }

  Future<void> _persistSnapshot(FileStorageSnapshot snapshot) async {
    final tempFile = File('${file.path}.tmp');
    final encoder = const JsonEncoder.withIndent('  ');
    await tempFile.writeAsString(
      encoder.convert(snapshot.toJson()),
      flush: true,
    );
    if (await file.exists()) {
      await file.delete();
    }
    await tempFile.rename(file.path);
  }
}

class FileStorageSnapshot {
  const FileStorageSnapshot({
    this.settings = const <String, Object?>{},
    this.history = const <HistoryRecord>[],
    this.follows = const <FollowRecord>[],
    this.tags = const <String>[],
  });

  final Map<String, Object?> settings;
  final List<HistoryRecord> history;
  final List<FollowRecord> follows;
  final List<String> tags;

  FileStorageSnapshot clone() {
    return FileStorageSnapshot(
      settings: _cloneSettingsMap(settings),
      history: List<HistoryRecord>.from(history),
      follows: List<FollowRecord>.from(follows),
      tags: List<String>.from(tags),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'settings': _cloneSettingsMap(settings),
      'history': [
        for (final item in history)
          {
            'provider_id': item.providerId,
            'room_id': item.roomId,
            'title': item.title,
            'streamer_name': item.streamerName,
            'viewed_at': item.viewedAt.toIso8601String(),
          },
      ],
      'follows': [
        for (final item in follows)
          {
            'provider_id': item.providerId,
            'room_id': item.roomId,
            'streamer_name': item.streamerName,
            'streamer_avatar_url': item.streamerAvatarUrl,
            'last_title': item.lastTitle,
            'last_area_name': item.lastAreaName,
            'last_cover_url': item.lastCoverUrl,
            'last_keyframe_url': item.lastKeyframeUrl,
            'tags': List<String>.from(item.tags),
          },
      ],
      'tags': List<String>.from(tags),
    };
  }

  static FileStorageSnapshot fromJson(Map<String, dynamic> json) {
    final settings = <String, Object?>{};
    final rawSettings = json['settings'];
    if (rawSettings is Map) {
      for (final entry in rawSettings.entries) {
        settings[entry.key.toString()] = _normalizeJsonValue(entry.value);
      }
    }

    return FileStorageSnapshot(
      settings: settings,
      history: _decodeHistory(json['history']),
      follows: _decodeFollows(json['follows']),
      tags: _decodeTags(json['tags']),
    );
  }

  static List<HistoryRecord> _decodeHistory(Object? raw) {
    if (raw is! List) {
      return const <HistoryRecord>[];
    }
    return raw.whereType<Map>().map((item) {
      final viewedAt = DateTime.tryParse(item['viewed_at']?.toString() ?? '');
      return HistoryRecord(
        providerId: item['provider_id']?.toString() ?? '',
        roomId: item['room_id']?.toString() ?? '',
        title: item['title']?.toString() ?? '',
        streamerName: item['streamer_name']?.toString() ?? '',
        viewedAt: viewedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
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
        streamerAvatarUrl: _normalizeOptionalString(
          item['streamer_avatar_url'],
        ),
        lastTitle: _normalizeOptionalString(item['last_title']),
        lastAreaName: _normalizeOptionalString(item['last_area_name']),
        lastCoverUrl: _normalizeOptionalString(item['last_cover_url']),
        lastKeyframeUrl: _normalizeOptionalString(item['last_keyframe_url']),
        tags: _decodeTags(item['tags']),
      );
    }).where((item) {
      return item.providerId.isNotEmpty && item.roomId.isNotEmpty;
    }).toList(growable: false);
  }

  static List<String> _decodeTags(Object? raw) {
    if (raw is! List) {
      return const <String>[];
    }
    final tags = raw
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList(growable: false);
    tags.sort();
    return tags;
  }
}

String? _normalizeOptionalString(Object? raw) {
  final value = raw?.toString().trim() ?? '';
  return value.isEmpty ? null : value;
}

Map<String, Object?> _cloneSettingsMap(Map<String, Object?> values) {
  return Map<String, Object?>.fromEntries(
    values.entries.map(
      (entry) => MapEntry(entry.key, _normalizeJsonValue(entry.value)),
    ),
  );
}

Object? _normalizeJsonValue(Object? value) {
  if (value == null || value is String || value is bool) {
    return value;
  }
  if (value is int || value is double) {
    return value;
  }
  if (value is num) {
    return value.toDouble();
  }
  if (value is List) {
    return value.map(_normalizeJsonValue).toList(growable: false);
  }
  if (value is Map) {
    return Map<String, Object?>.fromEntries(
      value.entries.map(
        (entry) => MapEntry(
          entry.key.toString(),
          _normalizeJsonValue(entry.value),
        ),
      ),
    );
  }
  return value.toString();
}
