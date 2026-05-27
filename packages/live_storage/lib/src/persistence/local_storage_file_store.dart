import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/follow_record.dart';
import '../models/history_record.dart';

class LocalStorageFileStore {
  LocalStorageFileStore._({
    required this.file,
    LocalStorageFileSystem fileSystem = const LocalStorageFileSystem(),
  }) : _fileSystem = fileSystem;

  final File file;
  final LocalStorageFileSystem _fileSystem;

  static Future<LocalStorageFileStore> open({
    required File file,
    bool repairCorruptFile = false,
    LocalStorageFileSystem fileSystem = const LocalStorageFileSystem(),
  }) async {
    final store = LocalStorageFileStore._(file: file, fileSystem: fileSystem);
    try {
      await store._ensureLoaded();
    } on LocalStorageCorruptionException catch (error) {
      if (!repairCorruptFile) {
        rethrow;
      }
      store._lastRecoveryInfo = await store._repairCorruptFile(error);
    }
    return store;
  }

  FileStorageSnapshot _snapshot = const FileStorageSnapshot();
  Future<void> _pending = Future<void>.value();
  bool _loaded = false;
  LocalStorageRecoveryInfo? _lastRecoveryInfo;

  LocalStorageRecoveryInfo? get lastRecoveryInfo => _lastRecoveryInfo;

  Map<String, Object?> settingsSnapshot() {
    return _cloneSettingsMap(_snapshot.settings);
  }

  Future<T> read<T>(T Function(FileStorageSnapshot snapshot) reader) async {
    await _pending;
    await _ensureLoaded();
    return reader(_snapshot.clone());
  }

  Future<T> update<T>(T Function(FileStorageSnapshot snapshot) updater) {
    final operation = _pending.then((_) async {
      await _ensureLoaded();
      final next = _snapshot.clone();
      final result = updater(next);
      await _persistSnapshot(next);
      _snapshot = next.clone();
      return result;
    });
    _pending = operation.then<void>((_) {}, onError: (_, __) {});
    return operation;
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) {
      return;
    }
    await _fileSystem.createDirectory(file.parent);
    await _recoverPendingReplacement();
    if (!await _fileSystem.exists(file)) {
      _snapshot = const FileStorageSnapshot();
      await _persistSnapshot(_snapshot);
      _loaded = true;
      return;
    }

    final raw = await _fileSystem.readAsString(file);
    if (raw.trim().isEmpty) {
      _snapshot = const FileStorageSnapshot();
      _loaded = true;
      return;
    }

