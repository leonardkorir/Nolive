import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:nolive_app/src/app/routing/app_routes.dart';
import 'package:nolive_app/src/features/library/application/load_follow_watchlist_use_case.dart';
import 'package:nolive_app/src/features/room/application/load_room_use_case.dart';
import 'package:nolive_app/src/features/room/application/room_session_controller.dart';
import 'package:nolive_app/src/features/room/presentation/room_controls_view_data.dart';
import 'package:nolive_app/src/features/settings/application/manage_player_preferences_use_case.dart';

typedef RoomPresentRoute = Future<void> Function(
  String routeName, {
  bool rootNavigator,
});
typedef RoomReplaceRoomRoute = Future<void> Function(RoomRouteArguments args);
typedef RoomPresentQuickActionsSheet = Future<void> Function({
  required RoomControlsViewData viewData,
  required Future<void> Function() onRefresh,
  required Future<void> Function() onShowQuality,
  required Future<void> Function() onShowLine,
  required Future<RoomControlsViewData> Function() onCycleScaleMode,
  required Future<void> Function() onEnterPictureInPicture,
  required Future<void> Function() onToggleDesktopMiniWindow,
  required Future<void> Function() onCaptureScreenshot,
  required Future<void> Function() onShowAutoCloseSheet,
  required Future<void> Function() onShowDebugPanel,
});
typedef RoomPresentQualitySheet = Future<void> Function({
  required LivePlayQuality selectedQuality,
  required List<LivePlayQuality> qualities,
  required Future<void> Function(LivePlayQuality quality) onSelected,
});
typedef RoomPresentLineSheet = Future<void> Function({
  required List<LivePlayUrl> playUrls,
  required PlaybackSource playbackSource,
  required Future<void> Function(LivePlayUrl playUrl) onSelected,
});
typedef RoomPresentAutoCloseSheet = Future<void> Function({
  required DateTime? scheduledCloseAt,
  required void Function(Duration? duration) onSelectDuration,
});
typedef RoomPresentPlayerDebugSheet = Future<void> Function({
  required RoomPlayerDebugViewData debugViewData,
});
typedef RoomResolveControlsViewData = RoomControlsViewData Function({
  required RoomSessionLoadResult state,
  required List<LivePlayUrl> playUrls,
  required PlaybackSource? playbackSource,
  required bool hasPlayback,
});
typedef RoomResolvePlayerDebugViewData = RoomPlayerDebugViewData Function({
  required RoomSessionLoadResult state,
  required PlaybackSource? playbackSource,
});
typedef RoomCycleScaleModeAndResolveControlsViewData =
    Future<RoomControlsViewData> Function({
  required RoomSessionLoadResult state,
  required List<LivePlayUrl> playUrls,
  required PlaybackSource? playbackSource,
  required bool hasPlayback,
});
typedef RoomPerformRefresh = Future<void> Function({
  bool showFeedback,
  bool reloadPlayer,
  bool forcePlaybackRebind,
});
typedef RoomOpenFollowRoomTransition = Future<void> Function(
  FollowWatchEntry entry, {
  required Future<void> Function(bool preserveFullscreen) commitNavigation,
  required void Function(String message) showMessage,
});

class RoomPageInteractionContext {
  const RoomPageInteractionContext({
    required this.isMounted,
    required this.exitFullscreenIfNeeded,
    required this.showMessage,
    required this.pushNamed,
    required this.pushReplacementToRoom,
    required this.popPage,
    required this.loadPlayerPreferences,
    required this.handlePlayerSettingsReturn,
    required this.handleDanmakuSettingsReturn,
    required this.resolveRoomFuture,
    required this.resolveIsLeavingRoom,
    required this.resolveCurrentPlaybackSource,
    required this.resolveCurrentPlayUrls,
    required this.resolveRequestedQuality,
    required this.resolveControlsViewData,
    required this.resolvePlayerDebugViewData,
    required this.cycleScaleModeAndResolveControlsViewData,
    required this.presentQuickActionsSheet,
    required this.presentQualitySheet,
    required this.presentLineSheet,
    required this.presentAutoCloseSheet,
    required this.presentPlayerDebugSheet,
    required this.enterPictureInPicture,
    required this.toggleDesktopMiniWindow,
    required this.captureScreenshot,
    required this.refreshRoom,
    required this.leaveRoomCleanup,
    required this.switchQuality,
    required this.switchLine,
    required this.resolveScheduledCloseAt,
    required this.setAutoCloseTimer,
    required this.openFollowRoomTransition,
  });

