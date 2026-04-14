import 'dart:async';

import 'package:floating/floating.dart';
import 'package:flutter/widgets.dart';
import 'package:live_player/live_player.dart';

import 'room_fullscreen_runtime_context.dart';
import 'room_fullscreen_session_platforms.dart';
import 'room_view_ui_state.dart';

typedef RoomClearGestureTipCallback = void Function(
    {required bool rescheduleChrome});

class RoomPictureInPictureContext {
  const RoomPictureInPictureContext({
    required this.runtime,
    required this.androidPlaybackBridge,
    required this.pipHost,
    required this.trace,
    required this.showMessage,
    required this.resolveBackgroundAutoPauseEnabled,
    required this.resolvePipHideDanmakuEnabled,
    required this.resolveDanmakuOverlayVisible,
    required this.updateDanmakuOverlayVisible,
    required this.resolvePipAspectRatio,
    required this.updateVolume,
    required this.readViewUiState,
    required this.updateViewUiState,
    required this.isDisposed,
    required this.applyFullscreenSystemUi,
    required this.scheduleFullscreenChromeAutoHide,
    required this.scheduleInlineChromeAutoHide,
    required this.cancelChromeAutoHideTimers,
    required this.clearGestureTip,
    required this.resolvePlaybackSourceForLifecycleRestore,
  });

  final RoomFullscreenRuntimeContext runtime;
  final RoomAndroidPlaybackBridgeFacade androidPlaybackBridge;
  final RoomPipHostFacade pipHost;
  final void Function(String message) trace;
  final void Function(String message) showMessage;
  final bool Function() resolveBackgroundAutoPauseEnabled;
  final bool Function() resolvePipHideDanmakuEnabled;
  final bool Function() resolveDanmakuOverlayVisible;
  final void Function(bool visible) updateDanmakuOverlayVisible;
  final Rational Function() resolvePipAspectRatio;
  final void Function(double value) updateVolume;
  final RoomViewUiState Function() readViewUiState;
  final void Function(RoomViewUiState Function(RoomViewUiState current))
      updateViewUiState;
  final bool Function() isDisposed;
  final Future<void> Function() applyFullscreenSystemUi;
  final void Function() scheduleFullscreenChromeAutoHide;
  final void Function() scheduleInlineChromeAutoHide;
  final void Function() cancelChromeAutoHideTimers;
  final RoomClearGestureTipCallback clearGestureTip;
  final Future<PlaybackSource?> Function()
      resolvePlaybackSourceForLifecycleRestore;
}

class RoomPictureInPictureCoordinator {
  RoomPictureInPictureCoordinator({required this.context});

  final RoomPictureInPictureContext context;

  StreamSubscription<PiPStatus>? _pipStatusSubscription;
  PlayerState? _lifecycleStoppedPlaybackState;
  bool _inlineChromeBeforePip = true;
  bool _fullscreenChromeBeforePip = true;
  bool _fullscreenLockButtonBeforePip = true;
  bool _followDrawerBeforePip = false;

  Future<void> primeRuntimeState() async {
    if (context.isDisposed()) {
      return;
    }
    _pipStatusSubscription ??=
        context.pipHost.statusStream.listen(_handlePipStatusChanged);
    final pipSupported = await context.pipHost.isPipAvailable();
    final mediaVolume = await context.androidPlaybackBridge.getMediaVolume();
    if (context.isDisposed()) {
      return;
    }
    if (mediaVolume != null) {
      context.updateVolume(mediaVolume);
    }
    context.updateViewUiState(
      (current) => current.copyWith(pipSupported: pipSupported),
    );
  }