    try {
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
        throw const FormatException(
          'Local storage snapshot JSON must be an object.',
        );
      }
    } on FormatException catch (error, stackTrace) {
      throw LocalStorageCorruptionException(
        file: file,
        message: 'Malformed local storage snapshot.',
        cause: error,
        causeStackTrace: stackTrace,
      );
    } on Object catch (error, stackTrace) {
      throw LocalStorageCorruptionException(
        file: file,
        message: 'Failed to decode local storage snapshot.',
        cause: error,
        causeStackTrace: stackTrace,
      );
    }
    _loaded = true;
  }

  Future<LocalStorageRecoveryInfo> _repairCorruptFile(
    LocalStorageCorruptionException error,
  ) async {
    final raw = await _fileSystem.readAsString(file);
    final backupFile = await _backupCorruptFile();
    final recovery = _recoverSnapshotSections(raw);
    _snapshot = recovery.snapshot;
    await _persistSnapshot(_snapshot);
    _loaded = true;
    return LocalStorageRecoveryInfo(
      corruptedFilePath: file.path,
      backupFilePath: backupFile.path,
      reason: error.message,
      recoveredSections: recovery.recoveredSections,
    );
  }

  Future<File> _backupCorruptFile() async {
    final suffix = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(':', '')
        .replaceAll('.', '')
        .replaceAll('-', '');
    final backupFile = File('${file.path}.corrupt-$suffix.bak');
    await _safeDelete(backupFile);
    try {
      await _fileSystem.rename(file, backupFile.path);
    } on FileSystemException {
      await _fileSystem.copy(file, backupFile.path);
    }
    return backupFile;
  }

  Future<void> _persistSnapshot(FileStorageSnapshot snapshot) async {
    final tempFile = File('${file.path}.tmp');
    final backupFile = _replacementBackupFile();
    final encoder = const JsonEncoder.withIndent('  ');
    await _safeDelete(tempFile);
    await _safeDelete(backupFile);
    await _fileSystem.writeAsString(
      tempFile,
      encoder.convert(snapshot.toJson()),
      flush: true,
    );
    if (!await _fileSystem.exists(file)) {
      await _replaceMissingTarget(tempFile, file);
      await _decodeSnapshotFile(file);
      return;
    }

    await _safeDelete(backupFile);
    var backupReady = false;
    try {
      try {
        await _fileSystem.rename(file, backupFile.path);
      } on FileSystemException {
        await _fileSystem.copy(file, backupFile.path);
      }
      backupReady = true;

      if (await _fileSystem.exists(file)) {
        await _fileSystem.delete(file);
      }

      await _replaceMissingTarget(tempFile, file);
      await _decodeSnapshotFile(file);
    } catch (_) {
      if (backupReady && await _fileSystem.exists(backupFile)) {
        await _restoreBackup(backupFile);
      }
      rethrow;
    } finally {
      await _safeDeleteBestEffort(tempFile);
      await _safeDeleteBestEffort(backupFile);
    }
  }

  Future<void> _recoverPendingReplacement() async {
    final tempFile = File('${file.path}.tmp');
    final backupFile = _replacementBackupFile();
    final hasTarget = await _fileSystem.exists(file);
    final hasTemp = await _fileSystem.exists(tempFile);
    final hasBackup = await _fileSystem.exists(backupFile);

    if (!hasTarget) {
      if (hasTemp && await _canDecodeSnapshotFile(tempFile)) {
        await _replaceMissingTarget(tempFile, file);
        await _safeDeleteBestEffort(backupFile);
        return;
      }
      if (hasBackup) {
        await _restoreBackup(backupFile);
      }
      await _safeDeleteBestEffort(tempFile);
      return;
    }

    if (hasTarget && !await _canDecodeSnapshotFile(file) && hasBackup) {
      await _restoreBackup(backupFile);
    } else {
      await _safeDeleteBestEffort(backupFile);
    }
    await _safeDeleteBestEffort(tempFile);
  }

  Future<FileStorageSnapshot> _decodeSnapshotFile(File candidate) async {
    final raw = await _fileSystem.readAsString(candidate);
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      return FileStorageSnapshot.fromJson(decoded);
    }
    if (decoded is Map) {
      return FileStorageSnapshot.fromJson(
        decoded.map((key, value) => MapEntry(key.toString(), value)),
      );
    }
    throw const FormatException(
        'Local storage snapshot JSON must be an object.');
  }

  Future<bool> _canDecodeSnapshotFile(File candidate) async {
    try {
      await _decodeSnapshotFile(candidate);
      return true;
    } on Object {
      return false;
    }
  }

  Future<void> _replaceMissingTarget(File source, File target) async {
    await _safeDelete(target);
    try {
      await _fileSystem.rename(source, target.path);
    } on FileSystemException {
      await _fileSystem.copy(source, target.path);
      await _safeDeleteBestEffort(source);
    }
  }

  Future<void> _restoreBackup(File backupFile) async {
    await _safeDelete(file);
    try {
      await _fileSystem.rename(backupFile, file.path);
    } on FileSystemException {
      await _fileSystem.copy(backupFile, file.path);
    }
  }

  Future<void> _safeDelete(File candidate) async {
    if (await _fileSystem.exists(candidate)) {
      await _fileSystem.delete(candidate);
      return;
    }
    if (await _fileSystem.directoryExists(candidate.path)) {
      await _fileSystem.deleteDirectory(Directory(candidate.path));
    }
  }

  Future<void> _safeDeleteBestEffort(File candidate) async {
    try {
      await _safeDelete(candidate);
    } on FileSystemException {
      // A persisted snapshot is already durable at this point. Cleanup
      // leftovers should not roll the caller back into an older snapshot.
    }
  }

  File _replacementBackupFile() => File('${file.path}.bak');
}

