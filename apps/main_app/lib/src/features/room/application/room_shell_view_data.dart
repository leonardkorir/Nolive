import 'package:live_core/live_core.dart';
import 'package:nolive_app/src/features/room/application/room_session_controller.dart';

/// Text the room shell and header show, derived from a loaded room.
///
/// These mappings used to be private methods on `_RoomPreviewPageState`, so the
/// user-visible rules they encode — viewer-count abbreviation, the avatar
/// initial, the room-id title fallback, the requested-vs-actual quality badge —
/// could only be checked by mounting the page.

/// Provider display name, falling back to the raw provider id.
String roomProviderLabel({
  required String? descriptorDisplayName,
  required ProviderId providerId,
}) {
  final label = normalizeDisplayText(descriptorDisplayName ?? providerId.value);
  return label;
}

/// Single uppercase initial for the shell avatar, or `?` when nothing is known.
String roomAvatarLabel({
  required String streamerName,
  required String providerLabel,
}) {
  final source = streamerName.isEmpty ? providerLabel : streamerName;
  if (source.isEmpty) {
    return '?';
  }
  return source.substring(0, 1).toUpperCase();
}

/// Room title for the loading shell, falling back to `房间号 <id>`.
String roomShellTitle({required String? roomTitle, required String roomId}) {
  final normalized = normalizeDisplayText(roomTitle);
  return normalized.isEmpty ? '房间号 $roomId' : normalized;
}

/// Viewer count as shown in the header: `-` when unknown, `万` above 10,000.
///
/// One decimal between 10,000 and 99,999, none from 100,000 up.
String roomViewerLabel(int? viewerCount) {
  if (viewerCount == null) {
    return '-';
  }
  if (viewerCount < 10000) {
    return '$viewerCount';
  }
  final scaled = viewerCount / 10000;
  return '${scaled.toStringAsFixed(viewerCount >= 100000 ? 0 : 1)}万';
}

/// Whether playback fell back to a different rendition than the one requested.
bool roomHasQualityFallback({
  required LivePlayQuality requested,
  required LivePlayQuality effective,
}) {
  return requested.id != effective.id || requested.label != effective.label;
}

/// Quality badge text: the plain label, or `请求 · 实际生效` on a fallback.
String roomQualityBadgeLabel({
  required LivePlayQuality requested,
  required LivePlayQuality effective,
}) {
  if (!roomHasQualityFallback(requested: requested, effective: effective)) {
    return effective.label;
  }
  return '${requested.label} · 实际${effective.label}';
}

/// Badge text only when playback actually fell back, otherwise null.
String? roomQualityBadgeLabelOrNull({
  required LivePlayQuality requested,
  required LivePlayQuality effective,
}) {
  if (!roomHasQualityFallback(requested: requested, effective: effective)) {
    return null;
  }
  return roomQualityBadgeLabel(requested: requested, effective: effective);
}

/// Poster for the loading shell: keyframe first, then cover.
String? roomShellPosterUrl(LiveRoomDetail? room) {
  return room?.keyframeUrl ?? room?.coverUrl;
}

/// Whether the resolved play source reported a Stripchat pdkey health alert.
bool roomHasPdkeyHealthAlert(RoomSessionLoadResult? state) {
  return state?.resolved?.hasPdkeyHealthAlert ?? false;
}
