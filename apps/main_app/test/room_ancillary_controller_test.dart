import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_storage/live_storage.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';
import 'package:nolive_app/src/features/room/application/room_ancillary_controller.dart';
import 'package:nolive_app/src/features/room/application/room_preview_dependencies.dart';

void main() {
  test('room ancillary controller loads danmaku session and follow state',
      () async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    await bootstrap.followRepository.upsert(
      const FollowRecord(
        providerId: 'bilibili',
        roomId: '66666',
        streamerName: '系统演示主播',
      ),
    );
    final dependencies = RoomPreviewDependencies.fromBootstrap(bootstrap);
    final snapshot = await bootstrap.loadRoom(
      providerId: ProviderId.bilibili,
      roomId: '66666',
    );
    final controller = RoomAncillaryController(
      dependencies: RoomAncillaryDependencies.fromPreviewDependencies(
        dependencies,
      ),
      providerId: ProviderId.bilibili,
    );

    final result = await controller.load(
      snapshot: snapshot,
      fallbackIsFollowed: false,
    );
    addTearDown(() => result.danmakuSession?.disconnect() ?? Future.value());

    expect(result.danmakuSession, isNotNull);
    expect(result.isFollowed, isTrue);
  });
}
