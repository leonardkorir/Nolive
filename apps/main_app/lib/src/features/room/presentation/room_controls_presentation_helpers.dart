import 'package:flutter/material.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:nolive_app/src/features/room/application/room_session_controller.dart';

typedef RoomWrapFlatTileScope = Widget Function({required Widget child});

Widget wrapRoomFlatTileScope({required Widget child}) {
  return ListTileTheme.merge(
    contentPadding: EdgeInsets.zero,
    minLeadingWidth: 24,
    minVerticalPadding: 0,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
    child: child,
  );
}

LivePlayQuality resolveRequestedQualityOfRoomState({
  required RoomSessionLoadResult state,
  required LivePlayQuality? selectedQuality,
}) {
  return selectedQuality ?? state.snapshot.selectedQuality;
}

LivePlayQuality resolveEffectiveQualityOfRoomState({
  required RoomSessionLoadResult state,
  required LivePlayQuality? selectedQuality,
  required LivePlayQuality? effectiveQuality,
}) {
  return effectiveQuality ??
      state.resolved?.effectiveQuality ??
      resolveRequestedQualityOfRoomState(
        state: state,
        selectedQuality: selectedQuality,
      );
}

String roomLineLabelOfPlayback(
  List<LivePlayUrl> playUrls,
  PlaybackSource playbackSource,
) {
  if (playUrls.isEmpty) {
    return '线路';
  }
  return playUrls
          .firstWhere(
            (item) => item.url == playbackSource.url.toString(),
            orElse: () => playUrls.first,
          )
          .lineLabel ??
      '线路';
}

String compactRoomQualityLabel(String label) {
  if (label.contains('原画')) {
    return '原画';
  }
  if (label.contains('蓝光')) {
    return '蓝光';
  }
  if (label.contains('超清')) {
    return '超清';
  }
  if (label.contains('高清')) {
    return '高清';
  }
  if (label.contains('流畅') || label.contains('标清')) {
    return '流畅';
  }
  return label.length <= 4 ? label : label.substring(0, 4);
}

String compactRoomLineLabel(String label) {
  if (label.startsWith('线路')) {
    return label;
  }
  return '线路';
}
