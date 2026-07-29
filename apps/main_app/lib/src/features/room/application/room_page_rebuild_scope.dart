import 'package:flutter/foundation.dart';
import 'package:live_player/live_player.dart';

/// Child notifiers that historically fanned into
/// [RoomPageSessionCoordinator.notifyListeners] (full room page rebuild).
enum RoomSessionChildNotifySource {
  /// Half-screen panel tab / pager selection.
  panelSelection,

  /// Follow drawer / follow panel watchlist hydration.
  followWatchlist,

  /// Playback / settings control actions that mutate session chrome.
  controlsAction,

  /// In-place follow room transition chrome.
  followRoomTransition,

  /// Core session `_replaceState` / load / identity.
  sessionState,

  /// Playback bootstrap / rebind controller.
  playbackController,

  /// Danmaku connection/reconnect state (not message list).
  danmakuState,

  /// Fullscreen / PiP session chrome.
  fullscreenSession,

  /// Native player runtime state stream.
  playerRuntime,
}

/// Whether a child notifier should fan into the session [ChangeNotifier]
/// (which the page uses to schedule a full room rebuild).
///
/// Panel selection and follow watchlist updates are handled via local
/// [ListenableBuilder]s so the player surface path is not rebuilt.
bool shouldSessionCoordinatorFanOutChildNotify(
  RoomSessionChildNotifySource source,
) {
  return switch (source) {
    RoomSessionChildNotifySource.panelSelection => false,
    RoomSessionChildNotifySource.followWatchlist => false,
    // Controls chrome (auto-close timer, capture capability) uses local
    // ListenableBuilder — do not rebuild player surface path.
    RoomSessionChildNotifySource.controlsAction => false,
    RoomSessionChildNotifySource.followRoomTransition => true,
    RoomSessionChildNotifySource.sessionState => true,
    RoomSessionChildNotifySource.playbackController => true,
    RoomSessionChildNotifySource.danmakuState => true,
    RoomSessionChildNotifySource.fullscreenSession => true,
    RoomSessionChildNotifySource.playerRuntime => true,
  };
}

/// Whether a session-child notify should schedule a full room page rebuild.
///
/// Same policy as [shouldSessionCoordinatorFanOutChildNotify] for the sources
/// the page still listens to directly.
bool shouldScheduleFullRoomPageRebuildForSessionChild(
  RoomSessionChildNotifySource source,
) {
  return shouldSessionCoordinatorFanOutChildNotify(source);
}

/// Progress signal used by the room loading shell first-frame gate.
///
/// Matches [resolveRoomHasRenderedVideo] progress branch (size comes from
/// diagnostics, not [PlayerState]).
bool playerStateHasFirstFrameProgress(PlayerState state) {
  return state.position > Duration.zero ||
      state.buffered > const Duration(milliseconds: 500);
}

bool _samePlaybackSourceIdentity(PlaybackSource? left, PlaybackSource? right) {
  if (identical(left, right)) {
    return true;
  }
  if (left == null || right == null) {
    return left == right;
  }
  return left.url == right.url &&
      left.externalAudio?.url == right.externalAudio?.url &&
      left.bufferProfile == right.bufferProfile;
}

/// Whether first non-zero video size (from diagnostics) must force a full room
/// page rebuild so the loading shell can dismiss without waiting for a
/// throttled position tick.
bool shouldForceRoomPageRebuildForVideoSizeChange({
  required int? previousWidth,
  required int? previousHeight,
  required int nextWidth,
  required int nextHeight,
}) {
  final hadSize = (previousWidth ?? 0) > 0 && (previousHeight ?? 0) > 0;
  final hasSize = nextWidth > 0 && nextHeight > 0;
  if (!hasSize) {
    return false;
  }
  if (!hadSize) {
    return true;
  }
  return previousWidth != nextWidth || previousHeight != nextHeight;
}

/// Whether a player runtime state update should schedule a full room page
/// rebuild (loading shell, error chrome, first frame, status transitions).
///
/// Steady playback **progress ticks** (position/buffer after first frame) must
/// return false so the player surface path is not rebuilt every second.
///
/// [forceRebuild] is set by the diagnostics first-size path when [PlayerState]
/// fields are unchanged but video dimensions just became available.
bool shouldScheduleFullRoomPageRebuildForPlayerState({
  required PlayerState? previous,
  required PlayerState next,
  bool forceRebuild = false,
}) {
  if (forceRebuild) {
    return true;
  }
  if (previous == null) {
    return true;
  }
  if (previous.status != next.status) {
    return true;
  }
  if (previous.errorMessage != next.errorMessage) {
    return true;
  }
  if (!_samePlaybackSourceIdentity(previous.source, next.source)) {
    return true;
  }
  if (previous.backend != next.backend) {
    return true;
  }
  final previousProgress = playerStateHasFirstFrameProgress(previous);
  final nextProgress = playerStateHasFirstFrameProgress(next);
  if (!previousProgress && nextProgress) {
    return true;
  }
  return false;
}

