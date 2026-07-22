import 'dart:async';
import 'dart:ui' as ui;

import 'package:floating/floating.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:nolive_app/src/features/room/application/room_ancillary_controller.dart';
import 'package:nolive_app/src/features/room/application/room_follow_watchlist_controller.dart';
import 'package:nolive_app/src/features/room/application/load_room_use_case.dart';
import 'package:nolive_app/src/features/room/application/resolve_play_source_use_case.dart';
import 'package:nolive_app/src/features/room/application/room_preview_dependencies.dart';
import 'package:nolive_app/src/features/room/application/room_session_controller.dart';
import 'package:nolive_app/src/features/room/presentation/room_danmaku_controller.dart';
import 'package:nolive_app/src/features/room/presentation/room_preview_runtime.dart';
import 'package:nolive_app/src/features/room/presentation/room_controls_presentation_helpers.dart';
import 'package:nolive_app/src/features/room/presentation/room_controls_view_data.dart';
import 'package:nolive_app/src/features/room/presentation/room_fullscreen_runtime_context.dart';
import 'package:nolive_app/src/features/room/presentation/room_fullscreen_session_controller.dart';
import 'package:nolive_app/src/features/room/presentation/room_gesture_ui_state.dart';
import 'package:nolive_app/src/features/room/presentation/room_panel_controller.dart';
import 'package:nolive_app/src/features/room/presentation/room_page_rebuild_scope.dart';
import 'package:nolive_app/src/features/room/presentation/room_page_session_coordinator.dart';
import 'package:nolive_app/src/features/room/presentation/room_page_ui_effects.dart';
import 'package:nolive_app/src/features/room/presentation/room_player_runtime_observer.dart';
import 'package:nolive_app/src/features/room/presentation/room_generic_line_failover.dart';
import 'package:nolive_app/src/features/room/presentation/room_playback_controller.dart';
import 'package:nolive_app/src/features/room/presentation/room_playback_session_state.dart';
import 'package:nolive_app/src/features/room/presentation/room_preview_page_chat_panels.dart';
import 'package:nolive_app/src/shared/application/room_diagnostics.dart';
import 'package:flutter/services.dart';
import 'package:nolive_app/src/features/room/presentation/room_preview_page_controls.dart';
import 'package:nolive_app/src/features/room/presentation/room_preview_page_danmaku.dart';
import 'package:nolive_app/src/features/room/presentation/room_preview_page_follow_actions.dart';
import 'package:nolive_app/src/features/room/presentation/room_preview_page_fullscreen.dart';
import 'package:nolive_app/src/features/room/presentation/room_preview_page_player_surface.dart';
import 'package:nolive_app/src/features/room/presentation/room_preview_page_sections.dart';
import 'package:nolive_app/src/features/room/presentation/room_preview_page_section_widgets.dart';
import 'package:nolive_app/src/features/room/presentation/room_runtime_helper_contexts.dart';
import 'package:nolive_app/src/features/room/presentation/room_runtime_view_adapter.dart';
import 'package:nolive_app/src/features/room/presentation/room_twitch_recovery_controller.dart';
import 'package:nolive_app/src/features/room/presentation/room_view_ui_state.dart';
import 'package:nolive_app/src/shared/domain/follow_watch_entry.dart';

import 'package:nolive_app/src/features/settings/application/manage_danmaku_preferences_use_case.dart';
import 'package:nolive_app/src/features/settings/application/manage_player_preferences_use_case.dart';
import 'package:nolive_app/src/features/settings/application/manage_room_ui_preferences_use_case.dart';
import 'package:nolive_app/src/shared/application/app_log.dart';
import 'package:nolive_app/src/shared/presentation/app_feedback.dart';

export 'room_playback_controller.dart'
    show
        shouldAttemptMdkBackendRefreshAfterSetSource,
        shouldForcePlaybackBootstrap,
        shouldPreRefreshMdkBackendBeforeSameSourceRebind,
        resolveMdkTextureRecoveryRetryDelay;
export 'room_follow_room_transition_coordinator.dart'
    show shouldResetMdkBeforeFullscreenFollowRoomSwitch;
export 'room_panel_controller.dart' show shouldSynchronizeRoomPanelPage;
export 'room_player_runtime_observer.dart'
    show
        formatPlayerDiagnosticsSummary,
        resolvePlayerDiagnosticsSourceSignature;
export 'room_preview_page_player_surface.dart'
    show
        resolveEmbeddedPlayerLifecycleViewFlags,
        resolveRoomPlayerPosterBackdropVisibility,
        resolveRoomPlayerWaitingForFirstFrame,
        resolveRoomHasRenderedVideo,
        shouldKeepRoomLoadingShellUntilFirstFrame,
        resolveFriendlyPlayerErrorMessage;
export 'room_page_rebuild_scope.dart'
    show
        RoomPreviewDisposePlan,
        RoomPreviewHeavyDisposeHooks,
        RoomPreviewHeavyDisposeStep,
        RoomSessionChildNotifySource,
        planRoomPreviewDispose,
        playerStateHasFirstFrameProgress,
        runRoomPreviewHeavyControllerDispose,
        shouldForceRoomPageRebuildForVideoSizeChange,
        shouldNotifyFullscreenSessionListeners,
        shouldScheduleFullRoomPageRebuildForPlayerState,
        shouldScheduleFullRoomPageRebuildForSessionChild,
        shouldSessionCoordinatorFanOutChildNotify;

@visibleForTesting
bool shouldCleanupPlaybackOnRoomPreviewDispose({
  required bool preserveRoomTransitionOnDispose,
  required bool leavingRoom,
}) {
  return !preserveRoomTransitionOnDispose && !leavingRoom;
}

@visibleForTesting
bool shouldWaitForRenderedPlayerSurfacePaint(
  RenderRepaintBoundary boundary, {
  bool debugMode = kDebugMode,
}) {
  if (!debugMode) {
    return false;
  }
  return boundary.debugNeedsPaint;
}

class RoomPreviewPage extends StatefulWidget {
  const RoomPreviewPage({
    required this.dependencies,
    required this.providerId,
    required this.roomId,
    this.startInFullscreen = false,
    super.key,
  });

  final RoomPreviewDependencies dependencies;
  final ProviderId providerId;
  final String roomId;
  final bool startInFullscreen;

  @override
  State<RoomPreviewPage> createState() => _RoomPreviewPageState();
}

