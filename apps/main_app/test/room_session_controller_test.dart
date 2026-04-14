import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';
import 'package:nolive_app/src/features/room/application/room_preview_dependencies.dart';
import 'package:nolive_app/src/features/room/application/room_session_controller.dart';
import 'package:nolive_app/src/features/settings/application/manage_history_preferences_use_case.dart';

void main() {
  test('room session controller loads and reloads without duplicating history',
      () async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    final controller = RoomSessionController(
      dependencies: RoomSessionDependencies.fromPreviewDependencies(
        RoomPreviewDependencies.fromBootstrap(bootstrap),
      ),
      providerId: ProviderId.bilibili,
      roomId: '66666',
      targetPlatform: TargetPlatform.android,
      isWeb: false,
    );

    final first = await controller.load();
    final historyAfterLoad = await bootstrap.historyRepository.listRecent();

    expect(first.snapshot.detail.roomId, '66666');
    expect(first.resolved, isNotNull);
    expect(first.playbackQuality, first.startupPlan.startupQuality);
    expect(controller.current, same(first));
    expect(historyAfterLoad, hasLength(1));

    final second = await controller.reload(
      preferredQualityId: first.playbackQuality.id,
    );
    final historyAfterReload = await bootstrap.historyRepository.listRecent();

    expect(second.snapshot.detail.roomId, '66666');
    expect(second.resolved, isNotNull);
    expect(second.playerPreferences.backend, first.playerPreferences.backend);
    expect(controller.current, same(second));
    expect(historyAfterReload, hasLength(1));

    controller.clearCurrent();
    expect(controller.current, isNull);
  });

  test('room session controller load respects disabled history preference',
      () async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    await bootstrap.updateHistoryPreferences(
      const HistoryPreferences(recordWatchHistory: false),
    );
    final controller = RoomSessionController(
      dependencies: RoomSessionDependencies.fromPreviewDependencies(
        RoomPreviewDependencies.fromBootstrap(bootstrap),
      ),
      providerId: ProviderId.bilibili,
      roomId: '66666',
      targetPlatform: TargetPlatform.android,
      isWeb: false,
    );

    await controller.load();

    expect(await bootstrap.historyRepository.listRecent(), isEmpty);
  });
}
