import 'package:flutter/foundation.dart';

@immutable
class RoomViewUiState {
  const RoomViewUiState({
    this.isFullscreen = false,
    this.fullscreenBootstrapPending = false,
    this.fullscreenBootstrapScheduled = false,
    this.desktopMiniWindowActive = false,
    this.showInlinePlayerChrome = true,
    this.showFullscreenChrome = true,
    this.showFullscreenLockButton = true,
    this.lockFullscreenControls = false,
    this.pipSupported = false,
    this.enteringPictureInPicture = false,
    this.pausedByLifecycle = false,
    this.restoreDanmakuAfterPip = false,
    this.danmakuVisibleBeforePip = true,
    this.fullscreenAutoApplied = false,
    this.showFullscreenFollowDrawer = false,
    this.inlineChromeBeforeLifecycle = true,
    this.fullscreenChromeBeforeLifecycle = true,
  });

  final bool isFullscreen;
  final bool fullscreenBootstrapPending;
  final bool fullscreenBootstrapScheduled;
  final bool desktopMiniWindowActive;
  final bool showInlinePlayerChrome;
  final bool showFullscreenChrome;
  final bool showFullscreenLockButton;
  final bool lockFullscreenControls;
  final bool pipSupported;
  final bool enteringPictureInPicture;
  final bool pausedByLifecycle;
  final bool restoreDanmakuAfterPip;
  final bool danmakuVisibleBeforePip;
  final bool fullscreenAutoApplied;
  final bool showFullscreenFollowDrawer;
  final bool inlineChromeBeforeLifecycle;
  final bool fullscreenChromeBeforeLifecycle;

  RoomViewUiState copyWith({
    bool? isFullscreen,
    bool? fullscreenBootstrapPending,
    bool? fullscreenBootstrapScheduled,
    bool? desktopMiniWindowActive,
    bool? showInlinePlayerChrome,
    bool? showFullscreenChrome,
    bool? showFullscreenLockButton,
    bool? lockFullscreenControls,
    bool? pipSupported,
    bool? enteringPictureInPicture,
    bool? pausedByLifecycle,
    bool? restoreDanmakuAfterPip,
    bool? danmakuVisibleBeforePip,
    bool? fullscreenAutoApplied,
    bool? showFullscreenFollowDrawer,
    bool? inlineChromeBeforeLifecycle,
    bool? fullscreenChromeBeforeLifecycle,
  }) {
    return RoomViewUiState(
      isFullscreen: isFullscreen ?? this.isFullscreen,
      fullscreenBootstrapPending:
          fullscreenBootstrapPending ?? this.fullscreenBootstrapPending,
      fullscreenBootstrapScheduled:
          fullscreenBootstrapScheduled ?? this.fullscreenBootstrapScheduled,
      desktopMiniWindowActive:
          desktopMiniWindowActive ?? this.desktopMiniWindowActive,
      showInlinePlayerChrome:
          showInlinePlayerChrome ?? this.showInlinePlayerChrome,
      showFullscreenChrome: showFullscreenChrome ?? this.showFullscreenChrome,
      showFullscreenLockButton:
          showFullscreenLockButton ?? this.showFullscreenLockButton,
      lockFullscreenControls:
          lockFullscreenControls ?? this.lockFullscreenControls,
      pipSupported: pipSupported ?? this.pipSupported,
      enteringPictureInPicture:
          enteringPictureInPicture ?? this.enteringPictureInPicture,
      pausedByLifecycle: pausedByLifecycle ?? this.pausedByLifecycle,
      restoreDanmakuAfterPip:
          restoreDanmakuAfterPip ?? this.restoreDanmakuAfterPip,
      danmakuVisibleBeforePip:
          danmakuVisibleBeforePip ?? this.danmakuVisibleBeforePip,
      fullscreenAutoApplied:
          fullscreenAutoApplied ?? this.fullscreenAutoApplied,
      showFullscreenFollowDrawer:
          showFullscreenFollowDrawer ?? this.showFullscreenFollowDrawer,
      inlineChromeBeforeLifecycle:
          inlineChromeBeforeLifecycle ?? this.inlineChromeBeforeLifecycle,
      fullscreenChromeBeforeLifecycle: fullscreenChromeBeforeLifecycle ??
          this.fullscreenChromeBeforeLifecycle,
    );
  }
}
