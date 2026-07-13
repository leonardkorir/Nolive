import 'package:flutter/foundation.dart';
import 'package:live_core/live_core.dart';
import 'package:nolive_app/src/features/room/application/room_ancillary_controller.dart';
import 'package:nolive_app/src/features/room/application/room_preview_dependencies.dart';
import 'package:nolive_app/src/features/room/application/room_session_controller.dart';
import 'package:nolive_app/src/features/room/presentation/room_danmaku_controller.dart';

/// Owns core room session / danmaku / ancillary façades.
///
/// Playback and fullscreen controllers still require page-bound callbacks
/// (mounted, MediaQuery, UI effects); they stay constructed by the page shell
/// but session load + danmaku open/filter ownership lives here.
class RoomPreviewRuntime {
  RoomPreviewRuntime({
    required this.dependencies,
    required this.providerId,
    required this.roomId,
    required this.targetPlatform,
    required this.isWeb,
    void Function(String message)? trace,
  }) : session = RoomSessionController(
         dependencies: RoomSessionDependencies.fromPreviewDependencies(
           dependencies,
         ),
         providerId: providerId,
         roomId: roomId,
         targetPlatform: targetPlatform,
         isWeb: isWeb,
         trace: trace,
       ),
       danmaku = RoomDanmakuController(
         dependencies: RoomDanmakuDependencies.fromPreviewDependencies(
           dependencies,
         ),
         providerId: providerId,
         trace: trace,
       ),
       ancillary = RoomAncillaryController(
         dependencies: RoomAncillaryDependencies.fromPreviewDependencies(
           dependencies,
         ),
         providerId: providerId,
         trace: trace,
       );

  final RoomPreviewDependencies dependencies;
  ProviderId providerId;
  String roomId;
  final TargetPlatform targetPlatform;
  final bool isWeb;

  final RoomSessionController session;
  final RoomDanmakuController danmaku;
  final RoomAncillaryController ancillary;

  void retargetRoom({
    required ProviderId providerId,
    required String roomId,
  }) {
    this.providerId = providerId;
    this.roomId = roomId;
    session.retargetRoom(providerId: providerId, roomId: roomId);
    danmaku.retargetRoom(providerId: providerId);
    ancillary.retargetRoom(providerId: providerId);
  }

  Future<void> dispose() async {
    await danmaku.dispose();
    session.clearCurrent();
  }
}
