import 'package:flutter/foundation.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:nolive_app/src/features/room/application/room_session_controller.dart';
import 'package:nolive_app/src/features/room/application/room_playback_session_state.dart';
import 'package:nolive_app/src/features/settings/application/manage_danmaku_preferences_use_case.dart';
import 'package:nolive_app/src/features/settings/application/manage_player_preferences_use_case.dart';
import 'package:nolive_app/src/features/settings/application/manage_room_ui_preferences_use_case.dart';

/// Immutable room page session state plus the rule for when a transition is
/// worth rebuilding the page.
///
/// Both used to sit inside room_page_session_coordinator.dart, which mixed the
/// value type and its change-detection policy in with 1,100 lines of async
/// orchestration. They are pure, so they belong in the application layer where
/// they can be asserted without constructing a coordinator.

const PlayerPreferences _defaultRoomPagePlayerPreferences = PlayerPreferences(
  autoPlayEnabled: true,
  preferHighestQuality: false,
  autoQualityEnabled: true,
  backend: PlayerBackend.mpv,
  volume: 1,
  mpvHardwareAccelerationEnabled: true,
  mpvCompatModeEnabled: false,
  mpvDoubleBufferingEnabled: false,
  mpvCustomOutputEnabled: false,
  mpvVideoOutputDriver: kDefaultMpvVideoOutputDriver,
  mpvAudioOutputDriver: kDefaultMpvAudioOutputDriver,
  mpvHardwareDecoder: kDefaultMpvHardwareDecoder,
  mpvLogEnabled: false,
  wifiQualityPreference: NetworkQualityPreference.middle,
  cellularQualityPreference: NetworkQualityPreference.lowest,
  mdkLowLatencyEnabled: true,
  mdkAndroidTunnelEnabled: false,
  mdkAndroidHardwareVideoDecoderEnabled: true,
  forceHttpsEnabled: false,
  androidAutoFullscreenEnabled: true,
  androidBackgroundAutoPauseEnabled: true,
  androidPipHideDanmakuEnabled: true,
  scaleMode: PlayerScaleMode.contain,
);

@immutable
class RoomPageSessionState {
  const RoomPageSessionState({
    this.latestLoadedState,
    this.playbackSession = const RoomPlaybackSessionState(),
    this.playerPreferences = _defaultRoomPagePlayerPreferences,
    this.danmakuPreferences = DanmakuPreferences.defaults,
    this.roomUiPreferences = RoomUiPreferences.defaults,
    this.blockedKeywords = const <String>[],
    this.isFollowed = false,
    this.ancillaryLoading = false,
    this.refreshInFlight = false,
    this.isLeavingRoom = false,
    this.showDanmakuOverlay = true,
    this.volume = 1,
  });

  const RoomPageSessionState.initial()
    : latestLoadedState = null,
      playbackSession = const RoomPlaybackSessionState(),
      playerPreferences = _defaultRoomPagePlayerPreferences,
      danmakuPreferences = DanmakuPreferences.defaults,
      roomUiPreferences = RoomUiPreferences.defaults,
      blockedKeywords = const <String>[],
      isFollowed = false,
      ancillaryLoading = false,
      refreshInFlight = false,
      isLeavingRoom = false,
      showDanmakuOverlay = true,
      volume = 1;

  final RoomSessionLoadResult? latestLoadedState;
  final RoomPlaybackSessionState playbackSession;
  final PlayerPreferences playerPreferences;
  final DanmakuPreferences danmakuPreferences;
  final RoomUiPreferences roomUiPreferences;
  final List<String> blockedKeywords;
  final bool isFollowed;
  final bool ancillaryLoading;
  final bool refreshInFlight;
  final bool isLeavingRoom;
  final bool showDanmakuOverlay;
  final double volume;

