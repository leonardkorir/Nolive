import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:live_player/live_player.dart';
import 'package:screen_brightness/screen_brightness.dart';

import 'package:nolive_app/src/app/platform/app_platform_capabilities.dart';

import 'room_desktop_mini_window_coordinator.dart';
import 'room_fullscreen_chrome_controller.dart';
import '../application/room_fullscreen_form_factor_policy.dart';
import '../application/room_fullscreen_runtime_context.dart';
import 'package:nolive_app/src/features/room/application/room_fullscreen_session_ports.dart';
import '../application/room_gesture_ui_state.dart';
import '../application/room_page_rebuild_scope.dart';
import 'room_picture_in_picture_coordinator.dart';
import '../application/room_playback_leave_cleanup_coordinator.dart';
import '../application/room_view_ui_state.dart';

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
        PlaybackStatus.error => true,
        _ => false,
      };
}

bool shouldRefreshNativeBackendAfterLeaveCleanup(PlayerState state) {
  return shouldRefreshMdkBackendAfterCleanup(state);
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
    required this.resolveIsVerticalVideo,
    this.resolveIsArcChromeOs,
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
  final RoomPipAspectRatio Function() resolvePipAspectRatio;
  final Size Function() resolveScreenSize;
  final Future<PlaybackSource?> Function()
  resolvePlaybackSourceForLifecycleRestore;
  final bool Function() resolveIsVerticalVideo;

  /// Optional override for tests; defaults to ChromeOS ARC version sniffing.
  final bool Function()? resolveIsArcChromeOs;
}

class RoomFullscreenSessionController extends ChangeNotifier {
  RoomFullscreenSessionController({
    required this.bindings,
    required this.platforms,
    bool startInFullscreen = false,
    ScreenBrightness? screenBrightness,
  }) {
    if (startInFullscreen) {
      // Seed before the first frame so follow-room switches never flash the
      // non-fullscreen tablet side panel while bootstrap is still pending.
      _viewUiState = const RoomViewUiState(
        fullscreenBootstrapPending: true,
        showInlinePlayerChrome: false,
        showFullscreenChrome: true,
        showFullscreenLockButton: true,
      );
    }
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
        applyFullscreenControlsLock: applyFullscreenControlsLock,
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
        shouldRefreshBackendAfterCleanup:
            shouldRefreshNativeBackendAfterLeaveCleanup,
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

  /// Last applied fullscreen orientation mode (phone portrait vs large flexible).
  RoomFullscreenVideoOrientationMode? _lastAppliedOrientationMode;

  RoomViewUiState get viewUiState => _viewUiState;
  RoomGestureUiState get gestureUiState => _gestureUiState;
  bool get preserveRoomTransitionOnDispose => _preserveRoomTransitionOnDispose;
  bool get fullscreenSessionActive => _viewUiState.fullscreenSessionActive;
  bool get supportsDesktopMiniWindow => platforms.desktopWindow.isSupported;
  bool get desktopMiniWindowActive => _viewUiState.desktopMiniWindowActive;

  void replaceViewUiState(RoomViewUiState next) {
    _replaceViewUiState(next);
  }

  void replaceGestureUiState(RoomGestureUiState next) {
    _replaceGestureUiState(next);
  }

  Future<void> initialize({required bool startInFullscreen}) async {
    _chromeController.cancelAutoHideTimers();
    _replaceGestureUiState(const RoomGestureUiState());
    _replaceViewUiState(
      _viewUiState.copyWith(
        isFullscreen: false,
        fullscreenBootstrapPending: startInFullscreen,
        fullscreenBootstrapScheduled: false,
        showInlinePlayerChrome: !startInFullscreen,
        showFullscreenChrome: true,
        showFullscreenLockButton: true,
        lockFullscreenControls: false,
        showFullscreenFollowDrawer: false,
      ),
    );
    _chromeController.clearGestureTip(rescheduleChrome: false);
    if (startInFullscreen) {
      _chromeController.scheduleFullscreenChromeAutoHide();
      // Keep immersive system UI across seamless follow-room replacements so
      // the landscape tablet chrome does not reappear mid-load.
      unawaited(applyFullscreenSystemUi());
    }
    await setScreenAwake(true);
    await _pipCoordinator.primeRuntimeState();
  }

  void resetAutoFullscreenApplied() {
    _replaceViewUiState(_viewUiState.copyWith(fullscreenAutoApplied: false));
  }

  void prepareForFollowRoomTransition() {
    _preserveRoomTransitionOnDispose = fullscreenSessionActive;
    _chromeController.cancelAutoHideTimers();
    _replaceGestureUiState(const RoomGestureUiState());
    _chromeController.clearGestureTip(rescheduleChrome: false);
    _chromeController.hideFullscreenFollowDrawer();
  }

  /// In-place room switch keeps this page mounted, so only chrome/drawer is
  /// cleared — never mark dispose-time system UI preservation.
  void prepareForInPlaceFollowRoomSwitch() {
    _chromeController.cancelAutoHideTimers();
    _replaceGestureUiState(const RoomGestureUiState());
    _chromeController.clearGestureTip(rescheduleChrome: false);
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
    bool videoAspectMayHaveChanged = false,
  }) {
    maybeApplyAutoFullscreen(
      playerState,
      playbackAvailable: playbackAvailable,
      autoFullscreenEnabled: autoFullscreenEnabled,
    );
    if (videoAspectMayHaveChanged) {
      maybeSyncFullscreenOrientationToVideoAspect();
    }
  }