class _RoomPreviewPageState extends State<RoomPreviewPage>
    with WidgetsBindingObserver {
  late final RoomPreviewRuntime _roomRuntime;
  late final RoomFullscreenSessionController _fullscreenSessionController;
  late final RoomPageUiEffects _pageUiEffects;
  late final RoomPageSessionCoordinator _pageSessionCoordinator;
  late final RoomPlayerRuntimeObserver _playerRuntimeObserver;
  late final RoomPlaybackController _playbackController;
  late final RoomRuntimeViewAdapter _runtimeViewAdapter;
  late final RoomTwitchRecoveryController _roomTwitchRecoveryController;
  RoomAncillaryController get _roomAncillaryController =>
      _roomRuntime.ancillary;
  RoomDanmakuController get _roomDanmakuController => _roomRuntime.danmaku;
  RoomSessionController get _roomSessionController => _roomRuntime.session;
  final GlobalKey _playerSurfaceCaptureKey = GlobalKey();
  bool _darkThemeActive = false;
  Size? _inlinePlayerViewportSize;
  bool _pageRebuildQueued = false;
  int _embeddedPlayerViewEpoch = 0;
  PlayerState? _currentPlayerState;
  RoomDanmakuState? _lastDanmakuStateForRebuild;
  bool _hasPageSessionCoordinator = false;
  final RoomGenericLineFailoverController _genericLineFailover =
      RoomGenericLineFailoverController();
  final RoomTerminalPlayReloadBudget _terminalPlayReloadBudget =
      RoomTerminalPlayReloadBudget();
  String? _terminalPlayReloadRoomKey;
  /// True after this room/source has reached [PlaybackStatus.playing] at least once.
  /// Used so mid-stream TCP glitches are not treated as hard-open.
  bool _playbackHasReachedPlaying = false;

  Future<RoomSessionLoadResult> get _future =>
      _pageSessionCoordinator.roomFuture;
  RoomPageSessionState get _pageSessionState => _pageSessionCoordinator.state;

  bool get _supportsPlayerCapture => _runtimeViewAdapter.supportsScreenshot;

  RoomUiPreferences get _roomUiPreferences =>
      _pageSessionState.roomUiPreferences;

  RoomFollowWatchlistState get _followWatchlistState =>
      _pageSessionCoordinator.followWatchlist.current;

  RoomDanmakuState get _danmakuState => _roomDanmakuController.current;

  DanmakuSession? get _danmakuSession => _danmakuState.session;

  ValueListenable<List<LiveMessage>> get _messagesNotifier =>
      _roomDanmakuController.messages;

  ValueListenable<List<LiveMessage>> get _superChatMessagesNotifier =>
      _roomDanmakuController.superChats;

  ValueListenable<List<LiveMessage>> get _playerSuperChatMessagesNotifier =>
      _roomDanmakuController.playerSuperChats;

  RoomPlaybackSessionState get _playbackSession =>
      _pageSessionState.playbackSession;

  bool get _isFollowed => _pageSessionState.isFollowed;

  PlayerPreferences get _playerPreferences =>
      _pageSessionState.playerPreferences;

  DanmakuPreferences get _danmakuPreferences =>
      _pageSessionState.danmakuPreferences;

  bool get _showDanmakuOverlay => _pageSessionState.showDanmakuOverlay;

  bool get _autoFullscreenEnabled =>
      _playerPreferences.androidAutoFullscreenEnabled;

  bool get _backgroundAutoPauseEnabled =>
      _playerPreferences.androidBackgroundAutoPauseEnabled;

  bool get _pipHideDanmakuEnabled =>
      _playerPreferences.androidPipHideDanmakuEnabled;

  double get _volume => _pageSessionState.volume;

  PlayerScaleMode get _scaleMode => _playerPreferences.scaleMode;

  double get _chatTextSize => _roomUiPreferences.chatTextSize;

  double get _chatTextGap => _roomUiPreferences.chatTextGap;

  bool get _chatBubbleStyle => _roomUiPreferences.chatBubbleStyle;

  bool get _showPlayerSuperChat => _roomUiPreferences.showPlayerSuperChat;

  int get _playerSuperChatDisplaySeconds =>
      _roomUiPreferences.playerSuperChatDisplaySeconds;

  bool get _ancillaryLoading => _pageSessionState.ancillaryLoading;

  bool get _isLeavingRoom => _pageSessionState.isLeavingRoom;

  RoomViewUiState get _viewUiState => _fullscreenSessionController.viewUiState;

  RoomGestureUiState get _gestureUiState =>
      _fullscreenSessionController.gestureUiState;

  bool get _isFullscreen => _viewUiState.isFullscreen;

  bool get _fullscreenBootstrapPending =>
      _viewUiState.fullscreenBootstrapPending;

  bool get _desktopMiniWindowActive => _viewUiState.desktopMiniWindowActive;

  bool get _showInlinePlayerChrome => _viewUiState.showInlinePlayerChrome;

  bool get _showFullscreenChrome => _viewUiState.showFullscreenChrome;

  bool get _showFullscreenLockButton => _viewUiState.showFullscreenLockButton;

  bool get _lockFullscreenControls => _viewUiState.lockFullscreenControls;

  bool get _pipSupported => _viewUiState.pipSupported;

  bool get _showFullscreenFollowDrawer =>
      _viewUiState.showFullscreenFollowDrawer;

  LivePlayQuality? get _selectedQuality => _playbackSession.selectedQuality;

  LivePlayQuality? get _effectiveQuality => _playbackSession.effectiveQuality;

  String? get _gestureTipText => _gestureUiState.tipText;

  RoomPanel get _selectedPanel => _pageSessionCoordinator.panel.selectedPanel;

  PlaybackSource? get _playbackSource => _playbackSession.playbackSource;

  List<LivePlayUrl> get _playUrls => _playbackSession.playUrls;

  bool get _roomPlaybackAvailable => _playbackSession.playbackAvailable;

  bool get _playerBindingInFlight => _playbackController.rebindInFlight;

  Key get _embeddedPlayerViewKey =>
      GlobalObjectKey('room-embedded-player-$_embeddedPlayerViewEpoch');

  LiveRoomDetail? get _activeRoomDetail => _playbackSession.activeRoomDetail;

  ProviderId get _activeProviderId => _pageSessionCoordinator.providerId;

  String get _activeRoomId => _pageSessionCoordinator.roomId;

  bool get _suspendEmbeddedPlayerForFollowRoomTransition =>
      _pageSessionCoordinator
          .followRoomTransition
          .suspendEmbeddedPlayerForTransition;

  bool get _supportsDesktopMiniWindow {
    return _fullscreenSessionController.supportsDesktopMiniWindow;
  }

  void _roomTrace(String message) {
    // Prefer live session identity after in-place follow switches.
    final providerId = _hasPageSessionCoordinator
        ? _pageSessionCoordinator.providerId
        : widget.providerId;
    final roomId = _hasPageSessionCoordinator
        ? _pageSessionCoordinator.roomId
        : widget.roomId;
    final prefix = '[RoomPreview/${providerId.value}/$roomId]';
    AppLog.instance.info('room', '$prefix $message');
    if (!kDebugMode) {
      return;
    }
    debugPrint('$prefix $message');
  }

  Future<void> _exitFullscreenIfNeeded() async {
    if (_isFullscreen) {
      await _exitFullscreen();
    }
  }

  LivePlayQuality _requestedQualityOf(RoomSessionLoadResult state) {
    return resolveRequestedQualityOfRoomState(
      state: state,
      selectedQuality: _selectedQuality,
    );
  }

  LivePlayQuality _effectiveQualityOf(RoomSessionLoadResult state) {
    return resolveEffectiveQualityOfRoomState(
      state: state,
      selectedQuality: _selectedQuality,
      effectiveQuality: _effectiveQuality,
    );
  }

  bool _hasQualityFallback(RoomSessionLoadResult state) {
    final requested = _requestedQualityOf(state);
    final effective = _effectiveQualityOf(state);
    return requested.id != effective.id || requested.label != effective.label;
  }

  String _qualityBadgeLabel(RoomSessionLoadResult state) {
    final requested = _requestedQualityOf(state);
    final effective = _effectiveQualityOf(state);
    if (!_hasQualityFallback(state)) {
      return effective.label;
    }
    return '${requested.label} · 实际${effective.label}';
  }

  String _lineLabelOf(
    List<LivePlayUrl> playUrls,
    PlaybackSource playbackSource,
  ) {
    return roomLineLabelOfPlayback(playUrls, playbackSource);
  }

  String _compactQualityLabel(String label) {
    return compactRoomQualityLabel(label);
  }

  String _compactLineLabel(String label) {
    return compactRoomLineLabel(label);
  }

  RoomLoadingShellViewData _loadingShellViewData({
    required ProviderDescriptor? descriptor,
    LiveRoomDetail? room,
  }) {
    final resolvedRoom = room ?? _activeRoomDetail;
    final providerLabel = normalizeDisplayText(
      descriptor?.displayName ?? _activeProviderId.value,
    );
    final streamerName = normalizeDisplayText(resolvedRoom?.streamerName);
    final avatarTextSource = streamerName.isEmpty
        ? providerLabel
        : streamerName;
    final avatarLabel = avatarTextSource.isEmpty
        ? '?'
        : avatarTextSource.substring(0, 1).toUpperCase();
    return RoomLoadingShellViewData(
      providerLabel: providerLabel,
      roomTitle: normalizeDisplayText(resolvedRoom?.title).isEmpty
          ? '房间号 $_activeRoomId'
          : normalizeDisplayText(resolvedRoom?.title),
      streamerName: streamerName,
      avatarLabel: avatarLabel,
      posterUrl: resolvedRoom?.keyframeUrl ?? resolvedRoom?.coverUrl,
    );
  }

  RoomSectionsViewData _sectionsViewData({
    required RoomSessionLoadResult state,
    required LiveRoomDetail room,
    required ProviderDescriptor? descriptor,
  }) {
    final providerLabel = descriptor?.displayName ?? widget.providerId.value;
    final streamerName = normalizeDisplayText(room.streamerName);
    final viewerLabel = room.viewerCount == null
        ? '-'
        : room.viewerCount! >= 10000
        ? '${(room.viewerCount! / 10000).toStringAsFixed(room.viewerCount! >= 100000 ? 0 : 1)}万'
        : '${room.viewerCount!}';
    final hasPdkeyHealthAlert = state.resolved?.hasPdkeyHealthAlert ?? false;
    return RoomSectionsViewData(
      providerLabel: providerLabel,
      streamerName: streamerName,
      streamerAvatarUrl: room.streamerAvatarUrl,
      roomLive: room.isLive,
      viewerLabel: viewerLabel,
      isFollowed: _isFollowed,
      statusPresentation: resolveRoomChaturbateStatusPresentation(
        room,
        hasPdkeyHealthAlert: hasPdkeyHealthAlert,
      ),
      qualityBadgeLabel: _hasQualityFallback(state)
          ? _qualityBadgeLabel(state)
          : null,
    );
  }

  RoomPlayerSurfaceViewData _playerSurfaceViewData({
    required LiveRoomDetail room,
    required bool hasPlayback,
    required bool embedPlayer,
    required bool fullscreen,
    String? inlineQualityLabel,
    String? inlineLineLabel,
  }) {
    final hasPdkeyHealthAlert =
        _roomSessionController.current?.resolved?.hasPdkeyHealthAlert ?? false;
    final statusPresentation = resolveRoomChaturbateStatusPresentation(
      room,
      hasPdkeyHealthAlert: hasPdkeyHealthAlert,
    );
    final diagnostics = widget.dependencies.playerRuntime.currentDiagnostics;
    final playerState = _currentPlayerState;
    final hasRenderedVideo = resolveRoomHasRenderedVideo(
      videoWidth: diagnostics.width,
      videoHeight: diagnostics.height,
      position: playerState?.position ?? Duration.zero,
      buffered: playerState?.buffered ?? Duration.zero,
      status: playerState?.status,
    );
    return RoomPlayerSurfaceViewData(
      room: room,
      hasPlayback: hasPlayback,
      embedPlayer: embedPlayer,
      fullscreen: fullscreen,
      suspendEmbeddedPlayer: _suspendEmbeddedPlayerForFollowRoomTransition,
      supportsEmbeddedView: _runtimeViewAdapter.supportsEmbeddedView,
      showDanmakuOverlay: _showDanmakuOverlay,
      showPlayerSuperChat: _showPlayerSuperChat,
      showInlinePlayerChrome: _showInlinePlayerChrome,
      playerBindingInFlight: _playerBindingInFlight,
      backendLabel: _runtimeViewAdapter.backendLabel,
      liveDurationLabel: formatRoomLiveDuration(room.startedAt),
      statusPresentation: statusPresentation,
      unavailableReason:
          statusPresentation?.description ?? '当前房间暂时没有公开播放流，请稍后刷新重试。',
      inlineQualityLabel: inlineQualityLabel,
      inlineLineLabel: inlineLineLabel,
      playbackStatus: _currentPlayerState?.status,
      playbackError: _currentPlayerState?.errorMessage,
      hasRenderedVideo: hasRenderedVideo,
    );
  }

  RoomFullscreenOverlayViewData _fullscreenOverlayViewData({
    required RoomSessionLoadResult state,
    required LiveRoomDetail room,
    required PlaybackSource playbackSource,
    required List<LivePlayUrl> playUrls,
  }) {
    final liveDuration = formatRoomLiveDuration(room.startedAt);
    final lineLabel =
        playUrls
            .firstWhere(
              (item) => item.url == playbackSource.url.toString(),
              orElse: () => playUrls.first,
            )
            .lineLabel ??
        '线路';
    return RoomFullscreenOverlayViewData(
      playerSurfaceData: _playerSurfaceViewData(
        room: room,
        hasPlayback: true,
        embedPlayer: true,
        fullscreen: true,
      ),
      danmakuPreferences: _danmakuPreferences,
      title:
          '${normalizeDisplayText(room.title)} - ${normalizeDisplayText(room.streamerName)}',
      liveDuration: liveDuration,
      qualityLabel: _effectiveQualityOf(state).label,
      lineLabel: lineLabel,
      showChrome: _showFullscreenChrome,
      showLockButton: _showFullscreenLockButton,
      lockControls: _lockFullscreenControls,
      gestureTipText: _gestureTipText,
      pipSupported: _pipSupported,
      supportsDesktopMiniWindow: _supportsDesktopMiniWindow,
      desktopMiniWindowActive: _desktopMiniWindowActive,
      supportsPlayerCapture: _supportsPlayerCapture,
      showDanmakuOverlay: _showDanmakuOverlay,
    );
  }

  Widget _embeddedPlayerView(double? aspectRatio) {
    final lifecycleViewFlags = resolveEmbeddedPlayerLifecycleViewFlags(
      androidPlaybackBridgeSupported: widget
          .dependencies
          .fullscreenSessionPlatforms
          .androidPlaybackBridge
          .isSupported,
      backgroundAutoPauseEnabled: _backgroundAutoPauseEnabled,
    );
    return RepaintBoundary(
      key: _playerSurfaceCaptureKey,
      child: _runtimeViewAdapter.buildEmbeddedView(
        key: _embeddedPlayerViewKey,
        aspectRatio: aspectRatio,
        fit: fitForRoomScaleMode(_scaleMode),
        pauseUponEnteringBackgroundMode:
            lifecycleViewFlags.pauseUponEnteringBackgroundMode,
        resumeUponEnteringForegroundMode:
            lifecycleViewFlags.resumeUponEnteringForegroundMode,
      ),
    );
  }

  Future<Uint8List?> _captureRenderedPlayerSurface() async {
    var boundaryContext = _playerSurfaceCaptureKey.currentContext;
    if (!mounted || boundaryContext == null) {
      return null;
    }
    var boundary = boundaryContext.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) {
      return null;
    }
    var view = View.maybeOf(boundaryContext);
    if (shouldWaitForRenderedPlayerSurfacePaint(boundary)) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) {
        return null;
      }
      boundary =
          _playerSurfaceCaptureKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null ||
          !boundary.attached ||
          shouldWaitForRenderedPlayerSurfacePaint(boundary)) {
        return null;
      }
    }
    final pixelRatio =
        (view?.devicePixelRatio ??
                WidgetsBinding
                    .instance
                    .platformDispatcher
                    .views
                    .first
                    .devicePixelRatio)
            .clamp(1.0, 2.0)
            .toDouble();
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    try {
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  void _scheduleTwitchPlaybackRecovery({
    required LoadedRoomSnapshot snapshot,
    required PlaybackSource? playbackSource,
    required List<LivePlayUrl> playUrls,
    required LivePlayQuality selectedQuality,
  }) {
    unawaited(
      _roomTwitchRecoveryController.scheduleRecovery(
        providerId: widget.providerId,
        snapshot: snapshot,
        playbackSource: playbackSource,
        playUrls: playUrls,
        selectedQuality: selectedQuality,
        resolveCurrentQuality: () => _selectedQuality ?? selectedQuality,
        isMounted: () => mounted,
        switchQuality: _switchQuality,
        refreshPlaybackSource: _refreshPlaybackSource,
        switchLine: _switchLine,
      ),
    );
  }

  void _resolveFullscreenBootstrap({
    required bool roomLoaded,
    required bool playbackAvailable,
  }) {
    _fullscreenSessionController.handleResolvedRoomState(
      roomLoaded: roomLoaded,
      playbackAvailable: playbackAvailable,
    );
  }

  Future<void> _cancelPendingFullscreenBootstrap({
    required bool scheduleInlineChrome,
  }) {
    return _fullscreenSessionController.cancelPendingFullscreenBootstrap(
      scheduleInlineChrome: scheduleInlineChrome,
    );
  }

  Future<void> _enterFullscreen() {
    return _fullscreenSessionController.enterFullscreen();
  }

  Future<void> _exitFullscreen() async {
    if (_fullscreenBootstrapPending) {
      await _cancelPendingFullscreenBootstrap(scheduleInlineChrome: true);
      return;
    }
    await _fullscreenSessionController.exitFullscreen();
    unawaited(_waitForPlayerBindingToFinish(reason: 'exit fullscreen'));
  }

  Future<void> _restoreSystemUi() {
    return _fullscreenSessionController.restoreSystemUi();
  }

  Future<void> _setScreenAwake(bool enabled) {
    return _fullscreenSessionController.setScreenAwake(enabled);
  }

  void _scheduleInlineChromeAutoHide() {
    _fullscreenSessionController.scheduleInlineChromeAutoHide();
  }

  void _scheduleFullscreenChromeAutoHide() {
    _fullscreenSessionController.scheduleFullscreenChromeAutoHide();
  }

  void _toggleInlinePlayerChrome() {
    _fullscreenSessionController.toggleInlinePlayerChrome();
  }

  void _showInlinePlayerChromeTemporarily() {
    _fullscreenSessionController.showInlinePlayerChromeTemporarily();
  }

  Future<void> _enterPictureInPicture() {
    return _fullscreenSessionController.enterPictureInPicture();
  }

  Future<void> _toggleDesktopMiniWindow() {
    return _fullscreenSessionController.toggleDesktopMiniWindow();
  }

  Future<void> _exitDesktopMiniWindow() {
    return _fullscreenSessionController.exitDesktopMiniWindow();
  }

  Future<void> _handleVerticalDragStart(DragStartDetails details) {
    return _fullscreenSessionController.handleVerticalDragStart(details);
  }

  Future<void> _handleVerticalDragUpdate(DragUpdateDetails details) {
    return _fullscreenSessionController.handleVerticalDragUpdate(details);
  }

  Future<void> _handleVerticalDragEnd(DragEndDetails details) {
    return _fullscreenSessionController.handleVerticalDragEnd();
  }

  Future<void> _switchQuality(
    LoadedRoomSnapshot snapshot,
    LivePlayQuality quality, {
    bool resetTwitchRecoveryAttempts = true,
    LivePlayQuality? twitchStartupPromotionQuality,
  }) {
    return _pageSessionCoordinator.controlsAction.switchQuality(
      snapshot,
      quality,
      resetTwitchRecoveryAttempts: resetTwitchRecoveryAttempts,
      twitchStartupPromotionQuality: twitchStartupPromotionQuality,
    );
  }

  Future<void> _refreshPlaybackSource(
    LoadedRoomSnapshot snapshot,
    LivePlayQuality quality, {
    LivePlayQuality? twitchStartupPromotionQuality,
    bool resetTwitchRecoveryAttempts = false,
    PlaybackSource? preferredPlaybackSource,
    List<LivePlayUrl>? currentPlayUrls,
  }) {
    return _pageSessionCoordinator.controlsAction.refreshPlaybackSource(
      snapshot,
      quality,
      twitchStartupPromotionQuality: twitchStartupPromotionQuality,
      resetTwitchRecoveryAttempts: resetTwitchRecoveryAttempts,
      preferredPlaybackSource: preferredPlaybackSource,
      currentPlayUrls: currentPlayUrls,
    );
  }

  Future<void> _switchLine(
    LivePlayUrl playUrl, {
    bool resetTwitchRecoveryAttempts = true,
  }) {
    return _pageSessionCoordinator.controlsAction.switchLine(
      playUrl,
      resetTwitchRecoveryAttempts: resetTwitchRecoveryAttempts,
    );
  }

  Future<void> _shareRoomLink(LiveRoomDetail room) {
    return _pageSessionCoordinator.controlsAction.shareRoomLink(
      room: room,
      playbackSource: _playbackSource,
    );
  }

  Future<void> _captureScreenshot() {
    return _pageSessionCoordinator.controlsAction.captureScreenshot();
  }

  Widget _buildControlsPanel({
    required RoomSessionLoadResult state,
    required List<LivePlayUrl> playUrls,
    required PlaybackSource? playbackSource,
    required bool hasPlayback,
  }) {
    return RoomControlsPanel(
      wrapFlatTileScope: wrapRoomFlatTileScope,
      viewData: _buildControlsViewData(
        state: state,
        playUrls: playUrls,
        playbackSource: playbackSource,
        hasPlayback: hasPlayback,
      ),
      onOpenPlayerSettings:
          _pageSessionCoordinator.pageInteraction.openPlayerSettings,
      onShowQuality: () {
        unawaited(
          _pageSessionCoordinator.pageInteraction.showQualitySheet(state),
        );
      },
      onShowLine: () {
        unawaited(
          _pageSessionCoordinator.pageInteraction.showLineSheet(
            playUrls,
            playbackSource!,
          ),
        );
      },
      onCycleScaleMode: () {
        final modes = PlayerScaleMode.values;
        final index = modes.indexOf(_scaleMode);
        unawaited(_updateScaleMode(modes[(index + 1) % modes.length]));
      },
      onEnterPictureInPicture: () {
        unawaited(_enterPictureInPicture());
      },
      onToggleDesktopMiniWindow: () {
        unawaited(_toggleDesktopMiniWindow());
      },
      onCaptureScreenshot: () {
        unawaited(_captureScreenshot());
      },
      onShowDebugPanel: () {
        unawaited(
          _pageSessionCoordinator.pageInteraction.showPlayerDebugSheet(
            state,
            playbackSource,
          ),
        );
      },
      onUpdateChatTextSize: (next) {
        final preferences = _roomUiPreferences.copyWith(
          chatTextSize: next.clamp(12, 22).toDouble(),
        );
        unawaited(_updateRoomUiPreferences(preferences));
      },
      onUpdateChatTextGap: (next) {
        final preferences = _roomUiPreferences.copyWith(
          chatTextGap: next.clamp(0, 12).toDouble(),
        );
        unawaited(_updateRoomUiPreferences(preferences));
      },
      onUpdateChatBubbleStyle: (value) {
        unawaited(
          _updateRoomUiPreferences(
            _roomUiPreferences.copyWith(chatBubbleStyle: value),
          ),
        );
      },
      onUpdateShowPlayerSuperChat: (value) {
        unawaited(
          _updateRoomUiPreferences(
            _roomUiPreferences.copyWith(showPlayerSuperChat: value),
          ),
        );
      },
      onUpdatePlayerSuperChatDisplaySeconds: (next) {
        unawaited(
          _updateRoomUiPreferences(
            _roomUiPreferences.copyWith(
              playerSuperChatDisplaySeconds: next.clamp(3, 30),
            ),
          ),
        );
      },
      onOpenDanmakuShield:
          _pageSessionCoordinator.pageInteraction.openDanmakuShield,
      onOpenDanmakuSettings:
          _pageSessionCoordinator.pageInteraction.openDanmakuSettings,
      onShowAutoCloseSheet: () {
        unawaited(_pageSessionCoordinator.pageInteraction.showAutoCloseSheet());
      },
    );
  }

  RoomControlsViewData _buildControlsViewData({
    required RoomSessionLoadResult state,
    required List<LivePlayUrl> playUrls,
    required PlaybackSource? playbackSource,
    required bool hasPlayback,
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
      scaleModeLabel: labelOfRoomScaleMode(_scaleMode),
      pipSupported: _pipSupported,
      supportsDesktopMiniWindow: _supportsDesktopMiniWindow,
      desktopMiniWindowActive: _desktopMiniWindowActive,
      supportsPlayerCapture: _supportsPlayerCapture,
      scheduledCloseAt: _pageSessionCoordinator.controlsAction.scheduledCloseAt,
      chatTextSize: _chatTextSize.round(),
      chatTextGap: _chatTextGap.round(),
      chatBubbleStyle: _chatBubbleStyle,
      showPlayerSuperChat: _showPlayerSuperChat,
      playerSuperChatDisplaySeconds: _playerSuperChatDisplaySeconds,
    );
  }

  Future<void> _toggleFollow(LoadedRoomSnapshot snapshot) {
    return _pageSessionCoordinator.followAction.toggleCurrentRoomFollow(
      snapshot: snapshot,
      currentlyFollowed: _isFollowed,
      followPanelSelected: _selectedPanel == RoomPanel.follow,
    );
  }

  Widget _buildFollowPanel({required BuildContext context}) {
    return ListenableBuilder(
      listenable: _pageSessionCoordinator.followWatchlist.listenable,
      builder: (context, _) {
        final followState = _followWatchlistState;
        final watchlist =
            followState.watchlist ?? const FollowWatchlist(entries: []);
        return buildRoomFollowPanel(
          context: context,
          followState: followState,
          entries: _pageSessionCoordinator.followAction.buildEntryViewData(
            watchlist,
          ),
          onRefresh: () => _ensureFollowWatchlistLoaded(force: true),
          onOpenSettings: () {
            unawaited(
              _pageSessionCoordinator.pageInteraction.openFollowSettings(),
            );
          },
          onOpenEntry: (entry) {
            unawaited(
              _pageSessionCoordinator.followAction.openFollowRoom(entry),
            );
          },
        );
      },
    );
  }

  Widget _buildFullscreenFollowDrawer(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        _pageSessionCoordinator.followWatchlist.listenable,
        _fullscreenSessionController,
      ]),
      builder: (context, _) {
        final followState = _followWatchlistState;
        final watchlist =
            followState.watchlist ?? const FollowWatchlist(entries: []);
        return buildRoomFullscreenFollowDrawer(
          context: context,
          showDrawer: _showFullscreenFollowDrawer,
          followState: followState,
          entries: _pageSessionCoordinator.followAction.buildEntryViewData(
            watchlist,
          ),
          onClose: _fullscreenSessionController.hideFullscreenFollowDrawer,
          onOpenEntry: (entry) {
            unawaited(
              _pageSessionCoordinator.followAction.openFollowRoom(entry),
            );
          },
        );
      },
    );
  }

  void _openFullscreenFollowDrawer() {
    _fullscreenSessionController.openFullscreenFollowDrawer();
  }

  RoomLoadErrorPresentation _describeRoomLoadError(Object? error) {
    return describeRoomLoadError(error);
  }

  Future<void> _copyRoomLoadDiagnostic(Object? error) async {
    final text = buildRoomErrorDiagnostic(
      providerId: _activeProviderId,
      roomId: _activeRoomId,
      error: error,
      stackTrace: error is Error ? error.stackTrace : null,
      extra: 'detail=${error?.toString() ?? ''}',
    );
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) {
      return;
    }
    showAppSnackBar(context, '错误信息已复制');
  }

  /// Sync playlist identity without wiping retry/line on every stop.
  void _syncGenericLineFailoverState({PlaybackSource? currentSource}) {
    if (!shouldUseGenericMultiLineFailover(_activeProviderId)) {
      _genericLineFailover.clear();
      return;
    }
    final urls = _playUrls;
    if (urls.isEmpty) {
      _genericLineFailover.clear();
      return;
    }
    _genericLineFailover.ensureSession(
      playUrls: urls,
      currentSource: currentSource ?? _playbackSource,
      sourceBuilder: (line) {
        return playbackSourceFromLivePlayUrl(
          line,
          quality: _effectiveQuality ?? _selectedQuality,
          providerId: _activeProviderId,
        );
      },
    );
    // Terminal reload budget resets only on successful playing (see
    // onPlayerStateChanged) so a failed reloadRoom cannot clear the cap.
  }

  void _ensureTerminalPlayReloadBudgetForActiveRoom() {
    final key = '${_activeProviderId.value}/$_activeRoomId';
    if (_terminalPlayReloadRoomKey == key) {
      return;
    }
    _terminalPlayReloadRoomKey = key;
    _terminalPlayReloadBudget.reset();
    _playbackHasReachedPlaying = false;
  }

  Future<void> _handleUnexpectedPlaybackStop(PlayerState state) async {
    if (_isLeavingRoom ||
        _playerBindingInFlight ||
        _pageSessionState.refreshInFlight) {
      return;
    }
    _ensureTerminalPlayReloadBudgetForActiveRoom();
    // ensureSession (not reset): preserve retry/line across repeated stops.
    _syncGenericLineFailoverState(currentSource: state.source);
    final hardOpen = PlaybackFailoverPolicy.isHardOpenFailure(
      state.errorMessage,
      hasReachedPlaying: _playbackHasReachedPlaying,
    );
    if (shouldUseGenericMultiLineFailover(_activeProviderId) &&
        _genericLineFailover.canHandle) {
      // Loop lines until bind succeeds or terminal — bind false is not
      // "all CDNs exhausted" and must not jump to full play-source reload.
      while (_genericLineFailover.canHandle) {
        final step = _genericLineFailover.nextStep(
          errorMessage: state.errorMessage,
        );
        if (step == null) {
          break;
        }
        if (step.action == PlaybackFailoverAction.terminalFailure) {
          await _reloadPlaySourcesAfterTerminal(
            hardOpen: hardOpen,
            lineIndex: step.lineIndex,
          );
          return;
        }
        if (step.playbackSource == null) {
          continue;
        }
        _roomTrace(
          'generic multi-line failover action=${step.action.name} '
          'line=${step.lineIndex + 1}/${_genericLineFailover.lines.length} '
          'retry=${step.retryCount} '
          'hardOpen=$hardOpen',
        );
        if (step.delay > Duration.zero) {
          await Future<void>.delayed(step.delay);
        }
        if (!mounted ||
            _isLeavingRoom ||
            _pageSessionState.refreshInFlight) {
          return;
        }
        final bound = await _playbackController.bindPlaybackSource(
          playbackSource: step.playbackSource!,
          label: 'generic multi-line failover',
          autoPlay: true,
          currentPlaybackSource: state.source,
        );
        if (bound) {
          return;
        }
        _roomTrace(
          'generic multi-line failover bind failed '
          'line=${step.lineIndex + 1} — try next line',
        );
      }
    }
    if (hardOpen) {
      await _reloadPlaySourcesAfterTerminal(hardOpen: true);
      return;
    }
    await _pageSessionCoordinator.refreshRoom(
      showFeedback: false,
      reloadPlayer: false,
      forcePlaybackRebind: true,
    );
  }

  /// Full play-URL re-fetch after multi-line terminal (or hard-open fallthrough).
  ///
  /// Budget + growing delay prevent tight loops when every CDN is dead.
  /// Slot is spent only after preconditions still pass post-delay; abort refunds.
  Future<void> _reloadPlaySourcesAfterTerminal({
    required bool hardOpen,
    int? lineIndex,
  }) async {
    final delay = _terminalPlayReloadBudget.peekDelay();
    if (delay == null) {
      _roomTrace(
        'generic multi-line failover terminal budget exhausted '
        'used=${_terminalPlayReloadBudget.used} hardOpen=$hardOpen — stop',
      );
      return;
    }
    _roomTrace(
      'generic multi-line failover terminal '
      '${lineIndex == null ? '' : 'line=${lineIndex + 1}/${_genericLineFailover.lines.length} '}'
      'hardOpen=$hardOpen used=${_terminalPlayReloadBudget.used} '
      'delayMs=${delay.inMilliseconds} — waiting before reload',
    );
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    if (!mounted ||
        _isLeavingRoom ||
        _pageSessionState.refreshInFlight) {
      _roomTrace(
        'generic multi-line failover terminal reload aborted '
        'after delay (mounted=$mounted leaving=$_isLeavingRoom '
        'refreshInFlight=${_pageSessionState.refreshInFlight}) — no budget spend',
      );
      return;
    }
    final spent = _terminalPlayReloadBudget.consume();
    if (spent == null) {
      _roomTrace(
        'generic multi-line failover terminal budget exhausted after delay '
        'hardOpen=$hardOpen — stop',
      );
      return;
    }
    _roomTrace(
      'generic multi-line failover terminal reload '
      'reload=${_terminalPlayReloadBudget.used} hardOpen=$hardOpen',
    );
    _genericLineFailover.clear();
    await _pageSessionCoordinator.refreshRoom(
      showFeedback: false,
      reloadPlayer: true,
      forcePlaybackRebind: true,
    );
  }

  Future<void> _waitForPlayerBindingToFinish({required String reason}) {
    return _pageSessionCoordinator.waitForPlayerBindingToFinish(reason: reason);
  }

  void _clearMdkTextureRecoveryState() {
    _playbackController.resetRecoveryState();
  }

  Future<void> _resetEmbeddedPlayerViewAfterBackendRefresh(String label) async {
    if (!mounted) {
      _roomTrace('$label mdk embedded view reset skipped unmounted');
      return;
    }
    setState(() {
      _embeddedPlayerViewEpoch += 1;
    });
    _roomTrace(
      '$label mdk embedded view reset epoch=$_embeddedPlayerViewEpoch',
    );
    await WidgetsBinding.instance.endOfFrame;
  }

  void _handleFullscreenSessionChanged() {
    _markPageNeedsBuild();
  }

  void _handlePageSessionCoordinatorChanged() {
    _markPageNeedsBuild();
  }

  void _handlePlaybackControllerChanged() {
    _markPageNeedsBuild();
  }

  void _markPageNeedsBuild() {
    if (!mounted) {
      return;
    }
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_pageRebuildQueued) {
        return;
      }
      _pageRebuildQueued = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _pageRebuildQueued = false;
        if (!mounted) {
          return;
        }
        setState(() {});
      });
      return;
    }
    setState(() {});
  }

  void _handleDanmakuStateChanged() {
    if (!mounted) {
      return;
    }
    final next = _roomDanmakuController.current;
    final previous = _lastDanmakuStateForRebuild;
    _lastDanmakuStateForRebuild = next;
    if (previous == null ||
        shouldScheduleFullRoomPageRebuildForDanmakuState(
          previous: previous,
          next: next,
        )) {
      _markPageNeedsBuild();
    }
  }

  void _handleDanmakuMessagesChanged() {
    _pageSessionCoordinator.chatViewport.handleMessagesChanged(
      selectedPanel: _selectedPanel,
    );
  }

  @override
  void initState() {
    super.initState();
    widget.dependencies.llhlsProxyRegistry.registerSession(
      providerId: widget.providerId,
      roomId: widget.roomId,
    );
    final playerRuntime = widget.dependencies.playerRuntime;
    _currentPlayerState = playerRuntime.currentState;
    final fullscreenRuntime = RoomFullscreenRuntimeContext.fromPlayerRuntime(
      playerRuntime,
    );
    final runtimeObservation = RoomRuntimeObservationContext.fromPlayerRuntime(
      playerRuntime,
    );
    final runtimeInspection = RoomRuntimeInspectionContext.fromPlayerRuntime(
      playerRuntime,
    );
    final runtimeControl = RoomRuntimeControlContext.fromPlayerRuntime(
      playerRuntime,
    );
    WidgetsBinding.instance.addObserver(this);
    _pageUiEffects = RoomPageUiEffects(
      context: context,
      isMounted: () => mounted,
      wrapFlatTileScope: wrapRoomFlatTileScope,
    );
    _runtimeViewAdapter = RoomRuntimeViewAdapter(playerRuntime);
    _roomRuntime = RoomPreviewRuntime(
      dependencies: widget.dependencies,
      providerId: widget.providerId,
      roomId: widget.roomId,
      targetPlatform: defaultTargetPlatform,
      isWeb: kIsWeb,
      trace: _roomTrace,
    );
    _roomDanmakuController.listenable.addListener(_handleDanmakuStateChanged);
    _roomDanmakuController.messages.addListener(_handleDanmakuMessagesChanged);
    _roomTwitchRecoveryController = RoomTwitchRecoveryController(
      runtime: runtimeInspection,
      trace: _roomTrace,
    );
    _playbackController = RoomPlaybackController(
      playerRuntime: playerRuntime,
      providerId: widget.providerId,
      trace: _roomTrace,
      isMounted: () => mounted,
      resolveCurrentPlaybackSource: () => _playbackSource,
      resetEmbeddedPlayerViewAfterBackendRefresh:
          _resetEmbeddedPlayerViewAfterBackendRefresh,
      waitForInitialEmbeddedSurfaceBootstrap:
          widget.dependencies.isLiveMode &&
          defaultTargetPlatform == TargetPlatform.android &&
          playerRuntime.supportsEmbeddedView,
    );
    _playbackController.addListener(_handlePlaybackControllerChanged);
    _fullscreenSessionController = RoomFullscreenSessionController(
      startInFullscreen: widget.startInFullscreen,
      bindings: RoomFullscreenSessionBindings(
        runtime: fullscreenRuntime,
        trace: _roomTrace,
        showMessage: _pageUiEffects.showMessage,
        ensureFollowWatchlistLoaded: () => _ensureFollowWatchlistLoaded(),
        resolveDarkThemeActive: () => _darkThemeActive,
        resolveBackgroundAutoPauseEnabled: () => _backgroundAutoPauseEnabled,
        resolvePipHideDanmakuEnabled: () => _pipHideDanmakuEnabled,
        resolveDanmakuOverlayVisible: () => _showDanmakuOverlay,
        updateDanmakuOverlayVisible: (visible) {
          _pageSessionCoordinator.updateDanmakuOverlayVisible(visible);
        },
        resolveVolume: () => _volume,
        updateVolume: (value) {
          _pageSessionCoordinator.updateVolume(value);
        },
        resolvePipAspectRatio: () {
          final size = _inlinePlayerViewportSize;
          final aspectSize = size != null && size.width > 0 && size.height > 0
              ? size
              : const Size(16, 9);
          final width = aspectSize.width.round().clamp(1, 4096);
          final height = aspectSize.height.round().clamp(1, 4096);
          return Rational(width, height);
        },
        resolveScreenSize: () =>
            mounted ? MediaQuery.sizeOf(context) : const Size(0, 0),
        resolvePlaybackSourceForLifecycleRestore: () =>
            _pageSessionCoordinator.resolvePlaybackSourceForLifecycleRestore(),
        resolveIsVerticalVideo: () {
          final diagnostics =
              widget.dependencies.playerRuntime.currentDiagnostics;
          final width = diagnostics.width ?? 0;
          final height = diagnostics.height ?? 0;
          return width > 0 && height > 0 && height > width;
        },
      ),
      platforms: widget.dependencies.fullscreenSessionPlatforms,
    );
    _pageSessionCoordinator = RoomPageSessionCoordinator(
      providerId: widget.providerId,
      roomId: widget.roomId,
      dependencies: widget.dependencies,
      sessionController: _roomSessionController,
      ancillaryController: _roomAncillaryController,
      danmakuController: _roomDanmakuController,
      playbackController: _playbackController,
      fullscreenSessionController: _fullscreenSessionController,
      twitchRecoveryController: _roomTwitchRecoveryController,
      resolveRuntimeCurrentPlaybackSource: () =>
          _runtimeViewAdapter.currentPlaybackSource,
      loadPlayerPreferences: () => widget.dependencies.loadPlayerPreferences(),
      updatePlayerPreferences: (preferences) =>
          widget.dependencies.updatePlayerPreferences(preferences),
      persistRoomUiPreferences: (preferences) =>
          widget.dependencies.updateRoomUiPreferences(preferences),
      trace: _roomTrace,
      isMounted: () => mounted,
      runtimeViewAdapter: _runtimeViewAdapter,
      pageUiEffects: _pageUiEffects,
      confirmUnfollow: (displayName) =>
          confirmRoomUnfollowDialog(context, displayName: displayName),
      captureRenderedPlayerSurface: _captureRenderedPlayerSurface,
      exitFullscreenIfNeeded: _exitFullscreenIfNeeded,
      enterPictureInPicture: _enterPictureInPicture,
      toggleDesktopMiniWindow: _toggleDesktopMiniWindow,
      runtimeInspection: runtimeInspection,
      runtimeControl: runtimeControl,
      scheduleTwitchRecovery: _scheduleTwitchPlaybackRecovery,
      syncPlayerRuntimeState: () => _playerRuntimeObserver.syncCurrentState(),
      initialLifecycleState: WidgetsBinding.instance.lifecycleState,
    );
    _hasPageSessionCoordinator = true;
    _pageSessionCoordinator.addListener(_handlePageSessionCoordinatorChanged);
    _fullscreenSessionController.addListener(_handleFullscreenSessionChanged);
    _playerRuntimeObserver = RoomPlayerRuntimeObserver(
      context: RoomPlayerRuntimeObserverContext(
        providerId: widget.providerId,
        roomId: widget.roomId,
        runtime: runtimeObservation,
        trace: _roomTrace,
        resolvePlaybackAvailable: () => _roomPlaybackAvailable,
        resolveIsLeavingRoom: () => _isLeavingRoom,
        resolvePlaybackRebindInFlight: () => _playerBindingInFlight,
        shouldRecoverUnexpectedStop: (_) {
          // Disable auto-recovery for Stripchat on unexpected playback stop.
          // Stripchat streams involve complex JS-bridge key decryptions and private-mode/P2P
          // status transitions. Blind hot-retries on stop can cause infinite loops fetching
          // non-existent play URLs (rate-limiting issues) when a broadcaster goes private or key expires.
          if (_activeProviderId == ProviderId.stripchat) {
            return false;
          }
          // Do not schedule recovery while a room refresh is already in flight.
          if (_pageSessionState.refreshInFlight) {
            return false;
          }
          return true;
        },
        // Douyu/mpv hard open failures must switch CDN immediately; soft stalls
        // keep the 2s debounce so brief completed/error blips are not flapped.
        resolveUnexpectedStopRecoveryDelay: (state) {
          if (PlaybackFailoverPolicy.isHardOpenFailure(
            state.errorMessage,
            hasReachedPlaying: _playbackHasReachedPlaying,
          )) {
            return Duration.zero;
          }
          return const Duration(seconds: 2);
        },
        onPlayerStateChanged:
            (state, {required playbackAvailable, forceRebuild = false}) {
          final previous = _currentPlayerState;
          _currentPlayerState = state;
          if (state.status == PlaybackStatus.playing) {
            _playbackHasReachedPlaying = true;
            // Reset terminal budget only after continuous healthy playing.
            _ensureTerminalPlayReloadBudgetForActiveRoom();
            _terminalPlayReloadBudget.notePlaying(isPlaying: true);
          } else {
            _terminalPlayReloadBudget.notePlaying(isPlaying: false);
          }
          _fullscreenSessionController.handlePlayerStateChanged(
            state,
            playbackAvailable: playbackAvailable,
            autoFullscreenEnabled: _autoFullscreenEnabled,
            // First video size from diagnostics (forceRebuild) may flip
            // horizontal→vertical after double-tap fullscreen.
            videoAspectMayHaveChanged: forceRebuild,
          );
          if (state.status == PlaybackStatus.error &&
              _roomSessionController.current?.resolved?.hasPdkeyHealthAlert ==
                  true) {
            _pageUiEffects.showMessage(
              'Stripchat 播放解密失败：pdkey 可能已失效或耗尽。请在"设置 -> 账户设置"中更新 Mouflon 密钥。',
            );
          }
          // Progress-only ticks after first frame must not rebuild the whole
          // room page. Status/error/source/progress first-frame and diagnostics
          // size first-frame (forceRebuild) do.
          if (shouldScheduleFullRoomPageRebuildForPlayerState(
            previous: previous,
            next: state,
            forceRebuild: forceRebuild,
          )) {
            _markPageNeedsBuild();
          }
        },
        onUnexpectedPlaybackStop: (state) {
          return _handleUnexpectedPlaybackStop(state);
        },
      ),
    );
    _pageSessionCoordinator.startInitialLoad();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (!widget.startInFullscreen) {
        _scheduleInlineChromeAutoHide();
      }
    });
    unawaited(
      _fullscreenSessionController.initialize(
        startInFullscreen: widget.startInFullscreen,
      ),
    );
    _playerRuntimeObserver.attach();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _darkThemeActive = Theme.of(context).brightness == Brightness.dark;
  }

  @override
  void dispose() {
    widget.dependencies.llhlsProxyRegistry.unregisterSession(
      roomId: _hasPageSessionCoordinator ? _activeRoomId : widget.roomId,
    );
    WidgetsBinding.instance.removeObserver(this);
    _clearMdkTextureRecoveryState();
    final disposePlan = planRoomPreviewDispose(
      cleanupPlayback: shouldCleanupPlaybackOnRoomPreviewDispose(
        preserveRoomTransitionOnDispose:
            _fullscreenSessionController.preserveRoomTransitionOnDispose,
        leavingRoom: _isLeavingRoom,
      ),
    );
    final coordinator = _pageSessionCoordinator;
    final playback = _playbackController;
    final fullscreen = _fullscreenSessionController;
    final runtime = _roomRuntime;
    final observer = _playerRuntimeObserver;
    final desktopMiniActive = _desktopMiniWindowActive;
    final preserveTransition = fullscreen.preserveRoomTransitionOnDispose;

    _roomDanmakuController.listenable.removeListener(
      _handleDanmakuStateChanged,
    );
    _roomDanmakuController.messages.removeListener(
      _handleDanmakuMessagesChanged,
    );
    coordinator.removeListener(_handlePageSessionCoordinatorChanged);
    playback.removeListener(_handlePlaybackControllerChanged);
    fullscreen.removeListener(_handleFullscreenSessionChanged);

    if (disposePlan.cleanupPlayback) {
      unawaited(_restoreSystemUi());
      unawaited(_setScreenAwake(false));
    }

    // Heavy controllers must outlive leave cleanup when cleanup is scheduled.
    // Ordering is owned by [runRoomPreviewHeavyControllerDispose] so tests
    // can assert cleanup-before-dispose without theater bool mirrors.
    unawaited(
      runRoomPreviewHeavyControllerDispose(
        plan: disposePlan,
        hooks: RoomPreviewHeavyDisposeHooks(
          cleanupPlaybackOnLeave: coordinator.cleanupPlaybackOnLeave,
          disposeRuntime: runtime.dispose,
          disposePlayback: playback.dispose,
          disposeDesktopMini: desktopMiniActive && !preserveTransition
              ? _exitDesktopMiniWindow
              : null,
          disposeFullscreen: fullscreen.dispose,
          disposeObserver: observer.dispose,
        ),
      ),
    );

    coordinator.dispose();
    _roomTwitchRecoveryController.dispose();
    super.dispose();
  }

  Future<void> _updateRoomUiPreferences(RoomUiPreferences preferences) async {
    await _pageSessionCoordinator.updateRoomUiPreferences(preferences);
  }

  Future<void> _ensureFollowWatchlistLoaded({bool force = false}) async {
    await _pageSessionCoordinator.followWatchlist.ensureLoaded(force: force);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    unawaited(_handleLifecycleState(state));
  }

  Future<void> _handleLifecycleState(AppLifecycleState state) async {
    _pageSessionCoordinator.handleLifecycleState(state);
    final enteringPictureInPicture = _viewUiState.enteringPictureInPicture;
    await _fullscreenSessionController.handleLifecycleState(state);
    final androidPlaybackBridge =
        widget.dependencies.fullscreenSessionPlatforms.androidPlaybackBridge;
    final inPictureInPictureMode = androidPlaybackBridge.isSupported
        ? await androidPlaybackBridge.isInPictureInPictureMode()
        : false;
    await _roomDanmakuController.handleLifecycleState(
      state: state,
      backgroundAutoPauseEnabled: _backgroundAutoPauseEnabled,
      inPictureInPictureMode: inPictureInPictureMode,
      enteringPictureInPicture: enteringPictureInPicture,
    );
  }

  Future<void> _updateScaleMode(PlayerScaleMode scaleMode) async {
    await _pageSessionCoordinator.updateScaleMode(scaleMode);
  }

  @override
  Widget build(BuildContext context) {
    final descriptor = widget.dependencies.findProviderDescriptorById(
      _activeProviderId.value,
    );
    final fullscreenSessionActive =
        _isFullscreen || _fullscreenBootstrapPending;

    final page = PopScope(
      canPop: _isLeavingRoom && !fullscreenSessionActive,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) {
          return;
        }
        if (_isFullscreen) {
          await _exitFullscreen();
          return;
        }
        if (_fullscreenBootstrapPending) {
          _cancelPendingFullscreenBootstrap(scheduleInlineChrome: true);
          return;
        }
        if (!_isLeavingRoom) {
          await _pageSessionCoordinator.pageInteraction.leaveRoom(
            exitFullscreenFirst: false,
          );
        }
      },
      child: Scaffold(
        appBar: fullscreenSessionActive
            ? null
            : AppBar(
                leading: IconButton(
                  key: const Key('room-leave-button'),
                  tooltip: '返回',
                  onPressed: _pageSessionCoordinator.pageInteraction.leaveRoom,
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                title: FutureBuilder<RoomSessionLoadResult>(
                  future: _future,
                  builder: (context, snapshot) {
                    final displayState = snapshot.data ??
                        _pageSessionCoordinator.state.latestLoadedState;
                    final resolvedTitle = normalizeDisplayText(
                      displayState?.snapshot.detail.title,
                    );
                    final activeTitle = normalizeDisplayText(
                      _activeRoomDetail?.title,
                    );
                    return Text(
                      resolvedTitle.isNotEmpty
                          ? resolvedTitle
                          : activeTitle.isNotEmpty
                          ? activeTitle
                          : '${descriptor?.displayName ?? _activeProviderId.value} · $_activeRoomId',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    );
                  },
                ),
                actions: [
                  IconButton(
                    key: const Key('room-appbar-more-button'),
                    tooltip: '更多',
                    onPressed: _pageSessionCoordinator
                        .pageInteraction
                        .showQuickActionsSheet,
                    icon: const Icon(Icons.more_horiz_rounded),
                  ),
                ],
              ),
        body: FutureBuilder<RoomSessionLoadResult>(
          future: _future,
          builder: (context, snapshot) {
            final displayState = snapshot.data ??
                _pageSessionCoordinator.state.latestLoadedState;
            if (snapshot.hasError && displayState == null) {
              _resolveFullscreenBootstrap(
                roomLoaded: true,
                playbackAvailable: false,
              );
              final presentation = _describeRoomLoadError(snapshot.error);
              return RoomErrorState(
                title: presentation.title,
                message: presentation.description,
                detail: '${snapshot.error}',
                onRetry: () =>
                    _pageSessionCoordinator.pageInteraction.refreshRoom(),
                onOpenSettings:
                    _pageSessionCoordinator.pageInteraction.openPlayerSettings,
                onCopyDiagnostic: () => _copyRoomLoadDiagnostic(snapshot.error),
              );
            }
            if (displayState == null) {
              return RoomLoadingRoomShell(
                data: _loadingShellViewData(descriptor: descriptor),
                immersive:
                    fullscreenSessionActive || widget.startInFullscreen,
                embeddedPlayerView: _runtimeViewAdapter.supportsEmbeddedView
                    ? _embeddedPlayerView(16 / 9)
                    : null,
              );
            }

            final state = displayState;
            final room = state.snapshot.detail;
            final isRefreshing =
                snapshot.connectionState != ConnectionState.done ||
                _pageSessionState.refreshInFlight;
            final playbackSource =
                _playbackSource ?? state.resolved?.playbackSource;
            final playUrls = _playUrls.isEmpty
                ? state.snapshot.playUrls
                : _playUrls;
            final hasPlayback = playbackSource != null && playUrls.isNotEmpty;
            final activePlaybackSource = hasPlayback ? playbackSource : null;
            final diagnostics =
                widget.dependencies.playerRuntime.currentDiagnostics;
            final playerState = _currentPlayerState;
            final hasRenderedVideo = resolveRoomHasRenderedVideo(
              videoWidth: diagnostics.width,
              videoHeight: diagnostics.height,
              position: playerState?.position ?? Duration.zero,
              buffered: playerState?.buffered ?? Duration.zero,
              status: playerState?.status,
            );
            _resolveFullscreenBootstrap(
              roomLoaded: true,
              playbackAvailable: hasPlayback,
            );
            _pageSessionCoordinator.panel.schedulePageSync();

            // Keep loading shell until real first frame — loadRoom/setSource
            // "ready" is too early and feels like a post-load stutter.
            if (shouldKeepRoomLoadingShellUntilFirstFrame(
              hasPlayback: hasPlayback,
              hasRenderedVideo: hasRenderedVideo,
              playbackStatus: playerState?.status,
            )) {
              return RoomLoadingRoomShell(
                data: _loadingShellViewData(
                  descriptor: descriptor,
                  room: room,
                ),
                immersive:
                    fullscreenSessionActive || widget.startInFullscreen,
                embeddedPlayerView: _runtimeViewAdapter.supportsEmbeddedView
                    ? _embeddedPlayerView(16 / 9)
                    : null,
              );
            }

            return Stack(
              children: [
                RoomPreviewSections(
                  data: _sectionsViewData(
                    state: state,
                    room: room,
                    descriptor: descriptor,
                  ),
                  pageController: _pageSessionCoordinator.panel.pageController,
                  selectedPanel: _selectedPanel,
                  panelListenable: _pageSessionCoordinator.panel,
                  resolveSelectedPanel: () =>
                      _pageSessionCoordinator.panel.selectedPanel,
                  onSelectPanel: _pageSessionCoordinator.panel.selectPanel,
                  onPageChanged:
                      _pageSessionCoordinator.panel.handlePageChanged,
                  chatPanel: RoomChatPanel(
                    messagesListenable: _messagesNotifier,
                    statusListenable: Listenable.merge([
                      _pageSessionCoordinator,
                      _roomDanmakuController.listenable,
                    ]),
                    resolveAncillaryLoading: () => _ancillaryLoading,
                    resolveHasDanmakuSession: () => _danmakuSession != null,
                    room: room,
                    scrollController:
                        _pageSessionCoordinator.chatViewport.controller,
                    chatTextSize: _chatTextSize,
                    chatTextGap: _chatTextGap,
                    chatBubbleStyle: _chatBubbleStyle,
                    onRefreshRoom: () {
                      unawaited(
                        _pageSessionCoordinator.pageInteraction.refreshRoom(
                          showFeedback: true,
                        ),
                      );
                    },
                  ),
                  superChatPanel: RoomSuperChatPanel(
                    messagesListenable: _superChatMessagesNotifier,
                    hasDanmakuSession: _danmakuSession != null,
                  ),
                  followPanel: _buildFollowPanel(context: context),
                  controlsPanel: ListenableBuilder(
                    listenable: _pageSessionCoordinator.controlsAction,
                    builder: (context, _) {
                      return _buildControlsPanel(
                        state: state,
                        playUrls: playUrls,
                        playbackSource: playbackSource,
                        hasPlayback: hasPlayback,
                      );
                    },
                  ),
                  playerSurface: RoomPlayerSurfaceSection(
                    data: _playerSurfaceViewData(
                      room: room,
                      hasPlayback: hasPlayback,
                      embedPlayer: !fullscreenSessionActive,
                      fullscreen: false,
                      inlineQualityLabel: hasPlayback
                          ? _compactQualityLabel(
                              _effectiveQualityOf(state).label,
                            )
                          : null,
                      inlineLineLabel: activePlaybackSource != null
                          ? _compactLineLabel(
                              _lineLabelOf(playUrls, activePlaybackSource),
                            )
                          : null,
                    ),
                    buildEmbeddedPlayerView: _embeddedPlayerView,
                    gestureTipText: _gestureUiState.tipText,
                    onVerticalDragStart: _handleVerticalDragStart,
                    onVerticalDragUpdate: _handleVerticalDragUpdate,
                    onVerticalDragEnd: _handleVerticalDragEnd,
                    onInlineViewportChanged: (size) {
                      if (_inlinePlayerViewportSize == size) {
                        return;
                      }
                      _inlinePlayerViewportSize = size;
                    },
                    onToggleInlineChrome: _toggleInlinePlayerChrome,
                    onEnterFullscreen: hasPlayback && !_playerBindingInFlight
                        ? () {
                            if (_playerBindingInFlight) {
                              return;
                            }
                            _inlinePlayerViewportSize = null;
                            unawaited(_enterFullscreen());
                          }
                        : null,
                    onRefresh: _playerBindingInFlight
                        ? null
                        : () {
                            unawaited(
                              _pageSessionCoordinator.pageInteraction
                                  .refreshRoom(showFeedback: true),
                            );
                          },
                    onToggleDanmakuOverlay: hasPlayback
                        ? () {
                            _pageSessionCoordinator.updateDanmakuOverlayVisible(
                              !_showDanmakuOverlay,
                            );
                          }
                        : null,
                    onOpenDanmakuSettings: _pageSessionCoordinator
                        .pageInteraction
                        .openDanmakuSettings,
                    onShowQuality: hasPlayback
                        ? () => _pageSessionCoordinator.pageInteraction
                              .showQualitySheet(state)
                        : null,
                    onShowLine: activePlaybackSource != null
                        ? () => _pageSessionCoordinator.pageInteraction
                              .showLineSheet(playUrls, activePlaybackSource)
                        : null,
                    onKeepInlinePlayerChromeVisible:
                        _showInlinePlayerChromeTemporarily,
                  ),
                  onToggleFollow: () => _toggleFollow(state.snapshot),
                  onRefresh: () => _pageSessionCoordinator.pageInteraction
                      .refreshRoom(showFeedback: true),
                  onShareRoom: () => _shareRoomLink(room),
                ),
                if (isRefreshing)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.surface.withValues(alpha: 0.24),
                        ),
                        child: const Center(
                          child: CircularProgressIndicator.adaptive(),
                        ),
                      ),
                    ),
                  ),
                if (_isLeavingRoom)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.surface.withValues(alpha: 0.32),
                        ),
                        child: const Center(
                          child: CircularProgressIndicator.adaptive(),
                        ),
                      ),
                    ),
                  ),
                if (fullscreenSessionActive && !hasPlayback)
                  Positioned.fill(
                    child: RoomLoadingRoomShell(
                      data: _loadingShellViewData(
                        descriptor: descriptor,
                        room: room,
                      ),
                      immersive: true,
                      embeddedPlayerView:
                          _runtimeViewAdapter.supportsEmbeddedView
                          ? _embeddedPlayerView(16 / 9)
                          : null,
                    ),
                  ),
                if (fullscreenSessionActive && hasPlayback)
                  Positioned.fill(
                    child: RoomFullscreenOverlaySection(
                      data: _fullscreenOverlayViewData(
                        state: state,
                        room: room,
                        playbackSource: playbackSource,
                        playUrls: playUrls,
                      ),
                      messagesListenable: _messagesNotifier,
                      playerSuperChatMessagesListenable:
                          _playerSuperChatMessagesNotifier,
                      followDrawer: _buildFullscreenFollowDrawer(context),
                      buildEmbeddedPlayerView: _embeddedPlayerView,
                      onToggleChrome:
                          _fullscreenSessionController.toggleFullscreenChrome,
                      onOpenFollowDrawer: _openFullscreenFollowDrawer,
                      onToggleFullscreen: () {
                        if (_isFullscreen || _fullscreenBootstrapPending) {
                          unawaited(_exitFullscreen());
                          return;
                        }
                        if (_playerBindingInFlight) {
                          return;
                        }
                        unawaited(_enterFullscreen());
                      },
                      onVerticalDragStart: (details) {
                        unawaited(_handleVerticalDragStart(details));
                      },
                      onVerticalDragUpdate: (details) {
                        unawaited(_handleVerticalDragUpdate(details));
                      },
                      onVerticalDragEnd: (details) {
                        unawaited(_handleVerticalDragEnd(details));
                      },
                      onExitFullscreen: _exitFullscreen,
                      onEnterPictureInPicture: () {
                        _scheduleFullscreenChromeAutoHide();
                        unawaited(_enterPictureInPicture());
                      },
                      onToggleDesktopMiniWindow: () {
                        _scheduleFullscreenChromeAutoHide();
                        unawaited(_toggleDesktopMiniWindow());
                      },
                      onCapture: () {
                        _scheduleFullscreenChromeAutoHide();
                        unawaited(_captureScreenshot());
                      },
                      onShowDebug: () {
                        _scheduleFullscreenChromeAutoHide();
                        unawaited(
                          _pageSessionCoordinator.pageInteraction
                              .showPlayerDebugSheet(state, playbackSource),
                        );
                      },
                      onShowMore: () {
                        unawaited(
                          _pageSessionCoordinator.pageInteraction
                              .showQuickActionsSheet(),
                        );
                        _scheduleFullscreenChromeAutoHide();
                      },
                      onToggleFullscreenLock:
                          _fullscreenSessionController.toggleFullscreenLock,
                      onRefresh: () {
                        if (_playerBindingInFlight) {
                          return;
                        }
                        unawaited(
                          _pageSessionCoordinator.pageInteraction.refreshRoom(
                            showFeedback: true,
                          ),
                        );
                        _scheduleFullscreenChromeAutoHide();
                      },
                      onToggleDanmakuOverlay: () {
                        _pageSessionCoordinator.updateDanmakuOverlayVisible(
                          !_showDanmakuOverlay,
                        );
                        _scheduleFullscreenChromeAutoHide();
                      },
                      onOpenDanmakuSettings: () {
                        unawaited(
                          _pageSessionCoordinator.pageInteraction
                              .openDanmakuSettings(),
                        );
                        _scheduleFullscreenChromeAutoHide();
                      },
                      onShowQuality: () {
                        unawaited(
                          _pageSessionCoordinator.pageInteraction
                              .showQualitySheet(state),
                        );
                        _scheduleFullscreenChromeAutoHide();
                      },
                      onShowLine: () {
                        unawaited(
                          _pageSessionCoordinator.pageInteraction.showLineSheet(
                            playUrls,
                            playbackSource,
                          ),
                        );
                        _scheduleFullscreenChromeAutoHide();
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );

    if (!widget
        .dependencies
        .fullscreenSessionPlatforms
        .androidPlaybackBridge
        .isSupported) {
      return page;
    }

    return widget.dependencies.fullscreenSessionPlatforms.pipHost.wrapSwitcher(
      childWhenDisabled: page,
      childWhenEnabled: RoomPictureInPictureChild(
        future: _future,
        currentPlaybackSource: _playbackSource,
        currentPlayUrls: _playUrls,
        supportsEmbeddedView: _runtimeViewAdapter.supportsEmbeddedView,
        buildEmbeddedPlayerView: _embeddedPlayerView,
      ),
    );
  }
}
