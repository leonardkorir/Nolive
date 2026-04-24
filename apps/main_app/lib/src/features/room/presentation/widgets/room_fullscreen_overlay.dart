import 'package:flutter/material.dart';
import 'package:live_core/live_core.dart';

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
    final normalizedGestureTip = normalizeDisplayText(gestureTipText);
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
          if (normalizedGestureTip.isNotEmpty)
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
                    normalizedGestureTip,
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
    final normalizedTitle = normalizeDisplayText(title);
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewportHeight = MediaQuery.sizeOf(context).height;
          final compactLandscape = viewportHeight < 420;
          final compact = constraints.maxWidth < 720;
          final dense = constraints.maxWidth < 600 || viewportHeight < 320;
          final narrow = constraints.maxWidth < 520 || viewportHeight < 300;
          final visibleSecondaryActionCount =
              (pipSupported && !narrow ? 1 : 0) +
                  (supportsDesktopMiniWindow && !narrow ? 1 : 0) +
                  (supportsPlayerCapture && !narrow ? 1 : 0) +
                  (!narrow ? 1 : 0);
          final stackedActions = constraints.maxWidth < 700 ||
              viewportHeight < 300 ||
              (constraints.maxWidth < 820 &&
                  normalizedTitle.length > 18 &&
                  visibleSecondaryActionCount >= 3);
          final ultraCompact = constraints.maxWidth < 420 ||
              viewportHeight < 300 ||
              compactLandscape;
          final baseButtonExtent = ultraCompact
              ? 32.0
              : compact
                  ? 36.0
                  : 40.0;
          final buttonExtent = stackedActions
              ? (baseButtonExtent -
                      (dense
                          ? 8.0
                          : compactLandscape
                              ? 6.0
                              : 2.0))
                  .clamp(26.0, 40.0)
                  .toDouble()
              : baseButtonExtent;
          final iconSize = ultraCompact
              ? 20.0
              : compact
                  ? 22.0
                  : 24.0;
          final titleFontSize = stackedActions
              ? ultraCompact
                  ? 15.0
                  : dense
                      ? 16.0
                      : 17.0
              : compact
                  ? 16.0
                  : ultraCompact
                      ? 15.0
                      : 18.0;
          final horizontalPadding = compactLandscape
              ? 6.0
              : compact
                  ? 8.0
                  : 10.0;
          final bottomPadding = compactLandscape
              ? 4.0
              : compact
                  ? 6.0
                  : 8.0;
          final secondaryActions = <Widget>[
            if (pipSupported && !narrow)
              _FullscreenChromeIconButton(
                key: const Key('room-fullscreen-pip-button'),
                onPressed: onEnterPictureInPicture,
                extent: buttonExtent,
                iconSize: iconSize,
                icon: const Icon(Icons.picture_in_picture_alt_outlined),
              ),
            if (supportsDesktopMiniWindow && !narrow)
              _FullscreenChromeIconButton(
                key: const Key('room-fullscreen-desktop-mini-window-button'),
                onPressed: onToggleDesktopMiniWindow,
                extent: buttonExtent,
                iconSize: iconSize,
                icon: Icon(
                  desktopMiniWindowActive
                      ? Icons.close_fullscreen_rounded
                      : Icons.open_in_new_rounded,
                ),
              ),
            if (supportsPlayerCapture && !narrow)
              _FullscreenChromeIconButton(
                key: const Key('room-fullscreen-capture-button'),
                onPressed: onCapture,
                extent: buttonExtent,
                iconSize: iconSize,
                icon: const Icon(Icons.camera_alt_outlined),
              ),
            if (!narrow)
              _FullscreenChromeIconButton(
                key: const Key('room-fullscreen-debug-button'),
                onPressed: onShowDebug,
                extent: buttonExtent,
                iconSize: iconSize,
                icon: const Icon(Icons.bug_report_outlined),
              ),
          ];
          return Container(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              MediaQuery.paddingOf(context).top + (compactLandscape ? 4 : 6),
              horizontalPadding,
              bottomPadding,
            ),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black87, Colors.transparent],
              ),
            ),
            child: stackedActions
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          _FullscreenChromeIconButton(
                            key: const Key('room-exit-fullscreen-button'),
                            onPressed: onExitFullscreen,
                            extent: buttonExtent,
                            iconSize: iconSize,
                            icon: const Icon(Icons.arrow_back),
                          ),
                          SizedBox(width: compact ? 2 : 4),
                          Expanded(
                            child: Text(
                              normalizedTitle,
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    fontSize: titleFontSize,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ),
                          _FullscreenChromeIconButton(
                            key: const Key('room-fullscreen-more-button'),
                            onPressed: onShowMore,
                            extent: buttonExtent,
                            iconSize: iconSize,
                            icon: const Icon(Icons.more_horiz_rounded),
                          ),
                        ],
                      ),
                      if (secondaryActions.isNotEmpty) ...[
                        SizedBox(height: dense ? 2 : 4),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Wrap(
                            spacing: 0,
                            runSpacing: 0,
                            alignment: WrapAlignment.end,
                            children: secondaryActions,
                          ),
                        ),
                      ],
                    ],
                  )
                : Row(
                    children: [
                      _FullscreenChromeIconButton(
                        key: const Key('room-exit-fullscreen-button'),
                        onPressed: onExitFullscreen,
                        extent: buttonExtent,
                        iconSize: iconSize,
                        icon: const Icon(Icons.arrow_back),
                      ),
                      SizedBox(width: compact ? 2 : 4),
                      Expanded(
                        child: Text(
                          normalizedTitle,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontSize: titleFontSize,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                      ),
                      ...secondaryActions,
                      _FullscreenChromeIconButton(
                        key: const Key('room-fullscreen-more-button'),
                        onPressed: onShowMore,
                        extent: buttonExtent,
                        iconSize: iconSize,
                        icon: const Icon(Icons.more_horiz_rounded),
                      ),
                    ],
                  ),
          );
        },
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
    final normalizedLiveDuration = normalizeDisplayText(liveDuration);
    final normalizedQualityLabel = normalizeDisplayText(qualityLabel);
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewportHeight = MediaQuery.sizeOf(context).height;
          final veryShort = viewportHeight < 300;
          final compact = constraints.maxWidth < 720;
          final dense = constraints.maxWidth < 640 || veryShort;
          final ultraCompact = constraints.maxWidth < 520 || veryShort;
          final baseButtonExtent = veryShort
              ? 30.0
              : dense
                  ? 36.0
                  : compact
                      ? 38.0
                      : 42.0;
          final buttonExtent = baseButtonExtent;
          final iconSize = veryShort
              ? 17.0
              : dense
                  ? ultraCompact
                      ? 19.0
                      : 21.0
                  : compact
                      ? 22.0
                      : 24.0;
          final baseLabelMaxWidth = dense
              ? ultraCompact
                  ? 46.0
                  : 52.0
              : compact
                  ? 60.0
                  : 72.0;
          final labelMaxWidth = baseLabelMaxWidth + (dense ? 4.0 : 10.0);
          final exitButtonWidth = buttonExtent;
          final labelFontSize = veryShort
              ? 12.0
              : dense
                  ? 13.0
                  : 14.0;
          final bottomInset = MediaQuery.paddingOf(context).bottom;
          final horizontalPadding = dense ? 10.0 : 14.0;
          final topPadding = 0.0;
          final maxChromeHeight = (viewportHeight * (veryShort ? 0.28 : 0.16))
              .clamp(42.0, 72.0)
              .toDouble();
          final chrome = Row(
            children: [
              _FullscreenChromeIconButton(
                key: const Key('room-fullscreen-refresh-button'),
                onPressed: onRefresh,
                extent: buttonExtent,
                iconSize: iconSize,
                icon: const Icon(Icons.refresh),
              ),
              _FullscreenChromeIconButton(
                key: const Key('room-fullscreen-danmaku-toggle-button'),
                onPressed: onToggleDanmakuOverlay,
                extent: buttonExtent,
                iconSize: iconSize,
                icon: Icon(
                  showDanmakuOverlay
                      ? Icons.subtitles_outlined
                      : Icons.subtitles_off_outlined,
                ),
              ),
              _FullscreenChromeIconButton(
                key: const Key('room-fullscreen-danmaku-settings-button'),
                onPressed: onOpenDanmakuSettings,
                extent: buttonExtent,
                iconSize: iconSize,
                icon: const Icon(Icons.tune_rounded),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    normalizedLiveDuration,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontSize: veryShort ? 13.0 : 15.0,
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ),
              _FullscreenChromeLabelButton(
                key: const Key('room-fullscreen-quality-button'),
                onPressed: onShowQuality,
                label: normalizedQualityLabel.isEmpty
                    ? '清晰度'
                    : normalizedQualityLabel,
                maxWidth: labelMaxWidth,
                fontSize: labelFontSize,
                horizontalPadding: dense ? 4 : 6,
              ),
              _FullscreenChromeLabelButton(
                key: const Key('room-fullscreen-line-button'),
                onPressed: onShowLine,
                label: '线路',
                maxWidth: labelMaxWidth,
                fontSize: labelFontSize,
                horizontalPadding: dense ? 4 : 6,
              ),
              _FullscreenChromeIconButton(
                key: const Key('room-fullscreen-exit-button'),
                onPressed: onExitFullscreen,
                extent: exitButtonWidth,
                iconSize: iconSize,
                icon: const Icon(Icons.fullscreen_exit),
              ),
            ],
          );
          return Container(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              topPadding,
              horizontalPadding,
              bottomInset,
            ),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black87],
              ),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxChromeHeight),
              child: chrome,
            ),
          );
        },
      ),
    );
  }
}

class _FullscreenChromeIconButton extends StatelessWidget {
  const _FullscreenChromeIconButton({
    required this.icon,
    required this.onPressed,
    this.extent = 40,
    this.iconSize = 22,
    super.key,
  });

  final Widget icon;
  final VoidCallback onPressed;
  final double extent;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      color: Colors.white,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints.tightFor(width: extent, height: extent),
      iconSize: iconSize,
      splashRadius: 20,
      icon: icon,
    );
  }
}

class _FullscreenChromeLabelButton extends StatelessWidget {
  const _FullscreenChromeLabelButton({
    required this.label,
    required this.onPressed,
    this.maxWidth = 72,
    this.fontSize = 13,
    this.horizontalPadding = 4,
    super.key,
  });

  final String label;
  final VoidCallback onPressed;
  final double maxWidth;
  final double fontSize;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
        minimumSize: Size(0, fontSize + 12),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          softWrap: false,
          style: TextStyle(
            color: Colors.white,
            fontSize: fontSize,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