/// Whether fullscreen session should notify the room page.
///
/// Skips no-op replacements so tip/chrome churn does not always force a rebuild
/// when both view and gesture snapshots are identical.
bool shouldNotifyFullscreenSessionListeners({
  required Object previousView,
  required Object nextView,
  required Object previousGesture,
  required Object nextGesture,
}) {
  if (identical(previousView, nextView) &&
      identical(previousGesture, nextGesture)) {
    return false;
  }
  return previousView != nextView || previousGesture != nextGesture;
}

/// Ordered dispose plan for room preview leave.
///
/// When [deferHeavyControllerDisposeUntilAfterCleanup] is true, playback /
/// fullscreen / danmaku / observer must not be disposed until
/// leave cleanup completes (avoids racing leave cleanup).
@immutable
class RoomPreviewDisposePlan {
  const RoomPreviewDisposePlan({
    required this.cleanupPlayback,
    required this.deferHeavyControllerDisposeUntilAfterCleanup,
  });

  final bool cleanupPlayback;
  final bool deferHeavyControllerDisposeUntilAfterCleanup;
}

/// Pure plan for room preview dispose ownership.
///
/// [cleanupPlayback] is typically [shouldCleanupPlaybackOnRoomPreviewDispose]
/// from the page module.
RoomPreviewDisposePlan planRoomPreviewDispose({required bool cleanupPlayback}) {
  return RoomPreviewDisposePlan(
    cleanupPlayback: cleanupPlayback,
    deferHeavyControllerDisposeUntilAfterCleanup: cleanupPlayback,
  );
}

/// Ordered steps for heavy controller teardown on room leave.
///
/// Used by [runRoomPreviewHeavyControllerDispose] and tests that assert
/// cleanup precedes dispose when [RoomPreviewDisposePlan.deferHeavyControllerDisposeUntilAfterCleanup]
/// is true.
enum RoomPreviewHeavyDisposeStep {
  cleanupPlaybackOnLeave,
  disposeRuntime,
  disposePlayback,
  disposeDesktopMini,
  disposeFullscreen,
  disposeObserver,
}

/// Hooks for [runRoomPreviewHeavyControllerDispose] (page wires real
/// controllers; tests wire order-recording fakes).
@immutable
class RoomPreviewHeavyDisposeHooks {
  const RoomPreviewHeavyDisposeHooks({
    required this.cleanupPlaybackOnLeave,
    required this.disposeRuntime,
    required this.disposePlayback,
    this.disposeDesktopMini,
    required this.disposeFullscreen,
    required this.disposeObserver,
  });

  final Future<void> Function() cleanupPlaybackOnLeave;
  final Future<void> Function() disposeRuntime;
  final void Function() disposePlayback;

  /// When null, desktop mini step is skipped.
  final Future<void> Function()? disposeDesktopMini;
  final void Function() disposeFullscreen;
  final Future<void> Function() disposeObserver;
}

/// Runs heavy dispose in the order required by [plan].
///
/// When deferred: **cleanup first**, then runtime / playback / mini /
/// fullscreen / observer. When not deferred: same heavy teardown without
/// cleanup (cleanup not needed / not scheduled).
///
/// Returns the ordered list of steps actually executed (for tests).
Future<List<RoomPreviewHeavyDisposeStep>> runRoomPreviewHeavyControllerDispose({
  required RoomPreviewDisposePlan plan,
  required RoomPreviewHeavyDisposeHooks hooks,
}) async {
  final steps = <RoomPreviewHeavyDisposeStep>[];

  if (plan.deferHeavyControllerDisposeUntilAfterCleanup) {
    try {
      await hooks.cleanupPlaybackOnLeave();
    } catch (_) {
      // Best-effort; next room still waits on serializeRoomTeardown.
    }
    steps.add(RoomPreviewHeavyDisposeStep.cleanupPlaybackOnLeave);
  }

  try {
    await hooks.disposeRuntime();
  } catch (_) {}
  steps.add(RoomPreviewHeavyDisposeStep.disposeRuntime);

  hooks.disposePlayback();
  steps.add(RoomPreviewHeavyDisposeStep.disposePlayback);

  final disposeDesktopMini = hooks.disposeDesktopMini;
  if (disposeDesktopMini != null) {
    try {
      await disposeDesktopMini();
    } catch (_) {}
    steps.add(RoomPreviewHeavyDisposeStep.disposeDesktopMini);
  }

  hooks.disposeFullscreen();
  steps.add(RoomPreviewHeavyDisposeStep.disposeFullscreen);

  try {
    await hooks.disposeObserver();
  } catch (_) {}
  steps.add(RoomPreviewHeavyDisposeStep.disposeObserver);

  return steps;
}
