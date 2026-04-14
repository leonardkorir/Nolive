import 'package:flutter_test/flutter_test.dart';
import 'package:live_player/live_player.dart';
import 'package:nolive_app/src/features/room/presentation/room_fullscreen_runtime_context.dart';
import 'package:nolive_app/src/shared/application/player_runtime_controller.dart';

import 'room_fullscreen_test_fakes.dart';

void main() {
  test('fullscreen runtime context forwards state and control operations',
      () async {
    final player = TestRecordingPlayer(playerBackend: PlayerBackend.mdk);
    addTearDown(player.dispose);
    final runtime = _RefreshTrackingPlayerRuntime(player);
    final context = RoomFullscreenRuntimeContext.fromPlayerRuntime(runtime);
    final source = PlaybackSource(
      url: Uri.parse('https://example.com/live.m3u8'),
    );
    player.emit(
      PlayerState(
        backend: PlayerBackend.mdk,
        status: PlaybackStatus.playing,
        source: source,
      ),
    );

    expect(context.readCurrentState().source, source);
    expect(context.resolveBackend(), PlayerBackend.mdk);

    await context.pause();
    await context.play();
    await context.stop();
    await context.refreshBackendWithoutPlaybackState();

    expect(
      player.events,
      containsAllInOrder(<String>['pause', 'play', 'stop', 'refreshBackend']),
    );
    expect(runtime.refreshCount, 1);
  });
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
