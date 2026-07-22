import 'dart:async';
import 'dart:ui' show AppLifecycleState;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show PageController;
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:nolive_app/src/features/room/application/load_room_use_case.dart';
import 'package:nolive_app/src/features/room/application/room_ancillary_controller.dart';
import 'package:nolive_app/src/features/room/application/room_session_controller.dart';
import 'package:nolive_app/src/features/room/presentation/room_danmaku_controller.dart';
import 'package:nolive_app/src/features/room/presentation/room_fullscreen_session_controller.dart';
import 'package:nolive_app/src/features/room/presentation/room_playback_controller.dart';
import 'package:nolive_app/src/features/room/presentation/room_playback_session_state.dart';
import 'package:nolive_app/src/features/room/presentation/room_playback_source_helpers.dart';
import 'package:nolive_app/src/features/room/presentation/room_controls_presentation_helpers.dart';
import 'package:nolive_app/src/features/room/presentation/room_twitch_recovery_controller.dart';
import 'package:nolive_app/src/features/settings/application/manage_danmaku_preferences_use_case.dart';
import 'package:nolive_app/src/features/settings/application/manage_player_preferences_use_case.dart';
import 'package:nolive_app/src/features/settings/application/manage_room_ui_preferences_use_case.dart';

// Added for refactored/absorbed components:
import 'package:nolive_app/src/features/room/application/room_preview_dependencies.dart';
import 'package:nolive_app/src/shared/application/app_log.dart';
import 'package:nolive_app/src/features/room/presentation/room_chat_viewport_coordinator.dart';
import 'package:nolive_app/src/features/room/presentation/room_controls_action_coordinator.dart';
import 'package:nolive_app/src/features/room/presentation/room_follow_action_coordinator.dart';
import 'package:nolive_app/src/features/room/presentation/room_follow_room_transition_coordinator.dart';
import 'package:nolive_app/src/features/room/presentation/room_page_interaction_coordinator.dart';
import 'package:nolive_app/src/features/room/application/room_follow_watchlist_controller.dart';
import 'package:nolive_app/src/features/room/presentation/room_panel_controller.dart';
import 'package:nolive_app/src/features/room/presentation/room_page_rebuild_scope.dart';
import 'package:nolive_app/src/features/room/presentation/room_page_ui_effects.dart';
import 'package:nolive_app/src/features/room/presentation/room_runtime_view_adapter.dart';
import 'package:nolive_app/src/features/room/presentation/room_controls_view_data.dart';
import 'package:nolive_app/src/features/room/presentation/room_runtime_helper_contexts.dart';
import 'package:nolive_app/src/features/room/presentation/room_preview_page_section_widgets.dart';

typedef RoomPageSessionMountCheck = bool Function();
typedef RoomPageSessionTrace = void Function(String message);
typedef RoomPageSessionResolveRuntimeSource = PlaybackSource? Function();
typedef RoomPageSessionScheduleTwitchRecovery =
    void Function({
      required LoadedRoomSnapshot snapshot,
      required PlaybackSource? playbackSource,
      required List<LivePlayUrl> playUrls,
      required LivePlayQuality selectedQuality,
    });
typedef RoomPageSessionSyncPlayerRuntime = void Function();

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