  Future<void> enterPictureInPicture() async {
    if (!context.androidPlaybackBridge.isSupported) {
      return;
    }
    context.trace('enter picture-in-picture');
    final viewState = context.readViewUiState();
    final pipAvailable =
        viewState.pipSupported || await context.pipHost.isPipAvailable();
    if (!pipAvailable) {
      context.showMessage('当前设备不支持画中画播放');
      return;
    }
    context.cancelChromeAutoHideTimers();
    final danmakuVisibleBeforePip = context.resolveDanmakuOverlayVisible();
    final shouldRestoreDanmaku =
        context.resolvePipHideDanmakuEnabled() && danmakuVisibleBeforePip;
    _inlineChromeBeforePip = viewState.showInlinePlayerChrome;
    _fullscreenChromeBeforePip = viewState.showFullscreenChrome;
    _fullscreenLockButtonBeforePip = viewState.showFullscreenLockButton;
    _followDrawerBeforePip = viewState.showFullscreenFollowDrawer;
    context.updateViewUiState(
      (current) => current.copyWith(
        enteringPictureInPicture: true,
        danmakuVisibleBeforePip: danmakuVisibleBeforePip,
        restoreDanmakuAfterPip: shouldRestoreDanmaku,
        showInlinePlayerChrome: false,
        showFullscreenChrome: false,
        showFullscreenLockButton: false,
        showFullscreenFollowDrawer: false,
      ),
    );
    if (shouldRestoreDanmaku) {
      context.updateDanmakuOverlayVisible(false);
    }
    context.clearGestureTip(rescheduleChrome: false);
    try {
      if (viewState.isFullscreen) {
        await context.androidPlaybackBridge.prepareForPictureInPicture();
      }
      final status = await context.pipHost.enablePip(
        aspectRatio: context.resolvePipAspectRatio(),
      );
      if (status == PiPStatus.enabled) {
        return;
      }
    } catch (error) {
      context.trace('enter picture-in-picture failed error=$error');
      await _restoreFromPictureInPictureFailure();
      context.showMessage('进入画中画失败，请稍后重试');
      return;
    }
    await restoreAfterFailedPictureInPicture();
    context.showMessage('进入画中画失败，请稍后重试');
  }

  Future<void> restoreAfterFailedPictureInPicture() async {
    await _restoreFromPictureInPictureFailure();
  }

  Future<void> handleLifecycleState(AppLifecycleState state) async {
    if (!context.androidPlaybackBridge.isSupported) {
      return;
    }
    context.trace('lifecycle state=${state.name}');
    if (state == AppLifecycleState.resumed) {
      final inPip =
          await context.androidPlaybackBridge.isInPictureInPictureMode();
      final lifecycleViewState = context.readViewUiState();
      context.updateViewUiState(
        (current) => current.copyWith(
          enteringPictureInPicture: false,
          showInlinePlayerChrome:
              lifecycleViewState.inlineChromeBeforeLifecycle,
          showFullscreenChrome:
              lifecycleViewState.fullscreenChromeBeforeLifecycle,
        ),
      );
      var currentViewState = context.readViewUiState();
      if (!inPip && currentViewState.restoreDanmakuAfterPip) {
        context.updateDanmakuOverlayVisible(
          currentViewState.danmakuVisibleBeforePip,
        );
        context.updateViewUiState(
          (current) => current.copyWith(restoreDanmakuAfterPip: false),
        );
        currentViewState = context.readViewUiState();
      }
      if (!inPip && currentViewState.isFullscreen) {
        await context.applyFullscreenSystemUi();
      }
      _scheduleChromeAutoHide(currentViewState);
      final stoppedPlaybackState = _lifecycleStoppedPlaybackState;
      if (!inPip && stoppedPlaybackState != null) {
        _lifecycleStoppedPlaybackState = null;
        await _restorePlaybackAfterLifecycleStop(stoppedPlaybackState);
        return;
      }
      if (!inPip && currentViewState.pausedByLifecycle) {
        context.updateViewUiState(
          (current) => current.copyWith(pausedByLifecycle: false),
        );
        await context.runtime.play();
      }
      return;
    }

    if (state != AppLifecycleState.hidden &&
        state != AppLifecycleState.paused) {
      return;
    }
    if (context.readViewUiState().enteringPictureInPicture) {
      return;
    }
    final inPip =
        await context.androidPlaybackBridge.isInPictureInPictureMode();
    if (inPip || !context.resolveBackgroundAutoPauseEnabled()) {
      return;
    }
    context.updateViewUiState(
      (current) => current.copyWith(
        inlineChromeBeforeLifecycle: current.showInlinePlayerChrome,
        fullscreenChromeBeforeLifecycle: current.showFullscreenChrome,
      ),
    );
    final playbackState = context.runtime.readCurrentState();
    if (_shouldStopPlaybackForLifecycle(playbackState)) {
      if (_lifecycleStoppedPlaybackState != null) {
        return;
      }
      _lifecycleStoppedPlaybackState = playbackState;
      context.updateViewUiState(
        (current) => current.copyWith(pausedByLifecycle: false),
      );
      await _stopPlaybackForLifecycle(playbackState);
      return;
    }
    if (playbackState.status == PlaybackStatus.playing) {
      context.updateViewUiState(
        (current) => current.copyWith(pausedByLifecycle: true),
      );
      await context.runtime.pause();
    }
  }

  Future<void> dispose() async {
    await _pipStatusSubscription?.cancel();
  }