_RecoveredStorageSnapshot _recoverSnapshotSections(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      return const _RecoveredStorageSnapshot(FileStorageSnapshot(), []);
    }
    final json = decoded.map((key, value) => MapEntry(key.toString(), value));
    final recovered = <String>[];

    final formatVersion = FileStorageSnapshot._decodeFormatVersion(
      json['format_version'],
    );
    final settings = <String, Object?>{};
    final rawSettings = json['settings'];
    if (rawSettings is Map) {
      for (final entry in rawSettings.entries) {
        settings[entry.key.toString()] = _normalizeJsonValue(entry.value);
      }
      recovered.add('settings');
    }

    final history = FileStorageSnapshot._decodeHistory(json['history']);
    if (history.isNotEmpty || json['history'] is List) {
      recovered.add('history');
    }

    final follows = FileStorageSnapshot._decodeFollows(json['follows']);
    if (follows.isNotEmpty || json['follows'] is List) {
      recovered.add('follows');
    }

    final tags = FileStorageSnapshot._decodeTags(json['tags']);
    if (tags.isNotEmpty || json['tags'] is List) {
      recovered.add('tags');
    }

    if (recovered.isEmpty) {
      return const _RecoveredStorageSnapshot(FileStorageSnapshot(), []);
    }
    return _RecoveredStorageSnapshot(
      FileStorageSnapshot(
        formatVersion: formatVersion,
        settings: settings,
        history: history,
        follows: follows,
        tags: tags,
      ),
      List<String>.unmodifiable(recovered),
    );
  } on Object {
    return _recoverSnapshotSectionsFromRaw(raw);
  }
}

_RecoveredStorageSnapshot _recoverSnapshotSectionsFromRaw(String raw) {
  final recovered = <String>[];
  var snapshot = const FileStorageSnapshot();

  final settingsJson = _extractJsonValueForKey(raw, 'settings');
  if (settingsJson != null) {
    try {
      final decoded = jsonDecode(settingsJson);
      if (decoded is Map) {
        final settings = <String, Object?>{};
        for (final entry in decoded.entries) {
          settings[entry.key.toString()] = _normalizeJsonValue(entry.value);
        }
        snapshot = snapshot.clone()..settings.addAll(settings);
        recovered.add('settings');
      }
    } on Object {
      // Keep scanning other sections; corruption recovery is best-effort.
    }
  }

  final historyJson = _extractJsonValueForKey(raw, 'history');
  if (historyJson != null) {
    try {
      final history =
          FileStorageSnapshot._decodeHistory(jsonDecode(historyJson));
      snapshot = FileStorageSnapshot(
        formatVersion: snapshot.formatVersion,
        settings: snapshot.settings,
        history: history,
        follows: snapshot.follows,
        tags: snapshot.tags,
      );
      recovered.add('history');
    } on Object {
      // Keep scanning other sections; corruption recovery is best-effort.
    }
  }

  final followsJson = _extractJsonValueForKey(raw, 'follows');
  if (followsJson != null) {
    try {
      final follows =
          FileStorageSnapshot._decodeFollows(jsonDecode(followsJson));
      snapshot = FileStorageSnapshot(
        formatVersion: snapshot.formatVersion,
        settings: snapshot.settings,
        history: snapshot.history,
        follows: follows,
        tags: snapshot.tags,
      );
      recovered.add('follows');
    } on Object {
      // Keep scanning other sections; corruption recovery is best-effort.
    }
  }

  final tagsJson = _extractJsonValueForKey(raw, 'tags');
  if (tagsJson != null) {
    try {
      final tags = FileStorageSnapshot._decodeTags(jsonDecode(tagsJson));
      snapshot = FileStorageSnapshot(
        formatVersion: snapshot.formatVersion,
        settings: snapshot.settings,
        history: snapshot.history,
        follows: snapshot.follows,
        tags: tags,
      );
      recovered.add('tags');
    } on Object {
      // Keep scanning other sections; corruption recovery is best-effort.
    }
  }

  return _RecoveredStorageSnapshot(
    snapshot,
    List<String>.unmodifiable(recovered),
  );
}