class RoomPageSessionCoordinator extends ChangeNotifier {
  RoomPageSessionCoordinator({
    required this.providerId,
    required this.roomId,
    required this.dependencies,
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
    required RoomRuntimeViewAdapter runtimeViewAdapter,
    required RoomPageUiEffects pageUiEffects,
    required RoomConfirmUnfollow confirmUnfollow,
    required Future<Uint8List?> Function() captureRenderedPlayerSurface,
    required Future<void> Function() exitFullscreenIfNeeded,
    required Future<void> Function() enterPictureInPicture,
    required Future<void> Function() toggleDesktopMiniWindow,
    required RoomRuntimeInspectionContext runtimeInspection,
    required RoomRuntimeControlContext runtimeControl,
    RoomPageSessionScheduleTwitchRecovery? scheduleTwitchRecovery,
    RoomPageSessionSyncPlayerRuntime? syncPlayerRuntimeState,
    AppLifecycleState? initialLifecycleState,
  }) : _scheduleTwitchRecovery =
           scheduleTwitchRecovery ?? _noopScheduleTwitchRecovery,
       _syncPlayerRuntimeState =
           syncPlayerRuntimeState ?? _noopSyncPlayerRuntimeState,
       _lifecycleState = initialLifecycleState ?? AppLifecycleState.resumed {
    
    panelPageController = PageController();
    chatViewport = RoomChatViewportCoordinator();
    
    followWatchlist = RoomFollowWatchlistController(
      dependencies: RoomFollowWatchlistDependencies.fromPreviewDependencies(dependencies),
      trace: trace,
    );
    // Panel / follow updates use local ListenableBuilders so they must not fan
    // into this ChangeNotifier (full room page rebuild / player surface path).
    if (shouldSessionCoordinatorFanOutChildNotify(
      RoomSessionChildNotifySource.followWatchlist,
    )) {
      followWatchlist.listenable.addListener(notifyListeners);
    }

    panel = RoomPanelController(
      pageController: panelPageController,
      onEnterChatPanel: () => chatViewport.scrollToBottom(force: true),
      onEnterFollowPanel: () {
        unawaited(followWatchlist.ensureLoaded());
      },
    );
    if (shouldSessionCoordinatorFanOutChildNotify(
      RoomSessionChildNotifySource.panelSelection,
    )) {
      panel.addListener(notifyListeners);
    }

    controlsAction = RoomControlsActionCoordinator(
      context: RoomControlsActionContext(
        providerId: providerId,
        roomId: roomId,
        targetPlatform: defaultTargetPlatform,
        isWeb: kIsWeb,
        runtime: runtimeControl,
        trace: trace,
        showMessage: pageUiEffects.showMessage,
        isMounted: () => _isActive,
        resolveAutoPlayEnabled: () => _state.playerPreferences.autoPlayEnabled,
        resolveForceHttpsEnabled: () => _state.playerPreferences.forceHttpsEnabled,
        resolvePlaybackAvailable: () => _state.playbackSession.playbackAvailable,
        resolveCurrentPlaybackSource: () => _state.playbackSession.playbackSource,
        resolvePlaybackReferenceSource: () => resolvePlaybackReferenceSource(),
        resolveCurrentPlayUrls: () => _state.playbackSession.playUrls,
        resolveSelectedQuality: () => _state.playbackSession.selectedQuality,
        resolveEffectiveQuality: () => _state.playbackSession.effectiveQuality,
        resolveActiveRoomDetail: () => _state.playbackSession.activeRoomDetail,
        resolveLatestLoadedState: () => _state.latestLoadedState,
        loadCurrentRoomDetailForDanmaku: loadCurrentRoomDetailForDanmaku,
        resolvePlaybackRefresh: (snapshot, quality) {
          return sessionController.resolvePlaybackRefresh(
            snapshot: snapshot,
            quality: quality,
            preferHttps: _state.playerPreferences.forceHttpsEnabled,
          );
        },
        playbackSourceFromLine: sessionController.playbackSourceFromLine,
        bindPlaybackSourceWithRecovery: _bindPlaybackSourceWithRecovery,
        replaceResolvedPlaybackSession: replaceResolvedPlaybackSession,
        updatePlaybackSourceForLineSwitch: updatePlaybackSourceForLineSwitch,
        schedulePlaybackBootstrap: schedulePlaybackBootstrap,
        scheduleTwitchRecovery: _scheduleTwitchRecovery,
        prepareTwitchForResolvedPlayback:
            twitchRecoveryController.prepareForResolvedPlayback,
        prepareTwitchForLineSwitch:
            twitchRecoveryController.prepareForLineSwitch,
        loadPlayerPreferences: () => dependencies.loadPlayerPreferences(),
        applyPlayerPreferences: applyPlayerPreferences,
        refreshRoom:
            ({
              bool showFeedback = false,
              bool reloadPlayer = false,
              bool forcePlaybackRebind = true,
            }) {
              return refreshRoom(
                showFeedback: showFeedback,
                reloadPlayer: reloadPlayer,
                forcePlaybackRebind: forcePlaybackRebind,
              );
            },
        loadDanmakuPreferences: () => dependencies.loadDanmakuPreferences(),
        loadBlockedKeywords: () => dependencies.loadBlockedKeywords(),
        applyDanmakuPreferences:
            ({required preferences, required blockedKeywords}) {
              applyDanmakuPreferences(
                preferences: preferences,
                blockedKeywords: blockedKeywords,
              );
            },
        openRoomDanmaku: ({required detail}) {
          return dependencies.openRoomDanmaku(
            providerId: providerId,
            detail: detail,
          );
        },
        bindDanmakuSession: bindDanmakuSession,
        leaveRoom: () => pageInteraction.leaveRoom(),
        captureRenderedPlayerSurface: captureRenderedPlayerSurface,
      ),
    );
    if (shouldSessionCoordinatorFanOutChildNotify(
      RoomSessionChildNotifySource.controlsAction,
    )) {
      controlsAction.addListener(notifyListeners);
    }

    followRoomTransition = RoomFollowRoomTransitionCoordinator(
      currentProviderId: providerId,
      currentRoomId: roomId,
      runtime: runtimeInspection,
      playbackController: playbackController,
      fullscreenSessionController: fullscreenSessionController,
      trace: trace,
      isMounted: () => _isActive,
    );
    followRoomTransition.addListener(notifyListeners);

    followAction = RoomFollowActionCoordinator(
      dependencies: RoomFollowActionDependencies.fromPreviewDependencies(dependencies),
      context: RoomFollowActionContext(
        resolveCurrentProviderId: () => providerId,
        resolveCurrentRoomId: () => roomId,
        showMessage: pageUiEffects.showMessage,
        isMounted: () => _isActive,
        confirmUnfollow: confirmUnfollow,
        applyCurrentFollowed: applyCurrentFollowed,
        replaceWatchlistSnapshot: followWatchlist.replaceSnapshot,
        ensureFollowWatchlistLoaded: ({force = false}) =>
            followWatchlist.ensureLoaded(force: force),
        commitFollowRoomNavigation: (entry) =>
            pageInteraction.commitFollowRoomNavigation(entry),
      ),
    );

    pageInteraction = RoomPageInteractionCoordinator(
      context: RoomPageInteractionContext(
        isMounted: () => _isActive,
        exitFullscreenIfNeeded: exitFullscreenIfNeeded,
        showMessage: pageUiEffects.showMessage,
        pushNamed: pageUiEffects.pushNamed,
        pushReplacementToRoom: pageUiEffects.pushReplacementToRoom,
        switchToRoomInPlace:
            ({
              required providerId,
              required roomId,
              required preserveFullscreen,
            }) {
              return switchToRoomInPlace(
                nextProviderId: providerId,
                nextRoomId: roomId,
              );
            },
        popPage: pageUiEffects.popPage,
        loadPlayerPreferences: () => dependencies.loadPlayerPreferences(),
        handlePlayerSettingsReturn: (previousPreferences) =>
            controlsAction.handlePlayerSettingsReturn(
              previousPreferences: previousPreferences,
            ),
        handleDanmakuSettingsReturn: controlsAction.handleDanmakuSettingsReturn,
        resolveRoomFuture: () => roomFuture,
        resolveIsLeavingRoom: () => state.isLeavingRoom,
        resolveCurrentPlaybackSource: () => state.playbackSession.playbackSource,
        resolveCurrentPlayUrls: () => state.playbackSession.playUrls,
        resolveRequestedQuality: _requestedQualityOf,
        resolveControlsViewData: ({
          required state,
          required playUrls,
          required playbackSource,
          required hasPlayback,
        }) {
          return RoomControlsViewData(
            hasPlayback: hasPlayback,
            playbackUnavailableReason:
                state.snapshot.playbackUnavailableReason ?? '当前房间暂无可用播放流',
            requestedQualityLabel: _requestedQualityOf(state).label,
            effectiveQualityLabel: _effectiveQualityOf(state).label,
            currentLineLabel: hasPlayback && playbackSource != null
                ? roomLineLabelOfPlayback(playUrls, playbackSource)
                : '不可用',
            scaleModeLabel: labelOfRoomScaleMode(_state.playerPreferences.scaleMode),
            pipSupported: fullscreenSessionController.viewUiState.pipSupported,
            supportsDesktopMiniWindow: fullscreenSessionController.supportsDesktopMiniWindow,
            desktopMiniWindowActive: fullscreenSessionController.viewUiState.desktopMiniWindowActive,
            supportsPlayerCapture: runtimeViewAdapter.supportsScreenshot,
            scheduledCloseAt: controlsAction.scheduledCloseAt,
            chatTextSize: _state.roomUiPreferences.chatTextSize.round(),
            chatTextGap: _state.roomUiPreferences.chatTextGap.round(),
            chatBubbleStyle: _state.roomUiPreferences.chatBubbleStyle,
            showPlayerSuperChat: _state.roomUiPreferences.showPlayerSuperChat,
            playerSuperChatDisplaySeconds: _state.roomUiPreferences.playerSuperChatDisplaySeconds,
          );
        },
        resolvePlayerDebugViewData: ({
          required state,
          required playbackSource,
        }) {
          final debugPlayUrls = _state.playbackSession.playUrls.isEmpty
              ? state.snapshot.playUrls
              : _state.playbackSession.playUrls;
          return RoomPlayerDebugViewData(
            backendLabel: runtimeViewAdapter.backendLabel,
            currentStatusLabel: runtimeViewAdapter.currentStatusLabel,
            requestedQualityLabel: _requestedQualityOf(state).label,
            effectiveQualityLabel: _effectiveQualityOf(state).label,
            currentLineLabel: playbackSource != null && debugPlayUrls.isNotEmpty
                ? roomLineLabelOfPlayback(debugPlayUrls, playbackSource)
                : '不可用',
            scaleModeLabel: labelOfRoomScaleMode(_state.playerPreferences.scaleMode),
            usingNativeDanmakuBatchMask: danmakuController.current.usingNativeBatchMask,
          );
        },
        cycleScaleModeAndResolveControlsViewData: ({
          required state,
          required playUrls,
          required playbackSource,
          required hasPlayback,
        }) async {
          final modes = PlayerScaleMode.values;
          final index = modes.indexOf(_state.playerPreferences.scaleMode);
          await updateScaleMode(modes[(index + 1) % modes.length]);
          return RoomControlsViewData(
            hasPlayback: hasPlayback,
            playbackUnavailableReason:
                state.snapshot.playbackUnavailableReason ?? '当前房间暂无可用播放流',
            requestedQualityLabel: _requestedQualityOf(state).label,
            effectiveQualityLabel: _effectiveQualityOf(state).label,
            currentLineLabel: hasPlayback && playbackSource != null
                ? roomLineLabelOfPlayback(playUrls, playbackSource)
                : '不可用',
            scaleModeLabel: labelOfRoomScaleMode(_state.playerPreferences.scaleMode),
            pipSupported: fullscreenSessionController.viewUiState.pipSupported,
            supportsDesktopMiniWindow: fullscreenSessionController.supportsDesktopMiniWindow,
            desktopMiniWindowActive: fullscreenSessionController.viewUiState.desktopMiniWindowActive,
            supportsPlayerCapture: runtimeViewAdapter.supportsScreenshot,
            scheduledCloseAt: controlsAction.scheduledCloseAt,
            chatTextSize: _state.roomUiPreferences.chatTextSize.round(),
            chatTextGap: _state.roomUiPreferences.chatTextGap.round(),
            chatBubbleStyle: _state.roomUiPreferences.chatBubbleStyle,
            showPlayerSuperChat: _state.roomUiPreferences.showPlayerSuperChat,
            playerSuperChatDisplaySeconds: _state.roomUiPreferences.playerSuperChatDisplaySeconds,
          );
        },
        presentQuickActionsSheet: pageUiEffects.presentQuickActionsSheet,
        presentQualitySheet: pageUiEffects.presentQualitySheet,
        presentLineSheet: pageUiEffects.presentLineSheet,
        presentAutoCloseSheet: pageUiEffects.presentAutoCloseSheet,
        presentPlayerDebugSheet: ({required debugViewData}) {
          return pageUiEffects.presentPlayerDebugSheet(
            debugViewData: debugViewData,
            diagnosticsStream: runtimeViewAdapter.diagnosticsStream,
            initialDiagnostics: runtimeViewAdapter.initialDiagnostics,
          );
        },
        enterPictureInPicture: enterPictureInPicture,
        toggleDesktopMiniWindow: toggleDesktopMiniWindow,
        captureScreenshot: () => controlsAction.captureScreenshot(),
        refreshRoom:
            ({
              bool showFeedback = false,
              bool reloadPlayer = false,
              bool forcePlaybackRebind = true,
            }) {
              return refreshRoom(
                showFeedback: showFeedback,
                reloadPlayer: reloadPlayer,
                forcePlaybackRebind: forcePlaybackRebind,
              );
            },
        leaveRoomCleanup: leaveRoom,
        switchQuality: (snapshot, quality) =>
            controlsAction.switchQuality(snapshot, quality),
        switchLine: controlsAction.switchLine,
        resolveScheduledCloseAt: () => controlsAction.scheduledCloseAt,
        setAutoCloseTimer: controlsAction.setAutoCloseTimer,
        openFollowRoomTransition: (entry, {required commitNavigation, required showMessage}) {
          return followRoomTransition.openFollowRoom(
            leavingRoom: _state.isLeavingRoom,
            commitNavigation: commitNavigation,
            showMessage: showMessage,
          );
        },
      ),
    );
  }

