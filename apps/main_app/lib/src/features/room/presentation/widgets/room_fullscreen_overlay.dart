import 'package:flutter/material.dart';

class RoomFullscreenOverlay extends StatelessWidget {
  const RoomFullscreenOverlay({
    required this.player,
    required this.followDrawer,
    required this.showChrome,
    required this.showLockButton,
    required this.lockControls,
    required this.gestureTipText,
    required this.pipSupported,
    required this.supportsDesktopMiniWindow,
    required this.desktopMiniWindowActive,
    required this.supportsPlayerCapture,
    required this.showDanmakuOverlay,
    required this.title,
    required this.liveDuration,
    required this.qualityLabel,
    required this.lineLabel,
    required this.onToggleChrome,
    required this.onOpenFollowDrawer,
    required this.onToggleFullscreen,
    required this.onVerticalDragStart,
    required this.onVerticalDragUpdate,
    required this.onVerticalDragEnd,
    required this.onExitFullscreen,
    required this.onEnterPictureInPicture,
    required this.onToggleDesktopMiniWindow,
    required this.onCapture,
    required this.onShowDebug,
    required this.onShowMore,
    required this.onToggleFullscreenLock,
    required this.onRefresh,
    required this.onToggleDanmakuOverlay,
    required this.onOpenDanmakuSettings,
    required this.onShowQuality,
    required this.onShowLine,
    super.key,
  });

  final Widget player;
  final Widget followDrawer;
  final bool showChrome;
  final bool showLockButton;
  final bool lockControls;
  final String? gestureTipText;
  final bool pipSupported;
  final bool supportsDesktopMiniWindow;
  final bool desktopMiniWindowActive;
  final bool supportsPlayerCapture;
  final bool showDanmakuOverlay;
  final String title;
  final String liveDuration;
  final String qualityLabel;
  final String lineLabel;
  final VoidCallback onToggleChrome;
  final VoidCallback onOpenFollowDrawer;
  final VoidCallback onToggleFullscreen;
  final GestureDragStartCallback onVerticalDragStart;
  final GestureDragUpdateCallback onVerticalDragUpdate;
  final GestureDragEndCallback onVerticalDragEnd;
  final VoidCallback onExitFullscreen;
  final VoidCallback onEnterPictureInPicture;
  final VoidCallback onToggleDesktopMiniWindow;
  final VoidCallback onCapture;
  final VoidCallback onShowDebug;
  final VoidCallback onShowMore;
  final VoidCallback onToggleFullscreenLock;
  final VoidCallback onRefresh;
  final VoidCallback onToggleDanmakuOverlay;
  final VoidCallback onOpenDanmakuSettings;
  final VoidCallback onShowQuality;
  final VoidCallback onShowLine;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      key: const Key('room-fullscreen-overlay'),
      color: Colors.black,
      child: Stack(
        children: [
          Positioned.fill(
            child: RoomFullscreenGestureLayer(
              lockControls: lockControls,
              onToggleChrome: onToggleChrome,
              onOpenFollowDrawer: onOpenFollowDrawer,
              onToggleFullscreen: onToggleFullscreen,
              onVerticalDragStart: onVerticalDragStart,
              onVerticalDragUpdate: onVerticalDragUpdate,
              onVerticalDragEnd: onVerticalDragEnd,
              child: player,
            ),
          ),
          if (gestureTipText != null)
            Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  child: Text(
                    gestureTipText!,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ),
            ),
          followDrawer,
          if (showChrome || (lockControls && showLockButton))
            Positioned(
              left: 8,
              top: MediaQuery.sizeOf(context).height * 0.42,
              child: IconButton(
                key: const Key('room-fullscreen-lock-button'),
                onPressed: onToggleFullscreenLock,
                color: Colors.white,
                icon: Icon(
                  lockControls
                      ? Icons.lock_outline_rounded
                      : Icons.lock_open_outlined,
                ),
              ),
            ),
          if (showChrome) ...[
            RoomFullscreenTopChrome(
              title: title,
              pipSupported: pipSupported,
              supportsDesktopMiniWindow: supportsDesktopMiniWindow,
              desktopMiniWindowActive: desktopMiniWindowActive,
              supportsPlayerCapture: supportsPlayerCapture,
              onExitFullscreen: onExitFullscreen,
              onEnterPictureInPicture: onEnterPictureInPicture,
              onToggleDesktopMiniWindow: onToggleDesktopMiniWindow,
              onCapture: onCapture,
              onShowDebug: onShowDebug,
              onShowMore: onShowMore,
            ),
            RoomFullscreenBottomChrome(
              showDanmakuOverlay: showDanmakuOverlay,
              liveDuration: liveDuration,
              qualityLabel: qualityLabel,
              lineLabel: lineLabel,
              onRefresh: onRefresh,
              onToggleDanmakuOverlay: onToggleDanmakuOverlay,
              onOpenDanmakuSettings: onOpenDanmakuSettings,
              onShowQuality: onShowQuality,
              onShowLine: onShowLine,
              onExitFullscreen: onExitFullscreen,
            ),
          ],
        ],
      ),
    );
  }
}