String? _extractJsonValueForKey(String raw, String key) {
  final keyIndex = raw.indexOf('"$key"');
  if (keyIndex < 0) {
    return null;
  }
  var cursor = raw.indexOf(':', keyIndex + key.length + 2);
  if (cursor < 0) {
    return null;
  }
  cursor += 1;
  while (cursor < raw.length && raw.codeUnitAt(cursor) <= 0x20) {
    cursor += 1;
  }
  if (cursor >= raw.length) {
    return null;
  }
  final opening = raw[cursor];
  final closing = opening == '{'
      ? '}'
      : opening == '['
          ? ']'
          : null;
  if (closing == null) {
    return null;
  }
  var depth = 0;
  var inString = false;
  var escaped = false;
  for (var index = cursor; index < raw.length; index += 1) {
    final char = raw[index];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (char == '\\') {
        escaped = true;
      } else if (char == '"') {
        inString = false;
      }
      continue;
    }
    if (char == '"') {
      inString = true;
      continue;
    }
    if (char == opening) {
      depth += 1;
    } else if (char == closing) {
      depth -= 1;
      if (depth == 0) {
        return raw.substring(cursor, index + 1);
      }
    }
  }
  return null;
}

class _RecoveredStorageSnapshot {
  const _RecoveredStorageSnapshot(this.snapshot, this.recoveredSections);

  final FileStorageSnapshot snapshot;
  final List<String> recoveredSections;
}

class LocalStorageFileSystem {
  const LocalStorageFileSystem();

  Future<void> createDirectory(Directory directory) {
    return directory.create(recursive: true);
  }

  Future<bool> exists(File file) {
    return file.exists();
  }

  Future<String> readAsString(File file) {
    return file.readAsString();
  }

  Future<void> writeAsString(
    File file,
    String contents, {
    bool flush = false,
  }) {
    return file.writeAsString(contents, flush: flush);
  }

  Future<File> rename(File file, String newPath) {
    return file.rename(newPath);
  }

  Future<File> copy(File file, String newPath) {
    return file.copy(newPath);
  }

  Future<void> delete(File file) {
    return file.delete();
  }

  Future<bool> directoryExists(String path) {
    return Directory(path).exists();
  }

  Future<void> deleteDirectory(Directory directory) {
    return directory.delete(recursive: true);
  }
}

class LocalStorageCorruptionException implements Exception {
  const LocalStorageCorruptionException({
    required this.file,
    required this.message,
    this.cause,
    this.causeStackTrace,
  });

  final File file;
  final String message;
  final Object? cause;
  final StackTrace? causeStackTrace;

  @override
  String toString() => '$message path=${file.path}';
}

class LocalStorageRecoveryInfo {
  const LocalStorageRecoveryInfo({
    required this.corruptedFilePath,
    required this.backupFilePath,
    required this.reason,
    this.recoveredSections = const <String>[],
  });

  final String corruptedFilePath;
  final String backupFilePath;
  final String reason;
  final List<String> recoveredSections;
}

class FileStorageSnapshot {
  const FileStorageSnapshot({
    this.formatVersion = currentFormatVersion,
    this.settings = const <String, Object?>{},
    this.history = const <HistoryRecord>[],
    this.follows = const <FollowRecord>[],
    this.tags = const <String>[],
  });

  static const int currentFormatVersion = 2;

  final int formatVersion;

  final Map<String, Object?> settings;
  final List<HistoryRecord> history;
  final List<FollowRecord> follows;
  final List<String> tags;

  FileStorageSnapshot clone() {
    return FileStorageSnapshot(
      formatVersion: formatVersion,
      settings: _cloneSettingsMap(settings),
      history: List<HistoryRecord>.from(history),
      follows: List<FollowRecord>.from(follows),
      tags: List<String>.from(tags),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'format_version': formatVersion,
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
      formatVersion: _decodeFormatVersion(json['format_version']),
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

  static int _decodeFormatVersion(Object? raw) {
    if (raw is int) {
      return raw;
    }
    if (raw is num) {
      return raw.toInt();
    }
    return int.tryParse(raw?.toString() ?? '') ?? 1;
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