  ProviderId providerId;
  String roomId;
  final RoomPreviewDependencies dependencies;
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

  late final RoomChatViewportCoordinator chatViewport;
  late final RoomControlsActionCoordinator controlsAction;
  late final RoomFollowActionCoordinator followAction;
  late final RoomFollowRoomTransitionCoordinator followRoomTransition;
  late final RoomPageInteractionCoordinator pageInteraction;
  late final RoomFollowWatchlistController followWatchlist;
  late final RoomPanelController panel;
  late final PageController panelPageController;

  int _embeddedPlayerViewEpoch = 0;
  int get embeddedPlayerViewEpoch => _embeddedPlayerViewEpoch;

  void incrementEmbeddedPlayerViewEpoch() {
    _embeddedPlayerViewEpoch += 1;
    notifyListeners();
  }

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

  bool get _isActive => !_disposed && isMounted();
  RoomPageSessionState get state => _state;
  Future<RoomSessionLoadResult> get roomFuture => _roomFuture;
  int _roomFutureToken = 0;
  int _ancillaryLoadToken = 0;
  bool _forcePlaybackRebindOnNextResolvedRoomState = false;
  AppLifecycleState _lifecycleState;
  Completer<void>? _foregroundResumeCompleter;

  Future<RoomSessionLoadResult> startInitialLoad({String? preferredQualityId}) {
    final future = _trackRoomFuture(
      _waitForPendingRoomTeardownAndLoad(
        preferredQualityId: preferredQualityId,
      ),
    );
    _roomFuture = future;
    return future;
  }

