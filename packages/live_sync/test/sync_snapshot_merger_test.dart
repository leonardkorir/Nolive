import 'package:live_core/live_core.dart';
import 'package:live_storage/live_storage.dart';
import 'package:live_sync/live_sync.dart';
import 'package:test/test.dart';

void main() {
  const merger = SyncSnapshotMerger();

  test('merge follows keeps tombstone when newer than re-follow', () {
    final local = FollowRecord(
      providerId: ProviderId.bilibili,
      roomId: '1',
      streamerName: 'A',
      deleted: true,
      updatedAt: DateTime(2026, 7, 10),
      addedAt: DateTime(2026, 1, 1),
    );
    final remote = FollowRecord(
      providerId: ProviderId.bilibili,
      roomId: '1',
      streamerName: 'A',
      deleted: false,
      addedAt: DateTime(2026, 7, 1),
    );

    final merged = merger.mergeFollows(local: [local], remote: [remote]);
    expect(merged, hasLength(1));
    expect(merged.single.deleted, isTrue);
  });

  test(
    'merge follows combines remote baseline duration with local sync delta',
    () {
      final local = FollowRecord(
        providerId: ProviderId.douyu,
        roomId: '9',
        streamerName: 'B',
        watchDurationSec: 100,
        syncDurationSec: 40,
        updatedAt: DateTime(2026, 7, 12),
      );
      final remote = FollowRecord(
        providerId: ProviderId.douyu,
        roomId: '9',
        streamerName: 'B-remote',
        watchDurationSec: 200,
        syncDurationSec: 0,
        updatedAt: DateTime(2026, 7, 11),
      );

      final merged = merger.mergeFollows(local: [local], remote: [remote]);
      expect(merged.single.watchDurationSec, 240);
      expect(merged.single.syncDurationSec, 0);
    },
  );

  test('merge histories uses remote base + local syncDuration', () {
    final local = HistoryRecord(
      providerId: ProviderId.huya,
      roomId: '3',
      title: 'L',
      streamerName: 'S',
      viewedAt: DateTime(2026, 7, 1),
      watchDurationSec: 50,
      syncDurationSec: 30,
      updatedAt: DateTime(2026, 7, 2),
    );
    final remote = HistoryRecord(
      providerId: ProviderId.huya,
      roomId: '3',
      title: 'R',
      streamerName: 'S',
      viewedAt: DateTime(2026, 7, 3),
      watchDurationSec: 100,
      syncDurationSec: 0,
      updatedAt: DateTime(2026, 7, 3),
    );

    final merged = merger.mergeHistories(local: [local], remote: [remote]);
    expect(merged.single.watchDurationSec, 130);
    expect(merged.single.syncDurationSec, 0);
  });

  test(
    'repository importSnapshot merge mode does not drop local-only follow',
    () async {
      final settingsRepository = InMemorySettingsRepository();
      final historyRepository = InMemoryHistoryRepository();
      final followRepository = InMemoryFollowRepository();
      final tagRepository = InMemoryTagRepository();
      final service = RepositorySyncSnapshotService(
        settingsRepository: settingsRepository,
        historyRepository: historyRepository,
        followRepository: followRepository,
        tagRepository: tagRepository,
      );

      await followRepository.upsert(
        FollowRecord(
          providerId: ProviderId.bilibili,
          roomId: 'local-only',
          streamerName: 'Local',
          addedAt: DateTime(2026, 7, 12),
        ),
      );
      await followRepository.upsert(
        FollowRecord(
          providerId: ProviderId.bilibili,
          roomId: 'shared',
          streamerName: 'Shared-local',
          watchDurationSec: 10,
          syncDurationSec: 5,
          updatedAt: DateTime(2026, 7, 12),
        ),
      );

      await service.importSnapshot(
        SyncSnapshot(
          follows: [
            FollowRecord(
              providerId: ProviderId.bilibili,
              roomId: 'shared',
              streamerName: 'Shared-remote',
              watchDurationSec: 100,
              updatedAt: DateTime(2026, 7, 10),
            ),
            FollowRecord(
              providerId: ProviderId.douyu,
              roomId: 'remote-only',
              streamerName: 'Remote',
              addedAt: DateTime(2026, 7, 12),
            ),
          ],
        ),
        mode: SyncImportMode.merge,
        lastSyncAt: DateTime(2026, 7, 1),
      );

      final follows = await followRepository.listAll();
      final ids = follows.map((e) => e.roomId).toSet();
      expect(ids, containsAll(['local-only', 'shared', 'remote-only']));
      final shared = follows.firstWhere((e) => e.roomId == 'shared');
      expect(shared.watchDurationSec, 105);
      expect(shared.syncDurationSec, 0);
    },
  );
}
