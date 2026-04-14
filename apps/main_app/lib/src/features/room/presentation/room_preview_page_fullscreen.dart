import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:live_core/live_core.dart';
import 'package:nolive_app/src/features/room/presentation/room_preview_page_danmaku.dart';
import 'package:nolive_app/src/features/room/presentation/room_preview_page_player_surface.dart';
import 'package:nolive_app/src/features/room/presentation/widgets/room_fullscreen_overlay.dart';
import 'package:nolive_app/src/features/settings/application/manage_danmaku_preferences_use_case.dart';

const Object _roomFullscreenOverlayViewDataNoChange = Object();

@immutable
class RoomFullscreenOverlayViewData {
  const RoomFullscreenOverlayViewData({
    required this.playerSurfaceData,
    required this.danmakuPreferences,
    required this.title,
    required this.liveDuration,
    required this.qualityLabel,
    required this.lineLabel,
    required this.showChrome,
    required this.showLockButton,
    required this.lockControls,
    required this.gestureTipText,
    required this.pipSupported,
    required this.supportsDesktopMiniWindow,
    required this.desktopMiniWindowActive,
    required this.supportsPlayerCapture,
    required this.showDanmakuOverlay,
  });

  final RoomPlayerSurfaceViewData playerSurfaceData;
  final DanmakuPreferences danmakuPreferences;
  final String title;
  final String liveDuration;
  final String qualityLabel;
  final String lineLabel;
  final bool showChrome;
  final bool showLockButton;
  final bool lockControls;
  final String? gestureTipText;
  final bool pipSupported;
  final bool supportsDesktopMiniWindow;
  final bool desktopMiniWindowActive;
  final bool supportsPlayerCapture;
  final bool showDanmakuOverlay;

  RoomFullscreenOverlayViewData copyWith({
    RoomPlayerSurfaceViewData? playerSurfaceData,
    DanmakuPreferences? danmakuPreferences,
    String? title,
    String? liveDuration,
    String? qualityLabel,
    String? lineLabel,
    bool? showChrome,
    bool? showLockButton,
    bool? lockControls,
    Object? gestureTipText = _roomFullscreenOverlayViewDataNoChange,
    bool? pipSupported,
    bool? supportsDesktopMiniWindow,
    bool? desktopMiniWindowActive,
    bool? supportsPlayerCapture,
    bool? showDanmakuOverlay,
  }) {
    return RoomFullscreenOverlayViewData(
      playerSurfaceData: playerSurfaceData ?? this.playerSurfaceData,
      danmakuPreferences: danmakuPreferences ?? this.danmakuPreferences,
      title: title ?? this.title,
      liveDuration: liveDuration ?? this.liveDuration,
      qualityLabel: qualityLabel ?? this.qualityLabel,
      lineLabel: lineLabel ?? this.lineLabel,
      showChrome: showChrome ?? this.showChrome,
      showLockButton: showLockButton ?? this.showLockButton,
      lockControls: lockControls ?? this.lockControls,
      gestureTipText: gestureTipText == _roomFullscreenOverlayViewDataNoChange
          ? this.gestureTipText
          : gestureTipText as String?,
      pipSupported: pipSupported ?? this.pipSupported,
      supportsDesktopMiniWindow:
          supportsDesktopMiniWindow ?? this.supportsDesktopMiniWindow,
      desktopMiniWindowActive:
          desktopMiniWindowActive ?? this.desktopMiniWindowActive,
      supportsPlayerCapture:
          supportsPlayerCapture ?? this.supportsPlayerCapture,
      showDanmakuOverlay: showDanmakuOverlay ?? this.showDanmakuOverlay,
    );
  }
}

class RoomFullscreenOverlaySection extends StatelessWidget {
  const RoomFullscreenOverlaySection({
    required this.data,
    required this.messagesListenable,
    required this.playerSuperChatMessagesListenable,
    required this.followDrawer,
    required this.buildEmbeddedPlayerView,
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

  final RoomFullscreenOverlayViewData data;
  final ValueListenable<List<LiveMessage>> messagesListenable;
  final ValueListenable<List<LiveMessage>> playerSuperChatMessagesListenable;
  final Widget followDrawer;
  final RoomEmbeddedPlayerViewBuilder buildEmbeddedPlayerView;
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
    final playerSurfaceData = data.playerSurfaceData.copyWith(
      showDanmakuOverlay: data.showDanmakuOverlay,
    );
    return RoomFullscreenOverlay(
      player: RoomPlayerSurfaceSection(
        data: playerSurfaceData,
        buildEmbeddedPlayerView: buildEmbeddedPlayerView,
        danmakuOverlay: _buildDanmakuOverlay(),
        playerSuperChatOverlay: RoomPlayerSuperChatOverlay(
          messagesListenable: playerSuperChatMessagesListenable,
          visible: playerSurfaceData.showPlayerSuperChat,
        ),
      ),
      followDrawer: followDrawer,
      showChrome: data.showChrome,
      showLockButton: data.showLockButton,
      lockControls: data.lockControls,
      gestureTipText: data.gestureTipText,
      pipSupported: data.pipSupported,
      supportsDesktopMiniWindow: data.supportsDesktopMiniWindow,
      desktopMiniWindowActive: data.desktopMiniWindowActive,
      supportsPlayerCapture: data.supportsPlayerCapture,
      showDanmakuOverlay: data.showDanmakuOverlay,
      title: data.title,
      liveDuration: data.liveDuration,
      qualityLabel: data.qualityLabel,
      lineLabel: data.lineLabel,
      onToggleChrome: onToggleChrome,
      onOpenFollowDrawer: onOpenFollowDrawer,
      onToggleFullscreen: onToggleFullscreen,
      onVerticalDragStart: onVerticalDragStart,
      onVerticalDragUpdate: onVerticalDragUpdate,
      onVerticalDragEnd: onVerticalDragEnd,
      onExitFullscreen: onExitFullscreen,
      onEnterPictureInPicture: onEnterPictureInPicture,
      onToggleDesktopMiniWindow: onToggleDesktopMiniWindow,
      onCapture: onCapture,
      onShowDebug: onShowDebug,
      onShowMore: onShowMore,
      onToggleFullscreenLock: onToggleFullscreenLock,
      onRefresh: onRefresh,
      onToggleDanmakuOverlay: onToggleDanmakuOverlay,
      onOpenDanmakuSettings: onOpenDanmakuSettings,
      onShowQuality: onShowQuality,
      onShowLine: onShowLine,
    );
  }

  Widget? _buildDanmakuOverlay() {
    if (!data.showDanmakuOverlay) {
      return null;
    }
    return ValueListenableBuilder<List<LiveMessage>>(
      valueListenable: messagesListenable,
      builder: (context, messages, _) {
        final overlayPool = messages
            .where((message) => message.type != LiveMessageType.online)
            .toList(growable: false);
        final overlayMessages = overlayPool.length <= 20
            ? overlayPool
            : overlayPool.sublist(overlayPool.length - 20);
        if (overlayMessages.isEmpty) {
          return const SizedBox.shrink();
        }
        return RoomDanmakuOverlay(
          messages: overlayMessages,
          fullscreen: true,
          preferences: data.danmakuPreferences,
        );
      },
    );
  }
}
