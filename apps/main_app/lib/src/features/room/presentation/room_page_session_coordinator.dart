import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:nolive_app/src/features/room/application/load_room_use_case.dart';
import 'package:nolive_app/src/features/room/application/room_ancillary_controller.dart';
import 'package:nolive_app/src/features/room/application/room_session_controller.dart';
import 'package:nolive_app/src/features/room/presentation/room_danmaku_controller.dart';
import 'package:nolive_app/src/features/room/presentation/room_fullscreen_session_controller.dart';
import 'package:nolive_app/src/features/room/presentation/room_playback_controller.dart';
import 'package:nolive_app/src/features/room/presentation/room_playback_session_state.dart';
import 'package:nolive_app/src/features/room/presentation/room_controls_presentation_helpers.dart';
import 'package:nolive_app/src/features/room/presentation/room_twitch_recovery_controller.dart';
import 'package:nolive_app/src/features/settings/application/manage_danmaku_preferences_use_case.dart';
import 'package:nolive_app/src/features/settings/application/manage_player_preferences_use_case.dart';
import 'package:nolive_app/src/features/settings/application/manage_room_ui_preferences_use_case.dart';

typedef RoomPageSessionMountCheck = bool Function();
typedef RoomPageSessionTrace = void Function(String message);
typedef RoomPageSessionResolveRuntimeSource = PlaybackSource? Function();
typedef RoomPageSessionScheduleTwitchRecovery = void Function({
  required LoadedRoomSnapshot snapshot,
  required PlaybackSource? playbackSource,
  required List<LivePlayUrl> playUrls,
  required LivePlayQuality selectedQuality,
});
typedef RoomPageSessionSyncPlayerRuntime = void Function();

