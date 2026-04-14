import 'package:live_player/live_player.dart';

import 'room_fullscreen_runtime_context.dart';
import 'room_fullscreen_session_platforms.dart';
import 'room_view_ui_state.dart';

typedef RoomShouldRefreshBackendAfterCleanup = bool Function(PlayerState state);

class RoomPlaybackLeaveCleanupContext {
  const RoomPlaybackLeaveCleanupContext({
    required this.runtime,
    required this.androidPlaybackBridge,
    required this.readViewUiState,
    required this.trace,
    required this.shouldRefreshBackendAfterCleanup,
  });

  final RoomFullscreenRuntimeContext runtime;
  final RoomAndroidPlaybackBridgeFacade androidPlaybackBridge;
  final RoomViewUiState Function() readViewUiState;
  final void Function(String message) trace;
  final RoomShouldRefreshBackendAfterCleanup shouldRefreshBackendAfterCleanup;
}

class RoomPlaybackLeaveCleanupCoordinator {
  RoomPlaybackLeaveCleanupCoordinator({required this.context});

  final RoomPlaybackLeaveCleanupContext context;

  bool _playbackCleanedUp = false;

  Future<void> cleanupPlaybackOnLeave() async {
    if (_playbackCleanedUp) {
      return;
    }
    _playbackCleanedUp = true;
    context.trace('cleanup playback start');
    final viewState = context.readViewUiState();
    final stateBeforeCleanup = context.runtime.readCurrentState();
    if (!context.androidPlaybackBridge.isSupported) {
      await _stopPlayerForCleanup(context.runtime);
      await _refreshBackendAfterCleanupIfNeeded(
        stateBeforeCleanup: stateBeforeCleanup,
      );
      return;
    }
    if (viewState.enteringPictureInPicture) {
      context.trace('cleanup playback skip stop due entering PiP');
      return;
    }
    final inPip =
        await context.androidPlaybackBridge.isInPictureInPictureMode();
    if (!inPip) {
      context.trace('cleanup playback stop inPip=$inPip');
      await _stopPlayerForCleanup(context.runtime);
      await _refreshBackendAfterCleanupIfNeeded(
        stateBeforeCleanup: stateBeforeCleanup,
      );
    }
  }

  Future<void> _stopPlayerForCleanup(
      RoomFullscreenRuntimeContext runtime) async {
    try {
      await runtime.stop();
    } catch (error) {
      context.trace('cleanup playback stop failed error=$error');
    }
  }

  Future<void> _refreshBackendAfterCleanupIfNeeded({
    required PlayerState stateBeforeCleanup,
  }) async {
    if (!context.shouldRefreshBackendAfterCleanup(stateBeforeCleanup)) {
      return;
    }
    final backend =
        stateBeforeCleanup.backend ?? context.runtime.resolveBackend();
    context.trace('cleanup playback refresh backend=${backend.name}');
    try {
      await context.runtime.refreshBackendWithoutPlaybackState();
    } catch (error) {
      context.trace(
        'cleanup playback refresh failed backend=${backend.name} error=$error',
      );
    }
  }
}