  /// When diagnostics first report size while fullscreen, re-apply mode:
  /// phone vertical → hard portrait; non-ARC large tablet vertical → hold;
  /// ARC stays long-edge landscape (no portrait re-apply).
  void maybeSyncFullscreenOrientationToVideoAspect() {
    if (_disposed ||
        !_viewUiState.fullscreenSessionActive ||
        _viewUiState.lockFullscreenControls) {
      return;
    }
    final mode = resolveFullscreenVideoOrientationMode();
    if (_lastAppliedOrientationMode == mode) {
      return;
    }
    bindings.trace(
      'fullscreen orientation re-apply mode=${mode.name} after size known',
    );
    unawaited(applyFullscreenSystemUi());
  }

  RoomFullscreenVideoOrientationMode resolveFullscreenVideoOrientationMode() {
    return resolveRoomFullscreenVideoOrientationMode(
      screenSize: bindings.resolveScreenSize(),
      verticalVideo: bindings.resolveIsVerticalVideo(),
      isArcChromeOs: _isArcChromeOs(),
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
    if (_disposed || _viewUiState.isFullscreen) {
      return;
    }
    bindings.trace('enter fullscreen');
    if (_viewUiState.desktopMiniWindowActive) {
      await _desktopMiniWindowCoordinator.exitDesktopMiniWindow(
        scheduleInlineChromeAutoHide:
            _chromeController.scheduleInlineChromeAutoHide,
        scheduleInlineChromeAfterExit: false,
      );
      if (_disposed || _viewUiState.isFullscreen) {
        return;
      }
    }
    _chromeController.cancelAutoHideTimers();
    _replaceViewUiState(
      _viewUiState.copyWith(
        isFullscreen: true,
        showInlinePlayerChrome: false,
        showFullscreenChrome: true,
        showFullscreenLockButton: true,
        lockFullscreenControls: false,
        showFullscreenFollowDrawer: false,
      ),
    );
    _chromeController.clearGestureTip(rescheduleChrome: false);
    _chromeController.scheduleFullscreenChromeAutoHide();
    await applyFullscreenSystemUi();
  }

  Future<void> exitFullscreen() async {
    if (_disposed || !_viewUiState.isFullscreen) {
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

  bool _isArcChromeOs() {
    return bindings.resolveIsArcChromeOs?.call() ??
        looksLikeArcChromeOsVersion(
          AppPlatformCapabilities.current().operatingSystemVersion,
        );
  }

  Future<void> applyFullscreenSystemUi() async {
    if (_disposed) {
      return;
    }
    try {
      await _applyOverlayStyle(darkBackground: true);
      if (_disposed) {
        return;
      }
      final mode = resolveFullscreenVideoOrientationMode();
      final verticalVideo = bindings.resolveIsVerticalVideo();
      final isArc = _isArcChromeOs();
      if (platforms.androidPlaybackBridge.isSupported) {
        if (isArc) {
          // Single ARC authority: native landscape-only only. Do not dual-write
          // Flutter multi-orientation lists (map to USER* and fight intercept).
          await platforms.androidPlaybackBridge.lockLandscape();
        } else {
          switch (mode) {
            case RoomFullscreenVideoOrientationMode.hardPortrait:
              // Phone + vertical stream: classic hard portrait.
              await platforms.systemUi.setPreferredOrientations(const [
                DeviceOrientation.portraitUp,
              ]);
              await platforms.androidPlaybackBridge.lockPortraitFullscreen();
            case RoomFullscreenVideoOrientationMode.userHoldPortraitOrLandscape:
              // Non-ARC large tablets only.
              await platforms.androidPlaybackBridge.restoreShellOrientation();
              await platforms.systemUi.setPreferredOrientations(
                kRoomVerticalLargeFormOrientations,
              );
            case RoomFullscreenVideoOrientationMode.longEdgeLandscape:
              await platforms.systemUi.setPreferredOrientations(const [
                DeviceOrientation.landscapeLeft,
                DeviceOrientation.landscapeRight,
              ]);
              // Native last: long-edge L/R (works without system free-rotate).
              await platforms.androidPlaybackBridge.lockLandscape();
          }
        }
        _lastAppliedOrientationMode = mode;
        bindings.trace(
          'fullscreen orientation mode=${mode.name} vertical=$verticalVideo '
          'arc=$isArc',
        );
        if (_disposed) {
          return;
        }
        await platforms.systemUi.setEnabledSystemUIMode(
          SystemUiMode.immersiveSticky,
        );
        return;
      }
      // Non-Android: Flutter orientations only (no native bridge).
      if (isArc) {
        // Desktop/web never is ARC; keep branch defensive.
        _lastAppliedOrientationMode = mode;
      } else {
        switch (mode) {
          case RoomFullscreenVideoOrientationMode.hardPortrait:
            await platforms.systemUi.setPreferredOrientations(const [
              DeviceOrientation.portraitUp,
            ]);
          case RoomFullscreenVideoOrientationMode.userHoldPortraitOrLandscape:
            await platforms.systemUi.setPreferredOrientations(
              kRoomVerticalLargeFormOrientations,
            );
          case RoomFullscreenVideoOrientationMode.longEdgeLandscape:
            await platforms.systemUi.setPreferredOrientations(const [
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ]);
        }
        _lastAppliedOrientationMode = mode;
      }
      if (_disposed) {
        return;
      }
      await platforms.systemUi.setEnabledSystemUIMode(
        SystemUiMode.immersiveSticky,
      );
    } catch (error) {
      bindings.trace('apply fullscreen system ui failed: $error');
      bindings.showMessage('切换全屏失败：$error');
    }
  }

  Future<void> restoreSystemUi() async {
    if (_disposed) {
      return;
    }
    try {
      final isArc = _isArcChromeOs();
      if (platforms.androidPlaybackBridge.isSupported) {
        // restoreShellOrientation: phone → free shell; ARC → landscape-only.
        await platforms.androidPlaybackBridge.restoreShellOrientation();
        if (!isArc) {
          await platforms.systemUi.setPreferredOrientations(
            kRoomAppPreferredOrientations,
          );
        }
        // ARC: no Flutter orientation list — native shell is sole writer.
      } else if (!isArc) {
        await platforms.systemUi.setPreferredOrientations(
          kRoomAppPreferredOrientations,
        );
      }
      _lastAppliedOrientationMode = null;
      if (_disposed) {
        return;
      }
      await _applyOverlayStyle(
        darkBackground: bindings.resolveDarkThemeActive(),
      );
      if (_disposed) {
        return;
      }
      if (platforms.androidPlaybackBridge.isSupported) {
        await platforms.systemUi.setEnabledSystemUIMode(
          SystemUiMode.edgeToEdge,
        );
      }
    } catch (error) {
      bindings.trace('restore system ui failed: $error');
      bindings.showMessage('恢复界面失败：$error');
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

  /// Fullscreen chrome lock: pin the current pose and stop sensor L/R flips.
  /// Unlock restores sensor landscape (or portrait) via [applyFullscreenSystemUi].
  ///
  /// Returns `false` when pin/restore failed so chrome can roll back UI lock.
  Future<bool> applyFullscreenControlsLock(bool locked) async {
    if (_disposed || !_viewUiState.fullscreenSessionActive) {
      return false;
    }
    try {
      if (!locked) {
        await applyFullscreenSystemUi();
        return true;
      }
      final size = bindings.resolveScreenSize();
      final landscape = size.width >= size.height;
      final isArc = _isArcChromeOs();
      if (platforms.androidPlaybackBridge.isSupported) {
        if (!isArc) {
          // Phone/tablet: SystemChrome first, native freeze last so L+R sensor
          // mapping cannot undo a fixed pin.
          if (landscape) {
            await platforms.systemUi.setPreferredOrientations(const [
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ]);
          } else {
            await platforms.systemUi.setPreferredOrientations(const [
              DeviceOrientation.portraitUp,
            ]);
          }
        }
        // ARC: native freeze only (sole orientation authority).
        final frozen = await platforms.androidPlaybackBridge
            .freezeFullscreenOrientation();
        if (!frozen) {
          bindings.trace(
            'fullscreen controls lock orientation failed: freeze returned false '
            'landscape=$landscape arc=$isArc',
          );
          return false;
        }
      } else if (landscape) {
        // Without a native freeze API, pin both landscape sides only.
        await platforms.systemUi.setPreferredOrientations(const [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      } else {
        await platforms.systemUi.setPreferredOrientations(const [
          DeviceOrientation.portraitUp,
        ]);
      }
      bindings.trace(
        'fullscreen controls lock orientation '
        'locked=true landscape=$landscape freeze=true arc=$isArc',
      );
      return true;
    } catch (error) {
      bindings.trace('fullscreen controls lock orientation failed: $error');
      return false;
    }
  }

  Future<void> toggleDesktopMiniWindow() async {
    if (_disposed || !platforms.desktopWindow.isSupported) {
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
      if (_disposed) {
        return;
      }
    } catch (error) {
      if (_disposed) {
        return;
      }
      bindings.showMessage('桌面小窗切换失败：$error');
    }
  }

  Future<void> exitDesktopMiniWindow() async {
    if (_disposed) {
      return;
    }
    await _desktopMiniWindowCoordinator.exitDesktopMiniWindow(
      scheduleInlineChromeAutoHide:
          _chromeController.scheduleInlineChromeAutoHide,
    );
  }

  Future<void> enterPictureInPicture() async {
    if (_disposed) {
      return;
    }
    await _pipCoordinator.enterPictureInPicture();
  }

  Future<void> restoreAfterFailedPictureInPicture() async {
    if (_disposed) {
      return;
    }
    await _pipCoordinator.restoreAfterFailedPictureInPicture();
  }

  Future<void> handleLifecycleState(AppLifecycleState state) async {
    if (_disposed) {
      return;
    }
    await _pipCoordinator.handleLifecycleState(state);
  }

  Future<void> cleanupPlaybackOnLeave() {
    _chromeController.cancelAutoHideTimers();
    _replaceViewUiState(_viewUiState.copyWith(pausedByLifecycle: false));
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
        _viewUiState.fullscreenSessionActive) {
      return;
    }
    final status = playerState?.status ?? PlaybackStatus.idle;
    if (status != PlaybackStatus.ready &&
        status != PlaybackStatus.playing &&
        status != PlaybackStatus.buffering) {
      return;
    }
    _replaceViewUiState(_viewUiState.copyWith(fullscreenAutoApplied: true));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed || _viewUiState.fullscreenSessionActive) {
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
    if (_disposed) {
      return;
    }
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
        unawaited(cancelPendingFullscreenBootstrap(scheduleInlineChrome: true));
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
          showFullscreenLockButton: true,
          lockFullscreenControls: false,
          showFullscreenFollowDrawer: false,
        ),
      );
      _chromeController.clearGestureTip(rescheduleChrome: false);
      _chromeController.scheduleFullscreenChromeAutoHide();
      await applyFullscreenSystemUi();
    });
  }

  Future<void> _applyOverlayStyle({required bool darkBackground}) async {
    final style =
        (darkBackground
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
    final previousView = _viewUiState;
    final previousGesture = _gestureUiState;
    _viewUiState = next;
    if (shouldNotifyFullscreenSessionListeners(
      previousView: previousView,
      nextView: next,
      previousGesture: previousGesture,
      nextGesture: previousGesture,
    )) {
      notifyListeners();
    }
  }

  void _replaceGestureUiState(RoomGestureUiState next) {
    if (_disposed) {
      return;
    }
    final previousView = _viewUiState;
    final previousGesture = _gestureUiState;
    _gestureUiState = next;
    if (shouldNotifyFullscreenSessionListeners(
      previousView: previousView,
      nextView: previousView,
      previousGesture: previousGesture,
      nextGesture: next,
    )) {
      notifyListeners();
    }
  }
}
