import 'dart:async';
import 'dart:typed_data';

import 'package:floating/floating.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:nolive_app/src/features/room/presentation/room_follow_room_transition_coordinator.dart';
import 'package:nolive_app/src/features/room/presentation/room_fullscreen_runtime_context.dart';
import 'package:nolive_app/src/features/room/presentation/room_fullscreen_session_controller.dart';
import 'package:nolive_app/src/features/room/presentation/room_fullscreen_session_platforms.dart';
import 'package:nolive_app/src/features/room/presentation/room_playback_controller.dart';
import 'package:nolive_app/src/features/room/presentation/room_runtime_helper_contexts.dart';
import 'package:nolive_app/src/features/room/presentation/room_view_ui_state.dart';
import 'package:nolive_app/src/shared/application/player_runtime_controller.dart';

import 'room_fullscreen_test_fakes.dart';

void main() {
  test('fullscreen preserve transition cleans up MDK runtime before commit',
      () async {
    final harness = _TestRoomTransitionHarness(
      playerBackend: PlayerBackend.mdk,
    );
    addTearDown(harness.dispose);
    harness.fullscreenController.replaceViewUiState(
      const RoomViewUiState(
        isFullscreen: true,
        showFullscreenFollowDrawer: true,
      ),
    );
    harness.player.emit(
      PlayerState(
        backend: PlayerBackend.mdk,
        status: PlaybackStatus.playing,
        source: harness.source,
      ),
    );

    var preserveFullscreen = false;
    await harness.coordinator.openFollowRoom(
      leavingRoom: false,
      commitNavigation: (preserve) {
        preserveFullscreen = preserve;
      },
      showMessage: harness.messages.add,
    );

    expect(preserveFullscreen, isTrue);
    expect(harness.player.events, contains('stop'));
    expect(harness.runtime.refreshCount, 1);
    expect(harness.messages, isEmpty);
  });

  test('cleanup failure restores current playback and reports message',
      () async {
    final harness = _TestRoomTransitionHarness(
      playerBackend: PlayerBackend.mdk,
      throwOnRefresh: true,
    );
    addTearDown(harness.dispose);
    harness.fullscreenController.replaceViewUiState(
      const RoomViewUiState(isFullscreen: true),
    );
    harness.player.emit(
      PlayerState(
        backend: PlayerBackend.mdk,
        status: PlaybackStatus.playing,
        source: harness.source,
      ),
    );
    var commitCalled = false;

    await harness.coordinator.openFollowRoom(
      leavingRoom: false,
      commitNavigation: (_) {
        commitCalled = true;
      },
      showMessage: harness.messages.add,
    );

    expect(commitCalled, isFalse);
    expect(harness.runtime.refreshCount, 1);
    expect(
      harness.player.events,
      containsAllInOrder(<String>['stop', 'setSource', 'play']),
    );
    expect(harness.messages, contains('切换直播间失败，请稍后重试'));
  });

  test('navigation failure after cleanup restores current playback', () async {
    final harness = _TestRoomTransitionHarness(
      playerBackend: PlayerBackend.mdk,
    );
    addTearDown(harness.dispose);
    harness.fullscreenController.replaceViewUiState(
      const RoomViewUiState(isFullscreen: true),
    );
    harness.player.emit(
      PlayerState(
        backend: PlayerBackend.mdk,
        status: PlaybackStatus.playing,
        source: harness.source,
      ),
    );

    await harness.coordinator.openFollowRoom(
      leavingRoom: false,
      commitNavigation: (_) {
        throw StateError('navigation failed');
      },
      showMessage: harness.messages.add,
    );

    expect(harness.runtime.refreshCount, 1);
    expect(
      harness.player.events,
      containsAllInOrder(
          <String>['stop', 'refreshBackend', 'setSource', 'play']),
    );
    expect(harness.messages, contains('切换直播间失败，请稍后重试'));
  });

  test('non-fullscreen non-MDK transition takes light path', () async {
    final harness = _TestRoomTransitionHarness(
      playerBackend: PlayerBackend.mpv,
    );
    addTearDown(harness.dispose);
    harness.player.emit(
      PlayerState(
        backend: PlayerBackend.mpv,
        status: PlaybackStatus.playing,
        source: harness.source,
      ),
    );

    var preserveFullscreen = true;
    await harness.coordinator.openFollowRoom(
      leavingRoom: false,
      commitNavigation: (preserve) {
        preserveFullscreen = preserve;
      },
      showMessage: harness.messages.add,
    );

    expect(preserveFullscreen, isFalse);
    expect(harness.player.events, isEmpty);
    expect(harness.runtime.refreshCount, 0);
    expect(harness.messages, isEmpty);
  });

  test('disposed stale transition does not continue cleanup or navigation',
      () async {
    final endOfFrame = Completer<void>();
    final harness = _TestRoomTransitionHarness(
      playerBackend: PlayerBackend.mdk,
      waitForEndOfFrame: () => endOfFrame.future,
    );
    harness.fullscreenController.replaceViewUiState(
      const RoomViewUiState(isFullscreen: true),
    );
    harness.player.emit(
      PlayerState(
        backend: PlayerBackend.mdk,
        status: PlaybackStatus.playing,
        source: harness.source,
      ),
    );
    var commitCalled = false;

    final future = harness.coordinator.openFollowRoom(
      leavingRoom: false,
      commitNavigation: (_) {
        commitCalled = true;
      },
      showMessage: harness.messages.add,
    );
    harness.coordinator.dispose();
    endOfFrame.complete();
    await future;
    harness.playbackController.dispose();
    harness.fullscreenController.dispose();
    await harness.player.dispose();

    expect(commitCalled, isFalse);
    expect(harness.runtime.refreshCount, 0);
    expect(harness.messages, isEmpty);
  });
}