  /// Stay on the same room page shell and retarget identity + session.
  /// Avoids tablet landscape side-panel flash from route replacement.
  Future<void> switchToRoomInPlace({
    required ProviderId nextProviderId,
    required String nextRoomId,
  }) async {
    if (!_isActive || _state.isLeavingRoom) {
      return;
    }
    if (nextProviderId == providerId && nextRoomId == roomId) {
      return;
    }
    if (_state.refreshInFlight) {
      trace('in-place room switch skipped refreshInFlight=true');
      return;
    }

    final previousProviderId = providerId;
    final previousRoomId = roomId;
    trace(
      'in-place room switch start '
      '${previousProviderId.value}/$previousRoomId -> '
      '${nextProviderId.value}/$nextRoomId',
    );

    fullscreenSessionController.prepareForInPlaceFollowRoomSwitch();
    // Keep the previous playback surface until the next room source binds so
    // fullscreen does not sit on a long black frame during network load.
    // Defer notify until roomFuture is swapped (single rebuild).
    if (!_disposed) {
      _state = _state.copyWith(refreshInFlight: true);
    }
    _forcePlaybackRebindOnNextResolvedRoomState = true;

    try {
      await danmakuController.closeSession();
      if (!_isActive) {
        return;
      }
      danmakuController.clearFeed();

      dependencies.llhlsProxyRegistry.unregisterSession(
        roomId: previousRoomId,
      );
      providerId = nextProviderId;
      roomId = nextRoomId;
      sessionController.retargetRoom(
        providerId: nextProviderId,
        roomId: nextRoomId,
      );
      danmakuController.retargetRoom(providerId: nextProviderId);
      ancillaryController.retargetRoom(providerId: nextProviderId);
      playbackController.providerId = nextProviderId;
      controlsAction.context.providerId = nextProviderId;
      controlsAction.context.roomId = nextRoomId;
      dependencies.llhlsProxyRegistry.registerSession(
        providerId: nextProviderId,
        roomId: nextRoomId,
      );

      // Keep previous latestLoadedState / last video frame while loading.
      final future = _trackRoomFuture(_load());
      _roomFuture = future;
      if (!_disposed) {
        notifyListeners();
      }
      await future;
      if (!_isActive) {
        return;
      }
      trace(
        'in-place room switch complete '
        '${nextProviderId.value}/$nextRoomId',
      );
    } catch (error, stackTrace) {
      trace('in-place room switch failed error=$error');
      AppLog.instance.error(
        'room',
        '[RoomPreview/${nextProviderId.value}/$nextRoomId] '
            'in-place room switch failed',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    } finally {
      if (_isActive) {
        _replaceState(_state.copyWith(refreshInFlight: false));
      }
    }
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
      frequencyWindowSeconds: preferences.frequencyWindowSeconds,
      maxFrequency: preferences.maxFrequency,
    );
  }

