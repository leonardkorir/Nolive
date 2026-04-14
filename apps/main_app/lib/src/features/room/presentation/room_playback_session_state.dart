import 'package:flutter/foundation.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';

@immutable
class RoomPlaybackSessionState {
  const RoomPlaybackSessionState({
    this.activeRoomDetail,
    this.selectedQuality,
    this.effectiveQuality,
    this.playbackSource,
    this.playUrls = const [],
    this.playbackAvailable = false,
    this.pendingPlaybackSource,
    this.pendingPlaybackAvailable = false,
    this.pendingPlaybackAutoPlay = false,
  });

  final LiveRoomDetail? activeRoomDetail;
  final LivePlayQuality? selectedQuality;
  final LivePlayQuality? effectiveQuality;
  final PlaybackSource? playbackSource;
  final List<LivePlayUrl> playUrls;
  final bool playbackAvailable;
  final PlaybackSource? pendingPlaybackSource;
  final bool pendingPlaybackAvailable;
  final bool pendingPlaybackAutoPlay;

  RoomPlaybackSessionState copyWith({
    LiveRoomDetail? activeRoomDetail,
    bool clearActiveRoomDetail = false,
    LivePlayQuality? selectedQuality,
    bool clearSelectedQuality = false,
    LivePlayQuality? effectiveQuality,
    bool clearEffectiveQuality = false,
    PlaybackSource? playbackSource,
    bool clearPlaybackSource = false,
    List<LivePlayUrl>? playUrls,
    bool? playbackAvailable,
    PlaybackSource? pendingPlaybackSource,
    bool clearPendingPlaybackSource = false,
    bool? pendingPlaybackAvailable,
    bool? pendingPlaybackAutoPlay,
  }) {
    return RoomPlaybackSessionState(
      activeRoomDetail: clearActiveRoomDetail
          ? null
          : activeRoomDetail ?? this.activeRoomDetail,
      selectedQuality:
          clearSelectedQuality ? null : selectedQuality ?? this.selectedQuality,
      effectiveQuality: clearEffectiveQuality
          ? null
          : effectiveQuality ?? this.effectiveQuality,
      playbackSource:
          clearPlaybackSource ? null : playbackSource ?? this.playbackSource,
      playUrls: playUrls ?? this.playUrls,
      playbackAvailable: playbackAvailable ?? this.playbackAvailable,
      pendingPlaybackSource: clearPendingPlaybackSource
          ? null
          : pendingPlaybackSource ?? this.pendingPlaybackSource,
      pendingPlaybackAvailable:
          pendingPlaybackAvailable ?? this.pendingPlaybackAvailable,
      pendingPlaybackAutoPlay:
          pendingPlaybackAutoPlay ?? this.pendingPlaybackAutoPlay,
    );
  }
}
