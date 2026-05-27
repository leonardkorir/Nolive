import 'dart:async';

import 'package:flutter/material.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:nolive_app/src/app/routing/app_routes.dart';
import 'package:nolive_app/src/features/room/presentation/room_controls_presentation_helpers.dart';
import 'package:nolive_app/src/features/room/presentation/room_controls_view_data.dart';
import 'package:nolive_app/src/features/room/presentation/room_preview_page_controls_actions.dart';

class RoomPageUiEffects {
  const RoomPageUiEffects({
    required this.context,
    required this.isMounted,
    required this.wrapFlatTileScope,
  });

  final BuildContext context;
  final bool Function() isMounted;
  final RoomWrapFlatTileScope wrapFlatTileScope;

  void showMessage(String message) {
    if (!isMounted()) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> pushNamed(
    String routeName, {
    bool rootNavigator = false,
  }) async {
    if (!isMounted()) {
      return;
    }
    await Navigator.of(context, rootNavigator: rootNavigator).pushNamed(
      routeName,
    );
  }

  Future<void> pushReplacementToRoom(RoomRouteArguments args) async {
    if (!isMounted()) {
      return;
    }
    await Navigator.of(context).pushReplacementNamed(
      AppRoutes.room,
      arguments: args,
    );
  }

  void popPage() {
    if (!isMounted()) {
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> presentPlayerDebugSheet({
    required RoomPlayerDebugViewData debugViewData,
    required Stream<PlayerDiagnostics> diagnosticsStream,
    required PlayerDiagnostics initialDiagnostics,
  }) {
    if (!isMounted()) {
      return Future<void>.value();
    }
    return showRoomPlayerDebugSheet(
      context: context,
      wrapFlatTileScope: wrapFlatTileScope,
      debugViewData: debugViewData,
      diagnosticsStream: diagnosticsStream,
      initialDiagnostics: initialDiagnostics,
    );
  }

  Future<void> presentQuickActionsSheet({
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
  }) {
    if (!isMounted()) {
      return Future<void>.value();
    }
    return showRoomQuickActionsSheet(
      context: context,
      wrapFlatTileScope: wrapFlatTileScope,
      viewData: viewData,
      onRefresh: onRefresh,
      onShowQuality: onShowQuality,
      onShowLine: onShowLine,
      onCycleScaleMode: onCycleScaleMode,
      onEnterPictureInPicture: onEnterPictureInPicture,
      onToggleDesktopMiniWindow: onToggleDesktopMiniWindow,
      onCaptureScreenshot: onCaptureScreenshot,
      onShowAutoCloseSheet: onShowAutoCloseSheet,
      onShowDebugPanel: onShowDebugPanel,
    );
  }

  Future<void> presentQualitySheet({
    required LivePlayQuality selectedQuality,
    required List<LivePlayQuality> qualities,
    required Future<void> Function(LivePlayQuality quality) onSelected,
  }) {
    if (!isMounted()) {
      return Future<void>.value();
    }
    return showRoomQualitySheet(
      context: context,
      wrapFlatTileScope: wrapFlatTileScope,
      selectedQuality: selectedQuality,
      qualities: qualities,
      onSelected: onSelected,
    );
  }

  Future<void> presentLineSheet({
    required List<LivePlayUrl> playUrls,
    required PlaybackSource playbackSource,
    required Future<void> Function(LivePlayUrl playUrl) onSelected,
  }) {
    if (!isMounted()) {
      return Future<void>.value();
    }
    return showRoomLineSheet(
      context: context,
      wrapFlatTileScope: wrapFlatTileScope,
      playbackSource: playbackSource,
      playUrls: playUrls,
      onSelected: onSelected,
    );
  }

  Future<void> presentAutoCloseSheet({
    required DateTime? scheduledCloseAt,
    required void Function(Duration? duration) onSelectDuration,
  }) {
    if (!isMounted()) {
      return Future<void>.value();
    }
    return showRoomAutoCloseSheet(
      context: context,
      wrapFlatTileScope: wrapFlatTileScope,
      scheduledCloseAt: scheduledCloseAt,
      onSelectDuration: onSelectDuration,
    );
  }
}
