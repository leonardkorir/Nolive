import 'package:floating/floating.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_player/live_player.dart';
import 'package:nolive_app/src/features/room/presentation/room_fullscreen_runtime_context.dart';
import 'package:nolive_app/src/features/room/presentation/room_picture_in_picture_coordinator.dart';
import 'package:nolive_app/src/features/room/presentation/room_view_ui_state.dart';
import 'package:nolive_app/src/shared/application/player_runtime_controller.dart';

import 'room_fullscreen_test_fakes.dart';

void main() {
  testWidgets('prime runtime state syncs PiP support and media volume', (
    tester,
  ) async {
    final harness = _PipHarness();
    addTearDown(harness.dispose);
    harness.android.mediaVolume = 0.35;
    harness.pipHost.pipAvailable = true;

    await harness.coordinator.primeRuntimeState();

    expect(harness.viewUiState.pipSupported, isTrue);
    expect(harness.volume, 0.35);
  });

  testWidgets('enter picture-in-picture success hides chrome and drawer', (
    tester,
  ) async {
    final harness = _PipHarness();
    addTearDown(harness.dispose);
    await harness.coordinator.primeRuntimeState();
    harness.viewUiState = const RoomViewUiState(
      isFullscreen: true,
      showFullscreenChrome: true,
      showFullscreenFollowDrawer: true,
    );

    await harness.coordinator.enterPictureInPicture();
    await tester.pump();

    expect(harness.viewUiState.enteringPictureInPicture, isFalse);
    expect(harness.viewUiState.showFullscreenChrome, isFalse);
    expect(harness.viewUiState.showFullscreenFollowDrawer, isFalse);
    expect(harness.android.events, contains('prepareForPictureInPicture'));
  });

  testWidgets('failed picture-in-picture restores danmaku and chrome', (
    tester,
  ) async {
    final harness = _PipHarness();
    addTearDown(harness.dispose);
    harness.viewUiState = const RoomViewUiState(
      isFullscreen: true,
      showFullscreenChrome: false,
      showFullscreenFollowDrawer: true,
    );
    harness.danmakuVisible = true;
    harness.pipHost.nextEnableStatus = PiPStatus.disabled;
    harness.pipHost.emitStatusOnEnable = false;

    await harness.coordinator.enterPictureInPicture();

    expect(harness.danmakuVisible, isTrue);
    expect(harness.viewUiState.enteringPictureInPicture, isFalse);
    expect(harness.viewUiState.showFullscreenFollowDrawer, isTrue);
    expect(harness.applyFullscreenSystemUiCount, 1);
    expect(harness.messages, contains('进入画中画失败，请稍后重试'));
  });

  testWidgets('pip disabled status restores prior ui and reapplies fullscreen',
      (tester) async {
    final harness = _PipHarness();
    addTearDown(harness.dispose);
    await harness.coordinator.primeRuntimeState();
    harness.viewUiState = const RoomViewUiState(
      isFullscreen: true,
      showFullscreenChrome: true,
      showFullscreenFollowDrawer: true,
    );
    harness.pipHost.emitStatusOnEnable = false;

    await harness.coordinator.enterPictureInPicture();
    harness.pipHost.emitStatus(PiPStatus.disabled);
    await tester.pump();

    expect(harness.viewUiState.showFullscreenChrome, isTrue);
    expect(harness.viewUiState.showFullscreenFollowDrawer, isTrue);
    expect(harness.applyFullscreenSystemUiCount, 1);
  });

  testWidgets(
      'lifecycle pause and resume suspend and restore playback outside pip', (
    tester,
  ) async {
    final harness = _PipHarness();
    addTearDown(harness.dispose);
    harness.player.emit(
      PlayerState(
        backend: PlayerBackend.mpv,
        status: PlaybackStatus.playing,
        source: PlaybackSource(url: Uri.parse('https://example.com/live.m3u8')),
      ),
    );
    harness.viewUiState = const RoomViewUiState(
      showInlinePlayerChrome: false,
      showFullscreenChrome: true,
    );

    await harness.coordinator.handleLifecycleState(AppLifecycleState.paused);
    expect(harness.player.events, contains('stop'));
    expect(harness.viewUiState.pausedByLifecycle, isFalse);

    await harness.coordinator.handleLifecycleState(AppLifecycleState.resumed);
    expect(harness.resolvePlaybackSourceForLifecycleRestoreCalls, 1);
    expect(
      harness.player.events,
      containsAllInOrder(<String>['stop', 'setSource', 'play']),
    );
    expect(harness.viewUiState.pausedByLifecycle, isFalse);
    expect(
      harness.player.currentState.source?.url.toString(),
      'https://example.com/restored.m3u8',
    );
  });

  testWidgets('prepare for picture-in-picture failure restores ui state', (
    tester,
  ) async {
    final harness = _PipHarness();
    addTearDown(harness.dispose);
    harness.android.prepareForPictureInPictureError = StateError(
      'prepare failed',
    );
    harness.viewUiState = const RoomViewUiState(
      isFullscreen: true,
      showFullscreenChrome: false,
      showFullscreenFollowDrawer: true,
    );
    harness.danmakuVisible = true;

    await harness.coordinator.enterPictureInPicture();
    await tester.pump();

    expect(harness.viewUiState.enteringPictureInPicture, isFalse);
    expect(harness.viewUiState.showFullscreenFollowDrawer, isTrue);
    expect(harness.danmakuVisible, isTrue);
    expect(harness.applyFullscreenSystemUiCount, 1);
    expect(harness.messages, contains('进入画中画失败，请稍后重试'));
  });
}

