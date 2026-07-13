import 'dart:collection';

import 'package:live_storage/live_storage.dart';

import '../model/sync_data_category.dart';
import '../model/sync_import_mode.dart';
import '../model/sync_snapshot.dart';
import 'sync_snapshot_merger.dart';

class RepositorySyncSnapshotService {
  const RepositorySyncSnapshotService({
    required this.settingsRepository,
    required this.historyRepository,
    required this.followRepository,
    required this.tagRepository,
    this.shouldIncludeSettingInSnapshot,
    this.merger = const SyncSnapshotMerger(),
  });

  final SettingsRepository settingsRepository;
  final HistoryRepository historyRepository;
  final FollowRepository followRepository;
  final TagRepository tagRepository;
  final bool Function(String key)? shouldIncludeSettingInSnapshot;
  final SyncSnapshotMerger merger;

  Future<SyncSnapshot> exportSnapshot() async {
    final settings = Map<String, Object?>.from(
      await settingsRepository.listAll(),
    )..removeWhere((key, _) {
        return key != 'blocked_keywords' &&
            shouldIncludeSettingInSnapshot?.call(key) == false;
      });
    final blockedKeywords = (settings.remove('blocked_keywords') as List?)
            ?.map((item) => item.toString())
            .toList(growable: false) ??
        const <String>[];

    return SyncSnapshot(
      settings: settings,
      history: await historyRepository.listRecent(),
      follows: await followRepository.listAll(),
      tags: await tagRepository.listAll(),
      blockedKeywords: blockedKeywords,
    );
  }

  Future<SyncSnapshot> exportCategory(SyncDataCategory category) async {
    final snapshot = await exportSnapshot();
    return switch (category) {
      SyncDataCategory.settings => SyncSnapshot(settings: snapshot.settings),
      SyncDataCategory.library => SyncSnapshot(
          follows: snapshot.follows,
          tags: snapshot.tags,
        ),
      SyncDataCategory.history => SyncSnapshot(history: snapshot.history),
      SyncDataCategory.blockedKeywords => SyncSnapshot(
          blockedKeywords: snapshot.blockedKeywords,
        ),
    };
  }

  Future<void> importSnapshot(
    SyncSnapshot snapshot, {
    bool clearExisting = true,
    SyncImportMode mode = SyncImportMode.replace,
    DateTime? lastSyncAt,
  }) async {
    if (mode == SyncImportMode.merge) {
      final local = await exportSnapshot();
      final merged = merger.mergeSnapshots(
        local: local,
        remote: snapshot,
        lastSyncAt: lastSyncAt,
      );
      await importSnapshot(merged, clearExisting: true);
      return;
    }

    if (clearExisting) {
      final existingSettings = await settingsRepository.listAll();
      for (final key in existingSettings.keys) {
        if (shouldIncludeSettingInSnapshot?.call(key) == false) {
          continue;
        }
        await settingsRepository.remove(key);
      }
      await historyRepository.clear();
      await followRepository.clear();
      await tagRepository.clear();
    }

    for (final entry in snapshot.settings.entries) {
      await settingsRepository.writeValue(entry.key, entry.value);
    }
    await settingsRepository.writeValue(
      'blocked_keywords',
      snapshot.blockedKeywords,
    );

    for (final record in snapshot.history) {
      await historyRepository.add(record);
    }
    for (final record in snapshot.follows) {
      if (record.deleted) {
        // Keep tombstones in storage so later bidirectional sync can propagate.
        await followRepository.upsert(record);
        continue;
      }
      await followRepository.upsert(record);
    }
    for (final tag in snapshot.tags) {
      await tagRepository.create(tag);
    }
  }

  Future<void> importCategory(
    SyncDataCategory category,
    SyncSnapshot snapshot, {
    bool clearExisting = true,
    SyncImportMode mode = SyncImportMode.replace,
    DateTime? lastSyncAt,
  }) async {
    if (mode == SyncImportMode.merge) {
      final local = await exportCategory(category);
      final mergedFull = merger.mergeSnapshots(
        local: local,
        remote: snapshot,
        lastSyncAt: lastSyncAt,
      );
      final partial = switch (category) {
        SyncDataCategory.settings =>
          SyncSnapshot(settings: mergedFull.settings),
        SyncDataCategory.library => SyncSnapshot(
            follows: mergedFull.follows,
            tags: mergedFull.tags,
          ),
        SyncDataCategory.history => SyncSnapshot(history: mergedFull.history),
        SyncDataCategory.blockedKeywords => SyncSnapshot(
            blockedKeywords: mergedFull.blockedKeywords,
          ),
      };
      await importCategory(category, partial, clearExisting: true);
      return;
    }

    switch (category) {
      case SyncDataCategory.settings:
        if (clearExisting) {
          final existingSettings = await settingsRepository.listAll();
          for (final key in existingSettings.keys) {
            if (key == 'blocked_keywords') {
              continue;
            }
            if (shouldIncludeSettingInSnapshot?.call(key) == false) {
              continue;
            }
            await settingsRepository.remove(key);
          }
        }
        for (final entry in snapshot.settings.entries) {
          await settingsRepository.writeValue(entry.key, entry.value);
        }
        return;
      case SyncDataCategory.library:
        if (clearExisting) {
          await followRepository.clear();
          await tagRepository.clear();
        }
        for (final record in snapshot.follows) {
          await followRepository.upsert(record);
        }
        for (final tag in snapshot.tags) {
          await tagRepository.create(tag);
        }
        return;
      case SyncDataCategory.history:
        if (clearExisting) {
          await historyRepository.clear();
        }
        for (final record in snapshot.history) {
          await historyRepository.add(record);
        }
        return;
      case SyncDataCategory.blockedKeywords:
        if (!clearExisting) {
          final existing =
              await settingsRepository.readValue<List>('blocked_keywords') ??
                  const <Object?>[];
          final merged = <String>[
            for (final item in existing) item.toString(),
            for (final item in snapshot.blockedKeywords) item,
          ];
          await settingsRepository.writeValue(
            'blocked_keywords',
            LinkedHashSet<String>.from(merged).toList(growable: false),
          );
          return;
        }
        await settingsRepository.writeValue(
          'blocked_keywords',
          snapshot.blockedKeywords,
        );
        return;
    }
  }
}
