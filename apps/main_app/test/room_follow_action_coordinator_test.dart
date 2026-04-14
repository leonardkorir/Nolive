import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_storage/live_storage.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';
import 'package:nolive_app/src/features/library/application/list_follow_records_use_case.dart';
import 'package:nolive_app/src/features/library/application/load_follow_watchlist_use_case.dart';
import 'package:nolive_app/src/features/room/application/room_preview_dependencies.dart';
import 'package:nolive_app/src/features/room/presentation/room_follow_action_coordinator.dart';

void main() {
  test('room follow action coordinator follows current room into snapshot',
      () async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    bootstrap.followWatchlistSnapshot.value =
        const FollowWatchlist(entries: <FollowWatchEntry>[]);
    final coordinator = _createCoordinator(bootstrap);
    final snapshot = await bootstrap.loadRoom(
      providerId: ProviderId.bilibili,
      roomId: '66666',
    );

    await coordinator.coordinator.toggleCurrentRoomFollow(
      snapshot: snapshot,
      currentlyFollowed: false,
      followPanelSelected: false,
    );

    expect(coordinator.followed, isTrue);
    expect(coordinator.replacedWatchlist, isNotNull);
    expect(
      coordinator.replacedWatchlist!.entries.any(
        (entry) =>
            entry.record.providerId == ProviderId.bilibili.value &&
            entry.roomId == '66666',
      ),
      isTrue,
    );
  });

  test('room follow action coordinator keeps state when unfollow is canceled',
      () async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    await bootstrap.followRepository.upsert(
      const FollowRecord(
        providerId: 'bilibili',
        roomId: '66666',
        streamerName: '系统演示主播',
      ),
    );
    bootstrap.followWatchlistSnapshot.value = FollowWatchlist(
      entries: [
        const FollowWatchEntry(
          record: FollowRecord(
            providerId: 'bilibili',
            roomId: '66666',
            streamerName: '系统演示主播',
          ),
          detail: LiveRoomDetail(
            providerId: 'bilibili',
            roomId: '66666',
            title: '演示房间',
            streamerName: '系统演示主播',
            isLive: true,
          ),
        ),
      ],
    );
    final coordinator = _createCoordinator(
      bootstrap,
      confirmUnfollow: (_) async => false,
      followed: true,
    );
    final snapshot = await bootstrap.loadRoom(
      providerId: ProviderId.bilibili,
      roomId: '66666',
    );

    await coordinator.coordinator.toggleCurrentRoomFollow(
      snapshot: snapshot,
      currentlyFollowed: true,
      followPanelSelected: true,
    );

    expect(coordinator.followed, isTrue);
    expect(coordinator.replacedWatchlist, isNull);
    expect(await bootstrap.followRepository.listAll(), hasLength(1));
  });

  test('room follow action coordinator removes current room after confirm',
      () async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    await bootstrap.followRepository.upsert(
      const FollowRecord(
        providerId: 'bilibili',
        roomId: '66666',
        streamerName: '系统演示主播',
      ),
    );
    bootstrap.followWatchlistSnapshot.value = FollowWatchlist(
      entries: [
        const FollowWatchEntry(
          record: FollowRecord(
            providerId: 'bilibili',
            roomId: '66666',
            streamerName: '系统演示主播',
          ),
          detail: LiveRoomDetail(
            providerId: 'bilibili',
            roomId: '66666',
            title: '演示房间',
            streamerName: '系统演示主播',
            isLive: true,
          ),
        ),
      ],
    );
    final coordinator = _createCoordinator(
      bootstrap,
      confirmUnfollow: (_) async => true,
      followed: true,
    );
    final snapshot = await bootstrap.loadRoom(
      providerId: ProviderId.bilibili,
      roomId: '66666',
    );

    await coordinator.coordinator.toggleCurrentRoomFollow(
      snapshot: snapshot,
      currentlyFollowed: true,
      followPanelSelected: true,
    );

    expect(coordinator.followed, isFalse);
    expect(coordinator.replacedWatchlist?.entries, isEmpty);
    expect(await bootstrap.followRepository.listAll(), isEmpty);
  });

  test('room follow action coordinator does not navigate for current room',
      () async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    final harness = _createCoordinator(bootstrap);
    final entry = const FollowWatchEntry(
      record: FollowRecord(
        providerId: 'bilibili',
        roomId: '66666',
        streamerName: '系统演示主播',
      ),
      detail: LiveRoomDetail(
        providerId: 'bilibili',
        roomId: '66666',
        title: '演示房间',
        streamerName: '系统演示主播',
        isLive: true,
      ),
    );

    await harness.coordinator.openFollowRoom(entry);

    expect(harness.messages.single, '当前已经在这个直播间里了');
    expect(harness.navigationCount, 0);
  });

  test(
      'room follow action coordinator falls back when provider descriptor is missing',
      () {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    final harness = _createCoordinator(bootstrap);
    final watchlist = FollowWatchlist(
      entries: [
        const FollowWatchEntry(
          record: FollowRecord(
            providerId: 'missing_provider',
            roomId: 'room-1',
            streamerName: '未知主播',
          ),
          detail: LiveRoomDetail(
            providerId: 'missing_provider',
            roomId: 'room-1',
            title: '未知房间',
            streamerName: '未知主播',
            isLive: true,
          ),
        ),
      ],
    );

    final entries = harness.coordinator.buildEntryViewData(watchlist);

    expect(entries, hasLength(1));
    expect(entries.single.providerDescriptor.displayName, 'missing_provider');
    expect(entries.single.providerDescriptor.id.value, 'missing_provider');
  });

  test(
      'room follow action coordinator preserves watchlist and forces reload when follow record lookup misses',
      () async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    const existingEntry = FollowWatchEntry(
      record: FollowRecord(
        providerId: 'bilibili',
        roomId: '12345',
        streamerName: '已存在主播',
      ),
      detail: LiveRoomDetail(
        providerId: 'bilibili',
        roomId: '12345',
        title: '已存在房间',
        streamerName: '已存在主播',
        isLive: true,
      ),
    );
    bootstrap.followWatchlistSnapshot.value = const FollowWatchlist(
      entries: [existingEntry],
    );
    final harness = _createCoordinator(
      bootstrap,
      listFollowRecords: ListFollowRecordsUseCase(_EmptyFollowRepository()),
    );
    final snapshot = await bootstrap.loadRoom(
      providerId: ProviderId.bilibili,
      roomId: '66666',
    );

    await harness.coordinator.toggleCurrentRoomFollow(
      snapshot: snapshot,
      currentlyFollowed: false,
      followPanelSelected: false,
    );

    expect(harness.followed, isTrue);
    expect(harness.replacedWatchlist, isNull);
    expect(harness.ensureLoadedCount, 1);
    expect(
      harness.dependencies.followWatchlistSnapshot.value?.entries,
      const [existingEntry],
    );
  });
}

