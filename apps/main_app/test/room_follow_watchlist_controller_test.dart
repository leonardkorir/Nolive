import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_storage/live_storage.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';
import 'package:nolive_app/src/features/library/application/load_follow_watchlist_use_case.dart';
import 'package:nolive_app/src/features/room/application/room_follow_watchlist_controller.dart';
import 'package:nolive_app/src/features/room/application/room_preview_dependencies.dart';

void main() {
  test('room follow watchlist controller loads and tracks runtime snapshot',
      () async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    final controller = RoomFollowWatchlistController(
      dependencies: RoomFollowWatchlistDependencies.fromPreviewDependencies(
        RoomPreviewDependencies.fromBootstrap(bootstrap),
      ),
    );
    addTearDown(controller.dispose);

    expect(controller.current.watchlist, isNull);
    expect(controller.current.hydrated, isFalse);

    await controller.ensureLoaded(force: true);

    expect(controller.current.watchlist, isNotNull);
    expect(controller.current.hydrated, isTrue);
    expect(
      bootstrap.followWatchlistSnapshot.value,
      same(controller.current.watchlist),
    );

    final replacement = FollowWatchlist(
      entries: [
        const FollowWatchEntry(
          record: FollowRecord(
            providerId: 'bilibili',
            roomId: 'custom-room',
            streamerName: '自定义主播',
          ),
          detail: LiveRoomDetail(
            providerId: 'bilibili',
            roomId: 'custom-room',
            title: '自定义房间',
            streamerName: '自定义主播',
            isLive: true,
          ),
        ),
      ],
    );
    controller.replaceSnapshot(replacement, hydrated: true);

    expect(controller.current.watchlist, same(replacement));
    expect(bootstrap.followWatchlistSnapshot.value, same(replacement));
  });

  test('room follow watchlist controller dedupes same-count snapshot traces',
      () {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    final traces = <String>[];
    final controller = RoomFollowWatchlistController(
      dependencies: RoomFollowWatchlistDependencies.fromPreviewDependencies(
        RoomPreviewDependencies.fromBootstrap(bootstrap),
      ),
      trace: traces.add,
    );
    addTearDown(controller.dispose);

    controller.replaceSnapshot(
      FollowWatchlist(
        entries: [
          const FollowWatchEntry(
            record: FollowRecord(
              providerId: 'bilibili',
              roomId: 'room-a',
              streamerName: '主播A',
            ),
            detail: LiveRoomDetail(
              providerId: 'bilibili',
              roomId: 'room-a',
              title: '房间A',
              streamerName: '主播A',
              isLive: true,
            ),
          ),
        ],
      ),
      hydrated: true,
    );
    controller.replaceSnapshot(
      FollowWatchlist(
        entries: [
          const FollowWatchEntry(
            record: FollowRecord(
              providerId: 'bilibili',
              roomId: 'room-b',
              streamerName: '主播B',
            ),
            detail: LiveRoomDetail(
              providerId: 'bilibili',
              roomId: 'room-b',
              title: '房间B',
              streamerName: '主播B',
              isLive: true,
            ),
          ),
        ],
      ),
      hydrated: true,
    );

    expect(
      traces.where(
          (trace) => trace.contains('follow watchlist snapshot updated')),
      hasLength(1),
    );
  });
}
