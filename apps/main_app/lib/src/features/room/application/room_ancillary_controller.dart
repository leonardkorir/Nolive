import 'package:flutter/foundation.dart';
import 'package:live_core/live_core.dart';

import 'load_room_use_case.dart';
import 'room_preview_dependencies.dart';

@immutable
class RoomAncillaryLoadResult {
  const RoomAncillaryLoadResult({
    required this.danmakuSession,
    required this.isFollowed,
  });

  final DanmakuSession? danmakuSession;
  final bool isFollowed;
}

class RoomAncillaryController {
  RoomAncillaryController({
    required this.dependencies,
    required this.providerId,
    this.trace,
  });

  final RoomAncillaryDependencies dependencies;
  final ProviderId providerId;
  final void Function(String message)? trace;

  Future<RoomAncillaryLoadResult> load({
    required LoadedRoomSnapshot snapshot,
    required bool fallbackIsFollowed,
  }) async {
    final startedAt = DateTime.now();
    _trace('ancillary start room=${snapshot.detail.roomId}');
    final danmakuFuture = dependencies.openRoomDanmaku(
      providerId: providerId,
      detail: snapshot.detail,
    );
    final followFuture = dependencies.isFollowedRoom(
      providerId: providerId.value,
      roomId: snapshot.detail.roomId,
    );

    DanmakuSession? danmakuSession;
    try {
      danmakuSession = await danmakuFuture;
    } catch (error) {
      _trace(
        'ancillary danmaku failed after '
        '${DateTime.now().difference(startedAt).inMilliseconds}ms: $error',
      );
    }

    var isFollowed = fallbackIsFollowed;
    try {
      isFollowed = await followFuture;
    } catch (error) {
      _trace(
        'ancillary follow failed after '
        '${DateTime.now().difference(startedAt).inMilliseconds}ms: $error',
      );
    }

    _trace(
      'ancillary complete in ${DateTime.now().difference(startedAt).inMilliseconds}ms '
      'danmaku=${danmakuSession != null} followed=$isFollowed',
    );
    return RoomAncillaryLoadResult(
      danmakuSession: danmakuSession,
      isFollowed: isFollowed,
    );
  }

  void _trace(String message) {
    trace?.call(message);
  }
}
