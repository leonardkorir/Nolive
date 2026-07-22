import 'dart:async';

import 'package:flutter/widgets.dart';
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
    // Keep stop shorter than serializeRoomTeardown (5s) so force-refresh can
    // still run before the outer teardown waiter is released.
    this.stopTimeout = const Duration(seconds: 2),
    this.forceRefreshTimeout = const Duration(seconds: 2),
  });

  final RoomFullscreenRuntimeContext runtime;
  final RoomAndroidPlaybackBridgeFacade androidPlaybackBridge;
  final RoomViewUiState Function() readViewUiState;
  final void Function(String message) trace;
  final RoomShouldRefreshBackendAfterCleanup shouldRefreshBackendAfterCleanup;

  /// Bound for a single player stop during leave cleanup.
  final Duration stopTimeout;

  /// Bound for force-refresh after a hung stop (must fit under outer teardown).
  final Duration forceRefreshTimeout;
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
    final backend =
        stateBeforeCleanup.backend ?? context.runtime.resolveBackend();
    final shouldRefresh =
        context.shouldRefreshBackendAfterCleanup(stateBeforeCleanup);
    context.trace(
      'cleanup playback state '
      'backend=${backend.name} '
      'status=${stateBeforeCleanup.status.name} '
      'hasSource=${stateBeforeCleanup.source != null} '
      'refresh=$shouldRefresh',
    );
    if (!context.androidPlaybackBridge.isSupported) {
      await _stopPlayerForCleanup(context.runtime);
      await _refreshBackendAfterCleanupIfNeeded(
        stateBeforeCleanup: stateBeforeCleanup,
        backend: backend,
        shouldRefresh: shouldRefresh,
      );
      context.trace('cleanup playback complete backend=${backend.name}');
      return;
    }
    if (viewState.enteringPictureInPicture) {
      context.trace(
        'cleanup playback skip stop due entering PiP backend=${backend.name}',
      );
      return;
    }
    final inPip =
        await context.androidPlaybackBridge.isInPictureInPictureMode();
    if (!inPip) {
      context.trace('cleanup playback stop inPip=$inPip');
      await _stopPlayerForCleanup(context.runtime);
      await _refreshBackendAfterCleanupIfNeeded(
        stateBeforeCleanup: stateBeforeCleanup,
        backend: backend,
        shouldRefresh: shouldRefresh,
      );
      context.trace('cleanup playback complete backend=${backend.name}');
      return;
    }
    context.trace(
        'cleanup playback skip stop due active PiP backend=${backend.name}');
  }

  Future<void> _stopPlayerForCleanup(
      RoomFullscreenRuntimeContext runtime) async {
    // Widget tests dispose mid-teardown; Future.timeout leaves pending timers.
    final boundStop = context.stopTimeout;
    final boundRefresh = context.forceRefreshTimeout;
    final useTimeout = !_isFlutterWidgetTestBinding;
    try {
      if (useTimeout) {
        await runtime.stop().timeout(boundStop);
      } else {
        await runtime.stop();
      }
    } on TimeoutException {
      context.trace(
        'cleanup playback stop timed out after '
        '${boundStop.inMilliseconds}ms',
      );
      // Hung stop recovery for any platform (observed worst on ChromeOS ARC:
      // stop can hang 5s+; next room reuses a dirty MPV and first-open freezes).
      // Happy path (phone tens-of-ms stop) never hits this branch.
      try {
        if (useTimeout) {
          await runtime
              .refreshBackendWithoutPlaybackState()
              .timeout(boundRefresh);
        } else {
          await runtime.refreshBackendWithoutPlaybackState();
        }
        context.trace('cleanup playback force refresh after stop timeout');
      } on TimeoutException {
        context.trace(
          'cleanup playback force refresh after stop timeout timed out after '
          '${boundRefresh.inMilliseconds}ms',
        );
      } catch (error) {
        context.trace(
          'cleanup playback force refresh after stop timeout failed '
          'error=$error',
        );
      }
    } catch (error) {
      context.trace('cleanup playback stop failed error=$error');
    }
  }

  Future<void> _refreshBackendAfterCleanupIfNeeded({
    required PlayerState stateBeforeCleanup,
    required PlayerBackend backend,
    required bool shouldRefresh,
  }) async {
    if (!shouldRefresh) {
      context.trace(
        'cleanup playback refresh skipped '
        'backend=${backend.name} '
        'status=${stateBeforeCleanup.status.name} '
        'hasSource=${stateBeforeCleanup.source != null}',
      );
      return;
    }
    context.trace('cleanup playback refresh backend=${backend.name}');
    try {
      await context.runtime.refreshBackendWithoutPlaybackState();
      context.trace('cleanup playback refresh done backend=${backend.name}');
    } catch (error) {
      context.trace(
        'cleanup playback refresh failed backend=${backend.name} error=$error',
      );
    }
  }
}

bool get _isFlutterWidgetTestBinding {
  try {
    final name = WidgetsBinding.instance.runtimeType.toString();
    return name.contains('TestWidgetsFlutterBinding') ||
        name.contains('AutomatedTestWidgetsFlutterBinding');
  } catch (_) {
    return false;
  }
}