class RoomFullscreenGestureLayer extends StatelessWidget {
  const RoomFullscreenGestureLayer({
    required this.lockControls,
    required this.onToggleChrome,
    required this.onOpenFollowDrawer,
    required this.onToggleFullscreen,
    required this.onVerticalDragStart,
    required this.onVerticalDragUpdate,
    required this.onVerticalDragEnd,
    required this.child,
    super.key,
  });

  final bool lockControls;
  final VoidCallback onToggleChrome;
  final VoidCallback onOpenFollowDrawer;
  final VoidCallback onToggleFullscreen;
  final GestureDragStartCallback onVerticalDragStart;
  final GestureDragUpdateCallback onVerticalDragUpdate;
  final GestureDragEndCallback onVerticalDragEnd;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onToggleChrome,
      onLongPressStart: lockControls
          ? null
          : (details) {
              final width = MediaQuery.sizeOf(context).width;
              if (details.globalPosition.dx < width * 0.68) {
                return;
              }
              onOpenFollowDrawer();
            },
      onDoubleTap: lockControls ? null : onToggleFullscreen,
      onVerticalDragStart: onVerticalDragStart,
      onVerticalDragUpdate: onVerticalDragUpdate,
      onVerticalDragEnd: onVerticalDragEnd,
      child: child,
    );
  }
}

class RoomFullscreenTopChrome extends StatelessWidget {
  const RoomFullscreenTopChrome({
    required this.title,
    required this.pipSupported,
    required this.supportsDesktopMiniWindow,
    required this.desktopMiniWindowActive,
    required this.supportsPlayerCapture,
    required this.onExitFullscreen,
    required this.onEnterPictureInPicture,
    required this.onToggleDesktopMiniWindow,
    required this.onCapture,
    required this.onShowDebug,
    required this.onShowMore,
    super.key,
  });