  void _handlePipStatusChanged(PiPStatus status) {
    if (context.isDisposed()) {
      return;
    }
    if (status == PiPStatus.enabled) {
      context.updateViewUiState(
        (current) => current.copyWith(
          enteringPictureInPicture: false,
          showInlinePlayerChrome: false,
          showFullscreenChrome: false,
          showFullscreenLockButton: false,
          showFullscreenFollowDrawer: false,
        ),
      );
      context.clearGestureTip(rescheduleChrome: false);
      return;
    }
    if (status == PiPStatus.disabled) {
      _restoreUiAfterPictureInPictureExit(
        reapplyFullscreenSystemUi: true,
      );
    }
  }

  Future<void> _restoreFromPictureInPictureFailure() async {
    await _restoreUiAfterPictureInPictureExit(
      reapplyFullscreenSystemUi: true,
    );
  }

  Future<void> _restoreUiAfterPictureInPictureExit({
    required bool reapplyFullscreenSystemUi,
  }) async {
    context.updateViewUiState(
      (current) => current.copyWith(
        enteringPictureInPicture: false,
        showInlinePlayerChrome: _inlineChromeBeforePip,
        showFullscreenChrome: _fullscreenChromeBeforePip,
        showFullscreenLockButton: _fullscreenLockButtonBeforePip,
        showFullscreenFollowDrawer: _followDrawerBeforePip,
      ),
    );
    var currentViewState = context.readViewUiState();
    if (currentViewState.restoreDanmakuAfterPip) {
      context.updateDanmakuOverlayVisible(
        currentViewState.danmakuVisibleBeforePip,
      );
      context.updateViewUiState(
        (current) => current.copyWith(restoreDanmakuAfterPip: false),
      );
      currentViewState = context.readViewUiState();
    }
    if (reapplyFullscreenSystemUi &&
        currentViewState.isFullscreen &&
        context.androidPlaybackBridge.isSupported) {
      await context.applyFullscreenSystemUi();
    }
    _scheduleChromeAutoHide(currentViewState);
  }

  void _scheduleChromeAutoHide(RoomViewUiState viewState) {
    if (viewState.isFullscreen && viewState.showFullscreenChrome) {
      context.scheduleFullscreenChromeAutoHide();
    } else if (!viewState.isFullscreen && viewState.showInlinePlayerChrome) {
      context.scheduleInlineChromeAutoHide();
    }
  }

  bool _shouldStopPlaybackForLifecycle(PlayerState state) {
    return state.source != null ||
        switch (state.status) {
          PlaybackStatus.buffering ||
          PlaybackStatus.playing ||
          PlaybackStatus.paused ||
          PlaybackStatus.completed ||
          PlaybackStatus.error =>
            true,
          _ => false,
        };
  }

  bool _shouldRefreshBackendAfterLifecycleStop(PlayerState state) {
    final backend = state.backend ?? context.runtime.resolveBackend();
    return backend == PlayerBackend.mdk &&
        (state.source != null ||
            switch (state.status) {
              PlaybackStatus.buffering ||
              PlaybackStatus.playing ||
              PlaybackStatus.paused ||
              PlaybackStatus.completed ||
              PlaybackStatus.error =>
                true,
              _ => false,
            });
  }

  Future<void> _stopPlaybackForLifecycle(PlayerState state) async {
    final backend = state.backend ?? context.runtime.resolveBackend();
    context.trace(
      'lifecycle stop playback backend=${backend.name} '
      'status=${state.status.name}',
    );
    try {
      await context.runtime.stop();
      if (!_shouldRefreshBackendAfterLifecycleStop(state)) {
        return;
      }
      context.trace('lifecycle refresh backend=${backend.name}');
      await context.runtime.refreshBackendWithoutPlaybackState();
    } catch (error) {
      _lifecycleStoppedPlaybackState = null;
      context.trace('lifecycle stop playback failed error=$error');
    }
  }

  Future<void> _restorePlaybackAfterLifecycleStop(
      PlayerState previousState) async {
    final backend = previousState.backend ?? context.runtime.resolveBackend();
    context.trace(
      'lifecycle restore playback backend=${backend.name} '
      'status=${previousState.status.name}',
    );
    try {
      final source = await context.resolvePlaybackSourceForLifecycleRestore();
      if (source == null) {
        return;
      }
      await context.runtime.setSource(source);
      final status = previousState.status;
      if (status == PlaybackStatus.paused) {
        await context.runtime.pause();
        return;
      }
      if (status == PlaybackStatus.playing ||
          status == PlaybackStatus.buffering ||
          status == PlaybackStatus.completed) {
        await context.runtime.play();
      }
    } catch (error) {
      context.trace('lifecycle restore playback failed error=$error');
    }
  }
}
