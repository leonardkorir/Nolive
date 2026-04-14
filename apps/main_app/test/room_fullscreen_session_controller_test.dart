import 'package:floating/floating.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_player/live_player.dart';
import 'package:nolive_app/src/features/room/presentation/room_fullscreen_runtime_context.dart';
import 'package:nolive_app/src/features/room/presentation/room_fullscreen_session_controller.dart';
import 'package:nolive_app/src/features/room/presentation/room_fullscreen_session_platforms.dart';
import 'package:nolive_app/src/features/room/presentation/room_view_ui_state.dart';
import 'package:nolive_app/src/shared/application/player_runtime_controller.dart';

import 'room_fullscreen_test_fakes.dart';

void main() {
  testWidgets('enter fullscreen updates view state and system orientation', (
    tester,
  ) async {
    final harness = _ControllerHarness();
    addTearDown(harness.dispose);

    await harness.controller.enterFullscreen();

    expect(harness.controller.viewUiState.isFullscreen, isTrue);
    expect(harness.controller.viewUiState.showInlinePlayerChrome, isFalse);
    expect(harness.android.events, contains('lockLandscape'));

    await harness.dispose();
  });

  testWidgets('cancel pending fullscreen bootstrap restores inline chrome', (
    tester,
  ) async {
    final harness = _ControllerHarness();
    addTearDown(harness.dispose);

    await harness.controller.initialize(startInFullscreen: true);
    await harness.controller.cancelPendingFullscreenBootstrap(
      scheduleInlineChrome: true,
    );

    expect(harness.controller.viewUiState.isFullscreen, isFalse);
    expect(harness.controller.viewUiState.fullscreenBootstrapPending, isFalse);
    expect(harness.controller.viewUiState.showInlinePlayerChrome, isTrue);
    expect(harness.android.events, contains('lockPortrait'));

    await harness.dispose();
  });

  testWidgets('auto fullscreen marks the room session as already applied', (
    tester,
  ) async {
    final harness = _ControllerHarness();
    addTearDown(harness.dispose);

    harness.player.emit(
      const PlayerState(
        backend: PlayerBackend.mpv,
        status: PlaybackStatus.playing,
      ),
    );
    harness.controller.handlePlayerStateChanged(
      harness.player.currentState,
      playbackAvailable: true,
      autoFullscreenEnabled: true,
    );
    await tester.pump();
    await tester.pump();

    expect(harness.controller.viewUiState.isFullscreen, isFalse);
    expect(harness.controller.viewUiState.fullscreenAutoApplied, isTrue);

    await harness.dispose();
  });

  testWidgets('failed picture-in-picture restores danmaku and fullscreen UI', (
    tester,
  ) async {
    final harness = _ControllerHarness();
    addTearDown(harness.dispose);
    harness.pipHost.nextEnableStatus = PiPStatus.disabled;
    harness.pipHost.emitStatusOnEnable = false;
    harness.danmakuVisible = true;
    harness.controller.replaceViewUiState(
      const RoomViewUiState(
        isFullscreen: true,
        showInlinePlayerChrome: false,
        showFullscreenChrome: false,
        showFullscreenFollowDrawer: true,
      ),
    );

    await harness.controller.enterPictureInPicture();

    expect(harness.danmakuVisible, isTrue);
    expect(harness.controller.viewUiState.enteringPictureInPicture, isFalse);
    expect(harness.controller.viewUiState.showFullscreenFollowDrawer, isTrue);
    expect(harness.controller.viewUiState.showFullscreenChrome, isFalse);
    expect(harness.android.events, contains('prepareForPictureInPicture'));
    expect(harness.android.events, contains('lockLandscape'));
    expect(harness.systemUi.lastMode, SystemUiMode.immersiveSticky);
    expect(harness.messages, contains('进入画中画失败，请稍后重试'));
  });

  testWidgets('failed picture-in-picture reapplies fullscreen once', (
    tester,
  ) async {
    final harness = _ControllerHarness();
    addTearDown(harness.dispose);
    harness.pipHost.nextEnableStatus = PiPStatus.disabled;
    harness.pipHost.emitStatusOnEnable = false;
    harness.controller.replaceViewUiState(
      const RoomViewUiState(isFullscreen: true),
    );

    await harness.controller.enterPictureInPicture();

    final lockLandscapeCount = harness.android.events
        .where((event) => event == 'lockLandscape')
        .length;
    expect(lockLandscapeCount, 1);
    expect(
      harness.android.events,
      containsAllInOrder(<String>[
        'prepareForPictureInPicture',
        'lockLandscape',
      ]),
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
  });

  testWidgets('locking fullscreen controls hides chrome until unlocked', (
    tester,
  ) async {
    final harness = _ControllerHarness();
    addTearDown(harness.dispose);
    harness.controller.replaceViewUiState(
      const RoomViewUiState(
        isFullscreen: true,
        showFullscreenChrome: true,
      ),
    );

    harness.controller.toggleFullscreenLock();
    expect(harness.controller.viewUiState.lockFullscreenControls, isTrue);
    expect(harness.controller.viewUiState.showFullscreenChrome, isFalse);
    expect(harness.controller.viewUiState.showFullscreenLockButton, isTrue);

    await tester.pump(const Duration(seconds: 3));
    expect(harness.controller.viewUiState.showFullscreenLockButton, isFalse);

    harness.controller.toggleFullscreenChrome();
    expect(harness.controller.viewUiState.showFullscreenLockButton, isTrue);

    harness.controller.toggleFullscreenLock();
    expect(harness.controller.viewUiState.lockFullscreenControls, isFalse);
    expect(harness.controller.viewUiState.showFullscreenChrome, isTrue);

    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('fullscreen picture-in-picture prepares orientation first', (
    tester,
  ) async {
    final harness = _ControllerHarness();
    addTearDown(harness.dispose);
    harness.controller.replaceViewUiState(
      const RoomViewUiState(isFullscreen: true),
    );

    await harness.controller.enterPictureInPicture();

    expect(
      harness.android.events,
      containsAllInOrder(<String>[
        'prepareForPictureInPicture',
      ]),
    );
  });

  testWidgets(
      'lifecycle pause and resume suspend and restore playback when enabled', (
    tester,
  ) async {
    final harness = _ControllerHarness();
    addTearDown(harness.dispose);
    harness.player.emit(
      PlayerState(
        backend: PlayerBackend.mpv,
        status: PlaybackStatus.playing,
        source: PlaybackSource(url: Uri.parse('https://example.com/live.m3u8')),
      ),
    );
    harness.controller.replaceViewUiState(
      const RoomViewUiState(
        showInlinePlayerChrome: false,
        showFullscreenChrome: true,
      ),
    );

    await harness.controller.handleLifecycleState(AppLifecycleState.paused);
    expect(harness.player.events, contains('stop'));
    expect(harness.controller.viewUiState.pausedByLifecycle, isFalse);

    await harness.controller.handleLifecycleState(AppLifecycleState.resumed);
    expect(harness.resolvePlaybackSourceForLifecycleRestoreCalls, 1);
    expect(
      harness.player.events,
      containsAllInOrder(<String>['stop', 'setSource', 'play']),
    );
    expect(harness.player.events, contains('play'));
    expect(harness.controller.viewUiState.pausedByLifecycle, isFalse);
    expect(harness.controller.viewUiState.showInlinePlayerChrome, isFalse);
    expect(
      harness.player.currentState.source?.url.toString(),
      'https://example.com/restored.m3u8',
    );
  });

  testWidgets(
      'fullscreen resume reapplies immersive landscape when leaving PiP',
      (tester) async {
    final harness = _ControllerHarness();
    addTearDown(harness.dispose);
    harness.controller.replaceViewUiState(
      const RoomViewUiState(
        isFullscreen: true,
        showFullscreenChrome: true,
        enteringPictureInPicture: true,
      ),
    );
    harness.android.inPictureInPictureMode = false;

    await harness.controller.handleLifecycleState(AppLifecycleState.resumed);

    expect(harness.android.events, contains('lockLandscape'));
    expect(harness.systemUi.lastMode, SystemUiMode.immersiveSticky);

    await harness.dispose();
  });

  testWidgets('lifecycle pause does not stop playback when auto pause is off', (
    tester,
  ) async {
    final harness = _ControllerHarness(
      backgroundAutoPauseEnabled: false,
    );
    addTearDown(harness.dispose);
    harness.player.emit(
      const PlayerState(
        backend: PlayerBackend.mpv,
        status: PlaybackStatus.playing,
      ),
    );

    await harness.controller.handleLifecycleState(AppLifecycleState.paused);

    expect(harness.player.events, isNot(contains('pause')));
    expect(harness.controller.viewUiState.pausedByLifecycle, isFalse);
  });

  testWidgets('cleanup playback stops only when not entering or already in PiP',
      (
    tester,
  ) async {
    final harness = _ControllerHarness();
    addTearDown(harness.dispose);

    await harness.controller.cleanupPlaybackOnLeave();
    expect(harness.player.events, contains('stop'));

    final enteringHarness = _ControllerHarness();
    addTearDown(enteringHarness.dispose);
    enteringHarness.controller.replaceViewUiState(
      const RoomViewUiState(enteringPictureInPicture: true),
    );
    await enteringHarness.controller.cleanupPlaybackOnLeave();
    expect(enteringHarness.player.events, isNot(contains('stop')));

    final pipHarness = _ControllerHarness();
    addTearDown(pipHarness.dispose);
    pipHarness.android.inPictureInPictureMode = true;
    await pipHarness.controller.cleanupPlaybackOnLeave();
    expect(pipHarness.player.events, isNot(contains('stop')));
  });

  testWidgets('cleanup playback refreshes MDK backend after stop', (
    tester,
  ) async {
    final harness = _ControllerHarness(
      playerBackend: PlayerBackend.mdk,
      refreshableRuntime: true,
    );
    addTearDown(harness.dispose);
    harness.player.emit(
      PlayerState(
        backend: PlayerBackend.mdk,
        status: PlaybackStatus.playing,
        source: PlaybackSource(url: Uri.parse('https://example.com/live.m3u8')),
      ),
    );

    await harness.controller.cleanupPlaybackOnLeave();

    expect(
      harness.player.events,
      containsAllInOrder(<String>['stop', 'refreshBackend']),
    );
    expect(harness.refreshRuntime?.refreshCount, 1);
  });

  test('cleanup helper only refreshes active MDK sessions', () {
    expect(
      shouldRefreshMdkBackendAfterCleanup(
        const PlayerState(
          backend: PlayerBackend.mdk,
          status: PlaybackStatus.error,
        ),
      ),
      isTrue,
    );
    expect(
      shouldRefreshMdkBackendAfterCleanup(
        const PlayerState(
          backend: PlayerBackend.mdk,
          status: PlaybackStatus.ready,
        ),
      ),
      isFalse,
    );
    expect(
      shouldRefreshMdkBackendAfterCleanup(
        PlayerState(
          backend: PlayerBackend.mpv,
          status: PlaybackStatus.playing,
          source:
              PlaybackSource(url: Uri.parse('https://example.com/live.m3u8')),
        ),
      ),
      isFalse,
    );
  });

  test('follow-room transition preserve flag can roll back after failure', () {
    final harness = _ControllerHarness();
    addTearDown(harness.dispose);
    harness.controller.replaceViewUiState(
      const RoomViewUiState(isFullscreen: true),
    );

    harness.controller.prepareForFollowRoomTransition();
    expect(harness.controller.preserveRoomTransitionOnDispose, isTrue);

    harness.controller.rollbackFollowRoomTransition();
    expect(harness.controller.preserveRoomTransitionOnDispose, isFalse);
  });
}

class _ControllerHarness {
  _ControllerHarness({
    this.backgroundAutoPauseEnabled = true,
    this.playerBackend = PlayerBackend.mpv,
    this.refreshableRuntime = false,
  })  : player = TestRecordingPlayer(playerBackend: playerBackend),
        android = TestRoomAndroidPlaybackBridgeFacade(),
        pipHost = TestRoomPipHostFacade(),
        desktopWindow = TestRoomDesktopWindowFacade(),
        screenAwake = TestRoomScreenAwakeFacade(),
        systemUi = TestRoomSystemUiFacade() {
    final playerRuntime = refreshableRuntime
        ? (_refreshRuntime = _RefreshTrackingPlayerRuntime(player))
        : PlayerRuntimeController(player);
    controller = RoomFullscreenSessionController(
      bindings: RoomFullscreenSessionBindings(
        runtime: RoomFullscreenRuntimeContext.fromPlayerRuntime(playerRuntime),
        trace: traces.add,
        showMessage: messages.add,
        ensureFollowWatchlistLoaded: () async {
          followWatchlistLoadCount += 1;
        },
        resolveDarkThemeActive: () => false,
        resolveBackgroundAutoPauseEnabled: () => backgroundAutoPauseEnabled,
        resolvePipHideDanmakuEnabled: () => true,
        resolveDanmakuOverlayVisible: () => danmakuVisible,
        updateDanmakuOverlayVisible: (visible) {
          danmakuVisible = visible;
        },
        resolveVolume: () => volume,
        updateVolume: (value) {
          volume = value;
        },
        resolvePipAspectRatio: () => Rational(16, 9),
        resolveScreenSize: () => const Size(1080, 1920),
        resolvePlaybackSourceForLifecycleRestore: () async {
          resolvePlaybackSourceForLifecycleRestoreCalls += 1;
          return restoredPlaybackSource;
        },
      ),
      platforms: RoomFullscreenSessionPlatforms(
        androidPlaybackBridge: android,
        pipHost: pipHost,
        desktopWindow: desktopWindow,
        screenAwake: screenAwake,
        systemUi: systemUi,
      ),
    );
  }

  final bool backgroundAutoPauseEnabled;
  final PlayerBackend playerBackend;
  final bool refreshableRuntime;
  final TestRecordingPlayer player;
  final TestRoomAndroidPlaybackBridgeFacade android;
  final TestRoomPipHostFacade pipHost;
  final TestRoomDesktopWindowFacade desktopWindow;
  final TestRoomScreenAwakeFacade screenAwake;
  final TestRoomSystemUiFacade systemUi;
  final List<String> traces = <String>[];
  final List<String> messages = <String>[];
  late final RoomFullscreenSessionController controller;
  _RefreshTrackingPlayerRuntime? _refreshRuntime;
  bool danmakuVisible = true;
  double volume = 0.6;
  PlaybackSource restoredPlaybackSource =
      PlaybackSource(url: Uri.parse('https://example.com/restored.m3u8'));
  int resolvePlaybackSourceForLifecycleRestoreCalls = 0;
  int followWatchlistLoadCount = 0;
  bool _disposed = false;

  _RefreshTrackingPlayerRuntime? get refreshRuntime => _refreshRuntime;

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    controller.dispose();
    await pipHost.dispose();
    await player.dispose();
  }
}

class _RefreshTrackingPlayerRuntime extends PlayerRuntimeController {
  _RefreshTrackingPlayerRuntime(this.player) : super(player);

  final TestRecordingPlayer player;
  int refreshCount = 0;

  @override
  Future<void> refreshBackend() async {
    refreshCount += 1;
    player.events.add('refreshBackend');
    player.emit(
      player.currentState.copyWith(
        status: PlaybackStatus.ready,
        clearSource: true,
        clearErrorMessage: true,
      ),
    );
  }
}
