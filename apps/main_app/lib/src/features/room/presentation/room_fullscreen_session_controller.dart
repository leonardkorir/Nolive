import 'dart:async';

import 'package:floating/floating.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:live_player/live_player.dart';
import 'package:screen_brightness/screen_brightness.dart';

import 'room_desktop_mini_window_coordinator.dart';
import 'room_fullscreen_chrome_controller.dart';
import 'room_fullscreen_runtime_context.dart';
import 'room_fullscreen_session_platforms.dart';
import 'room_gesture_ui_state.dart';
import 'room_picture_in_picture_coordinator.dart';
import 'room_playback_leave_cleanup_coordinator.dart';
import 'room_view_ui_state.dart';

bool shouldRefreshMdkBackendAfterCleanup(PlayerState state) {
  if (state.backend != PlayerBackend.mdk) {
    return false;
  }
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

class RoomFullscreenSessionBindings {
  const RoomFullscreenSessionBindings({
    required this.runtime,
    required this.trace,
    required this.showMessage,
    required this.ensureFollowWatchlistLoaded,
    required this.resolveDarkThemeActive,
    required this.resolveBackgroundAutoPauseEnabled,
    required this.resolvePipHideDanmakuEnabled,
    required this.resolveDanmakuOverlayVisible,
    required this.updateDanmakuOverlayVisible,
    required this.resolveVolume,
    required this.updateVolume,
    required this.resolvePipAspectRatio,
    required this.resolveScreenSize,
    required this.resolvePlaybackSourceForLifecycleRestore,
  });

  final RoomFullscreenRuntimeContext runtime;
  final void Function(String message) trace;
  final void Function(String message) showMessage;
  final Future<void> Function() ensureFollowWatchlistLoaded;
  final bool Function() resolveDarkThemeActive;
  final bool Function() resolveBackgroundAutoPauseEnabled;
  final bool Function() resolvePipHideDanmakuEnabled;
  final bool Function() resolveDanmakuOverlayVisible;
  final void Function(bool visible) updateDanmakuOverlayVisible;
  final double Function() resolveVolume;
  final void Function(double value) updateVolume;
  final Rational Function() resolvePipAspectRatio;
  final Size Function() resolveScreenSize;
  final Future<PlaybackSource?> Function()
      resolvePlaybackSourceForLifecycleRestore;
}

class RoomFullscreenSessionController extends ChangeNotifier {
  RoomFullscreenSessionController({
    required this.bindings,
    required this.platforms,
    ScreenBrightness? screenBrightness,
  }) {
    _chromeController = RoomFullscreenChromeController(
      context: RoomFullscreenChromeContext(
        androidPlaybackBridge: platforms.androidPlaybackBridge,
        ensureFollowWatchlistLoaded: bindings.ensureFollowWatchlistLoaded,
        resolveScreenSize: bindings.resolveScreenSize,
        resolveVolume: bindings.resolveVolume,
        updateVolume: bindings.updateVolume,
        readViewUiState: () => _viewUiState,
        updateViewUiState: _updateViewUiState,
        readGestureUiState: () => _gestureUiState,
        updateGestureUiState: _updateGestureUiState,
        isDisposed: () => _disposed,
      ),
      screenBrightness: screenBrightness,
    );
    _pipCoordinator = RoomPictureInPictureCoordinator(
      context: RoomPictureInPictureContext(
        runtime: bindings.runtime,
        androidPlaybackBridge: platforms.androidPlaybackBridge,
        pipHost: platforms.pipHost,
        trace: bindings.trace,
        showMessage: bindings.showMessage,
        resolveBackgroundAutoPauseEnabled:
            bindings.resolveBackgroundAutoPauseEnabled,
        resolvePipHideDanmakuEnabled: bindings.resolvePipHideDanmakuEnabled,
        resolveDanmakuOverlayVisible: bindings.resolveDanmakuOverlayVisible,
        updateDanmakuOverlayVisible: bindings.updateDanmakuOverlayVisible,
        resolvePipAspectRatio: bindings.resolvePipAspectRatio,
        updateVolume: bindings.updateVolume,
        readViewUiState: () => _viewUiState,
        updateViewUiState: _updateViewUiState,
        isDisposed: () => _disposed,
        applyFullscreenSystemUi: applyFullscreenSystemUi,
        scheduleFullscreenChromeAutoHide:
            _chromeController.scheduleFullscreenChromeAutoHide,
        scheduleInlineChromeAutoHide:
            _chromeController.scheduleInlineChromeAutoHide,
        cancelChromeAutoHideTimers: _chromeController.cancelAutoHideTimers,
        clearGestureTip: _chromeController.clearGestureTip,
        resolvePlaybackSourceForLifecycleRestore:
            bindings.resolvePlaybackSourceForLifecycleRestore,
      ),
    );
    _desktopMiniWindowCoordinator = RoomDesktopMiniWindowCoordinator(
      context: RoomDesktopMiniWindowContext(
        desktopWindow: platforms.desktopWindow,
        readViewUiState: () => _viewUiState,
        updateViewUiState: _updateViewUiState,
        isDisposed: () => _disposed,
      ),
    );
    _playbackLeaveCleanupCoordinator = RoomPlaybackLeaveCleanupCoordinator(
      context: RoomPlaybackLeaveCleanupContext(
        runtime: bindings.runtime,
        androidPlaybackBridge: platforms.androidPlaybackBridge,
        readViewUiState: () => _viewUiState,
        trace: bindings.trace,
        shouldRefreshBackendAfterCleanup: shouldRefreshMdkBackendAfterCleanup,
      ),
    );
  }

  final RoomFullscreenSessionBindings bindings;
  final RoomFullscreenSessionPlatforms platforms;

  late final RoomFullscreenChromeController _chromeController;
  late final RoomPictureInPictureCoordinator _pipCoordinator;
  late final RoomDesktopMiniWindowCoordinator _desktopMiniWindowCoordinator;
  late final RoomPlaybackLeaveCleanupCoordinator
      _playbackLeaveCleanupCoordinator;

  RoomViewUiState _viewUiState = const RoomViewUiState();
  RoomGestureUiState _gestureUiState = const RoomGestureUiState();

  bool _preserveRoomTransitionOnDispose = false;
  bool _disposed = false;
  int _fullscreenBootstrapRequestToken = 0;

  RoomViewUiState get viewUiState => _viewUiState;
  RoomGestureUiState get gestureUiState => _gestureUiState;
  bool get preserveRoomTransitionOnDispose => _preserveRoomTransitionOnDispose;
  bool get fullscreenSessionActive =>
      _viewUiState.isFullscreen || _viewUiState.fullscreenBootstrapPending;
  bool get supportsDesktopMiniWindow => platforms.desktopWindow.isSupported;
  bool get desktopMiniWindowActive => _viewUiState.desktopMiniWindowActive;

  void replaceViewUiState(RoomViewUiState next) {
    _replaceViewUiState(next);
  }

  void replaceGestureUiState(RoomGestureUiState next) {
    _replaceGestureUiState(next);
  }

  Future<void> initialize({required bool startInFullscreen}) async {
    if (startInFullscreen) {
      _replaceViewUiState(
        _viewUiState.copyWith(fullscreenBootstrapPending: true),
      );
    }
    await setScreenAwake(true);
    await _pipCoordinator.primeRuntimeState();
  }

  void resetAutoFullscreenApplied() {
    _replaceViewUiState(
      _viewUiState.copyWith(fullscreenAutoApplied: false),
    );
  }

  void prepareForFollowRoomTransition() {
    _preserveRoomTransitionOnDispose = fullscreenSessionActive;
    _chromeController.hideFullscreenFollowDrawer();
  }

  void rollbackFollowRoomTransition() {
    _preserveRoomTransitionOnDispose = false;
  }

  void handleResolvedRoomState({
    required bool roomLoaded,
    required bool playbackAvailable,
  }) {
    _resolveFullscreenBootstrap(
      roomLoaded: roomLoaded,
      playbackAvailable: playbackAvailable,
    );
  }

  void handlePlayerStateChanged(
    PlayerState? playerState, {
    required bool playbackAvailable,
    required bool autoFullscreenEnabled,
  }) {
    maybeApplyAutoFullscreen(
      playerState,
      playbackAvailable: playbackAvailable,
      autoFullscreenEnabled: autoFullscreenEnabled,
    );
  }

  void toggleFullscreenChrome() {
    _chromeController.toggleFullscreenChrome();
  }

  void toggleFullscreenLock() {
    _chromeController.toggleFullscreenLock();
  }

  void openFullscreenFollowDrawer() {
    _chromeController.openFullscreenFollowDrawer();
  }

  void hideFullscreenFollowDrawer() {
    _chromeController.hideFullscreenFollowDrawer();
  }

  void toggleInlinePlayerChrome() {
    _chromeController.toggleInlinePlayerChrome();
  }

  void showInlinePlayerChromeTemporarily() {
    _chromeController.showInlinePlayerChromeTemporarily();
  }

  void scheduleFullscreenChromeAutoHide() {
    _chromeController.scheduleFullscreenChromeAutoHide();
  }

  void scheduleInlineChromeAutoHide() {
    _chromeController.scheduleInlineChromeAutoHide();
  }

  void showGestureTip(String text) {
    _chromeController.showGestureTip(text);
  }

  void clearGestureTip() {
    _chromeController.clearGestureTip(rescheduleChrome: true);
  }

  Future<void> enterFullscreen() async {
    if (_viewUiState.isFullscreen) {
      return;
    }
    bindings.trace('enter fullscreen');
    if (_viewUiState.desktopMiniWindowActive) {
      await _desktopMiniWindowCoordinator.exitDesktopMiniWindow(
        scheduleInlineChromeAutoHide:
            _chromeController.scheduleInlineChromeAutoHide,
        scheduleInlineChromeAfterExit: false,
      );
    }
    _chromeController.cancelAutoHideTimers();
    _replaceViewUiState(
      _viewUiState.copyWith(
        isFullscreen: true,
        showInlinePlayerChrome: false,
        showFullscreenChrome: true,
        showFullscreenLockButton: true,
        showFullscreenFollowDrawer: false,
      ),
    );
    _chromeController.clearGestureTip(rescheduleChrome: false);
    _chromeController.scheduleFullscreenChromeAutoHide();
    await applyFullscreenSystemUi();
  }

  Future<void> exitFullscreen() async {
    if (!_viewUiState.isFullscreen) {
      return;
    }
    bindings.trace('exit fullscreen');
    _chromeController.cancelAutoHideTimers();
    _replaceViewUiState(
      _viewUiState.copyWith(
        isFullscreen: false,
        showInlinePlayerChrome: true,
        showFullscreenChrome: true,
        showFullscreenLockButton: true,
        lockFullscreenControls: false,
        showFullscreenFollowDrawer: false,
      ),
    );
    _chromeController.clearGestureTip(rescheduleChrome: false);
    _chromeController.scheduleInlineChromeAutoHide();
    await restoreSystemUi();
  }

  Future<void> applyFullscreenSystemUi() async {
    await _applyOverlayStyle(darkBackground: true);
    if (platforms.androidPlaybackBridge.isSupported) {
      await platforms.androidPlaybackBridge.lockLandscape();
      await platforms.systemUi.setEnabledSystemUIMode(
        SystemUiMode.immersiveSticky,
      );
      return;
    }
    await platforms.systemUi.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  Future<void> restoreSystemUi() async {
    if (platforms.androidPlaybackBridge.isSupported) {
      await platforms.androidPlaybackBridge.lockPortrait();
    } else {
      await platforms.systemUi.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
    }
    await _applyOverlayStyle(
      darkBackground: bindings.resolveDarkThemeActive(),
    );
    if (platforms.androidPlaybackBridge.isSupported) {
      await platforms.systemUi.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  Future<void> setScreenAwake(bool enabled) async {
    if (!platforms.androidPlaybackBridge.isSupported &&
        !platforms.desktopWindow.isSupported) {
      return;
    }
    try {
      await platforms.screenAwake.toggle(enabled: enabled);
    } catch (_) {}
  }

  Future<void> toggleDesktopMiniWindow() async {
    if (!platforms.desktopWindow.isSupported) {
      return;
    }
    try {
      if (_viewUiState.desktopMiniWindowActive) {
        await _desktopMiniWindowCoordinator.exitDesktopMiniWindow(
          scheduleInlineChromeAutoHide:
              _chromeController.scheduleInlineChromeAutoHide,
        );
      } else {
        await _desktopMiniWindowCoordinator.enterDesktopMiniWindow(
          exitFullscreen: exitFullscreen,
          scheduleInlineChromeAutoHide:
              _chromeController.scheduleInlineChromeAutoHide,
        );
      }
    } catch (error) {
      bindings.showMessage('桌面小窗切换失败：$error');
    }
  }

  Future<void> exitDesktopMiniWindow() {
    return _desktopMiniWindowCoordinator.exitDesktopMiniWindow(
      scheduleInlineChromeAutoHide:
          _chromeController.scheduleInlineChromeAutoHide,
    );
  }

  Future<void> enterPictureInPicture() {
    return _pipCoordinator.enterPictureInPicture();
  }

  Future<void> restoreAfterFailedPictureInPicture() {
    return _pipCoordinator.restoreAfterFailedPictureInPicture();
  }

  Future<void> handleLifecycleState(AppLifecycleState state) {
    return _pipCoordinator.handleLifecycleState(state);
  }

  Future<void> cleanupPlaybackOnLeave() {
    _chromeController.cancelAutoHideTimers();
    _replaceViewUiState(
      _viewUiState.copyWith(pausedByLifecycle: false),
    );
    return _playbackLeaveCleanupCoordinator.cleanupPlaybackOnLeave();
  }

  void maybeApplyAutoFullscreen(
    PlayerState? playerState, {
    required bool playbackAvailable,
    required bool autoFullscreenEnabled,
  }) {
    if (!platforms.androidPlaybackBridge.isSupported ||
        !playbackAvailable ||
        !autoFullscreenEnabled ||
        _viewUiState.fullscreenAutoApplied ||
        _viewUiState.isFullscreen) {
      return;
    }
    final status = playerState?.status ?? PlaybackStatus.idle;
    if (status != PlaybackStatus.ready &&
        status != PlaybackStatus.playing &&
        status != PlaybackStatus.buffering) {
      return;
    }
    _replaceViewUiState(
      _viewUiState.copyWith(fullscreenAutoApplied: true),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed || _viewUiState.isFullscreen) {
        return;
      }
      unawaited(enterFullscreen());
    });
  }

  Future<void> handleVerticalDragStart(DragStartDetails details) {
    return _chromeController.handleVerticalDragStart(details);
  }

  Future<void> handleVerticalDragUpdate(DragUpdateDetails details) {
    return _chromeController.handleVerticalDragUpdate(details);
  }

  Future<void> handleVerticalDragEnd() {
    return _chromeController.handleVerticalDragEnd();
  }

  Future<void> cancelPendingFullscreenBootstrap({
    required bool scheduleInlineChrome,
  }) async {
    if (!_viewUiState.fullscreenBootstrapPending &&
        !_viewUiState.fullscreenBootstrapScheduled) {
      return;
    }
    _fullscreenBootstrapRequestToken += 1;
    _replaceViewUiState(
      _viewUiState.copyWith(
        fullscreenBootstrapPending: false,
        fullscreenBootstrapScheduled: false,
        showInlinePlayerChrome: true,
        showFullscreenChrome: true,
        showFullscreenFollowDrawer: false,
      ),
    );
    _chromeController.clearGestureTip(rescheduleChrome: false);
    await restoreSystemUi();
    if (scheduleInlineChrome) {
      _chromeController.scheduleInlineChromeAutoHide();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _chromeController.dispose();
    unawaited(_pipCoordinator.dispose());
    super.dispose();
  }

  void _resolveFullscreenBootstrap({
    required bool roomLoaded,
    required bool playbackAvailable,
  }) {
    if (!_viewUiState.fullscreenBootstrapPending || _viewUiState.isFullscreen) {
      return;
    }
    if (!roomLoaded) {
      return;
    }
    final token = ++_fullscreenBootstrapRequestToken;
    if (!playbackAvailable) {
      if (_viewUiState.fullscreenBootstrapScheduled) {
        return;
      }
      _replaceViewUiState(
        _viewUiState.copyWith(fullscreenBootstrapScheduled: true),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_disposed ||
            token != _fullscreenBootstrapRequestToken ||
            !_viewUiState.fullscreenBootstrapPending) {
          return;
        }
        unawaited(
          cancelPendingFullscreenBootstrap(scheduleInlineChrome: true),
        );
      });
      return;
    }
    if (_viewUiState.fullscreenBootstrapScheduled) {
      return;
    }
    _replaceViewUiState(
      _viewUiState.copyWith(fullscreenBootstrapScheduled: true),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_disposed ||
          token != _fullscreenBootstrapRequestToken ||
          !_viewUiState.fullscreenBootstrapPending ||
          _viewUiState.isFullscreen) {
        return;
      }
      _replaceViewUiState(
        _viewUiState.copyWith(
          fullscreenBootstrapPending: false,
          fullscreenBootstrapScheduled: false,
          isFullscreen: true,
          showInlinePlayerChrome: false,
          showFullscreenChrome: true,
          showFullscreenFollowDrawer: false,
        ),
      );
      _chromeController.clearGestureTip(rescheduleChrome: false);
      _chromeController.scheduleFullscreenChromeAutoHide();
      await applyFullscreenSystemUi();
    });
  }

  Future<void> _applyOverlayStyle({required bool darkBackground}) async {
    final style = (darkBackground
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark)
        .copyWith(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
    );
    await platforms.systemUi.setSystemUIOverlayStyle(style);
  }

  void _updateViewUiState(
    RoomViewUiState Function(RoomViewUiState current) updater,
  ) {
    _replaceViewUiState(updater(_viewUiState));
  }

  void _updateGestureUiState(
    RoomGestureUiState Function(RoomGestureUiState current) updater,
  ) {
    _replaceGestureUiState(updater(_gestureUiState));
  }

  void _replaceViewUiState(RoomViewUiState next) {
    if (_disposed) {
      return;
    }
    _viewUiState = next;
    notifyListeners();
  }

  void _replaceGestureUiState(RoomGestureUiState next) {
    if (_disposed) {
      return;
    }
    _gestureUiState = next;
    notifyListeners();
  }
}
