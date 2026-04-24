import 'package:flutter_test/flutter_test.dart';
import 'package:live_player/live_player.dart';
import 'package:nolive_app/src/features/room/presentation/room_fullscreen_runtime_context.dart';
import 'package:nolive_app/src/features/room/presentation/room_fullscreen_session_controller.dart';
import 'package:nolive_app/src/features/room/presentation/room_playback_leave_cleanup_coordinator.dart';
import 'package:nolive_app/src/features/room/presentation/room_view_ui_state.dart';
import 'package:nolive_app/src/shared/application/player_runtime_controller.dart';

import 'room_fullscreen_test_fakes.dart';

void main() {
  test('cleanup only runs once and refreshes active MDK sessions', () async {
    final harness = _CleanupHarness(
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

    await harness.coordinator.cleanupPlaybackOnLeave();
    await harness.coordinator.cleanupPlaybackOnLeave();

    expect(
      harness.player.events,
      containsAllInOrder(<String>['stop', 'refreshBackend']),
    );
    expect(
      harness.player.events.where((event) => event == 'stop').length,
      1,
    );
    expect(harness.refreshRuntime?.refreshCount, 1);
    expect(
      harness.traces,
      containsAll(<String>[
        'cleanup playback refresh backend=mdk',
        'cleanup playback refresh done backend=mdk',
      ]),
    );
  });

  test(
      'cleanup stops active MPV sessions without backend refresh on Android leave',
      () async {
    final harness = _CleanupHarness(
      playerBackend: PlayerBackend.mpv,
      refreshableRuntime: true,
    );
    addTearDown(harness.dispose);
    harness.player.emit(
      PlayerState(
        backend: PlayerBackend.mpv,
        status: PlaybackStatus.playing,
        source: PlaybackSource(url: Uri.parse('https://example.com/live.m3u8')),
      ),
    );

    await harness.coordinator.cleanupPlaybackOnLeave();

    expect(harness.player.events, contains('stop'));
    expect(harness.player.events, isNot(contains('refreshBackend')));
    expect(harness.refreshRuntime?.refreshCount, 0);
    expect(
      harness.traces,
      containsAll(<String>[
        'cleanup playback state backend=mpv status=playing hasSource=true refresh=false',
        'cleanup playback refresh skipped backend=mpv status=playing hasSource=true',
      ]),
    );
  });

  test('cleanup skips stop while entering picture-in-picture', () async {
    final harness = _CleanupHarness();
    addTearDown(harness.dispose);
    harness.viewUiState = const RoomViewUiState(enteringPictureInPicture: true);

    await harness.coordinator.cleanupPlaybackOnLeave();

    expect(harness.player.events, isNot(contains('stop')));
  });

  test('cleanup skips stop while already in picture-in-picture', () async {
    final harness = _CleanupHarness();
    addTearDown(harness.dispose);
    harness.android.inPictureInPictureMode = true;

    await harness.coordinator.cleanupPlaybackOnLeave();

    expect(harness.player.events, isNot(contains('stop')));
  });
}

class _CleanupHarness {
  _CleanupHarness({
    this.playerBackend = PlayerBackend.mpv,
    this.refreshableRuntime = false,
  }) : player = TestRecordingPlayer(playerBackend: playerBackend) {
    final playerRuntime = refreshableRuntime
        ? (_refreshRuntime = _RefreshTrackingPlayerRuntime(player))
        : PlayerRuntimeController(player);
    coordinator = RoomPlaybackLeaveCleanupCoordinator(
      context: RoomPlaybackLeaveCleanupContext(
        runtime: RoomFullscreenRuntimeContext.fromPlayerRuntime(playerRuntime),
        androidPlaybackBridge: android,
        readViewUiState: () => viewUiState,
        trace: traces.add,
        shouldRefreshBackendAfterCleanup:
            shouldRefreshNativeBackendAfterLeaveCleanup,
      ),
    );
  }

  final PlayerBackend playerBackend;
  final bool refreshableRuntime;
  final TestRecordingPlayer player;
  final TestRoomAndroidPlaybackBridgeFacade android =
      TestRoomAndroidPlaybackBridgeFacade();
  late final RoomPlaybackLeaveCleanupCoordinator coordinator;
  final List<String> traces = <String>[];
  RoomViewUiState viewUiState = const RoomViewUiState();
  _RefreshTrackingPlayerRuntime? _refreshRuntime;

  _RefreshTrackingPlayerRuntime? get refreshRuntime => _refreshRuntime;

  Future<void> dispose() async {
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
