import 'dart:async';

import 'package:flutter/material.dart';
import 'package:screen_brightness/screen_brightness.dart';

import 'room_fullscreen_session_platforms.dart';
import 'room_gesture_ui_state.dart';
import 'room_view_ui_state.dart';

class RoomFullscreenChromeContext {
  const RoomFullscreenChromeContext({
    required this.androidPlaybackBridge,
    required this.ensureFollowWatchlistLoaded,
    required this.resolveScreenSize,
    required this.resolveVolume,
    required this.updateVolume,
    required this.readViewUiState,
    required this.updateViewUiState,
    required this.readGestureUiState,
    required this.updateGestureUiState,
    required this.isDisposed,
  });

  final RoomAndroidPlaybackBridgeFacade androidPlaybackBridge;
  final Future<void> Function() ensureFollowWatchlistLoaded;
  final Size Function() resolveScreenSize;
  final double Function() resolveVolume;
  final void Function(double value) updateVolume;
  final RoomViewUiState Function() readViewUiState;
  final void Function(RoomViewUiState Function(RoomViewUiState current))
      updateViewUiState;
  final RoomGestureUiState Function() readGestureUiState;
  final void Function(
    RoomGestureUiState Function(RoomGestureUiState current) updater,
  ) updateGestureUiState;
  final bool Function() isDisposed;
}

class RoomFullscreenChromeController {
  RoomFullscreenChromeController({
    required this.context,
    ScreenBrightness? screenBrightness,
  }) : _screenBrightness = screenBrightness ?? ScreenBrightness();

  final RoomFullscreenChromeContext context;
  final ScreenBrightness _screenBrightness;

  Timer? _fullscreenChromeTimer;
  Timer? _inlineChromeTimer;
  Timer? _gestureTipTimer;

  void dispose() {
    _fullscreenChromeTimer?.cancel();
    _inlineChromeTimer?.cancel();
    _gestureTipTimer?.cancel();
  }

  void cancelAutoHideTimers() {
    _fullscreenChromeTimer?.cancel();
    _inlineChromeTimer?.cancel();
  }

  void toggleFullscreenChrome() {
    final viewState = context.readViewUiState();
    if (viewState.showFullscreenFollowDrawer) {
      hideFullscreenFollowDrawer();
      return;
    }
    if (viewState.lockFullscreenControls) {
      if (!viewState.showFullscreenLockButton) {
        context.updateViewUiState(
          (current) => current.copyWith(showFullscreenLockButton: true),
        );
      }
      scheduleFullscreenChromeAutoHide();
      return;
    }
    final next = !viewState.showFullscreenChrome;
    context.updateViewUiState(
      (current) => current.copyWith(showFullscreenChrome: next),
    );
    if (next) {
      scheduleFullscreenChromeAutoHide();
    } else {
      _fullscreenChromeTimer?.cancel();
    }
  }

  void toggleFullscreenLock() {
    final nextLocked = !context.readViewUiState().lockFullscreenControls;
    context.updateViewUiState(
      (current) => current.copyWith(
        lockFullscreenControls: nextLocked,
        showFullscreenChrome: nextLocked ? false : true,
        showFullscreenLockButton: true,
        showFullscreenFollowDrawer:
            nextLocked ? false : current.showFullscreenFollowDrawer,
      ),
    );
    scheduleFullscreenChromeAutoHide();
  }

  void openFullscreenFollowDrawer() {
    final viewState = context.readViewUiState();
    if (viewState.showFullscreenFollowDrawer) {
      return;
    }
    _fullscreenChromeTimer?.cancel();
    context.updateViewUiState(
      (current) => current.copyWith(
        showFullscreenChrome: false,
        showFullscreenFollowDrawer: true,
      ),
    );
    unawaited(context.ensureFollowWatchlistLoaded());
  }

  void hideFullscreenFollowDrawer() {
    if (!context.readViewUiState().showFullscreenFollowDrawer) {
      return;
    }
    context.updateViewUiState(
      (current) => current.copyWith(showFullscreenFollowDrawer: false),
    );
  }

  void toggleInlinePlayerChrome() {
    final viewState = context.readViewUiState();
    if (viewState.isFullscreen) {
      return;
    }
    _inlineChromeTimer?.cancel();
    final next = !viewState.showInlinePlayerChrome;
    context.updateViewUiState(
      (current) => current.copyWith(showInlinePlayerChrome: next),
    );
    if (next) {
      scheduleInlineChromeAutoHide();
    }
  }

  void showInlinePlayerChromeTemporarily() {
    if (context.readViewUiState().isFullscreen) {
      return;
    }
    _inlineChromeTimer?.cancel();
    context.updateViewUiState(
      (current) => current.copyWith(showInlinePlayerChrome: true),
    );
    scheduleInlineChromeAutoHide();
  }