  final String title;
  final bool pipSupported;
  final bool supportsDesktopMiniWindow;
  final bool desktopMiniWindowActive;
  final bool supportsPlayerCapture;
  final VoidCallback onExitFullscreen;
  final VoidCallback onEnterPictureInPicture;
  final VoidCallback onToggleDesktopMiniWindow;
  final VoidCallback onCapture;
  final VoidCallback onShowDebug;
  final VoidCallback onShowMore;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      child: Container(
        padding: EdgeInsets.fromLTRB(
          10,
          MediaQuery.paddingOf(context).top + 6,
          10,
          8,
        ),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black87, Colors.transparent],
          ),
        ),
        child: Row(
          children: [
            _FullscreenChromeIconButton(
              key: const Key('room-exit-fullscreen-button'),
              onPressed: onExitFullscreen,
              icon: const Icon(Icons.arrow_back),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            if (pipSupported)
              _FullscreenChromeIconButton(
                key: const Key('room-fullscreen-pip-button'),
                onPressed: onEnterPictureInPicture,
                icon: const Icon(Icons.picture_in_picture_alt_outlined),
              ),
            if (supportsDesktopMiniWindow)
              _FullscreenChromeIconButton(
                key: const Key('room-fullscreen-desktop-mini-window-button'),
                onPressed: onToggleDesktopMiniWindow,
                icon: Icon(
                  desktopMiniWindowActive
                      ? Icons.close_fullscreen_rounded
                      : Icons.open_in_new_rounded,
                ),
              ),
            if (supportsPlayerCapture)
              _FullscreenChromeIconButton(
                key: const Key('room-fullscreen-capture-button'),
                onPressed: onCapture,
                icon: const Icon(Icons.camera_alt_outlined),
              ),
            _FullscreenChromeIconButton(
              key: const Key('room-fullscreen-debug-button'),
              onPressed: onShowDebug,
              icon: const Icon(Icons.bug_report_outlined),
            ),
            _FullscreenChromeIconButton(
              key: const Key('room-fullscreen-more-button'),
              onPressed: onShowMore,
              icon: const Icon(Icons.more_horiz_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class RoomFullscreenBottomChrome extends StatelessWidget {
  const RoomFullscreenBottomChrome({
    required this.showDanmakuOverlay,
    required this.liveDuration,
    required this.qualityLabel,
    required this.lineLabel,
    required this.onRefresh,
    required this.onToggleDanmakuOverlay,
    required this.onOpenDanmakuSettings,
    required this.onShowQuality,
    required this.onShowLine,
    required this.onExitFullscreen,
    super.key,
  });

  final bool showDanmakuOverlay;
  final String liveDuration;
  final String qualityLabel;
  final String lineLabel;
  final VoidCallback onRefresh;
  final VoidCallback onToggleDanmakuOverlay;
  final VoidCallback onOpenDanmakuSettings;
  final VoidCallback onShowQuality;
  final VoidCallback onShowLine;
  final VoidCallback onExitFullscreen;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: EdgeInsets.fromLTRB(
          14,
          18,
          14,
          MediaQuery.paddingOf(context).bottom + 12,
        ),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black87],
          ),
        ),
        child: Row(
          children: [
            _FullscreenChromeIconButton(
              key: const Key('room-fullscreen-refresh-button'),
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh),
            ),
            _FullscreenChromeIconButton(
              key: const Key('room-fullscreen-danmaku-toggle-button'),
              onPressed: onToggleDanmakuOverlay,
              icon: Icon(
                showDanmakuOverlay
                    ? Icons.subtitles_outlined
                    : Icons.subtitles_off_outlined,
              ),
            ),
            _FullscreenChromeIconButton(
              key: const Key('room-fullscreen-danmaku-settings-button'),
              onPressed: onOpenDanmakuSettings,
              icon: const Icon(Icons.tune_rounded),
            ),
            Expanded(
              child: Center(
                child: Text(
                  liveDuration,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ),
            _FullscreenChromeLabelButton(
              key: const Key('room-fullscreen-quality-button'),
              onPressed: onShowQuality,
              label: qualityLabel,
            ),
            _FullscreenChromeLabelButton(
              key: const Key('room-fullscreen-line-button'),
              onPressed: onShowLine,
              label: lineLabel,
            ),
            _FullscreenChromeIconButton(
              key: const Key('room-fullscreen-exit-button'),
              onPressed: onExitFullscreen,
              icon: const Icon(Icons.fullscreen_exit),
            ),
          ],
        ),
      ),
    );
  }
}

class _FullscreenChromeIconButton extends StatelessWidget {
  const _FullscreenChromeIconButton({
    required this.icon,
    required this.onPressed,
    super.key,
  });

  final Widget icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      color: Colors.white,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 40, height: 40),
      iconSize: 22,
      splashRadius: 20,
      icon: icon,
    );
  }
}

class _FullscreenChromeLabelButton extends StatelessWidget {
  const _FullscreenChromeLabelButton({
    required this.label,
    required this.onPressed,
    super.key,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        minimumSize: const Size(0, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 72),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          softWrap: false,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
