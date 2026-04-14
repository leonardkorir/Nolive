import 'dart:async';

import 'package:floating/floating.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:nolive_app/src/app/routing/app_routes.dart';
import 'package:nolive_app/src/features/room/application/room_ancillary_controller.dart';
import 'package:nolive_app/src/features/room/application/room_follow_watchlist_controller.dart';
import 'package:nolive_app/src/features/room/application/load_room_use_case.dart';
import 'package:nolive_app/src/features/room/application/room_preview_dependencies.dart';
import 'package:nolive_app/src/features/room/application/room_session_controller.dart';
import 'package:nolive_app/src/features/room/presentation/room_chat_viewport_coordinator.dart';
import 'package:nolive_app/src/features/room/presentation/room_danmaku_controller.dart';
import 'package:nolive_app/src/features/room/presentation/room_controls_action_coordinator.dart';
import 'package:nolive_app/src/features/room/presentation/room_controls_presentation_helpers.dart';
import 'package:nolive_app/src/features/room/presentation/room_controls_view_data.dart';
import 'package:nolive_app/src/features/room/presentation/room_follow_action_coordinator.dart';
import 'package:nolive_app/src/features/room/presentation/room_follow_room_transition_coordinator.dart';
import 'package:nolive_app/src/features/room/presentation/room_fullscreen_runtime_context.dart';
import 'package:nolive_app/src/features/room/presentation/room_fullscreen_session_controller.dart';
import 'package:nolive_app/src/features/room/presentation/room_gesture_ui_state.dart';
import 'package:nolive_app/src/features/room/presentation/room_panel_controller.dart';
import 'package:nolive_app/src/features/room/presentation/room_page_interaction_coordinator.dart';
import 'package:nolive_app/src/features/room/presentation/room_page_session_coordinator.dart';
import 'package:nolive_app/src/features/room/presentation/room_player_runtime_observer.dart';
import 'package:nolive_app/src/features/room/presentation/room_playback_controller.dart';
import 'package:nolive_app/src/features/room/presentation/room_playback_session_state.dart';
import 'package:nolive_app/src/features/room/presentation/room_preview_page_chat_panels.dart';
import 'package:nolive_app/src/features/room/presentation/room_preview_page_controls.dart';
import 'package:nolive_app/src/features/room/presentation/room_preview_page_controls_actions.dart';
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
import 'package:nolive_app/src/features/library/application/load_follow_watchlist_use_case.dart';
import 'package:nolive_app/src/features/settings/application/manage_danmaku_preferences_use_case.dart';
import 'package:nolive_app/src/features/settings/application/manage_player_preferences_use_case.dart';
import 'package:nolive_app/src/features/settings/application/manage_room_ui_preferences_use_case.dart';
import 'package:nolive_app/src/shared/application/app_log.dart';

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
        resolveRoomPlayerPosterBackdropVisibility;

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
  late final RoomAncillaryController _roomAncillaryController;
  late final RoomChatViewportCoordinator _chatViewportCoordinator;
  late final RoomControlsActionCoordinator _controlsActionCoordinator;
  late final RoomDanmakuController _roomDanmakuController;
  late final RoomFollowActionCoordinator _followActionCoordinator;
  late final RoomFollowWatchlistController _followWatchlistController;
  late final RoomFollowRoomTransitionCoordinator
      _followRoomTransitionCoordinator;
  late final RoomFullscreenSessionController _fullscreenSessionController;
  late final RoomPanelController _panelController;
  late final RoomPageInteractionCoordinator _pageInteractionCoordinator;
  late final RoomPageSessionCoordinator _pageSessionCoordinator;
  late final RoomPlayerRuntimeObserver _playerRuntimeObserver;
  late final RoomPlaybackController _playbackController;
  late final RoomRuntimeViewAdapter _runtimeViewAdapter;
  late final RoomSessionController _roomSessionController;
  late final RoomTwitchRecoveryController _roomTwitchRecoveryController;
  final PageController _panelPageController = PageController();
  bool _darkThemeActive = false;
  Size? _inlinePlayerViewportSize;
  bool _pageRebuildQueued = false;
  int _embeddedPlayerViewEpoch = 0;

  Future<RoomSessionLoadResult> get _future =>
      _pageSessionCoordinator.roomFuture;
  RoomPageSessionState get _pageSessionState => _pageSessionCoordinator.state;

  bool get _supportsPlayerCapture => _runtimeViewAdapter.supportsScreenshot;

  RoomUiPreferences get _roomUiPreferences =>
      _pageSessionState.roomUiPreferences;

  RoomFollowWatchlistState get _followWatchlistState =>
      _followWatchlistController.current;

  RoomDanmakuState get _danmakuState => _roomDanmakuController.current;

  DanmakuSession? get _danmakuSession => _danmakuState.session;

  ValueListenable<List<LiveMessage>> get _messagesNotifier =>
      _roomDanmakuController.messages;

  ValueListenable<List<LiveMessage>> get _superChatMessagesNotifier =>
      _roomDanmakuController.superChats;

  ValueListenable<List<LiveMessage>> get _playerSuperChatMessagesNotifier =>
      _roomDanmakuController.playerSuperChats;

  RoomSessionLoadResult? get _latestLoadedState =>
      _pageSessionState.latestLoadedState;

  RoomPlaybackSessionState get _playbackSession =>
      _pageSessionState.playbackSession;

  bool get _isFollowed => _pageSessionState.isFollowed;

  PlayerPreferences get _playerPreferences =>
      _pageSessionState.playerPreferences;

  DanmakuPreferences get _danmakuPreferences =>
      _pageSessionState.danmakuPreferences;

  bool get _autoPlayEnabled => _playerPreferences.autoPlayEnabled;

  bool get _forceHttpsEnabled => _playerPreferences.forceHttpsEnabled;

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

  bool get _usingNativeDanmakuBatchMask => _danmakuState.usingNativeBatchMask;

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

  RoomPanel get _selectedPanel => _panelController.selectedPanel;

  PlaybackSource? get _playbackSource => _playbackSession.playbackSource;

  List<LivePlayUrl> get _playUrls => _playbackSession.playUrls;

  bool get _roomPlaybackAvailable => _playbackSession.playbackAvailable;

  bool get _playerBindingInFlight => _playbackController.rebindInFlight;

  Key get _embeddedPlayerViewKey =>
      GlobalObjectKey('room-embedded-player-$_embeddedPlayerViewEpoch');

  LiveRoomDetail? get _activeRoomDetail => _playbackSession.activeRoomDetail;

  bool get _suspendEmbeddedPlayerForFollowRoomTransition =>
      _followRoomTransitionCoordinator.suspendEmbeddedPlayerForTransition;

  bool get _supportsDesktopMiniWindow {
    return _fullscreenSessionController.supportsDesktopMiniWindow;
  }

  void _roomTrace(String message) {
    final prefix = '[RoomPreview/${widget.providerId.value}/${widget.roomId}]';
    AppLog.instance.info('room', '$prefix $message');
    if (!kDebugMode) {
      return;
    }
    debugPrint(
      '$prefix $message',
    );
  }

  void _showPageMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _pushNamedRoute(
    String routeName, {
    bool rootNavigator = false,
  }) async {
    if (!mounted) {
      return;
    }
    await Navigator.of(context, rootNavigator: rootNavigator).pushNamed(
      routeName,
    );
  }

  Future<void> _pushReplacementToRoom(RoomRouteArguments args) async {
    if (!mounted) {
      return;
    }
    await Navigator.of(context).pushReplacementNamed(
      AppRoutes.room,
      arguments: args,
    );
  }

  Future<void> _exitFullscreenIfNeeded() async {
    if (_isFullscreen) {
      await _exitFullscreen();
    }
  }

  void _popPage() {
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
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
  }) {
    final room = _activeRoomDetail;
    final providerLabel = descriptor?.displayName ?? widget.providerId.value;
    final streamerName = normalizeDisplayText(room?.streamerName);
    final avatarTextSource =
        streamerName.isEmpty ? providerLabel : streamerName;
    final avatarLabel = avatarTextSource.isEmpty
        ? '?'
        : avatarTextSource.substring(0, 1).toUpperCase();
    return RoomLoadingShellViewData(
      providerLabel: providerLabel,
      roomTitle: room?.title ?? '房间号 ${widget.roomId}',
      streamerName: streamerName,
      avatarLabel: avatarLabel,
      posterUrl: room?.keyframeUrl ?? room?.coverUrl,
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
    return RoomSectionsViewData(
      providerLabel: providerLabel,
      streamerName: streamerName,
      streamerAvatarUrl: room.streamerAvatarUrl,
      roomLive: room.isLive,
      viewerLabel: viewerLabel,
      isFollowed: _isFollowed,
      statusPresentation: resolveRoomChaturbateStatusPresentation(room),
      qualityBadgeLabel:
          _hasQualityFallback(state) ? _qualityBadgeLabel(state) : null,
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
    final statusPresentation = resolveRoomChaturbateStatusPresentation(room);
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
    );
  }

  RoomFullscreenOverlayViewData _fullscreenOverlayViewData({
    required RoomSessionLoadResult state,
    required LiveRoomDetail room,
    required PlaybackSource playbackSource,
    required List<LivePlayUrl> playUrls,
  }) {
    final liveDuration = formatRoomLiveDuration(room.startedAt);
    final lineLabel = playUrls
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
      androidPlaybackBridgeSupported: widget.dependencies
          .fullscreenSessionPlatforms.androidPlaybackBridge.isSupported,
      backgroundAutoPauseEnabled: _backgroundAutoPauseEnabled,
    );
    return _runtimeViewAdapter.buildEmbeddedView(
      key: _embeddedPlayerViewKey,
      aspectRatio: aspectRatio,
      fit: fitForRoomScaleMode(_scaleMode),
      pauseUponEnteringBackgroundMode:
          lifecycleViewFlags.pauseUponEnteringBackgroundMode,
      resumeUponEnteringForegroundMode:
          lifecycleViewFlags.resumeUponEnteringForegroundMode,
    );
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

  PlaybackSource? _resolvePlaybackReferenceSource() {
    return _runtimeViewAdapter.currentPlaybackSource ??
        _playbackSource ??
        _playbackController.pendingPlaybackSource;
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
    await _waitForPlayerBindingToFinish(reason: 'exit fullscreen');
    await _fullscreenSessionController.exitFullscreen();
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
    return _controlsActionCoordinator.switchQuality(
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
    return _controlsActionCoordinator.refreshPlaybackSource(
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
    return _controlsActionCoordinator.switchLine(
      playUrl,
      resetTwitchRecoveryAttempts: resetTwitchRecoveryAttempts,
    );
  }

  Future<void> _shareRoomLink(LiveRoomDetail room) {
    return _controlsActionCoordinator.shareRoomLink(
      room: room,
      playbackSource: _playbackSource,
    );
  }

  Future<void> _captureScreenshot() {
    return _controlsActionCoordinator.captureScreenshot();
  }

  Future<void> _presentPlayerDebugSheet({
    required RoomPlayerDebugViewData debugViewData,
  }) {
    return showRoomPlayerDebugSheet(
      context: context,
      wrapFlatTileScope: wrapRoomFlatTileScope,
      debugViewData: debugViewData,
      diagnosticsStream: _runtimeViewAdapter.diagnosticsStream,
      initialDiagnostics: _runtimeViewAdapter.initialDiagnostics,
    );
  }

  Future<void> _presentQuickActionsSheet({
    required RoomControlsViewData viewData,
    required Future<void> Function() onRefresh,
    required Future<void> Function() onShowQuality,
    required Future<void> Function() onShowLine,
    required Future<RoomControlsViewData> Function() onCycleScaleMode,
    required Future<void> Function() onEnterPictureInPicture,
    required Future<void> Function() onToggleDesktopMiniWindow,
    required Future<void> Function() onCaptureScreenshot,
    required Future<void> Function() onShowAutoCloseSheet,
    required Future<void> Function() onShowDebugPanel,
  }) {
    return showRoomQuickActionsSheet(
      context: context,
      wrapFlatTileScope: wrapRoomFlatTileScope,
      viewData: viewData,
      onRefresh: onRefresh,
      onShowQuality: onShowQuality,
      onShowLine: onShowLine,
      onCycleScaleMode: onCycleScaleMode,
      onEnterPictureInPicture: onEnterPictureInPicture,
      onToggleDesktopMiniWindow: onToggleDesktopMiniWindow,
      onCaptureScreenshot: onCaptureScreenshot,
      onShowAutoCloseSheet: onShowAutoCloseSheet,
      onShowDebugPanel: onShowDebugPanel,
    );
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
      onOpenPlayerSettings: _pageInteractionCoordinator.openPlayerSettings,
      onShowQuality: () {
        unawaited(_pageInteractionCoordinator.showQualitySheet(state));
      },
      onShowLine: () {
        unawaited(
          _pageInteractionCoordinator.showLineSheet(playUrls, playbackSource!),
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
          _pageInteractionCoordinator.showPlayerDebugSheet(
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
      onOpenDanmakuShield: _pageInteractionCoordinator.openDanmakuShield,
      onOpenDanmakuSettings: _pageInteractionCoordinator.openDanmakuSettings,
      onShowAutoCloseSheet: () {
        unawaited(_pageInteractionCoordinator.showAutoCloseSheet());
      },
    );
  }

  Future<void> _presentQualitySheet({
    required LivePlayQuality selectedQuality,
    required List<LivePlayQuality> qualities,
    required Future<void> Function(LivePlayQuality quality) onSelected,
  }) {
    return showRoomQualitySheet(
      context: context,
      wrapFlatTileScope: wrapRoomFlatTileScope,
      selectedQuality: selectedQuality,
      qualities: qualities,
      onSelected: onSelected,
    );
  }

  Future<void> _presentLineSheet({
    required List<LivePlayUrl> playUrls,
    required PlaybackSource playbackSource,
    required Future<void> Function(LivePlayUrl playUrl) onSelected,
  }) {
    return showRoomLineSheet(
      context: context,
      wrapFlatTileScope: wrapRoomFlatTileScope,
      playbackSource: playbackSource,
      playUrls: playUrls,
      onSelected: onSelected,
    );
  }

  Future<void> _presentAutoCloseSheet({
    required DateTime? scheduledCloseAt,
    required void Function(Duration? duration) onSelectDuration,
  }) {
    return showRoomAutoCloseSheet(
      context: context,
      wrapFlatTileScope: wrapRoomFlatTileScope,
      scheduledCloseAt: scheduledCloseAt,
      onSelectDuration: onSelectDuration,
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
      scheduledCloseAt: _controlsActionCoordinator.scheduledCloseAt,
      chatTextSize: _chatTextSize.round(),
      chatTextGap: _chatTextGap.round(),
      chatBubbleStyle: _chatBubbleStyle,
      showPlayerSuperChat: _showPlayerSuperChat,
      playerSuperChatDisplaySeconds: _playerSuperChatDisplaySeconds,
    );
  }

  RoomPlayerDebugViewData _buildPlayerDebugViewData({
    required RoomSessionLoadResult state,
    required PlaybackSource? playbackSource,
  }) {
    final debugPlayUrls =
        _playUrls.isEmpty ? state.snapshot.playUrls : _playUrls;
    final hasPlayback = playbackSource != null && debugPlayUrls.isNotEmpty;
    return RoomPlayerDebugViewData(
      backendLabel: _runtimeViewAdapter.backendLabel,
      currentStatusLabel: _runtimeViewAdapter.currentStatusLabel,
      requestedQualityLabel: _requestedQualityOf(state).label,
      effectiveQualityLabel: _effectiveQualityOf(state).label,
      currentLineLabel: hasPlayback
          ? roomLineLabelOfPlayback(debugPlayUrls, playbackSource)
          : '暂无',
      scaleModeLabel: labelOfRoomScaleMode(_scaleMode),
      usingNativeDanmakuBatchMask: _usingNativeDanmakuBatchMask,
    );
  }

  Future<void> _toggleFollow(LoadedRoomSnapshot snapshot) {
    return _followActionCoordinator.toggleCurrentRoomFollow(
      snapshot: snapshot,
      currentlyFollowed: _isFollowed,
      followPanelSelected: _selectedPanel == RoomPanel.follow,
    );
  }

  Widget _buildFollowPanel({
    required BuildContext context,
  }) {
    final followState = _followWatchlistState;
    final watchlist =
        followState.watchlist ?? const FollowWatchlist(entries: []);
    return buildRoomFollowPanel(
      context: context,
      followState: followState,
      entries: _followActionCoordinator.buildEntryViewData(watchlist),
      onRefresh: () => _ensureFollowWatchlistLoaded(force: true),
      onOpenSettings: () {
        unawaited(_pageInteractionCoordinator.openFollowSettings());
      },
      onOpenEntry: (entry) {
        unawaited(_followActionCoordinator.openFollowRoom(entry));
      },
    );
  }

  Widget _buildFullscreenFollowDrawer(BuildContext context) {
    final followState = _followWatchlistState;
    final watchlist =
        followState.watchlist ?? const FollowWatchlist(entries: []);
    return buildRoomFullscreenFollowDrawer(
      context: context,
      showDrawer: _showFullscreenFollowDrawer,
      followState: followState,
      entries: _followActionCoordinator.buildEntryViewData(watchlist),
      onClose: _fullscreenSessionController.hideFullscreenFollowDrawer,
      onOpenEntry: (entry) {
        unawaited(_followActionCoordinator.openFollowRoom(entry));
      },
    );
  }

  void _openFullscreenFollowDrawer() {
    _fullscreenSessionController.openFullscreenFollowDrawer();
  }

  RoomLoadErrorPresentation _describeRoomLoadError(Object? error) {
    return describeRoomLoadError(error);
  }

  void _replaceResolvedPlaybackSession({
    required LiveRoomDetail activeRoomDetail,
    required LivePlayQuality selectedQuality,
    required LivePlayQuality effectiveQuality,
    required PlaybackSource? playbackSource,
    required List<LivePlayUrl> playUrls,
  }) {
    _pageSessionCoordinator.replaceResolvedPlaybackSession(
      activeRoomDetail: activeRoomDetail,
      selectedQuality: selectedQuality,
      effectiveQuality: effectiveQuality,
      playbackSource: playbackSource,
      playUrls: playUrls,
    );
  }

  void _schedulePlaybackBootstrap({
    required PlaybackSource? playbackSource,
    required bool hasPlayback,
    required bool autoPlay,
    bool force = false,
  }) {
    _pageSessionCoordinator.schedulePlaybackBootstrap(
      playbackSource: playbackSource,
      hasPlayback: hasPlayback,
      autoPlay: autoPlay,
      force: force,
    );
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
    return _playbackController.bindPlaybackSource(
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

  Future<void> _waitForPlayerBindingToFinish({
    required String reason,
  }) {
    return _pageSessionCoordinator.waitForPlayerBindingToFinish(
      reason: reason,
    );
  }

  void _clearMdkTextureRecoveryState() {
    _playbackController.resetRecoveryState();
  }

  Future<void> _resetEmbeddedPlayerViewAfterBackendRefresh(
    String label,
  ) async {
    if (mounted) {
      setState(() {
        _embeddedPlayerViewEpoch += 1;
      });
    } else {
      _embeddedPlayerViewEpoch += 1;
    }
    _roomTrace(
        '$label mdk embedded view reset epoch=$_embeddedPlayerViewEpoch');
    await WidgetsBinding.instance.endOfFrame;
  }

  void _updatePlaybackSourceForLineSwitch({
    required PlaybackSource playbackSource,
    required bool hasPlayback,
  }) {
    _pageSessionCoordinator.updatePlaybackSourceForLineSwitch(
      playbackSource: playbackSource,
      hasPlayback: hasPlayback,
    );
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

  void _handlePanelControllerChanged() {
    _markPageNeedsBuild();
  }

  void _handleFollowRoomTransitionCoordinatorChanged() {
    _markPageNeedsBuild();
  }

  void _handleControlsActionCoordinatorChanged() {
    if (!mounted) {
      return;
    }
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

  void _handleFollowWatchlistStateChanged() {
    if (!mounted) {
      return;
    }
    _markPageNeedsBuild();
  }

  void _handleDanmakuStateChanged() {
    if (!mounted) {
      return;
    }
    _markPageNeedsBuild();
  }

  void _handleDanmakuMessagesChanged() {
    _chatViewportCoordinator.handleMessagesChanged(
      selectedPanel: _selectedPanel,
    );
  }

  @override
  void initState() {
    super.initState();
    final playerRuntime = widget.dependencies.playerRuntime;
    final fullscreenRuntime =
        RoomFullscreenRuntimeContext.fromPlayerRuntime(playerRuntime);
    final runtimeObservation =
        RoomRuntimeObservationContext.fromPlayerRuntime(playerRuntime);
    final runtimeInspection =
        RoomRuntimeInspectionContext.fromPlayerRuntime(playerRuntime);
    final runtimeControl =
        RoomRuntimeControlContext.fromPlayerRuntime(playerRuntime);
    WidgetsBinding.instance.addObserver(this);
    _runtimeViewAdapter = RoomRuntimeViewAdapter(playerRuntime);
    _chatViewportCoordinator = RoomChatViewportCoordinator();
    _roomAncillaryController = RoomAncillaryController(
      dependencies: RoomAncillaryDependencies.fromPreviewDependencies(
        widget.dependencies,
      ),
      providerId: widget.providerId,
      trace: _roomTrace,
    );
    _roomDanmakuController = RoomDanmakuController(
      dependencies: RoomDanmakuDependencies.fromPreviewDependencies(
        widget.dependencies,
      ),
      providerId: widget.providerId,
      trace: _roomTrace,
    );
    _roomDanmakuController.listenable.addListener(_handleDanmakuStateChanged);
    _roomDanmakuController.messages.addListener(_handleDanmakuMessagesChanged);
    _followWatchlistController = RoomFollowWatchlistController(
      dependencies: RoomFollowWatchlistDependencies.fromPreviewDependencies(
        widget.dependencies,
      ),
      trace: _roomTrace,
    );
    _followWatchlistController.listenable
        .addListener(_handleFollowWatchlistStateChanged);
    _panelController = RoomPanelController(
      pageController: _panelPageController,
      onEnterChatPanel: () => _chatViewportCoordinator.scrollToBottom(
        force: true,
      ),
      onEnterFollowPanel: () {
        unawaited(_ensureFollowWatchlistLoaded());
      },
    );
    _panelController.addListener(_handlePanelControllerChanged);
    _roomSessionController = RoomSessionController(
      dependencies: RoomSessionDependencies.fromPreviewDependencies(
        widget.dependencies,
      ),
      providerId: widget.providerId,
      roomId: widget.roomId,
      targetPlatform: defaultTargetPlatform,
      isWeb: kIsWeb,
      trace: _roomTrace,
    );
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
    );
    _playbackController.addListener(_handlePlaybackControllerChanged);
    _fullscreenSessionController = RoomFullscreenSessionController(
      bindings: RoomFullscreenSessionBindings(
        runtime: fullscreenRuntime,
        trace: _roomTrace,
        showMessage: _showPageMessage,
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
      ),
      platforms: widget.dependencies.fullscreenSessionPlatforms,
    );
    _pageSessionCoordinator = RoomPageSessionCoordinator(
      providerId: widget.providerId,
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
      scheduleTwitchRecovery: _scheduleTwitchPlaybackRecovery,
      syncPlayerRuntimeState: () => _playerRuntimeObserver.syncCurrentState(),
    );
    _pageSessionCoordinator.addListener(_handlePageSessionCoordinatorChanged);
    _controlsActionCoordinator = RoomControlsActionCoordinator(
      context: RoomControlsActionContext(
        providerId: widget.providerId,
        roomId: widget.roomId,
        targetPlatform: defaultTargetPlatform,
        isWeb: kIsWeb,
        runtime: runtimeControl,
        trace: _roomTrace,
        showMessage: _showPageMessage,
        isMounted: () => mounted,
        resolveAutoPlayEnabled: () => _autoPlayEnabled,
        resolveForceHttpsEnabled: () => _forceHttpsEnabled,
        resolvePlaybackAvailable: () => _roomPlaybackAvailable,
        resolveCurrentPlaybackSource: () => _playbackSource,
        resolvePlaybackReferenceSource: () => _resolvePlaybackReferenceSource(),
        resolveCurrentPlayUrls: () => _playUrls,
        resolveSelectedQuality: () => _selectedQuality,
        resolveEffectiveQuality: () => _effectiveQuality,
        resolveActiveRoomDetail: () => _activeRoomDetail,
        resolveLatestLoadedState: () => _latestLoadedState,
        loadCurrentRoomDetailForDanmaku:
            _pageSessionCoordinator.loadCurrentRoomDetailForDanmaku,
        resolvePlaybackRefresh: (snapshot, quality) {
          return _roomSessionController.resolvePlaybackRefresh(
            snapshot: snapshot,
            quality: quality,
            preferHttps: _forceHttpsEnabled,
          );
        },
        playbackSourceFromLine: _roomSessionController.playbackSourceFromLine,
        bindPlaybackSourceWithRecovery: _bindPlaybackSourceWithRecovery,
        replaceResolvedPlaybackSession: _replaceResolvedPlaybackSession,
        updatePlaybackSourceForLineSwitch: _updatePlaybackSourceForLineSwitch,
        schedulePlaybackBootstrap: _schedulePlaybackBootstrap,
        scheduleTwitchRecovery: _scheduleTwitchPlaybackRecovery,
        prepareTwitchForResolvedPlayback:
            _roomTwitchRecoveryController.prepareForResolvedPlayback,
        prepareTwitchForLineSwitch:
            _roomTwitchRecoveryController.prepareForLineSwitch,
        loadPlayerPreferences: () =>
            widget.dependencies.loadPlayerPreferences(),
        applyPlayerPreferences: (preferences) =>
            _pageSessionCoordinator.applyPlayerPreferences(preferences),
        refreshRoom: ({
          bool showFeedback = false,
          bool reloadPlayer = false,
          bool forcePlaybackRebind = true,
        }) {
          return _pageSessionCoordinator.refreshRoom(
            showFeedback: showFeedback,
            reloadPlayer: reloadPlayer,
            forcePlaybackRebind: forcePlaybackRebind,
          );
        },
        loadDanmakuPreferences: () =>
            widget.dependencies.loadDanmakuPreferences(),
        loadBlockedKeywords: () => widget.dependencies.loadBlockedKeywords(),
        applyDanmakuPreferences: ({
          required preferences,
          required blockedKeywords,
        }) {
          _pageSessionCoordinator.applyDanmakuPreferences(
            preferences: preferences,
            blockedKeywords: blockedKeywords,
          );
        },
        openRoomDanmaku: ({required detail}) {
          return widget.dependencies.openRoomDanmaku(
            providerId: widget.providerId,
            detail: detail,
          );
        },
        bindDanmakuSession: _pageSessionCoordinator.bindDanmakuSession,
        leaveRoom: () => _pageInteractionCoordinator.leaveRoom(),
      ),
    );
    _controlsActionCoordinator.addListener(
      _handleControlsActionCoordinatorChanged,
    );
    _followRoomTransitionCoordinator = RoomFollowRoomTransitionCoordinator(
      currentProviderId: widget.providerId,
      currentRoomId: widget.roomId,
      runtime: runtimeInspection,
      playbackController: _playbackController,
      fullscreenSessionController: _fullscreenSessionController,
      trace: _roomTrace,
      isMounted: () => mounted,
    );
    _followRoomTransitionCoordinator.addListener(
      _handleFollowRoomTransitionCoordinatorChanged,
    );
    _followActionCoordinator = RoomFollowActionCoordinator(
      dependencies: RoomFollowActionDependencies.fromPreviewDependencies(
        widget.dependencies,
      ),
      context: RoomFollowActionContext(
        currentProviderId: widget.providerId,
        currentRoomId: widget.roomId,
        showMessage: _showPageMessage,
        isMounted: () => mounted,
        confirmUnfollow: (displayName) => confirmRoomUnfollowDialog(
          context,
          displayName: displayName,
        ),
        applyCurrentFollowed: _pageSessionCoordinator.applyCurrentFollowed,
        replaceWatchlistSnapshot: _followWatchlistController.replaceSnapshot,
        ensureFollowWatchlistLoaded: ({force = false}) =>
            _ensureFollowWatchlistLoaded(force: force),
        commitFollowRoomNavigation: (entry) =>
            _pageInteractionCoordinator.commitFollowRoomNavigation(entry),
      ),
    );
    _pageInteractionCoordinator = RoomPageInteractionCoordinator(
      context: RoomPageInteractionContext(
        isMounted: () => mounted,
        exitFullscreenIfNeeded: _exitFullscreenIfNeeded,
        showMessage: _showPageMessage,
        pushNamed: _pushNamedRoute,
        pushReplacementToRoom: _pushReplacementToRoom,
        popPage: _popPage,
        loadPlayerPreferences: () =>
            widget.dependencies.loadPlayerPreferences(),
        handlePlayerSettingsReturn: (previousPreferences) =>
            _controlsActionCoordinator.handlePlayerSettingsReturn(
          previousPreferences: previousPreferences,
        ),
        handleDanmakuSettingsReturn:
            _controlsActionCoordinator.handleDanmakuSettingsReturn,
        resolveRoomFuture: () => _future,
        resolveIsLeavingRoom: () => _isLeavingRoom,
        resolveCurrentPlaybackSource: () => _playbackSource,
        resolveCurrentPlayUrls: () => _playUrls,
        resolveRequestedQuality: _requestedQualityOf,
        resolveControlsViewData: _buildControlsViewData,
        resolvePlayerDebugViewData: _buildPlayerDebugViewData,
        cycleScaleModeAndResolveControlsViewData: ({
          required state,
          required playUrls,
          required playbackSource,
          required hasPlayback,
        }) async {
          final modes = PlayerScaleMode.values;
          final index = modes.indexOf(_scaleMode);
          await _updateScaleMode(modes[(index + 1) % modes.length]);
          return _buildControlsViewData(
            state: state,
            playUrls: playUrls,
            playbackSource: playbackSource,
            hasPlayback: hasPlayback,
          );
        },
        presentQuickActionsSheet: ({
          required viewData,
          required onRefresh,
          required onShowQuality,
          required onShowLine,
          required onCycleScaleMode,
          required onEnterPictureInPicture,
          required onToggleDesktopMiniWindow,
          required onCaptureScreenshot,
          required onShowAutoCloseSheet,
          required onShowDebugPanel,
        }) {
          return _presentQuickActionsSheet(
            viewData: viewData,
            onRefresh: onRefresh,
            onShowQuality: onShowQuality,
            onShowLine: onShowLine,
            onCycleScaleMode: onCycleScaleMode,
            onEnterPictureInPicture: onEnterPictureInPicture,
            onToggleDesktopMiniWindow: onToggleDesktopMiniWindow,
            onCaptureScreenshot: onCaptureScreenshot,
            onShowAutoCloseSheet: onShowAutoCloseSheet,
            onShowDebugPanel: onShowDebugPanel,
          );
        },
        presentQualitySheet: ({
          required selectedQuality,
          required qualities,
          required onSelected,
        }) {
          return _presentQualitySheet(
            selectedQuality: selectedQuality,
            qualities: qualities,
            onSelected: onSelected,
          );
        },
        presentLineSheet: ({
          required playUrls,
          required playbackSource,
          required onSelected,
        }) {
          return _presentLineSheet(
            playUrls: playUrls,
            playbackSource: playbackSource,
            onSelected: onSelected,
          );
        },
        presentAutoCloseSheet: ({
          required scheduledCloseAt,
          required onSelectDuration,
        }) {
          return _presentAutoCloseSheet(
            scheduledCloseAt: scheduledCloseAt,
            onSelectDuration: onSelectDuration,
          );
        },
        presentPlayerDebugSheet: ({required debugViewData}) {
          return _presentPlayerDebugSheet(debugViewData: debugViewData);
        },
        enterPictureInPicture: _enterPictureInPicture,
        toggleDesktopMiniWindow: _toggleDesktopMiniWindow,
        captureScreenshot: _captureScreenshot,
        refreshRoom: ({
          bool showFeedback = false,
          bool reloadPlayer = false,
          bool forcePlaybackRebind = true,
        }) {
          return _pageSessionCoordinator.refreshRoom(
            showFeedback: showFeedback,
            reloadPlayer: reloadPlayer,
            forcePlaybackRebind: forcePlaybackRebind,
          );
        },
        leaveRoomCleanup: _pageSessionCoordinator.leaveRoom,
        switchQuality: (snapshot, quality) =>
            _controlsActionCoordinator.switchQuality(snapshot, quality),
        switchLine: _controlsActionCoordinator.switchLine,
        resolveScheduledCloseAt: () =>
            _controlsActionCoordinator.scheduledCloseAt,
        setAutoCloseTimer: _controlsActionCoordinator.setAutoCloseTimer,
        openFollowRoomTransition: (
          entry, {
          required commitNavigation,
          required showMessage,
        }) {
          return _followRoomTransitionCoordinator.openFollowRoom(
            leavingRoom: _isLeavingRoom,
            commitNavigation: (preserveFullscreen) {
              unawaited(commitNavigation(preserveFullscreen));
            },
            showMessage: showMessage,
          );
        },
      ),
    );
    _fullscreenSessionController.addListener(_handleFullscreenSessionChanged);
    _playerRuntimeObserver = RoomPlayerRuntimeObserver(
      context: RoomPlayerRuntimeObserverContext(
        providerId: widget.providerId,
        roomId: widget.roomId,
        runtime: runtimeObservation,
        trace: _roomTrace,
        resolvePlaybackAvailable: () => _roomPlaybackAvailable,
        onPlayerStateChanged: (
          state, {
          required playbackAvailable,
        }) {
          _fullscreenSessionController.handlePlayerStateChanged(
            state,
            playbackAvailable: playbackAvailable,
            autoFullscreenEnabled: _autoFullscreenEnabled,
          );
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
    WidgetsBinding.instance.removeObserver(this);
    _clearMdkTextureRecoveryState();
    _roomDanmakuController.listenable
        .removeListener(_handleDanmakuStateChanged);
    _roomDanmakuController.messages.removeListener(
      _handleDanmakuMessagesChanged,
    );
    _roomDanmakuController.dispose();
    _followWatchlistController.listenable
        .removeListener(_handleFollowWatchlistStateChanged);
    _followWatchlistController.dispose();
    _panelController.removeListener(_handlePanelControllerChanged);
    _panelController.dispose();
    _controlsActionCoordinator
        .removeListener(_handleControlsActionCoordinatorChanged);
    _controlsActionCoordinator.dispose();
    _pageSessionCoordinator
        .removeListener(_handlePageSessionCoordinatorChanged);
    _pageSessionCoordinator.dispose();
    _roomTwitchRecoveryController.dispose();
    _playbackController.removeListener(_handlePlaybackControllerChanged);
    _playbackController.dispose();
    _followRoomTransitionCoordinator.removeListener(
      _handleFollowRoomTransitionCoordinatorChanged,
    );
    _followRoomTransitionCoordinator.dispose();
    _fullscreenSessionController
        .removeListener(_handleFullscreenSessionChanged);
    unawaited(_playerRuntimeObserver.dispose());
    if (!_fullscreenSessionController.preserveRoomTransitionOnDispose) {
      unawaited(_restoreSystemUi());
      unawaited(_setScreenAwake(false));
      unawaited(_pageSessionCoordinator.cleanupPlaybackOnLeave());
    }
    _chatViewportCoordinator.dispose();
    _panelPageController.dispose();
    if (_desktopMiniWindowActive &&
        !_fullscreenSessionController.preserveRoomTransitionOnDispose) {
      unawaited(_exitDesktopMiniWindow());
    }
    _fullscreenSessionController.dispose();
    super.dispose();
  }

  Future<void> _updateRoomUiPreferences(RoomUiPreferences preferences) async {
    await _pageSessionCoordinator.updateRoomUiPreferences(preferences);
  }

  Future<void> _ensureFollowWatchlistLoaded({bool force = false}) async {
    await _followWatchlistController.ensureLoaded(force: force);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    unawaited(_handleLifecycleState(state));
  }

  Future<void> _handleLifecycleState(AppLifecycleState state) async {
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
    final descriptor =
        widget.dependencies.findProviderDescriptorById(widget.providerId.value);
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
          await _pageInteractionCoordinator.leaveRoom(
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
                  onPressed: _pageInteractionCoordinator.leaveRoom,
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                title: FutureBuilder<RoomSessionLoadResult>(
                  future: _future,
                  builder: (context, snapshot) {
                    return Text(
                      snapshot.data?.snapshot.detail.title ??
                          _activeRoomDetail?.title ??
                          '${descriptor?.displayName ?? widget.providerId.value} · ${widget.roomId}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    );
                  },
                ),
                actions: [
                  IconButton(
                    key: const Key('room-appbar-more-button'),
                    tooltip: '更多',
                    onPressed:
                        _pageInteractionCoordinator.showQuickActionsSheet,
                    icon: const Icon(Icons.more_horiz_rounded),
                  ),
                ],
              ),
        body: FutureBuilder<RoomSessionLoadResult>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.hasError && !snapshot.hasData) {
              _resolveFullscreenBootstrap(
                roomLoaded: true,
                playbackAvailable: false,
              );
              final presentation = _describeRoomLoadError(snapshot.error);
              return RoomErrorState(
                title: presentation.title,
                message: presentation.description,
                detail: '${snapshot.error}',
                onRetry: () => _pageInteractionCoordinator.refreshRoom(),
                onOpenSettings: _pageInteractionCoordinator.openPlayerSettings,
              );
            }
            if (!snapshot.hasData) {
              return RoomLoadingRoomShell(
                data: _loadingShellViewData(
                  descriptor: descriptor,
                ),
              );
            }

            final state = snapshot.data!;
            final room = state.snapshot.detail;
            final isRefreshing =
                snapshot.connectionState != ConnectionState.done;
            final playbackSource =
                _playbackSource ?? state.resolved?.playbackSource;
            final playUrls =
                _playUrls.isEmpty ? state.snapshot.playUrls : _playUrls;
            final hasPlayback = playbackSource != null && playUrls.isNotEmpty;
            final activePlaybackSource = hasPlayback ? playbackSource : null;
            _panelController.schedulePageSync();

            return Stack(
              children: [
                RoomPreviewSections(
                  data: _sectionsViewData(
                    state: state,
                    room: room,
                    descriptor: descriptor,
                  ),
                  pageController: _panelPageController,
                  selectedPanel: _selectedPanel,
                  onSelectPanel: _panelController.selectPanel,
                  onPageChanged: _panelController.handlePageChanged,
                  chatPanel: RoomChatPanel(
                    messagesListenable: _messagesNotifier,
                    ancillaryLoading: _ancillaryLoading,
                    hasDanmakuSession: _danmakuSession != null,
                    room: room,
                    scrollController: _chatViewportCoordinator.controller,
                    chatTextSize: _chatTextSize,
                    chatTextGap: _chatTextGap,
                    chatBubbleStyle: _chatBubbleStyle,
                    onRefreshRoom: () {
                      unawaited(
                        _pageInteractionCoordinator.refreshRoom(
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
                  controlsPanel: _buildControlsPanel(
                    state: state,
                    playUrls: playUrls,
                    playbackSource: playbackSource,
                    hasPlayback: hasPlayback,
                  ),
                  playerSurface: RoomPlayerSurfaceSection(
                    data: _playerSurfaceViewData(
                      room: room,
                      hasPlayback: hasPlayback,
                      embedPlayer: !fullscreenSessionActive,
                      fullscreen: false,
                      inlineQualityLabel: hasPlayback
                          ? _compactQualityLabel(
                              _effectiveQualityOf(state).label)
                          : null,
                      inlineLineLabel: activePlaybackSource != null
                          ? _compactLineLabel(
                              _lineLabelOf(playUrls, activePlaybackSource),
                            )
                          : null,
                    ),
                    buildEmbeddedPlayerView: _embeddedPlayerView,
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
                            unawaited(_enterFullscreen());
                          }
                        : null,
                    onRefresh: _playerBindingInFlight
                        ? null
                        : () {
                            unawaited(
                              _pageInteractionCoordinator.refreshRoom(
                                showFeedback: true,
                              ),
                            );
                          },
                    onToggleDanmakuOverlay: hasPlayback
                        ? () {
                            _pageSessionCoordinator.updateDanmakuOverlayVisible(
                              !_showDanmakuOverlay,
                            );
                          }
                        : null,
                    onOpenDanmakuSettings:
                        _pageInteractionCoordinator.openDanmakuSettings,
                    onShowQuality: hasPlayback
                        ? () => _pageInteractionCoordinator.showQualitySheet(
                              state,
                            )
                        : null,
                    onShowLine: activePlaybackSource != null
                        ? () => _pageInteractionCoordinator.showLineSheet(
                              playUrls,
                              activePlaybackSource,
                            )
                        : null,
                    onKeepInlinePlayerChromeVisible:
                        _showInlinePlayerChromeTemporarily,
                  ),
                  onToggleFollow: () => _toggleFollow(state.snapshot),
                  onRefresh: () => _pageInteractionCoordinator.refreshRoom(
                    showFeedback: true,
                  ),
                  onShareRoom: () => _shareRoomLink(room),
                ),
                if (isRefreshing)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surface
                              .withValues(alpha: 0.24),
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
                          color: Theme.of(context)
                              .colorScheme
                              .surface
                              .withValues(alpha: 0.32),
                        ),
                        child: const Center(
                          child: CircularProgressIndicator.adaptive(),
                        ),
                      ),
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
                        if (_playerBindingInFlight) {
                          return;
                        }
                        if (_isFullscreen) {
                          unawaited(_exitFullscreen());
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
                          _pageInteractionCoordinator.showPlayerDebugSheet(
                            state,
                            playbackSource,
                          ),
                        );
                      },
                      onShowMore: () {
                        unawaited(
                          _pageInteractionCoordinator.showQuickActionsSheet(),
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
                          _pageInteractionCoordinator.refreshRoom(
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
                          _pageInteractionCoordinator.openDanmakuSettings(),
                        );
                        _scheduleFullscreenChromeAutoHide();
                      },
                      onShowQuality: () {
                        unawaited(
                          _pageInteractionCoordinator.showQualitySheet(state),
                        );
                        _scheduleFullscreenChromeAutoHide();
                      },
                      onShowLine: () {
                        unawaited(
                          _pageInteractionCoordinator.showLineSheet(
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

    if (!widget.dependencies.fullscreenSessionPlatforms.androidPlaybackBridge
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
