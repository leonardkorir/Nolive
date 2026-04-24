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
  final resolved = playUrls
          .firstWhere(
            (item) => item.url == playbackSource.url.toString(),
            orElse: () => playUrls.first,
          )
          .lineLabel ??
      '线路';
  final normalized = normalizeDisplayText(resolved);
  return normalized.isEmpty ? '线路' : normalized;
}

String compactRoomQualityLabel(String label) {
  final normalized = normalizeDisplayText(label);
  if (normalized.contains('原画')) {
    return '原画';
  }
  if (normalized.contains('蓝光')) {
    return '蓝光';
  }
  if (normalized.contains('超清')) {
    return '超清';
  }
  if (normalized.contains('高清')) {
    return '高清';
  }
  if (normalized.contains('流畅') || normalized.contains('标清')) {
    return '流畅';
  }
  return normalized.length <= 4 ? normalized : normalized.substring(0, 4);
}

String compactRoomLineLabel(String label) {
  final normalized = normalizeDisplayText(label);
  if (normalized.startsWith('线路')) {
    return normalized;
  }
  return '线路';
}
