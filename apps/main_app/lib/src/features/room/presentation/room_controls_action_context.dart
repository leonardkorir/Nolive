import 'package:flutter/foundation.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:nolive_app/src/features/room/application/load_room_use_case.dart';
import 'package:nolive_app/src/features/room/application/resolve_play_source_use_case.dart';
import 'package:nolive_app/src/features/room/application/room_session_controller.dart';
import 'package:nolive_app/src/features/room/presentation/room_runtime_helper_contexts.dart';
import 'package:nolive_app/src/features/settings/application/manage_danmaku_preferences_use_case.dart';
import 'package:nolive_app/src/features/settings/application/manage_player_preferences_use_case.dart';

bool shouldRefreshRoomAfterPlayerSettingsReturn({
  required PlayerPreferences previous,
  required PlayerPreferences next,
}) {
  return previous.preferHighestQuality != next.preferHighestQuality ||
      previous.forceHttpsEnabled != next.forceHttpsEnabled;
}

typedef RoomResolvePlaybackRefresh = Future<ResolvedPlaySource> Function(
  LoadedRoomSnapshot snapshot,
  LivePlayQuality quality,
);

typedef RoomPlaybackSourceFromLine = PlaybackSource Function(
  LivePlayUrl playUrl, {
  LivePlayQuality? quality,
});

typedef RoomBindPlaybackSourceWithRecovery = Future<bool> Function({
  required PlaybackSource playbackSource,
  required String label,
  bool autoPlay,
  Duration autoPlayDelay,
  PlaybackSource? currentPlaybackSource,
  bool preferFreshBackendBeforeFirstSetSource,
  bool Function()? shouldAbortRetry,
});

typedef RoomReplaceResolvedPlaybackSession = void Function({
  required LiveRoomDetail activeRoomDetail,
  required LivePlayQuality selectedQuality,
  required LivePlayQuality effectiveQuality,
  required PlaybackSource? playbackSource,
  required List<LivePlayUrl> playUrls,
});

typedef RoomUpdatePlaybackSourceForLineSwitch = void Function({
  required PlaybackSource playbackSource,
  required bool hasPlayback,
});

typedef RoomSchedulePlaybackBootstrap = void Function({
  required PlaybackSource? playbackSource,
  required bool hasPlayback,
  required bool autoPlay,
  bool force,
});

typedef RoomScheduleTwitchRecovery = void Function({
  required LoadedRoomSnapshot snapshot,
  required PlaybackSource? playbackSource,
  required List<LivePlayUrl> playUrls,
  required LivePlayQuality selectedQuality,
});

typedef RoomRefreshRoom = Future<void> Function({
  bool showFeedback,
  bool reloadPlayer,
  bool forcePlaybackRebind,
});

typedef RoomApplyPlayerPreferences = void Function(
  PlayerPreferences preferences,
);

typedef RoomApplyDanmakuPreferences = void Function({
  required DanmakuPreferences preferences,
  required List<String> blockedKeywords,
});

typedef RoomPersistScreenshot = Future<String?> Function({
  required Uint8List bytes,
  required String fileName,
});

typedef RoomCaptureRenderedPlayerSurface = Future<Uint8List?> Function();

class RoomControlsActionContext {
  const RoomControlsActionContext({
    required this.providerId,
    required this.roomId,
    required this.targetPlatform,
    required this.isWeb,
    required this.runtime,
    required this.trace,
    required this.showMessage,
    required this.isMounted,
    required this.resolveAutoPlayEnabled,
    required this.resolveForceHttpsEnabled,
    required this.resolvePlaybackAvailable,
    required this.resolveCurrentPlaybackSource,
    required this.resolvePlaybackReferenceSource,
    required this.resolveCurrentPlayUrls,
    required this.resolveSelectedQuality,
    required this.resolveEffectiveQuality,
    required this.resolveActiveRoomDetail,
    required this.resolveLatestLoadedState,
    required this.loadCurrentRoomDetailForDanmaku,
    required this.resolvePlaybackRefresh,
    required this.playbackSourceFromLine,
    required this.bindPlaybackSourceWithRecovery,
    required this.replaceResolvedPlaybackSession,
    required this.updatePlaybackSourceForLineSwitch,
    required this.schedulePlaybackBootstrap,
    required this.scheduleTwitchRecovery,
    required this.prepareTwitchForResolvedPlayback,
    required this.prepareTwitchForLineSwitch,
    required this.loadPlayerPreferences,
    required this.applyPlayerPreferences,
    required this.refreshRoom,
    required this.loadDanmakuPreferences,
    required this.loadBlockedKeywords,
    required this.applyDanmakuPreferences,
    required this.openRoomDanmaku,
    required this.bindDanmakuSession,
    required this.leaveRoom,
    this.captureRenderedPlayerSurface,
  });

  final ProviderId providerId;
  final String roomId;
  final TargetPlatform targetPlatform;
  final bool isWeb;
  final RoomRuntimeControlContext runtime;
  final void Function(String message) trace;
  final void Function(String message) showMessage;
  final bool Function() isMounted;
  final bool Function() resolveAutoPlayEnabled;
  final bool Function() resolveForceHttpsEnabled;
  final bool Function() resolvePlaybackAvailable;
  final PlaybackSource? Function() resolveCurrentPlaybackSource;
  final PlaybackSource? Function() resolvePlaybackReferenceSource;
  final List<LivePlayUrl> Function() resolveCurrentPlayUrls;
  final LivePlayQuality? Function() resolveSelectedQuality;
  final LivePlayQuality? Function() resolveEffectiveQuality;
  final LiveRoomDetail? Function() resolveActiveRoomDetail;
  final RoomSessionLoadResult? Function() resolveLatestLoadedState;
  final Future<LiveRoomDetail?> Function() loadCurrentRoomDetailForDanmaku;
  final RoomResolvePlaybackRefresh resolvePlaybackRefresh;
  final RoomPlaybackSourceFromLine playbackSourceFromLine;
  final RoomBindPlaybackSourceWithRecovery bindPlaybackSourceWithRecovery;
  final RoomReplaceResolvedPlaybackSession replaceResolvedPlaybackSession;
  final RoomUpdatePlaybackSourceForLineSwitch updatePlaybackSourceForLineSwitch;
  final RoomSchedulePlaybackBootstrap schedulePlaybackBootstrap;
  final RoomScheduleTwitchRecovery scheduleTwitchRecovery;
  final void Function({
    LivePlayQuality? startupPromotionQuality,
    required bool resetAttempts,
  }) prepareTwitchForResolvedPlayback;
  final void Function({required bool resetAttempts}) prepareTwitchForLineSwitch;
  final Future<PlayerPreferences> Function() loadPlayerPreferences;
  final RoomApplyPlayerPreferences applyPlayerPreferences;
  final RoomRefreshRoom refreshRoom;
  final Future<DanmakuPreferences> Function() loadDanmakuPreferences;
  final Future<List<String>> Function() loadBlockedKeywords;
  final RoomApplyDanmakuPreferences applyDanmakuPreferences;
  final Future<DanmakuSession?> Function({required LiveRoomDetail detail})
      openRoomDanmaku;
  final Future<void> Function(DanmakuSession? session) bindDanmakuSession;
  final Future<void> Function() leaveRoom;
  final RoomCaptureRenderedPlayerSurface? captureRenderedPlayerSurface;
}