class _EmptyFollowRepository implements FollowRepository {
  @override
  Future<void> clear() async {}

  @override
  Future<bool> exists(String providerId, String roomId) async => false;

  @override
  Future<List<FollowRecord>> listAll() async => const <FollowRecord>[];

  @override
  Future<void> remove(String providerId, String roomId) async {}

  @override
  Future<void> upsert(FollowRecord record) async {}

  @override
  Future<void> upsertAll(Iterable<FollowRecord> records) async {}
}

class _FollowCoordinatorHarness {
  _FollowCoordinatorHarness({
    required this.coordinator,
    required this.dependencies,
    required this.messages,
    required this.followed,
  });

  final RoomFollowActionCoordinator coordinator;
  final RoomFollowActionDependencies dependencies;
  final List<String> messages;
  bool followed;
  FollowWatchlist? replacedWatchlist;
  bool? replacedHydrated;
  int ensureLoadedCount = 0;
  int navigationCount = 0;
}

_FollowCoordinatorHarness _createCoordinator(
  AppBootstrap bootstrap, {
  RoomConfirmUnfollow? confirmUnfollow,
  bool followed = false,
  ListFollowRecordsUseCase? listFollowRecords,
}) {
  final dependencies = RoomFollowActionDependencies(
    followWatchlistSnapshot: bootstrap.followWatchlistSnapshot,
    toggleFollowRoom: bootstrap.toggleFollowRoom,
    listFollowRecords: listFollowRecords ?? bootstrap.listFollowRecords,
    findProviderDescriptorById: bootstrap.findProviderDescriptorById,
  );
  final messages = <String>[];
  late final _FollowCoordinatorHarness harness;
  final coordinator = RoomFollowActionCoordinator(
    dependencies: dependencies,
    context: RoomFollowActionContext(
      currentProviderId: ProviderId.bilibili,
      currentRoomId: '66666',
      showMessage: messages.add,
      isMounted: () => true,
      confirmUnfollow: confirmUnfollow ?? (_) async => true,
      applyCurrentFollowed: (next) {
        harness.followed = next;
      },
      replaceWatchlistSnapshot: (watchlist, {required hydrated}) {
        harness.replacedWatchlist = watchlist;
        harness.replacedHydrated = hydrated;
        dependencies.followWatchlistSnapshot.value = watchlist;
      },
      ensureFollowWatchlistLoaded: ({force = false}) async {
        harness.ensureLoadedCount += 1;
      },
      commitFollowRoomNavigation: (_) async {
        harness.navigationCount += 1;
      },
    ),
  );
  harness = _FollowCoordinatorHarness(
    coordinator: coordinator,
    dependencies: dependencies,
    messages: messages,
    followed: followed,
  );
  return harness;
}
