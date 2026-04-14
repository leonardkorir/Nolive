import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:nolive_app/src/shared/application/app_log.dart';

import 'room_fullscreen_session_controller.dart';
import 'room_playback_controller.dart';
import 'room_runtime_helper_contexts.dart';

typedef RoomFollowRoomTransitionMountCheck = bool Function();
typedef RoomFollowRoomTransitionTrace = void Function(String message);
typedef RoomFollowRoomTransitionEndOfFrame = Future<void> Function();
typedef RoomFollowRoomTransitionNavigation = void Function(
  bool preserveFullscreen,
);
typedef RoomFollowRoomTransitionShowMessage = void Function(String message);

@visibleForTesting
bool shouldResetMdkBeforeFullscreenFollowRoomSwitch({
  required bool fullscreenSessionActive,
  required PlayerState playerState,
  required PlayerBackend runtimeBackend,
}) {
  final backend = playerState.backend ?? runtimeBackend;
  return fullscreenSessionActive && backend == PlayerBackend.mdk;
}

class RoomFollowRoomTransitionCoordinator extends ChangeNotifier {
  RoomFollowRoomTransitionCoordinator({
    required this.currentProviderId,
    required this.currentRoomId,
    required this.runtime,
    required this.playbackController,
    required this.fullscreenSessionController,
    required this.trace,
    required this.isMounted,
    RoomFollowRoomTransitionEndOfFrame? waitForEndOfFrame,
  }) : _waitForEndOfFrame =
            waitForEndOfFrame ?? (() => WidgetsBinding.instance.endOfFrame);

  final ProviderId currentProviderId;
  final String currentRoomId;
  final RoomRuntimeInspectionContext runtime;
  final RoomPlaybackController playbackController;
  final RoomFullscreenSessionController fullscreenSessionController;
  final RoomFollowRoomTransitionTrace trace;
  final RoomFollowRoomTransitionMountCheck isMounted;
  final RoomFollowRoomTransitionEndOfFrame _waitForEndOfFrame;

  bool _disposed = false;
  bool _transitionInFlight = false;
  bool _suspendEmbeddedPlayerForTransition = false;
  int _transitionGeneration = 0;

  bool get transitionInFlight => _transitionInFlight;

  bool get suspendEmbeddedPlayerForTransition =>
      _suspendEmbeddedPlayerForTransition;

  Future<void> openFollowRoom({
    required bool leavingRoom,
    required RoomFollowRoomTransitionNavigation commitNavigation,
    required RoomFollowRoomTransitionShowMessage showMessage,
  }) async {
    if (leavingRoom || _transitionInFlight) {
      return;
    }
    final generation = ++_transitionGeneration;
    _replaceState(inFlight: true);
    final preserveFullscreen =
        fullscreenSessionController.fullscreenSessionActive;
    final stateBeforeTransition = runtime.readCurrentState();
    final shouldResetMdk = shouldResetMdkBeforeFullscreenFollowRoomSwitch(
      fullscreenSessionActive: preserveFullscreen,
      playerState: stateBeforeTransition,
      runtimeBackend: runtime.resolveBackend(),
    );
    var restorePlaybackOnFailure = false;
    fullscreenSessionController.prepareForFollowRoomTransition();
    var navigationCommitted = false;
    try {
      if (shouldResetMdk) {
        restorePlaybackOnFailure = true;
        await _prepareMdkFullscreenFollowRoomTransition(
          generation: generation,
          stateBeforeCleanup: stateBeforeTransition,
        );
        if (!_isActive(generation)) {
          return;
        }
      }
      commitNavigation(preserveFullscreen);
      navigationCommitted = true;
    } catch (error, stackTrace) {
      if (restorePlaybackOnFailure) {
        await _restorePlaybackAfterFailedFollowRoomTransition(
          generation: generation,
          stateBeforeTransition: stateBeforeTransition,
          failureError: error,
          failureStackTrace: stackTrace,
        );
      }
      trace('follow-room transition failed error=$error');
      AppLog.instance.error(
        'room',
        '[RoomPreview/${currentProviderId.value}/$currentRoomId] '
            'follow-room transition failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (_isActive(generation)) {
        showMessage('切换直播间失败，请稍后重试');
      }
    } finally {
      if (!navigationCommitted) {
        fullscreenSessionController.rollbackFollowRoomTransition();
        _clearTransitionState(generation);
      }
    }
  }

