import 'package:live_player/live_player.dart';
import 'package:nolive_app/src/shared/application/player_runtime_controller.dart';

class RoomFullscreenRuntimeContext {
  const RoomFullscreenRuntimeContext({
    required this.readCurrentState,
    required this.resolveBackend,
    required this.setSource,
    required this.play,
    required this.pause,
    required this.stop,
    required this.refreshBackendWithoutPlaybackState,
  });

  factory RoomFullscreenRuntimeContext.fromPlayerRuntime(
    PlayerRuntimeController runtime,
  ) {
    return RoomFullscreenRuntimeContext(
      readCurrentState: () => runtime.currentState,
      resolveBackend: () => runtime.backend,
      setSource: runtime.setSource,
      play: runtime.play,
      pause: runtime.pause,
      stop: runtime.stop,
      refreshBackendWithoutPlaybackState:
          runtime.refreshBackendWithoutPlaybackState,
    );
  }

  final PlayerState Function() readCurrentState;
  final PlayerBackend Function() resolveBackend;
  final Future<void> Function(PlaybackSource source) setSource;
  final Future<void> Function() play;
  final Future<void> Function() pause;
  final Future<void> Function() stop;
  final Future<void> Function() refreshBackendWithoutPlaybackState;
}
