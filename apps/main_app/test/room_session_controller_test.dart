import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';
import 'package:nolive_app/src/features/room/application/load_room_use_case.dart';
import 'package:nolive_app/src/features/room/application/room_preview_dependencies.dart';
import 'package:nolive_app/src/features/room/application/room_session_controller.dart';
import 'package:nolive_app/src/features/settings/application/manage_history_preferences_use_case.dart';

void main() {
  test(
    'room session controller loads and reloads without duplicating history',
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
    },
  );

  test(
    'room session controller load respects disabled history preference',
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
    },
  );

  test('room session controller keeps Android runtime gain neutral', () async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    final currentPreferences = await bootstrap.loadPlayerPreferences();
    await bootstrap.updatePlayerPreferences(
      currentPreferences.copyWith(volume: 0.25),
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

    expect(bootstrap.playerRuntime.currentState.volume, 1.0);
  });

  test(
    'room session controller restores persisted non-Android volume',
    () async {
      final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
      final currentPreferences = await bootstrap.loadPlayerPreferences();
      await bootstrap.updatePlayerPreferences(
        currentPreferences.copyWith(volume: 0.25),
      );
      final controller = RoomSessionController(
        dependencies: RoomSessionDependencies.fromPreviewDependencies(
          RoomPreviewDependencies.fromBootstrap(bootstrap),
        ),
        providerId: ProviderId.bilibili,
        roomId: '66666',
        targetPlatform: TargetPlatform.iOS,
        isWeb: false,
      );

      await controller.load();

      expect(bootstrap.playerRuntime.currentState.volume, 0.25);
    },
  );

  test('stripchat startup plan keeps requested quality', () {
    final auto = LivePlayQuality(id: 'auto', label: 'Auto', isDefault: true);
    final q960 = LivePlayQuality(id: '960p', label: '960P');
    final snapshot = LoadedRoomSnapshot(
      providerId: ProviderId.stripchat,
      detail: const LiveRoomDetail(
        providerId: 'stripchat',
        roomId: 'asian-asami',
        title: 'title',
        streamerName: 'streamer',
        sourceUrl: 'https://zh.stripchat.com/asian-asami',
        isLive: true,
      ),
      qualities: [auto, q960],
      selectedQuality: q960,
      playUrls: const [],
    );

    final plan = resolveRoomStartupPlan(
      snapshot: snapshot,
      requestedQuality: q960,
    );

    expect(plan.startupQuality.id, '960p');
    expect(plan.promotionQuality, isNull);
  });
}
