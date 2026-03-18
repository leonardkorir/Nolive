import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:live_storage/live_storage.dart';
import 'package:nolive_app/src/features/library/application/load_follow_watchlist_use_case.dart';

class FollowTransferSummary {
  const FollowTransferSummary({
    required this.importedCount,
    required this.createdCount,
    required this.updatedCount,
    required this.createdTagCount,
    required this.totalCount,
  });

  final int importedCount;
  final int createdCount;
  final int updatedCount;
  final int createdTagCount;
  final int totalCount;
}

class ExportFollowListJsonUseCase {
  const ExportFollowListJsonUseCase(this.followRepository);

  final FollowRepository followRepository;

  Future<String> call() async {
    final follows = await followRepository.listAll();
    final exported = follows
        .map(_encodeLegacyCompatibleFollowRecord)
        .toList(growable: false);
    return const JsonEncoder.withIndent('  ').convert(exported);
  }
}

class ImportFollowListJsonUseCase {
  const ImportFollowListJsonUseCase({
    required this.followRepository,
    required this.tagRepository,
    this.followWatchlistSnapshot,
    this.followDataRevision,
  });

  final FollowRepository followRepository;
  final TagRepository tagRepository;
  final ValueNotifier<FollowWatchlist?>? followWatchlistSnapshot;
  final ValueNotifier<int>? followDataRevision;

  Future<FollowTransferSummary> call(String rawJson) async {
    final records = _decodeImportedFollowRecords(rawJson);
    final existingTags = (await tagRepository.listAll()).toSet();
    var createdCount = 0;
    var updatedCount = 0;
    var createdTagCount = 0;

    for (final record in records) {
      final exists = await followRepository.exists(
        record.providerId,
        record.roomId,
      );
      await followRepository.upsert(record);
      if (exists) {
        updatedCount += 1;
      } else {
        createdCount += 1;
      }

      for (final tag in record.tags) {
        final normalizedTag = tag.trim();
        if (normalizedTag.isEmpty || !existingTags.add(normalizedTag)) {
          continue;
        }
        await tagRepository.create(normalizedTag);
        createdTagCount += 1;
      }
    }

    final totalCount = (await followRepository.listAll()).length;
    followWatchlistSnapshot?.value = null;
    if (followDataRevision != null) {
      followDataRevision!.value += 1;
    }
    return FollowTransferSummary(
      importedCount: records.length,
      createdCount: createdCount,
      updatedCount: updatedCount,
      createdTagCount: createdTagCount,
      totalCount: totalCount,
    );
  }
}

Map<String, Object?> _encodeLegacyCompatibleFollowRecord(FollowRecord record) {
  return {
    'id': '${record.providerId}_${record.roomId}',
    'roomId': record.roomId,
    'siteId': record.providerId,
    'userName': record.streamerName,
    'face': record.streamerAvatarUrl ?? '',
    'title': record.lastTitle ?? '',
    'areaName': record.lastAreaName ?? '',
    'coverUrl': record.lastCoverUrl ?? '',
    'keyframeUrl': record.lastKeyframeUrl ?? '',
    'addTime': DateTime.now().toIso8601String(),
    'watchDuration': '00:00:00',
    'tag': record.tags.isNotEmpty ? record.tags.first : '全部',
    'remark': record.streamerName,
    'romanName': '',
    'tags': record.tags,
  };
}

List<FollowRecord> _decodeImportedFollowRecords(String rawJson) {
  final decoded = jsonDecode(rawJson);
  final entries = switch (decoded) {
    List<dynamic> values => values,
    Map<String, dynamic> values when values['follows'] is List<dynamic> =>
      values['follows'] as List<dynamic>,
    _ => throw const FormatException(
        '关注导入 JSON 必须是数组，或包含 follows 字段的对象。',
      ),
  };

  return entries.map(_decodeImportedFollowRecord).toList(growable: false);
}

FollowRecord _decodeImportedFollowRecord(Object? raw) {
  if (raw is! Map) {
    throw const FormatException('关注导入项必须是对象。');
  }
  final item = Map<String, Object?>.from(raw);
  final providerId = _requiredField(
    item['providerId'] ?? item['provider_id'] ?? item['siteId'],
    fieldName: 'providerId/provider_id/siteId',
  );
  final roomId = _requiredField(
    item['roomId'] ?? item['room_id'],
    fieldName: 'roomId/room_id',
  );
  final streamerName = _firstNonEmptyString(
        [
          item['streamerName'],
          item['streamer_name'],
          item['userName'],
          item['remark'],
        ],
      ) ??
      roomId;

  return FollowRecord(
    providerId: providerId,
    roomId: roomId,
    streamerName: streamerName,
    streamerAvatarUrl: _firstNonEmptyString(
      [
        item['streamerAvatarUrl'],
        item['streamer_avatar_url'],
        item['face'],
      ],
    ),
    lastTitle: _firstNonEmptyString(
      [
        item['lastTitle'],
        item['last_title'],
        item['title'],
        item['liveTitle'],
      ],
    ),
    lastAreaName: _firstNonEmptyString(
      [
        item['lastAreaName'],
        item['last_area_name'],
        item['areaName'],
        item['area_name'],
        item['liveAreaName'],
      ],
    ),
    lastCoverUrl: _firstNonEmptyString(
      [
        item['lastCoverUrl'],
        item['last_cover_url'],
        item['coverUrl'],
        item['cover_url'],
        item['cover'],
      ],
    ),
    lastKeyframeUrl: _firstNonEmptyString(
      [
        item['lastKeyframeUrl'],
        item['last_keyframe_url'],
        item['keyframeUrl'],
        item['keyframe_url'],
        item['keyframe'],
      ],
    ),
    tags: _decodeTags(item),
  );
}

List<String> _decodeTags(Map<String, Object?> item) {
  final tags = <String>[];
  final seen = <String>{};

  final rawTags = item['tags'];
  if (rawTags is List) {
    for (final rawTag in rawTags) {
      final tag = rawTag?.toString().trim() ?? '';
      if (tag.isEmpty || !seen.add(tag)) {
        continue;
      }
      tags.add(tag);
    }
  }

  final singleTag = item['tag']?.toString().trim() ?? '';
  if (singleTag.isNotEmpty && singleTag != '全部' && seen.add(singleTag)) {
    tags.add(singleTag);
  }

  return List<String>.unmodifiable(tags);
}

String _requiredField(Object? raw, {required String fieldName}) {
  final value = raw?.toString().trim() ?? '';
  if (value.isEmpty) {
    throw FormatException('关注导入项缺少必填字段：$fieldName');
  }
  return value;
}

String? _firstNonEmptyString(List<Object?> candidates) {
  for (final candidate in candidates) {
    final normalized = candidate?.toString().trim() ?? '';
    if (normalized.isNotEmpty) {
      return normalized;
    }
  }
  return null;
}