class _PipHarness {
  _PipHarness() {
    playerRuntime = PlayerRuntimeController(player);
    coordinator = RoomPictureInPictureCoordinator(
      context: RoomPictureInPictureContext(
        runtime: RoomFullscreenRuntimeContext.fromPlayerRuntime(playerRuntime),
        androidPlaybackBridge: android,
        pipHost: pipHost,
        trace: traces.add,
        showMessage: messages.add,
        resolveBackgroundAutoPauseEnabled: () => backgroundAutoPauseEnabled,
        resolvePipHideDanmakuEnabled: () => true,
        resolveDanmakuOverlayVisible: () => danmakuVisible,
        updateDanmakuOverlayVisible: (visible) {
          danmakuVisible = visible;
        },
        resolvePipAspectRatio: () => Rational(16, 9),
        updateVolume: (value) {
          volume = value;
        },
        readViewUiState: () => viewUiState,
        updateViewUiState: (updater) {
          viewUiState = updater(viewUiState);
        },
        isDisposed: () => disposed,
        applyFullscreenSystemUi: () async {
          applyFullscreenSystemUiCount += 1;
        },
        scheduleFullscreenChromeAutoHide: () {
          scheduleFullscreenChromeAutoHideCount += 1;
        },
        scheduleInlineChromeAutoHide: () {
          scheduleInlineChromeAutoHideCount += 1;
        },
        cancelChromeAutoHideTimers: () {
          cancelChromeAutoHideCount += 1;
        },
        clearGestureTip: ({required bool rescheduleChrome}) {
          clearGestureTipCount += 1;
        },
        resolvePlaybackSourceForLifecycleRestore: () async {
          resolvePlaybackSourceForLifecycleRestoreCalls += 1;
          return restoredPlaybackSource;
        },
      ),
    );
  }

  final TestRecordingPlayer player = TestRecordingPlayer();
  late final PlayerRuntimeController playerRuntime;
  final TestRoomAndroidPlaybackBridgeFacade android =
      TestRoomAndroidPlaybackBridgeFacade();
  final TestRoomPipHostFacade pipHost = TestRoomPipHostFacade();
  late final RoomPictureInPictureCoordinator coordinator;
  final List<String> traces = <String>[];
  final List<String> messages = <String>[];
  RoomViewUiState viewUiState = const RoomViewUiState();
  bool disposed = false;
  bool backgroundAutoPauseEnabled = true;
  bool danmakuVisible = true;
  double volume = 0.6;
  PlaybackSource restoredPlaybackSource =
      PlaybackSource(url: Uri.parse('https://example.com/restored.m3u8'));
  int resolvePlaybackSourceForLifecycleRestoreCalls = 0;
  int applyFullscreenSystemUiCount = 0;
  int scheduleFullscreenChromeAutoHideCount = 0;
  int scheduleInlineChromeAutoHideCount = 0;
  int cancelChromeAutoHideCount = 0;
  int clearGestureTipCount = 0;

  Future<void> dispose() async {
    disposed = true;
    await coordinator.dispose();
    await pipHost.dispose();
    await player.dispose();
  }
}