  final bool Function() isMounted;
  final Future<void> Function() exitFullscreenIfNeeded;
  final void Function(String message) showMessage;
  final RoomPresentRoute pushNamed;
  final RoomReplaceRoomRoute pushReplacementToRoom;
  final void Function() popPage;
  final Future<PlayerPreferences> Function() loadPlayerPreferences;
  final Future<void> Function(PlayerPreferences previousPreferences)
      handlePlayerSettingsReturn;
  final Future<void> Function() handleDanmakuSettingsReturn;
  final Future<RoomSessionLoadResult> Function() resolveRoomFuture;
  final bool Function() resolveIsLeavingRoom;
  final PlaybackSource? Function() resolveCurrentPlaybackSource;
  final List<LivePlayUrl> Function() resolveCurrentPlayUrls;
  final LivePlayQuality Function(RoomSessionLoadResult state)
      resolveRequestedQuality;
  final RoomResolveControlsViewData resolveControlsViewData;
  final RoomResolvePlayerDebugViewData resolvePlayerDebugViewData;
  final RoomCycleScaleModeAndResolveControlsViewData
      cycleScaleModeAndResolveControlsViewData;
  final RoomPresentQuickActionsSheet presentQuickActionsSheet;
  final RoomPresentQualitySheet presentQualitySheet;
  final RoomPresentLineSheet presentLineSheet;
  final RoomPresentAutoCloseSheet presentAutoCloseSheet;
  final RoomPresentPlayerDebugSheet presentPlayerDebugSheet;
  final Future<void> Function() enterPictureInPicture;
  final Future<void> Function() toggleDesktopMiniWindow;
  final Future<void> Function() captureScreenshot;
  final RoomPerformRefresh refreshRoom;
  final Future<void> Function() leaveRoomCleanup;
  final Future<void> Function(LoadedRoomSnapshot snapshot, LivePlayQuality quality)
      switchQuality;
  final Future<void> Function(LivePlayUrl playUrl) switchLine;
  final DateTime? Function() resolveScheduledCloseAt;
  final void Function(Duration? duration) setAutoCloseTimer;
  final RoomOpenFollowRoomTransition openFollowRoomTransition;
}

class RoomPageInteractionCoordinator {
  const RoomPageInteractionCoordinator({
    required this.context,
  });

  final RoomPageInteractionContext context;

  Future<void> openPlayerSettings() {
    return _openSettingsRoute(
      AppRoutes.playerSettings,
      onReturn: context.handlePlayerSettingsReturn,
    );
  }

  Future<void> openDanmakuSettings() {
    return _openAuxiliarySettingsRoute(
      AppRoutes.danmakuSettings,
      onReturn: context.handleDanmakuSettingsReturn,
    );
  }

  Future<void> openDanmakuShield() {
    return context.pushNamed(AppRoutes.danmakuShield);
  }

  Future<void> openFollowSettings() {
    return context.pushNamed(
      AppRoutes.followSettings,
      rootNavigator: true,
    );
  }

  Future<void> showPlayerDebugSheet(
    RoomSessionLoadResult state,
    PlaybackSource? playbackSource,
  ) {
    return context.presentPlayerDebugSheet(
      debugViewData: context.resolvePlayerDebugViewData(
        state: state,
        playbackSource: playbackSource,
      ),
    );
  }