class _TestRoomTransitionHarness {
  _TestRoomTransitionHarness({
    required PlayerBackend playerBackend,
    bool throwOnRefresh = false,
    Future<void> Function()? waitForEndOfFrame,
  }) : messages = <String>[] {
    player = _RecordingTestPlayer(playerBackend: playerBackend);
    runtime = _TestRefreshRuntime(
      player,
      throwOnRefresh: throwOnRefresh,
    );
    playbackController = RoomPlaybackController(
      playerRuntime: runtime,
      providerId: ProviderId.bilibili,
      trace: (_) {},
      isMounted: () => true,
      resolveCurrentPlaybackSource: () => runtime.currentState.source,
      resetEmbeddedPlayerViewAfterBackendRefresh: (_) async {},
      schedulePostFrame: (action) {
        unawaited(action());
      },
      waitForEndOfFrame: () async {},
    );
    fullscreenController = RoomFullscreenSessionController(
      bindings: RoomFullscreenSessionBindings(
        runtime: RoomFullscreenRuntimeContext.fromPlayerRuntime(runtime),
        trace: (_) {},
        showMessage: (_) {},
        ensureFollowWatchlistLoaded: () async {},
        resolveDarkThemeActive: () => false,
        resolveBackgroundAutoPauseEnabled: () => true,
        resolvePipHideDanmakuEnabled: () => true,
        resolveDanmakuOverlayVisible: () => true,
        updateDanmakuOverlayVisible: (_) {},
        resolveVolume: () => 1,
        updateVolume: (_) {},
        resolvePipAspectRatio: () => const Rational(16, 9),
        resolveScreenSize: () => const Size(1080, 1920),
        resolvePlaybackSourceForLifecycleRestore: () async => null,
      ),
      platforms: RoomFullscreenSessionPlatforms(
        androidPlaybackBridge: TestRoomAndroidPlaybackBridgeFacade(),
        pipHost: TestRoomPipHostFacade(),
        desktopWindow: TestRoomDesktopWindowFacade(),
        screenAwake: TestRoomScreenAwakeFacade(),
        systemUi: TestRoomSystemUiFacade(),
      ),
    );
    coordinator = RoomFollowRoomTransitionCoordinator(
      currentProviderId: ProviderId.bilibili,
      currentRoomId: '66666',
      runtime: RoomRuntimeInspectionContext.fromPlayerRuntime(runtime),
      playbackController: playbackController,
      fullscreenSessionController: fullscreenController,
      trace: (_) {},
      isMounted: () => true,
      waitForEndOfFrame: waitForEndOfFrame ?? (() async {}),
    );
  }