  void scheduleFullscreenChromeAutoHide() {
    _fullscreenChromeTimer?.cancel();
    final viewState = context.readViewUiState();
    final gestureState = context.readGestureUiState();
    if (!viewState.isFullscreen ||
        viewState.showFullscreenFollowDrawer ||
        viewState.enteringPictureInPicture ||
        gestureState.tipText != null) {
      return;
    }
    if (viewState.lockFullscreenControls) {
      if (!viewState.showFullscreenLockButton) {
        return;
      }
      _fullscreenChromeTimer = Timer(const Duration(seconds: 2), () {
        final currentViewState = context.readViewUiState();
        final currentGestureState = context.readGestureUiState();
        if (context.isDisposed() ||
            !currentViewState.isFullscreen ||
            !currentViewState.lockFullscreenControls ||
            !currentViewState.showFullscreenLockButton ||
            currentViewState.showFullscreenFollowDrawer ||
            currentViewState.enteringPictureInPicture ||
            currentGestureState.tipText != null) {
          return;
        }
        context.updateViewUiState(
          (current) => current.copyWith(showFullscreenLockButton: false),
        );
      });
      return;
    }
    _fullscreenChromeTimer = Timer(const Duration(seconds: 2), () {
      final currentViewState = context.readViewUiState();
      final currentGestureState = context.readGestureUiState();
      if (context.isDisposed() ||
          !currentViewState.isFullscreen ||
          currentViewState.lockFullscreenControls ||
          currentViewState.showFullscreenFollowDrawer ||
          currentViewState.enteringPictureInPicture ||
          currentGestureState.tipText != null) {
        return;
      }
      context.updateViewUiState(
        (current) => current.copyWith(showFullscreenChrome: false),
      );
    });
  }

  void scheduleInlineChromeAutoHide() {
    _inlineChromeTimer?.cancel();
    final viewState = context.readViewUiState();
    if (viewState.isFullscreen || !viewState.showInlinePlayerChrome) {
      return;
    }
    _inlineChromeTimer = Timer(const Duration(seconds: 2), () {
      final currentViewState = context.readViewUiState();
      if (context.isDisposed() ||
          currentViewState.isFullscreen ||
          !currentViewState.showInlinePlayerChrome) {
        return;
      }
      context.updateViewUiState(
        (current) => current.copyWith(showInlinePlayerChrome: false),
      );
    });
  }

  void showGestureTip(String text) {
    _gestureTipTimer?.cancel();
    _fullscreenChromeTimer?.cancel();
    context.updateGestureUiState(
      (current) => current.copyWith(tipText: text),
    );
    if (context.readViewUiState().isFullscreen) {
      context.updateViewUiState(
        (current) => current.copyWith(
          showFullscreenChrome: true,
          showFullscreenLockButton: true,
        ),
      );
    }
    _gestureTipTimer = Timer(const Duration(milliseconds: 900), () {
      if (context.isDisposed()) {
        return;
      }
      clearGestureTip(rescheduleChrome: true);
    });
  }

  void clearGestureTip({required bool rescheduleChrome}) {
    _gestureTipTimer?.cancel();
    _gestureTipTimer = null;
    if (context.readGestureUiState().tipText == null) {
      return;
    }
    context.updateGestureUiState(
      (current) => current.copyWith(clearTipText: true),
    );
    final viewState = context.readViewUiState();
    if (rescheduleChrome &&
        viewState.isFullscreen &&
        viewState.showFullscreenChrome) {
      scheduleFullscreenChromeAutoHide();
    }
  }

  Future<void> handleVerticalDragStart(DragStartDetails details) async {
    final viewState = context.readViewUiState();
    if (!context.androidPlaybackBridge.isSupported ||
        !viewState.isFullscreen ||
        viewState.lockFullscreenControls) {
      return;
    }
    final screenSize = context.resolveScreenSize();
    context.updateGestureUiState(
      (current) => current.copyWith(
        tracking: true,
        adjustingBrightness: details.globalPosition.dx < screenSize.width / 2,
        startY: details.globalPosition.dy,
      ),
    );
    final mediaVolume = await context.androidPlaybackBridge.getMediaVolume();
    context.updateGestureUiState(
      (current) => current.copyWith(
        startVolume: mediaVolume ?? context.resolveVolume(),
      ),
    );
    try {
      final brightness = await _screenBrightness.application;
      context.updateGestureUiState(
        (current) => current.copyWith(startBrightness: brightness),
      );
    } catch (_) {
      context.updateGestureUiState(
        (current) => current.copyWith(startBrightness: 0.5),
      );
    }
  }

  Future<void> handleVerticalDragUpdate(DragUpdateDetails details) async {
    final gestureState = context.readGestureUiState();
    final viewState = context.readViewUiState();
    if (!gestureState.tracking ||
        !context.androidPlaybackBridge.isSupported ||
        viewState.lockFullscreenControls) {
      return;
    }
    final height = context.resolveScreenSize().height * 0.55;
    final delta = (gestureState.startY - details.globalPosition.dy) / height;
    if (gestureState.adjustingBrightness) {
      final brightness = (gestureState.startBrightness + delta).clamp(0.0, 1.0);
      try {
        await _screenBrightness.setApplicationScreenBrightness(brightness);
      } catch (_) {}
      showGestureTip('亮度 ${(brightness * 100).round()}%');
      return;
    }
    final nextVolume = (gestureState.startVolume + delta).clamp(0.0, 1.0);
    await context.androidPlaybackBridge.setMediaVolume(nextVolume);
    context.updateVolume(nextVolume);
    showGestureTip('音量 ${(nextVolume * 100).round()}%');
  }

  Future<void> handleVerticalDragEnd() async {
    if (!context.readGestureUiState().tracking) {
      return;
    }
    context.updateGestureUiState(
      (current) => current.copyWith(tracking: false),
    );
    final viewState = context.readViewUiState();
    if (viewState.isFullscreen && viewState.showFullscreenChrome) {
      scheduleFullscreenChromeAutoHide();
    }
  }
}