  Future<void> showQuickActionsSheet() async {
    late final RoomSessionLoadResult state;
    try {
      state = await context.resolveRoomFuture();
    } catch (_) {
      if (!context.isMounted()) {
        return;
      }
      context.showMessage('房间尚未准备完成，请稍后再试');
      return;
    }
    if (!context.isMounted()) {
      return;
    }
    final resolvedPlaybackSource =
        context.resolveCurrentPlaybackSource() ?? state.resolved?.playbackSource;
    final currentPlayUrls = context.resolveCurrentPlayUrls();
    final resolvedPlayUrls =
        currentPlayUrls.isEmpty ? state.snapshot.playUrls : currentPlayUrls;
    final hasPlayback =
        resolvedPlaybackSource != null && resolvedPlayUrls.isNotEmpty;
    await context.presentQuickActionsSheet(
      viewData: context.resolveControlsViewData(
        state: state,
        playUrls: resolvedPlayUrls,
        playbackSource: resolvedPlaybackSource,
        hasPlayback: hasPlayback,
      ),
      onRefresh: () => refreshRoom(showFeedback: true),
      onShowQuality: () => showQualitySheet(state),
      onShowLine: () => showLineSheet(
        resolvedPlayUrls,
        resolvedPlaybackSource!,
      ),
      onCycleScaleMode: () => context.cycleScaleModeAndResolveControlsViewData(
        state: state,
        playUrls: resolvedPlayUrls,
        playbackSource: resolvedPlaybackSource,
        hasPlayback: hasPlayback,
      ),
      onEnterPictureInPicture: context.enterPictureInPicture,
      onToggleDesktopMiniWindow: context.toggleDesktopMiniWindow,
      onCaptureScreenshot: context.captureScreenshot,
      onShowAutoCloseSheet: showAutoCloseSheet,
      onShowDebugPanel: () => showPlayerDebugSheet(
        state,
        resolvedPlaybackSource,
      ),
    );
  }

  Future<void> showQualitySheet(RoomSessionLoadResult state) {
    return context.presentQualitySheet(
      selectedQuality: context.resolveRequestedQuality(state),
      qualities: state.snapshot.qualities,
      onSelected: (quality) => context.switchQuality(state.snapshot, quality),
    );
  }

  Future<void> showLineSheet(
    List<LivePlayUrl> playUrls,
    PlaybackSource playbackSource,
  ) {
    return context.presentLineSheet(
      playUrls: playUrls,
      playbackSource: playbackSource,
      onSelected: context.switchLine,
    );
  }

  Future<void> showAutoCloseSheet() {
    return context.presentAutoCloseSheet(
      scheduledCloseAt: context.resolveScheduledCloseAt(),
      onSelectDuration: context.setAutoCloseTimer,
    );
  }

  Future<void> refreshRoom({
    bool showFeedback = false,
    bool reloadPlayer = false,
    bool forcePlaybackRebind = true,
  }) async {
    try {
      await context.refreshRoom(
        showFeedback: showFeedback,
        reloadPlayer: reloadPlayer,
        forcePlaybackRebind: forcePlaybackRebind,
      );
      if (!showFeedback || !context.isMounted()) {
        return;
      }
      context.showMessage('房间信息已刷新');
    } catch (_) {
      if (!showFeedback || !context.isMounted()) {
        return;
      }
      context.showMessage('房间刷新失败，请稍后重试');
    }
  }

  Future<void> leaveRoom({
    bool exitFullscreenFirst = true,
  }) async {
    if (context.resolveIsLeavingRoom()) {
      return;
    }
    if (exitFullscreenFirst) {
      await context.exitFullscreenIfNeeded();
      if (!context.isMounted()) {
        return;
      }
    }
    await context.leaveRoomCleanup();
    if (!context.isMounted()) {
      return;
    }
    context.popPage();
  }

  Future<void> commitFollowRoomNavigation(FollowWatchEntry entry) {
    return context.openFollowRoomTransition(
      entry,
      commitNavigation: (preserveFullscreen) {
        return context.pushReplacementToRoom(
          RoomRouteArguments(
            providerId: ProviderId(entry.record.providerId),
            roomId: entry.roomId,
            startInFullscreen: preserveFullscreen,
          ),
        );
      },
      showMessage: context.showMessage,
    );
  }

  Future<void> _openSettingsRoute(
    String routeName, {
    required Future<void> Function(PlayerPreferences previousPreferences)
        onReturn,
  }) async {
    final previousPreferences = await context.loadPlayerPreferences();
    if (!context.isMounted()) {
      return;
    }
    await context.exitFullscreenIfNeeded();
    if (!context.isMounted()) {
      return;
    }
    await context.pushNamed(routeName);
    if (!context.isMounted()) {
      return;
    }
    await onReturn(previousPreferences);
  }

  Future<void> _openAuxiliarySettingsRoute(
    String routeName, {
    required Future<void> Function() onReturn,
  }) async {
    await context.exitFullscreenIfNeeded();
    if (!context.isMounted()) {
      return;
    }
    await context.pushNamed(routeName);
    if (!context.isMounted()) {
      return;
    }
    await onReturn();
  }
}
