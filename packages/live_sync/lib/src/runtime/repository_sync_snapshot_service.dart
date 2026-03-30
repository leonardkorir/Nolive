import 'package:live_storage/live_storage.dart';

import '../model/sync_data_category.dart';
import '../model/sync_snapshot.dart';

class RepositorySyncSnapshotService {
  const RepositorySyncSnapshotService({
    required this.settingsRepository,
    required this.historyRepository,
    required this.followRepository,
    required this.tagRepository,
  });

  final SettingsRepository settingsRepository;
  final HistoryRepository historyRepository;
  final FollowRepository followRepository;
  final TagRepository tagRepository;

  Future<SyncSnapshot> exportSnapshot() async {
    final settings =
        Map<String, Object?>.from(await settingsRepository.listAll());
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
  }) async {
    if (clearExisting) {
      final existingSettings = await settingsRepository.listAll();
      for (final key in existingSettings.keys) {
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
  }) async {
    switch (category) {
      case SyncDataCategory.settings:
        if (clearExisting) {
          final existingSettings = await settingsRepository.listAll();
          for (final key in existingSettings.keys) {
            if (key == 'blocked_keywords') {
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
        await settingsRepository.writeValue(
          'blocked_keywords',
          snapshot.blockedKeywords,
        );
        return;
    }
  }
}