  late final _RecordingTestPlayer player;
  late final _TestRefreshRuntime runtime;
  late final RoomPlaybackController playbackController;
  late final RoomFullscreenSessionController fullscreenController;
  late final RoomFollowRoomTransitionCoordinator coordinator;
  final List<String> messages;
  final PlaybackSource source = PlaybackSource(
    url: Uri.parse('https://example.com/live.m3u8'),
  );

  Future<void> dispose() async {
    coordinator.dispose();
    playbackController.dispose();
    fullscreenController.dispose();
    await player.dispose();
  }
}

class _TestRefreshRuntime extends PlayerRuntimeController {
  _TestRefreshRuntime(
    this.player, {
    this.throwOnRefresh = false,
  }) : super(player);

  final _RecordingTestPlayer player;
  final bool throwOnRefresh;
  int refreshCount = 0;

  @override
  Future<void> refreshBackendWithoutPlaybackState() async {
    refreshCount += 1;
    player.events.add('refreshBackend');
    if (throwOnRefresh) {
      throw StateError('refresh failed');
    }
  }
}

class _RecordingTestPlayer implements BasePlayer {
  _RecordingTestPlayer({
    this.playerBackend = PlayerBackend.mpv,
  }) : _currentState = PlayerState(backend: playerBackend);

  final List<String> events = <String>[];
  final PlayerBackend playerBackend;
  final StreamController<PlayerState> _states =
      StreamController<PlayerState>.broadcast();
  final StreamController<PlayerDiagnostics> _diagnostics =
      StreamController<PlayerDiagnostics>.broadcast();

  PlayerState _currentState;

  @override
  PlayerBackend get backend => playerBackend;

  @override
  Stream<PlayerState> get states => _states.stream;

  @override
  Stream<PlayerDiagnostics> get diagnostics => _diagnostics.stream;

  @override
  PlayerState get currentState => _currentState;

  @override
  PlayerDiagnostics get currentDiagnostics =>
      PlayerDiagnostics(backend: playerBackend);

  @override
  bool get supportsEmbeddedView => true;

  @override
  bool get supportsScreenshot => true;

  @override
  Future<void> initialize() async {
    events.add('initialize');
  }

  @override
  Future<void> setSource(PlaybackSource source) async {
    events.add('setSource');
    emit(
      _currentState.copyWith(
        source: source,
        status: PlaybackStatus.ready,
        clearErrorMessage: true,
      ),
    );
  }

  @override
  Future<void> play() async {
    events.add('play');
    emit(_currentState.copyWith(status: PlaybackStatus.playing));
  }

  @override
  Future<void> pause() async {
    events.add('pause');
    emit(_currentState.copyWith(status: PlaybackStatus.paused));
  }

  @override
  Future<void> stop() async {
    events.add('stop');
    emit(
      _currentState.copyWith(
        status: PlaybackStatus.ready,
        clearSource: true,
      ),
    );
  }

  @override
  Future<void> setVolume(double value) async {
    emit(_currentState.copyWith(volume: value));
  }

  @override
  Future<Uint8List?> captureScreenshot() async => Uint8List.fromList(<int>[1]);

  @override
  Widget buildView({
    Key? key,
    double? aspectRatio,
    BoxFit fit = BoxFit.contain,
    bool pauseUponEnteringBackgroundMode = true,
    bool resumeUponEnteringForegroundMode = false,
  }) {
    return SizedBox(key: key);
  }

  void emit(PlayerState next) {
    _currentState = next.copyWith(backend: backend);
    if (!_states.isClosed) {
      _states.add(_currentState);
    }
  }

  @override
  Future<void> dispose() async {
    await _states.close();
    await _diagnostics.close();
  }
}