  Future<void> _prepareMdkFullscreenFollowRoomTransition({
    required int generation,
    required PlayerState stateBeforeCleanup,
  }) async {
    trace(
      'fullscreen follow-room transition mdk detach-surface '
      'status=${stateBeforeCleanup.status.name}',
    );
    _replaceState(suspendEmbedded: true);
    await _waitForEndOfFrame();
    if (!_isActive(generation)) {
      return;
    }
    if (!shouldRefreshMdkBackendAfterCleanup(stateBeforeCleanup)) {
      return;
    }
    trace(
      'fullscreen follow-room transition mdk cleanup '
      'source=${_summarizePlaybackSource(stateBeforeCleanup.source)}',
    );
    await playbackController.stopCurrentPlayback(
      label: 'fullscreen follow-room transition mdk cleanup',
    );
    if (!_isActive(generation)) {
      return;
    }
    await playbackController.refreshBackendWithoutPlaybackState(
      label: 'fullscreen follow-room transition mdk cleanup',
    );
  }

  Future<void> _restorePlaybackAfterFailedFollowRoomTransition({
    required int generation,
    required PlayerState stateBeforeTransition,
    required Object failureError,
    required StackTrace failureStackTrace,
  }) async {
    final source = stateBeforeTransition.source;
    if (source == null || !_isActive(generation)) {
      return;
    }
    trace(
      'fullscreen follow-room transition restore current room '
      'status=${stateBeforeTransition.status.name}',
    );
    try {
      await playbackController.restorePlaybackState(
        previousState: stateBeforeTransition,
        label: 'fullscreen follow-room transition',
      );
    } catch (restoreError, restoreStackTrace) {
      AppLog.instance.error(
        'room',
        '[RoomPreview/${currentProviderId.value}/$currentRoomId] '
            'follow-room transition restore failed after cleanup error',
        error: restoreError,
        stackTrace: restoreStackTrace,
      );
      AppLog.instance.error(
        'room',
        '[RoomPreview/${currentProviderId.value}/$currentRoomId] '
            'original follow-room transition failure kept for context',
        error: failureError,
        stackTrace: failureStackTrace,
      );
    }
  }

  bool _isActive(int generation) {
    return !_disposed && _transitionGeneration == generation && isMounted();
  }

  void _clearTransitionState(int generation) {
    if (_transitionGeneration != generation) {
      return;
    }
    _replaceState(
      inFlight: false,
      suspendEmbedded: false,
    );
  }

  void _replaceState({
    bool? inFlight,
    bool? suspendEmbedded,
  }) {
    final nextInFlight = inFlight ?? _transitionInFlight;
    final nextSuspend = suspendEmbedded ?? _suspendEmbeddedPlayerForTransition;
    if (_transitionInFlight == nextInFlight &&
        _suspendEmbeddedPlayerForTransition == nextSuspend) {
      return;
    }
    _transitionInFlight = nextInFlight;
    _suspendEmbeddedPlayerForTransition = nextSuspend;
    if (!_disposed) {
      notifyListeners();
    }
  }

  String _summarizePlaybackSource(PlaybackSource? source) {
    final url = source?.url;
    if (url == null) {
      return '-';
    }
    final audio = source?.externalAudio?.url;
    final base = '${url.host}${url.path}';
    if (audio == null) {
      return base;
    }
    return '$base + audio=${audio.host}${audio.path}';
  }

  @override
  void dispose() {
    _disposed = true;
    _transitionGeneration += 1;
    super.dispose();
  }
}