  void applyCurrentFollowed(bool followed) {
    if (_state.isFollowed == followed) {
      return;
    }
    _replaceState(_state.copyWith(isFollowed: followed));
  }

  void handleLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    if (state == AppLifecycleState.resumed) {
      _completeForegroundResumeWaiter();
    }
  }

  void updateDanmakuOverlayVisible(bool visible) {
    if (_state.showDanmakuOverlay == visible) {
      return;
    }
    _replaceState(_state.copyWith(showDanmakuOverlay: visible));
  }

  void updateVolume(double value) {
    final normalized = value.clamp(0.0, 1.0);
    if (_state.volume == normalized) {
      return;
    }
    _replaceState(_state.copyWith(volume: normalized));
    // Gesture volume previously only updated UI state; system AudioManager on
    // ChromeOS ARC often no-ops, so player volume must be driven here.
    unawaited(dependencies.playerRuntime.setVolume(normalized));
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
      frequencyWindowSeconds: _state.danmakuPreferences.frequencyWindowSeconds,
      maxFrequency: _state.danmakuPreferences.maxFrequency,
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

  Future<void> waitForPlayerBindingToFinish({required String reason}) {
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
    // Single notify: refresh flag + roomFuture swap (avoid double rebuild).
    if (!_disposed) {
      _state = _state.copyWith(refreshInFlight: true);
    }
    final previousFuture = _roomFuture;
    final future = _trackRoomFuture(
      reloadPlayer
          ? _load(
              preferredQualityId: _state.playbackSession.selectedQuality?.id,
            )
          : _refreshRoomData(
              previousFuture: previousFuture,
              preferredQualityId: _state.playbackSession.selectedQuality?.id,
            ),
    );
    _roomFuture = future;
    if (!_disposed) {
      notifyListeners();
    }
    danmakuController.clearFeed();
    try {
      await future;
    } catch (_) {
      if (_isActive) {
        rethrow;
      }
    } finally {
      if (_isActive) {
        _replaceState(_state.copyWith(refreshInFlight: false));
      }
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
        rethrow;
      }
    }
  }

  Future<void> cleanupPlaybackOnLeave() {
    trace('cleanup playback coordinator queued');
    return sessionController.dependencies.playerRuntime.serializeRoomTeardown(
      () async {
        trace('cleanup playback coordinator start');
        await waitForPlayerBindingToFinish(reason: 'cleanup playback');
        await fullscreenSessionController.cleanupPlaybackOnLeave();
        await danmakuController.closeSession();
        trace('cleanup playback coordinator complete');
      },
    );
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

  Future<bool> _bindPlaybackSourceWithRecovery({
    required PlaybackSource playbackSource,
    required String label,
    bool autoPlay = false,
    Duration autoPlayDelay = Duration.zero,
    PlaybackSource? currentPlaybackSource,
    bool preferFreshBackendBeforeFirstSetSource = false,
    bool Function()? shouldAbortRetry,
  }) {
    return playbackController.bindPlaybackSource(
      playbackSource: playbackSource,
      label: label,
      autoPlay: autoPlay,
      autoPlayDelay: autoPlayDelay,
      currentPlaybackSource: currentPlaybackSource,
      preferFreshBackendBeforeFirstSetSource:
          preferFreshBackendBeforeFirstSetSource,
      shouldAbortRetry: shouldAbortRetry,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _roomFutureToken += 1;
    _ancillaryLoadToken += 1;
    _completeForegroundResumeWaiter();
    sessionController.clearCurrent();

    if (shouldSessionCoordinatorFanOutChildNotify(
      RoomSessionChildNotifySource.panelSelection,
    )) {
      panel.removeListener(notifyListeners);
    }
    panel.dispose();
    panelPageController.dispose();
    if (shouldSessionCoordinatorFanOutChildNotify(
      RoomSessionChildNotifySource.followWatchlist,
    )) {
      followWatchlist.listenable.removeListener(notifyListeners);
    }
    followWatchlist.dispose();
    chatViewport.dispose();
    if (shouldSessionCoordinatorFanOutChildNotify(
      RoomSessionChildNotifySource.controlsAction,
    )) {
      controlsAction.removeListener(notifyListeners);
    }
    controlsAction.dispose();
    followRoomTransition.removeListener(notifyListeners);
    followRoomTransition.dispose();

    super.dispose();
  }

  Future<RoomSessionLoadResult> _load({String? preferredQualityId}) async {
    final shouldContinue = await _waitForForegroundBeforeRoomLoad();
    if (!shouldContinue) {
      return _cancelledRoomLoadFuture();
    }
    return sessionController.load(preferredQualityId: preferredQualityId);
  }

  Future<RoomSessionLoadResult> _waitForPendingRoomTeardownAndLoad({
    String? preferredQualityId,
  }) async {
    final runtime = sessionController.dependencies.playerRuntime;
    if (runtime.hasPendingRoomTeardown) {
      trace('load waiting for pending cleanup');
      await runtime.waitForPendingRoomTeardown();
      trace('load pending cleanup released');
    }
    return _load(preferredQualityId: preferredQualityId);
  }

  Future<RoomSessionLoadResult> _trackRoomFuture(
    Future<RoomSessionLoadResult> future,
  ) {
    final token = ++_roomFutureToken;
    return future.then(
      (state) async {
        if (_isActive && token == _roomFutureToken) {
          await _handleResolvedRoomState(state);
        }
        return state;
      },
      onError: (Object error, StackTrace stackTrace) {
        if (_isActive && token == _roomFutureToken) {
          _handleRoomLoadFailure();
          throw error;
        }
        return Future<RoomSessionLoadResult>.error(error, stackTrace);
      },
    );
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
      frequencyWindowSeconds: danmakuPreferences.frequencyWindowSeconds,
      maxFrequency: danmakuPreferences.maxFrequency,
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
      'room session applied playback=${summarizePlaybackSource(_state.playbackSession.playbackSource)} '
      'quality=${next.playbackQuality.id}/${next.playbackQuality.label}',
    );
  }

  void _scheduleAncillaryLoad({required LoadedRoomSnapshot snapshot}) {
    final token = ++_ancillaryLoadToken;
    _replaceState(_state.copyWith(ancillaryLoading: true));
    unawaited(_loadAncillaryRoomState(token: token, snapshot: snapshot));
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
    _replaceState(
      _state.copyWith(isFollowed: result.isFollowed, ancillaryLoading: false),
    );
    if (!_isActive || token != _ancillaryLoadToken) {
      await result.danmakuSession?.disconnect();
      return;
    }
    await danmakuController.bindSession(
      activeRoomDetail: snapshot.detail,
      session: result.danmakuSession,
    );
    if (!_isActive || token != _ancillaryLoadToken) {
      return;
    }
  }

  Future<RoomSessionLoadResult> _refreshRoomData({
    required Future<RoomSessionLoadResult> previousFuture,
    String? preferredQualityId,
  }) async {
    final shouldContinue = await _waitForForegroundBeforeRoomLoad();
    if (!shouldContinue) {
      return _cancelledRoomLoadFuture();
    }
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
    try {
      return await sessionController.reload(
        preferredQualityId: preferredQualityId,
      );
    } on ProviderParseException catch (error) {
      final current = sessionController.current;
      final hasCurrentPlayback =
          current?.snapshot.hasPlayback == true && current?.resolved != null;
      if (providerId == ProviderId.youtube && hasCurrentPlayback) {
        _forcePlaybackRebindOnNextResolvedRoomState = false;
        trace(
          'refresh retained current youtube playback after reload failure: ${error.message}',
        );
        return current!;
      }
      rethrow;
    }
  }

  Future<bool> _waitForForegroundBeforeRoomLoad() async {
    while (_isActive && _lifecycleState != AppLifecycleState.resumed) {
      final waitingForState = _lifecycleState;
      trace('load waiting for resumed lifecycle state=${waitingForState.name}');
      final completer = _foregroundResumeCompleter ??= Completer<void>();
      await completer.future;
      if (_isActive) {
        trace('load resumed lifecycle released');
      }
    }
    return _isActive;
  }

  Future<RoomSessionLoadResult> _cancelledRoomLoadFuture() {
    final latest = _state.latestLoadedState;
    if (latest != null) {
      return Future<RoomSessionLoadResult>.value(latest);
    }
    return Future<RoomSessionLoadResult>.error(
      const RoomSessionCancelledException(),
    );
  }

  void _completeForegroundResumeWaiter() {
    final completer = _foregroundResumeCompleter;
    _foregroundResumeCompleter = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
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

  LivePlayQuality _effectiveQualityOf(RoomSessionLoadResult state) {
    return resolveEffectiveQualityOfRoomState(
      state: state,
      selectedQuality: _state.playbackSession.selectedQuality,
      effectiveQuality: _state.playbackSession.effectiveQuality,
    );
  }

  void _replaceState(RoomPageSessionState next) {
    if (_disposed) {
      return;
    }
    final previous = _state;
    _state = next;
    if (shouldNotifyRoomPageSessionListeners(
      previous: previous,
      next: next,
    )) {
      notifyListeners();
    }
  }
}

/// Whether a session state transition should fan into page rebuild listeners.
///
/// Ignores bootstrap-only [RoomPlaybackSessionState] pending fields that the
/// room page does not read (pendingPlaybackSource / Available / AutoPlay).
@visibleForTesting
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