const PlayerPreferences _defaultRoomPagePlayerPreferences = PlayerPreferences(
  autoPlayEnabled: true,
  preferHighestQuality: false,
  backend: PlayerBackend.mpv,
  volume: 1,
  mpvHardwareAccelerationEnabled: true,
  mpvCompatModeEnabled: false,
  mpvDoubleBufferingEnabled: false,
  mpvCustomOutputEnabled: false,
  mpvVideoOutputDriver: kDefaultMpvVideoOutputDriver,
  mpvHardwareDecoder: kDefaultMpvHardwareDecoder,
  mpvLogEnabled: false,
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

class RoomPageSessionCoordinator extends ChangeNotifier {
  RoomPageSessionCoordinator({
    required this.providerId,
    required this.sessionController,
    required this.ancillaryController,
    required this.danmakuController,
    required this.playbackController,
    required this.fullscreenSessionController,
    required this.twitchRecoveryController,
    required this.resolveRuntimeCurrentPlaybackSource,
    required this.loadPlayerPreferences,
    required this.updatePlayerPreferences,
    required this.persistRoomUiPreferences,
    required this.trace,
    required this.isMounted,
    RoomPageSessionScheduleTwitchRecovery? scheduleTwitchRecovery,
    RoomPageSessionSyncPlayerRuntime? syncPlayerRuntimeState,
  })  : _scheduleTwitchRecovery =
            scheduleTwitchRecovery ?? _noopScheduleTwitchRecovery,
        _syncPlayerRuntimeState =
            syncPlayerRuntimeState ?? _noopSyncPlayerRuntimeState;

  final ProviderId providerId;
  final RoomSessionController sessionController;
  final RoomAncillaryController ancillaryController;
  final RoomDanmakuController danmakuController;
  final RoomPlaybackController playbackController;
  final RoomFullscreenSessionController fullscreenSessionController;
  final RoomTwitchRecoveryController twitchRecoveryController;
  final RoomPageSessionResolveRuntimeSource resolveRuntimeCurrentPlaybackSource;
  final Future<PlayerPreferences> Function() loadPlayerPreferences;
  final Future<void> Function(PlayerPreferences preferences)
      updatePlayerPreferences;
  final Future<void> Function(RoomUiPreferences preferences)
      persistRoomUiPreferences;
  final RoomPageSessionTrace trace;
  final RoomPageSessionMountCheck isMounted;
  final RoomPageSessionScheduleTwitchRecovery _scheduleTwitchRecovery;
  final RoomPageSessionSyncPlayerRuntime _syncPlayerRuntimeState;

  static void _noopSyncPlayerRuntimeState() {}

  static void _noopScheduleTwitchRecovery({
    required LoadedRoomSnapshot snapshot,
    required PlaybackSource? playbackSource,
    required List<LivePlayUrl> playUrls,
    required LivePlayQuality selectedQuality,
  }) {}

  RoomPageSessionState _state = const RoomPageSessionState.initial();
  late Future<RoomSessionLoadResult> _roomFuture;
  bool _disposed = false;
  int _roomFutureToken = 0;
  int _ancillaryLoadToken = 0;
  bool _forcePlaybackRebindOnNextResolvedRoomState = false;

  RoomPageSessionState get state => _state;
  Future<RoomSessionLoadResult> get roomFuture => _roomFuture;
  bool get _isActive => !_disposed && isMounted();

  Future<RoomSessionLoadResult> startInitialLoad({String? preferredQualityId}) {
    final future =
        _trackRoomFuture(_load(preferredQualityId: preferredQualityId));
    _roomFuture = future;
    return future;
  }

  void applyPlayerPreferences(PlayerPreferences preferences) {
    _replaceState(
      _state.copyWith(
        playerPreferences: preferences,
        volume: preferences.volume,
      ),
    );
  }

  void applyDanmakuPreferences({
    required DanmakuPreferences preferences,
    required List<String> blockedKeywords,
  }) {
    _replaceState(
      _state.copyWith(
        danmakuPreferences: preferences,
        blockedKeywords: blockedKeywords,
        showDanmakuOverlay: preferences.enabledByDefault,
      ),
    );
    danmakuController.configure(
      blockedKeywords: blockedKeywords,
      preferNativeBatchMask: preferences.nativeBatchMaskEnabled,
      playerSuperChatDisplaySeconds:
          _state.roomUiPreferences.playerSuperChatDisplaySeconds,
    );
  }

  void applyCurrentFollowed(bool followed) {
    if (_state.isFollowed == followed) {
      return;
    }
    _replaceState(_state.copyWith(isFollowed: followed));
  }

  void updateDanmakuOverlayVisible(bool visible) {
    if (_state.showDanmakuOverlay == visible) {
      return;
    }
    _replaceState(_state.copyWith(showDanmakuOverlay: visible));
  }

  void updateVolume(double value) {
    if (_state.volume == value) {
      return;
    }
    _replaceState(_state.copyWith(volume: value));
  }

  Future<void> updateScaleMode(PlayerScaleMode scaleMode) async {
    final preferences = (await loadPlayerPreferences()).copyWith(
      scaleMode: scaleMode,
    );
    await updatePlayerPreferences(preferences);
    if (!_isActive) {
      return;
    }
    applyPlayerPreferences(preferences);
  }

  Future<void> updateRoomUiPreferences(RoomUiPreferences preferences) async {
    _replaceState(_state.copyWith(roomUiPreferences: preferences));
    await persistRoomUiPreferences(preferences);
    danmakuController.configure(
      blockedKeywords: _state.blockedKeywords,
      preferNativeBatchMask: _state.danmakuPreferences.nativeBatchMaskEnabled,
      playerSuperChatDisplaySeconds: preferences.playerSuperChatDisplaySeconds,
    );
  }

  Future<LiveRoomDetail?> loadCurrentRoomDetailForDanmaku() async {
    try {
      final state = await roomFuture;
      return state.snapshot.detail;
    } catch (_) {
      return _state.latestLoadedState?.snapshot.detail;
    }
  }

  Future<void> bindDanmakuSession(DanmakuSession? session) async {
    final detail = _state.playbackSession.activeRoomDetail;
    if (detail == null) {
      await danmakuController.closeSession();
      return;
    }
    await danmakuController.bindSession(
      activeRoomDetail: detail,
      session: session,
    );
  }

  void replaceResolvedPlaybackSession({
    required LiveRoomDetail activeRoomDetail,
    required LivePlayQuality selectedQuality,
    required LivePlayQuality effectiveQuality,
    required PlaybackSource? playbackSource,
    required List<LivePlayUrl> playUrls,
  }) {
    _replaceState(
      _state.copyWith(
        playbackSession: _state.playbackSession.copyWith(
          activeRoomDetail: activeRoomDetail,
          selectedQuality: selectedQuality,
          effectiveQuality: effectiveQuality,
          playbackSource: playbackSource,
          clearPlaybackSource: playbackSource == null,
          playUrls: playUrls,
          playbackAvailable: playbackSource != null && playUrls.isNotEmpty,
        ),
      ),
    );
  }

  void updatePlaybackSourceForLineSwitch({
    required PlaybackSource playbackSource,
    required bool hasPlayback,
  }) {
    _replaceState(
      _state.copyWith(
        playbackSession: _state.playbackSession.copyWith(
          playbackSource: playbackSource,
          playbackAvailable: hasPlayback,
        ),
      ),
    );
  }

  void schedulePlaybackBootstrap({
    required PlaybackSource? playbackSource,
    required bool hasPlayback,
    required bool autoPlay,
    bool force = false,
  }) {
    _replaceState(
      _state.copyWith(
        playbackSession: _state.playbackSession.copyWith(
          pendingPlaybackSource: playbackSource,
          clearPendingPlaybackSource: playbackSource == null,
          pendingPlaybackAvailable: hasPlayback,
          pendingPlaybackAutoPlay: autoPlay,
        ),
      ),
    );
    playbackController.schedulePlaybackBootstrap(
      playbackSource: playbackSource,
      hasPlayback: hasPlayback,
      autoPlay: autoPlay,
      force: force,
    );
  }

  PlaybackSource? resolvePlaybackReferenceSource() {
    return resolveRuntimeCurrentPlaybackSource() ??
        _state.playbackSession.playbackSource ??
        playbackController.pendingPlaybackSource;
  }

  Future<void> waitForPlayerBindingToFinish({
    required String reason,
  }) {
    return playbackController.waitForPlaybackRebindToFinish(reason: reason);
  }

  Future<void> refreshRoom({
    bool showFeedback = false,
    bool reloadPlayer = false,
    bool forcePlaybackRebind = true,
  }) async {
    if (playbackController.rebindInFlight) {
      trace(
        'refresh skipped reloadPlayer=$reloadPlayer '
        'forcePlaybackRebind=$forcePlaybackRebind playbackRebindInFlight=true',
      );
      return;
    }
    if (_state.refreshInFlight) {
      trace(
        'refresh skipped reloadPlayer=$reloadPlayer '
        'forcePlaybackRebind=$forcePlaybackRebind inFlight=true',
      );
      return;
    }
    _forcePlaybackRebindOnNextResolvedRoomState =
        forcePlaybackRebind && !reloadPlayer;
    _replaceState(_state.copyWith(refreshInFlight: true));
    final previousFuture = _roomFuture;
    final future = _trackRoomFuture(
      reloadPlayer
          ? _load(
              preferredQualityId: _state.playbackSession.selectedQuality?.id)
          : _refreshRoomData(
              previousFuture: previousFuture,
              preferredQualityId: _state.playbackSession.selectedQuality?.id,
            ),
    );
    _roomFuture = future;
    notifyListeners();
    danmakuController.clearFeed();
    try {
      await future;
    } finally {
      _replaceState(_state.copyWith(refreshInFlight: false));
    }
  }

  Future<void> leaveRoom() async {
    if (_state.isLeavingRoom) {
      return;
    }
    _replaceState(_state.copyWith(isLeavingRoom: true));
    try {
      await cleanupPlaybackOnLeave();
    } catch (_) {
      if (_isActive) {
        _replaceState(_state.copyWith(isLeavingRoom: false));
      }
      rethrow;
    }
  }

  Future<void> cleanupPlaybackOnLeave() async {
    await waitForPlayerBindingToFinish(reason: 'cleanup playback');
    await fullscreenSessionController.cleanupPlaybackOnLeave();
    await danmakuController.closeSession();
  }

  Future<PlaybackSource?> resolvePlaybackSourceForLifecycleRestore() async {
    final latestLoadedState = _state.latestLoadedState;
    final selectedQuality = _state.playbackSession.selectedQuality;
    if (latestLoadedState == null || selectedQuality == null) {
      return _state.playbackSession.playbackSource;
    }
    final resolved = await sessionController.resolvePlaybackRefresh(
      snapshot: latestLoadedState.snapshot,
      quality: selectedQuality,
      preferHttps: _state.playerPreferences.forceHttpsEnabled,
    );
    if (_isActive) {
      replaceResolvedPlaybackSession(
        activeRoomDetail: latestLoadedState.snapshot.detail,
        selectedQuality: selectedQuality,
        effectiveQuality: resolved.effectiveQuality,
        playbackSource: resolved.playbackSource,
        playUrls: resolved.playUrls,
      );
    }
    return resolved.playbackSource;
  }

  @override
  void dispose() {
    _disposed = true;
    _ancillaryLoadToken += 1;
    sessionController.clearCurrent();
    super.dispose();
  }

  Future<RoomSessionLoadResult> _load({String? preferredQualityId}) {
    return sessionController.load(
      preferredQualityId: preferredQualityId,
    );
  }

  Future<RoomSessionLoadResult> _trackRoomFuture(
    Future<RoomSessionLoadResult> future,
  ) {
    final token = ++_roomFutureToken;
    return future.then((state) async {
      if (_isActive && token == _roomFutureToken) {
        await _handleResolvedRoomState(state);
      }
      return state;
    }, onError: (Object error, StackTrace stackTrace) {
      if (_isActive && token == _roomFutureToken) {
        _handleRoomLoadFailure();
      }
      throw error;
    });
  }

  Future<void> _handleResolvedRoomState(RoomSessionLoadResult next) async {
    final forcePlaybackRebind = _forcePlaybackRebindOnNextResolvedRoomState;
    _forcePlaybackRebindOnNextResolvedRoomState = false;
    final hadPreviousState = _state.latestLoadedState != null;
    _applyLoadedRoomSession(
      next,
      resetFullscreenAutoApplied: !hadPreviousState,
    );
    final playbackSource = _state.playbackSession.playbackSource;
    final playUrls = _state.playbackSession.playUrls;
    final hasPlayback = playbackSource != null && playUrls.isNotEmpty;
    _setPlaybackAvailability(hasPlayback);
    schedulePlaybackBootstrap(
      playbackSource: playbackSource,
      hasPlayback: hasPlayback,
      autoPlay: next.playerPreferences.autoPlayEnabled,
      force: forcePlaybackRebind,
    );
    _scheduleTwitchRecovery(
      snapshot: next.snapshot,
      playbackSource: playbackSource,
      playUrls: playUrls,
      selectedQuality: _requestedQualityOf(next),
    );
    fullscreenSessionController.handleResolvedRoomState(
      roomLoaded: true,
      playbackAvailable: hasPlayback,
    );
    _syncPlayerRuntimeState();
  }

  void _handleRoomLoadFailure() {
    _forcePlaybackRebindOnNextResolvedRoomState = false;
    _ancillaryLoadToken += 1;
    playbackController.resetRecoveryState();
    sessionController.clearCurrent();
    _replaceState(
      _state.copyWith(
        clearLatestLoadedState: true,
        ancillaryLoading: false,
        playbackSession: _state.playbackSession.copyWith(
          playbackAvailable: false,
        ),
      ),
    );
    fullscreenSessionController.handleResolvedRoomState(
      roomLoaded: true,
      playbackAvailable: false,
    );
    _syncPlayerRuntimeState();
  }

  void _applyLoadedRoomSession(
    RoomSessionLoadResult next, {
    required bool resetFullscreenAutoApplied,
  }) {
    final playerPreferences = next.playerPreferences;
    final danmakuPreferences = next.danmakuPreferences;
    final roomUiPreferences = next.roomUiPreferences;

    twitchRecoveryController.applyStartupPlan(next.startupPlan);
    if (resetFullscreenAutoApplied) {
      fullscreenSessionController.resetAutoFullscreenApplied();
    }
    danmakuController.configure(
      blockedKeywords: next.blockedKeywords,
      preferNativeBatchMask: danmakuPreferences.nativeBatchMaskEnabled,
      playerSuperChatDisplaySeconds:
          roomUiPreferences.playerSuperChatDisplaySeconds,
    );
    replaceResolvedPlaybackSession(
      activeRoomDetail: next.snapshot.detail,
      selectedQuality: next.playbackQuality,
      effectiveQuality: next.resolved?.effectiveQuality ?? next.playbackQuality,
      playbackSource: next.resolved?.playbackSource,
      playUrls: next.resolved?.playUrls ?? next.snapshot.playUrls,
    );
    _replaceState(
      _state.copyWith(
        latestLoadedState: next,
        playerPreferences: playerPreferences,
        danmakuPreferences: danmakuPreferences,
        roomUiPreferences: roomUiPreferences,
        blockedKeywords: next.blockedKeywords,
        volume: playerPreferences.volume,
        showDanmakuOverlay: danmakuPreferences.enabledByDefault,
      ),
    );
    _scheduleAncillaryLoad(snapshot: next.snapshot);
    trace(
      'room session applied playback=${_summarizePlaybackSource(_state.playbackSession.playbackSource)} '
      'quality=${next.playbackQuality.id}/${next.playbackQuality.label}',
    );
  }

  void _scheduleAncillaryLoad({
    required LoadedRoomSnapshot snapshot,
  }) {
    final token = ++_ancillaryLoadToken;
    _replaceState(_state.copyWith(ancillaryLoading: true));
    unawaited(
      _loadAncillaryRoomState(
        token: token,
        snapshot: snapshot,
      ),
    );
  }

  Future<void> _loadAncillaryRoomState({
    required int token,
    required LoadedRoomSnapshot snapshot,
  }) async {
    final result = await ancillaryController.load(
      snapshot: snapshot,
      fallbackIsFollowed: _state.isFollowed,
    );

    if (!_isActive || token != _ancillaryLoadToken) {
      await result.danmakuSession?.disconnect();
      return;
    }
    await bindDanmakuSession(result.danmakuSession);
    if (!_isActive || token != _ancillaryLoadToken) {
      return;
    }
    _replaceState(
      _state.copyWith(
        isFollowed: result.isFollowed,
        ancillaryLoading: false,
      ),
    );
  }

  Future<RoomSessionLoadResult> _refreshRoomData({
    required Future<RoomSessionLoadResult> previousFuture,
    String? preferredQualityId,
  }) async {
    if (sessionController.current == null) {
      try {
        await previousFuture;
      } catch (_) {
        return _load(preferredQualityId: preferredQualityId);
      }
    }
    if (sessionController.current == null) {
      return _load(preferredQualityId: preferredQualityId);
    }
    return sessionController.reload(
      preferredQualityId: preferredQualityId,
    );
  }

  void _setPlaybackAvailability(bool value) {
    if (_state.playbackSession.playbackAvailable == value) {
      return;
    }
    _replaceState(
      _state.copyWith(
        playbackSession: _state.playbackSession.copyWith(
          playbackAvailable: value,
        ),
      ),
    );
  }

  LivePlayQuality _requestedQualityOf(RoomSessionLoadResult state) {
    return resolveRequestedQualityOfRoomState(
      state: state,
      selectedQuality: _state.playbackSession.selectedQuality,
    );
  }

  void _replaceState(RoomPageSessionState next) {
    if (_disposed) {
      return;
    }
    _state = next;
    notifyListeners();
  }

  String _summarizePlaybackSource(PlaybackSource? source) {
    final url = source?.url;
    if (url == null) {
      return '-';
    }
    final audio = source?.externalAudio?.url;
    final base = '${url.host}${url.path}';
    if (audio == null) {
      return base;
    }
    return '$base + audio=${audio.host}${audio.path}';
  }
}