  RoomPageSessionState copyWith({
    RoomSessionLoadResult? latestLoadedState,
    bool clearLatestLoadedState = false,
    RoomPlaybackSessionState? playbackSession,
    PlayerPreferences? playerPreferences,
    DanmakuPreferences? danmakuPreferences,
    RoomUiPreferences? roomUiPreferences,
    List<String>? blockedKeywords,
    bool? isFollowed,
    bool? ancillaryLoading,
    bool? refreshInFlight,
    bool? isLeavingRoom,
    bool? showDanmakuOverlay,
    double? volume,
  }) {
    return RoomPageSessionState(
      latestLoadedState: clearLatestLoadedState
          ? null
          : latestLoadedState ?? this.latestLoadedState,
      playbackSession: playbackSession ?? this.playbackSession,
      playerPreferences: playerPreferences ?? this.playerPreferences,
      danmakuPreferences: danmakuPreferences ?? this.danmakuPreferences,
      roomUiPreferences: roomUiPreferences ?? this.roomUiPreferences,
      blockedKeywords: blockedKeywords ?? this.blockedKeywords,
      isFollowed: isFollowed ?? this.isFollowed,
      ancillaryLoading: ancillaryLoading ?? this.ancillaryLoading,
      refreshInFlight: refreshInFlight ?? this.refreshInFlight,
      isLeavingRoom: isLeavingRoom ?? this.isLeavingRoom,
      showDanmakuOverlay: showDanmakuOverlay ?? this.showDanmakuOverlay,
      volume: volume ?? this.volume,
    );
  }
}

/// Whether a session state transition should fan into page rebuild listeners.
///
/// Ignores bootstrap-only [RoomPlaybackSessionState] pending fields that the
/// room page does not read (pendingPlaybackSource / Available / AutoPlay).
bool shouldNotifyRoomPageSessionListeners({
  required RoomPageSessionState previous,
  required RoomPageSessionState next,
}) {
  if (identical(previous, next)) {
    return false;
  }
  if (!identical(previous.latestLoadedState, next.latestLoadedState)) {
    return true;
  }
  if (!_roomPlaybackSessionUiEqual(
    previous.playbackSession,
    next.playbackSession,
  )) {
    return true;
  }
  if (!identical(previous.playerPreferences, next.playerPreferences)) {
    return true;
  }
  if (!identical(previous.danmakuPreferences, next.danmakuPreferences)) {
    return true;
  }
  if (!identical(previous.roomUiPreferences, next.roomUiPreferences)) {
    return true;
  }
  if (!_stringListEqual(previous.blockedKeywords, next.blockedKeywords)) {
    return true;
  }
  if (previous.isFollowed != next.isFollowed) {
    return true;
  }
  if (previous.ancillaryLoading != next.ancillaryLoading) {
    return true;
  }
  if (previous.refreshInFlight != next.refreshInFlight) {
    return true;
  }
  if (previous.isLeavingRoom != next.isLeavingRoom) {
    return true;
  }
  if (previous.showDanmakuOverlay != next.showDanmakuOverlay) {
    return true;
  }
  if (previous.volume != next.volume) {
    return true;
  }
  return false;
}

bool _roomPlaybackSessionUiEqual(
  RoomPlaybackSessionState left,
  RoomPlaybackSessionState right,
) {
  if (identical(left, right)) {
    return true;
  }
  return identical(left.activeRoomDetail, right.activeRoomDetail) &&
      identical(left.selectedQuality, right.selectedQuality) &&
      identical(left.effectiveQuality, right.effectiveQuality) &&
      _playbackSourceUiEqual(left.playbackSource, right.playbackSource) &&
      _playUrlsUiEqual(left.playUrls, right.playUrls) &&
      left.playbackAvailable == right.playbackAvailable;
}

bool _playbackSourceUiEqual(PlaybackSource? left, PlaybackSource? right) {
  if (identical(left, right)) {
    return true;
  }
  if (left == null || right == null) {
    return left == right;
  }
  return left.url == right.url &&
      left.externalAudio?.url == right.externalAudio?.url &&
      left.bufferProfile == right.bufferProfile;
}

bool _playUrlsUiEqual(List<LivePlayUrl> left, List<LivePlayUrl> right) {
  if (identical(left, right)) {
    return true;
  }
  if (left.length != right.length) {
    return false;
  }
  for (var i = 0; i < left.length; i += 1) {
    final a = left[i];
    final b = right[i];
    if (identical(a, b)) {
      continue;
    }
    if (a.url != b.url || a.lineLabel != b.lineLabel) {
      return false;
    }
  }
  return true;
}

bool _stringListEqual(List<String> left, List<String> right) {
  if (identical(left, right)) {
    return true;
  }
  if (left.length != right.length) {
    return false;
  }
  for (var i = 0; i < left.length; i += 1) {
    if (left[i] != right[i]) {
      return false;
    }
  }
  return true;
}

class RoomSessionCancelledException implements Exception {
  const RoomSessionCancelledException();

  @override
  String toString() => 'Room session load cancelled.';
}
