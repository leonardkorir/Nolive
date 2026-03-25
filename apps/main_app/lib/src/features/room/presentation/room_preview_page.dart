import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:floating/floating.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_player/live_player.dart';
import 'package:live_storage/live_storage.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';
import 'package:nolive_app/src/app/platform/android_playback_bridge.dart';
import 'package:nolive_app/src/app/routing/app_routes.dart';
import 'package:nolive_app/src/features/room/application/load_room_use_case.dart';
import 'package:nolive_app/src/features/room/application/room_playback_backend_policy.dart';
import 'package:nolive_app/src/features/room/application/room_playback_startup_quality_policy.dart';
import 'package:nolive_app/src/features/room/application/resolve_play_source_use_case.dart';
import 'package:nolive_app/src/features/room/application/twitch_playback_recovery.dart';
import 'package:nolive_app/src/features/room/presentation/room_danmaku_batch.dart';
import 'package:nolive_app/src/features/library/application/load_follow_watchlist_use_case.dart';
import 'package:nolive_app/src/features/settings/application/manage_danmaku_preferences_use_case.dart';
import 'package:nolive_app/src/features/settings/application/manage_player_preferences_use_case.dart';
import 'package:nolive_app/src/features/settings/application/manage_room_ui_preferences_use_case.dart';
import 'package:nolive_app/src/features/settings/presentation/player_settings_page.dart';
import 'package:nolive_app/src/shared/presentation/theme/zh_text.dart';
import 'package:nolive_app/src/shared/presentation/widgets/app_surface_card.dart';
import 'package:nolive_app/src/shared/presentation/widgets/follow_watch_row.dart';
import 'package:nolive_app/src/shared/presentation/widgets/persisted_network_image.dart';
import 'package:nolive_app/src/shared/presentation/widgets/streamer_avatar.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

part 'room_preview_page_controls.dart';
part 'room_preview_page_player_system.dart';
part 'room_preview_page_player_surface.dart';
part 'room_preview_page_fullscreen.dart';
part 'room_preview_page_danmaku.dart';
part 'room_preview_page_follow.dart';
part 'room_preview_page_state_support.dart';
part 'room_preview_page_sections.dart';
part 'room_preview_page_panels.dart';
part 'room_preview_page_section_widgets.dart';

class RoomPreviewPage extends StatefulWidget {
  const RoomPreviewPage({
    required this.bootstrap,
    required this.providerId,
    required this.roomId,
    this.startInFullscreen = false,
    super.key,
  });

  final AppBootstrap bootstrap;
  final ProviderId providerId;
  final String roomId;
  final bool startInFullscreen;

  @override
  State<RoomPreviewPage> createState() => _RoomPreviewPageState();
}

class _RoomPreviewPageState extends State<RoomPreviewPage>
    with WidgetsBindingObserver {
  late Future<_RoomPageState> _future;
  Future<FollowWatchlist>? _followWatchlistFuture;
  FollowWatchlist? _followWatchlistCache;
  bool _followWatchlistHydrated = false;
  int _followWatchlistRequestId = 0;
  LivePlayQuality? _selectedQuality;
  LivePlayQuality? _effectiveQuality;
  PlaybackSource? _playbackSource;
  List<LivePlayUrl> _playUrls = const [];
  PlaybackSource? _pendingPlaybackSource;
  bool _pendingPlaybackAvailable = false;
  bool _pendingPlaybackAutoPlay = false;
  bool _playbackBootstrapScheduled = false;
  bool _isFollowed = false;
  bool _autoPlayEnabled = true;
  bool _forceHttpsEnabled = false;
  bool _showDanmakuOverlay = true;
  DanmakuPreferences _danmakuPreferences = DanmakuPreferences.defaults;
  bool _isFullscreen = false;
  bool _fullscreenBootstrapPending = false;
  bool _fullscreenBootstrapScheduled = false;
  bool _showInlinePlayerChrome = true;
  bool _showFullscreenChrome = true;
  bool _lockFullscreenControls = false;
  bool _autoFullscreenEnabled = true;
  bool _backgroundAutoPauseEnabled = true;
  bool _pipHideDanmakuEnabled = true;
  bool _pipSupported = false;
  bool _enteringPictureInPicture = false;
  bool _pausedByLifecycle = false;
  bool _restoreDanmakuAfterPip = false;
  bool _danmakuVisibleBeforePip = true;
  bool _fullscreenAutoApplied = false;
  bool _gestureTracking = false;
  bool _gestureAdjustingBrightness = false;
  double _gestureStartY = 0;
  double _gestureStartVolume = 1;
  double _gestureStartBrightness = 0.5;
  String? _gestureTipText;
  double _volume = 1;
  PlayerScaleMode _scaleMode = PlayerScaleMode.contain;
  final ScreenBrightness _screenBrightness = ScreenBrightness();
  final Floating _floating = Floating();
  DanmakuSession? _danmakuSession;
  StreamSubscription<LiveMessage>? _danmakuSubscription;
  StreamSubscription<PiPStatus>? _pipStatusSubscription;
  final List<LiveMessage> _pendingDanmakuMessages = <LiveMessage>[];
  final ValueNotifier<List<LiveMessage>> _messagesNotifier =
      ValueNotifier<List<LiveMessage>>(const []);
  final ValueNotifier<List<LiveMessage>> _superChatMessagesNotifier =
      ValueNotifier<List<LiveMessage>>(const []);
  final ValueNotifier<List<LiveMessage>> _playerSuperChatMessagesNotifier =
      ValueNotifier<List<LiveMessage>>(const []);
  _RoomPanel _selectedPanel = _RoomPanel.chat;
  Timer? _danmakuFlushTimer;
  Timer? _fullscreenChromeTimer;
  Timer? _inlineChromeTimer;
  Timer? _autoCloseTimer;
  DateTime? _scheduledCloseAt;
  double _chatTextSize = 14;
  double _chatTextGap = 4;
  bool _chatBubbleStyle = false;
  bool _showPlayerSuperChat = true;
  int _playerSuperChatDisplaySeconds = 8;
  final ScrollController _chatScrollController = ScrollController();
  final PageController _panelPageController = PageController();
  bool _isLeavingRoom = false;
  bool _playbackCleanedUp = false;
  bool _darkThemeActive = false;
  Size? _inlinePlayerViewportSize;
  LiveRoomDetail? _activeRoomDetail;
  List<String> _blockedDanmakuKeywords = const [];
  bool _showFullscreenFollowDrawer = false;
  Timer? _gestureTipTimer;
  Timer? _playerSuperChatOverlayTimer;
  Timer? _danmakuReconnectTimer;
  bool _danmakuReconnectInFlight = false;
  int _danmakuReconnectAttempt = 0;
  bool _preserveRoomTransitionOnDispose = false;
  StreamSubscription<PlayerState>? _playerStateLogSubscription;
  String? _lastPlayerStateLogSignature;
  int _ancillaryLoadToken = 0;
  bool _ancillaryLoading = false;
  int _twitchRecoveryToken = 0;
  String? _twitchRecoverySourceKey;
  int _twitchRecoveryAttempts = 0;
  LivePlayQuality? _twitchStartupPromotionQuality;

  void _roomTrace(String message) {
    if (!kDebugMode) {
      return;
    }
    debugPrint(
      '[RoomPreview/${widget.providerId.value}/${widget.roomId}] $message',
    );
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

  void _attachPlayerStateLogging() {
    _playerStateLogSubscription ??= widget.bootstrap.player.states.listen((
      state,
    ) {
      final signature = [
        state.status.name,
        state.errorMessage ?? '',
        _summarizePlaybackSource(state.source),
        (state.buffered.inSeconds / 5).floor(),
      ].join('|');
      if (_lastPlayerStateLogSignature == signature) {
        return;
      }
      _lastPlayerStateLogSignature = signature;
      _roomTrace(
        'player status=${state.status.name} '
        'buffer=${state.buffered.inMilliseconds}ms '
        'pos=${state.position.inMilliseconds}ms '
        'source=${_summarizePlaybackSource(state.source)} '
        'error=${state.errorMessage ?? '-'}',
      );
    });
  }

  void _updateViewState(VoidCallback updater) {
    if (!mounted) {
      updater();
      return;
    }
    setState(updater);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.startInFullscreen) {
      _fullscreenBootstrapPending = true;
    }
    _future = _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (!widget.startInFullscreen) {
        _scheduleInlineChromeAutoHide();
      }
    });
    widget.bootstrap.followWatchlistSnapshot
        .addListener(_handleFollowWatchlistSnapshotChanged);
    _followWatchlistCache = _runtimeFollowWatchlistSnapshot;
    _followWatchlistHydrated = _runtimeFollowWatchlistSnapshot != null;
    unawaited(_setScreenAwake(true));
    unawaited(_primeAndroidPlaybackState());
    _attachPlayerStateLogging();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _darkThemeActive = Theme.of(context).brightness == Brightness.dark;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ancillaryLoadToken += 1;
    widget.bootstrap.followWatchlistSnapshot
        .removeListener(_handleFollowWatchlistSnapshotChanged);
    _fullscreenChromeTimer?.cancel();
    _inlineChromeTimer?.cancel();
    _autoCloseTimer?.cancel();
    _gestureTipTimer?.cancel();
    _playerSuperChatOverlayTimer?.cancel();
    _danmakuReconnectTimer?.cancel();
    unawaited(_playerStateLogSubscription?.cancel());
    if (!_preserveRoomTransitionOnDispose) {
      unawaited(_restoreSystemUi());
      unawaited(_setScreenAwake(false));
      unawaited(_cleanupPlaybackOnLeave());
    }
    unawaited(_pipStatusSubscription?.cancel());
    _chatScrollController.dispose();
    _panelPageController.dispose();
    _disposeDanmakuSessionNow();
    _messagesNotifier.dispose();
    _superChatMessagesNotifier.dispose();
    _playerSuperChatMessagesNotifier.dispose();
    super.dispose();
  }

  Future<_RoomPageState> _load({String? preferredQualityId}) async {
    final startedAt = DateTime.now();
    _roomTrace('load start preferredQuality=${preferredQualityId ?? '-'}');
    final preferences = await widget.bootstrap.loadPlayerPreferences();
    final blockedKeywords = await widget.bootstrap.loadBlockedKeywords();
    final danmakuPreferences = await widget.bootstrap.loadDanmakuPreferences();
    final roomUiPreferences = await widget.bootstrap.loadRoomUiPreferences();
    final player = widget.bootstrap.player;
    final runtimeBackend = resolveRoomPlaybackBackend(
      providerId: widget.providerId,
      preferredBackend: preferences.backend,
      targetPlatform: defaultTargetPlatform,
      isWeb: kIsWeb,
    );
    if (runtimeBackend != preferences.backend) {
      _roomTrace(
        'runtime backend override '
        '${preferences.backend.name} -> ${runtimeBackend.name}',
      );
    }
    if (player is SwitchablePlayer && player.backend != runtimeBackend) {
      await player.switchBackend(runtimeBackend);
    }
    await player.initialize();
    await player.setVolume(Platform.isAndroid ? 1.0 : preferences.volume);

    final snapshot = await widget.bootstrap.loadRoom(
      providerId: widget.providerId,
      roomId: widget.roomId,
      preferHighestQuality: preferences.preferHighestQuality,
    );
    _roomTrace(
      'loadRoom done in ${DateTime.now().difference(startedAt).inMilliseconds}ms '
      'qualities=${snapshot.qualities.length} '
      'playUrls=${snapshot.playUrls.length} '
      'selected=${snapshot.selectedQuality.id}/${snapshot.selectedQuality.label}',
    );
    final requestedQuality = preferredQualityId == null
        ? snapshot.selectedQuality
        : snapshot.qualities.firstWhere(
            (item) => item.id == preferredQualityId,
            orElse: () => snapshot.selectedQuality,
          );
    final startupRequestedQuality = resolveRoomStartupRequestedQuality(
      providerId: snapshot.providerId,
      qualities: snapshot.qualities,
      requestedQuality: requestedQuality,
      targetPlatform: defaultTargetPlatform,
      explicitSelection: preferredQualityId != null,
      isWeb: kIsWeb,
    );
    final startupPlan = _resolveTwitchStartupPlan(
      snapshot: snapshot,
      requestedQuality: startupRequestedQuality,
    );
    final playbackQuality = startupPlan.startupQuality;
    _applyTwitchStartupPlan(startupPlan);
    if (playbackQuality.id != requestedQuality.id ||
        playbackQuality.label != requestedQuality.label) {
      _roomTrace(
        'startup quality adjusted '
        '${requestedQuality.id}/${requestedQuality.label} -> '
        '${playbackQuality.id}/${playbackQuality.label}',
      );
    }
    final resolved = await _resolveRoomPlayback(
      snapshot: snapshot,
      quality: playbackQuality,
      preferHttps: preferences.forceHttpsEnabled,
    );

    _chatTextSize = roomUiPreferences.chatTextSize;
    _chatTextGap = roomUiPreferences.chatTextGap;
    _chatBubbleStyle = roomUiPreferences.chatBubbleStyle;
    _showPlayerSuperChat = roomUiPreferences.showPlayerSuperChat;
    _playerSuperChatDisplaySeconds =
        roomUiPreferences.playerSuperChatDisplaySeconds;
    _activeRoomDetail = snapshot.detail;
    _blockedDanmakuKeywords = blockedKeywords;

    _autoPlayEnabled = preferences.autoPlayEnabled;
    _forceHttpsEnabled = preferences.forceHttpsEnabled;
    _autoFullscreenEnabled = preferences.androidAutoFullscreenEnabled;
    _backgroundAutoPauseEnabled = preferences.androidBackgroundAutoPauseEnabled;
    _pipHideDanmakuEnabled = preferences.androidPipHideDanmakuEnabled;
    _scaleMode = preferences.scaleMode;
    _fullscreenAutoApplied = false;
    _volume = preferences.volume;
    _danmakuPreferences = danmakuPreferences;
    _showDanmakuOverlay = danmakuPreferences.enabledByDefault;
    _selectedQuality = playbackQuality;
    _effectiveQuality = resolved?.effectiveQuality ?? playbackQuality;
    _playbackSource = resolved?.playbackSource;
    _playUrls = resolved?.playUrls ?? snapshot.playUrls;
    _scheduleAncillaryLoad(
      snapshot: snapshot,
      blockedKeywords: blockedKeywords,
    );
    _roomTrace(
      'load core complete in ${DateTime.now().difference(startedAt).inMilliseconds}ms '
      'playback=${_summarizePlaybackSource(_playbackSource)}',
    );
    return _RoomPageState(
      snapshot: snapshot,
      resolved: resolved,
      preferences: preferences,
    );
  }

  Future<ResolvedPlaySource?> _resolveRoomPlayback({
    required LoadedRoomSnapshot snapshot,
    required LivePlayQuality quality,
    required bool preferHttps,
  }) async {
    if (!snapshot.hasPlayback) {
      return null;
    }
    final startedAt = DateTime.now();
    final resolved = await widget.bootstrap.resolvePlaySource(
      providerId: widget.providerId,
      detail: snapshot.detail,
      quality: quality,
      preferHttps: preferHttps,
      preloadedPlayUrls: _canReuseSnapshotPlayUrls(
        snapshot: snapshot,
        requestedQuality: quality,
      )
          ? snapshot.playUrls
          : null,
    );
    _roomTrace(
      'resolvePlaySource done in ${DateTime.now().difference(startedAt).inMilliseconds}ms '
      'quality=${quality.id}/${quality.label} '
      'effective=${resolved.effectiveQuality.id}/${resolved.effectiveQuality.label} '
      'playback=${_summarizePlaybackSource(resolved.playbackSource)}',
    );
    return resolved;
  }

  bool _canReuseSnapshotPlayUrls({
    required LoadedRoomSnapshot snapshot,
    required LivePlayQuality requestedQuality,
  }) {
    return snapshot.selectedQuality.id == requestedQuality.id &&
        snapshot.selectedQuality.label == requestedQuality.label;
  }

  void _scheduleAncillaryLoad({
    required LoadedRoomSnapshot snapshot,
    required List<String> blockedKeywords,
  }) {
    final token = ++_ancillaryLoadToken;
    _updateViewState(() {
      _ancillaryLoading = true;
    });
    unawaited(
      _loadAncillaryRoomState(
        token: token,
        snapshot: snapshot,
        blockedKeywords: blockedKeywords,
      ),
    );
  }

  Future<void> _loadAncillaryRoomState({
    required int token,
    required LoadedRoomSnapshot snapshot,
    required List<String> blockedKeywords,
  }) async {
    final startedAt = DateTime.now();
    _roomTrace('ancillary start room=${snapshot.detail.roomId}');
    final danmakuFuture = widget.bootstrap.openRoomDanmaku(
      providerId: widget.providerId,
      detail: snapshot.detail,
    );
    final followFuture = widget.bootstrap.isFollowedRoom(
      providerId: widget.providerId.value,
      roomId: snapshot.detail.roomId,
    );

    DanmakuSession? danmakuSession;
    try {
      danmakuSession = await danmakuFuture;
      if (!mounted || token != _ancillaryLoadToken) {
        await danmakuSession?.disconnect();
        return;
      }
      await _bindDanmakuSession(danmakuSession, blockedKeywords);
      if (!mounted || token != _ancillaryLoadToken) {
        await _disposeDanmakuSession();
        return;
      }
    } catch (error) {
      _roomTrace(
        'ancillary danmaku failed after '
        '${DateTime.now().difference(startedAt).inMilliseconds}ms: $error',
      );
    }

    var isFollowed = _isFollowed;
    try {
      isFollowed = await followFuture;
    } catch (error) {
      _roomTrace(
        'ancillary follow failed after '
        '${DateTime.now().difference(startedAt).inMilliseconds}ms: $error',
      );
    }

    if (!mounted || token != _ancillaryLoadToken) {
      return;
    }
    _updateViewState(() {
      _isFollowed = isFollowed;
      _ancillaryLoading = false;
    });
    _roomTrace(
      'ancillary complete in ${DateTime.now().difference(startedAt).inMilliseconds}ms '
      'danmaku=${danmakuSession != null} followed=$isFollowed',
    );
  }

  Future<void> _updateRoomUiPreferences(RoomUiPreferences preferences) async {
    setState(() {
      _chatTextSize = preferences.chatTextSize;
      _chatTextGap = preferences.chatTextGap;
      _chatBubbleStyle = preferences.chatBubbleStyle;
      _showPlayerSuperChat = preferences.showPlayerSuperChat;
      _playerSuperChatDisplaySeconds =
          preferences.playerSuperChatDisplaySeconds;
    });
    await widget.bootstrap.updateRoomUiPreferences(preferences);
    _syncPlayerSuperChatOverlay();
  }

  Future<void> _ensureFollowWatchlistLoaded({bool force = false}) async {
    if (!force &&
        (_followWatchlistFuture != null || _followWatchlistHydrated)) {
      return;
    }

    final requestId = ++_followWatchlistRequestId;
    final future = widget.bootstrap.loadFollowWatchlist();
    if (mounted) {
      setState(() {
        _followWatchlistFuture = future;
      });
    } else {
      _followWatchlistFuture = future;
    }

    try {
      final watchlist = await future;
      if (!mounted || requestId != _followWatchlistRequestId) {
        return;
      }
      widget.bootstrap.followWatchlistSnapshot.value = watchlist;
      setState(() {
        _followWatchlistCache = watchlist;
        _followWatchlistFuture = null;
        _followWatchlistHydrated = true;
      });
    } catch (_) {
      if (!mounted || requestId != _followWatchlistRequestId) {
        return;
      }
      setState(() {
        _followWatchlistFuture = null;
      });
    }
  }

  Future<void> _refreshRoom({
    bool showFeedback = false,
    bool reloadPlayer = false,
  }) async {
    final previousFuture = _future;
    final future = reloadPlayer
        ? _load(preferredQualityId: _selectedQuality?.id)
        : _refreshRoomData(
            previousFuture: previousFuture,
            preferredQualityId: _selectedQuality?.id,
          );
    setState(() {
      _future = future;
    });
    _resetDanmakuReconnectState();
    _messagesNotifier.value = const [];
    _superChatMessagesNotifier.value = const [];
    _playerSuperChatMessagesNotifier.value = const [];
    try {
      await future;
      if (!mounted || !showFeedback) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('房间信息已刷新')),
      );
    } catch (_) {
      if (!mounted || !showFeedback) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('房间刷新失败，请稍后重试')),
      );
    }
  }

  Future<_RoomPageState> _refreshRoomData({
    required Future<_RoomPageState> previousFuture,
    String? preferredQualityId,
  }) async {
    try {
      final previous = await previousFuture;
      return _reloadRoomData(
        previous,
        preferredQualityId: preferredQualityId,
      );
    } catch (_) {
      return _load(preferredQualityId: preferredQualityId);
    }
  }

  Future<_RoomPageState> _reloadRoomData(
    _RoomPageState previous, {
    String? preferredQualityId,
  }) async {
    final preferences = previous.preferences;
    final blockedKeywords = await widget.bootstrap.loadBlockedKeywords();

    final snapshot = await widget.bootstrap.loadRoom(
      providerId: widget.providerId,
      roomId: widget.roomId,
      preferHighestQuality: preferences.preferHighestQuality,
      recordHistory: false,
    );
    final requestedQuality = preferredQualityId == null
        ? snapshot.selectedQuality
        : snapshot.qualities.firstWhere(
            (item) => item.id == preferredQualityId,
            orElse: () => snapshot.selectedQuality,
          );
    final startupRequestedQuality = resolveRoomStartupRequestedQuality(
      providerId: snapshot.providerId,
      qualities: snapshot.qualities,
      requestedQuality: requestedQuality,
      targetPlatform: defaultTargetPlatform,
      explicitSelection: preferredQualityId != null,
      isWeb: kIsWeb,
    );
    final startupPlan = _resolveTwitchStartupPlan(
      snapshot: snapshot,
      requestedQuality: startupRequestedQuality,
    );
    final playbackQuality = startupPlan.startupQuality;
    _applyTwitchStartupPlan(startupPlan);
    final resolved = await _resolveRoomPlayback(
      snapshot: snapshot,
      quality: playbackQuality,
      preferHttps: preferences.forceHttpsEnabled,
    );

    _activeRoomDetail = snapshot.detail;
    _blockedDanmakuKeywords = blockedKeywords;
    _selectedQuality = playbackQuality;
    _effectiveQuality = resolved?.effectiveQuality ?? playbackQuality;
    _playbackSource = resolved?.playbackSource;
    _playUrls = resolved?.playUrls ?? snapshot.playUrls;
    _scheduleAncillaryLoad(
      snapshot: snapshot,
      blockedKeywords: blockedKeywords,
    );
    return _RoomPageState(
      snapshot: snapshot,
      resolved: resolved,
      preferences: preferences,
    );
  }

  void _applyTwitchStartupPlan(TwitchStartupPlan plan) {
    _twitchStartupPromotionQuality = plan.promotionQuality;
    _twitchRecoveryToken += 1;
    _twitchRecoverySourceKey = null;
    _twitchRecoveryAttempts = 0;
  }

  TwitchStartupPlan _resolveTwitchStartupPlan({
    required LoadedRoomSnapshot snapshot,
    required LivePlayQuality requestedQuality,
  }) {
    if (snapshot.providerId != ProviderId.twitch) {
      return TwitchStartupPlan(startupQuality: requestedQuality);
    }
    return resolveTwitchStartupPlan(
      qualities: snapshot.qualities,
      requestedQuality: requestedQuality,
    );
  }

  Future<void> _leaveRoom() async {
    if (_isLeavingRoom) {
      return;
    }
    if (_isFullscreen) {
      await _exitFullscreen();
      return;
    }
    if (mounted) {
      setState(() {
        _isLeavingRoom = true;
      });
    } else {
      _isLeavingRoom = true;
    }
    await _cleanupPlaybackOnLeave();
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _cleanupPlaybackOnLeave() async {
    if (_playbackCleanedUp) {
      return;
    }
    _playbackCleanedUp = true;
    _fullscreenChromeTimer?.cancel();
    _inlineChromeTimer?.cancel();
    _pausedByLifecycle = false;
    final player = widget.bootstrap.player;
    if (!Platform.isAndroid) {
      await player.stop();
      return;
    }
    if (_enteringPictureInPicture) {
      return;
    }
    final inPip =
        await AndroidPlaybackBridge.instance.isInPictureInPictureMode();
    if (!inPip) {
      await player.stop();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    unawaited(_handleLifecycleState(state));
  }

  Future<void> _handleLifecycleState(AppLifecycleState state) async {
    if (!Platform.isAndroid) {
      return;
    }
    final player = widget.bootstrap.player;
    if (state == AppLifecycleState.resumed) {
      final inPip =
          await AndroidPlaybackBridge.instance.isInPictureInPictureMode();
      _enteringPictureInPicture = false;
      if (!inPip && _restoreDanmakuAfterPip && mounted) {
        setState(() {
          _showDanmakuOverlay = _danmakuVisibleBeforePip;
          _restoreDanmakuAfterPip = false;
        });
      }
      if (!inPip && _pausedByLifecycle) {
        _pausedByLifecycle = false;
        await player.play();
      }
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      if (_enteringPictureInPicture) {
        return;
      }
      final inPip =
          await AndroidPlaybackBridge.instance.isInPictureInPictureMode();
      if (inPip) {
        return;
      }
      if (!_backgroundAutoPauseEnabled) {
        return;
      }
      if (player.currentState.status == PlaybackStatus.playing) {
        _pausedByLifecycle = true;
        await player.pause();
      }
    }
  }

  Future<void> _updateScaleMode(PlayerScaleMode scaleMode) async {
    final preferences = await widget.bootstrap.loadPlayerPreferences();
    await widget.bootstrap.updatePlayerPreferences(
      preferences.copyWith(scaleMode: scaleMode),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _scaleMode = scaleMode;
    });
  }

  void _maybeApplyAutoFullscreen(
    PlayerState? playerState, {
    required bool playbackAvailable,
  }) {
    if (!Platform.isAndroid ||
        !playbackAvailable ||
        !_autoFullscreenEnabled ||
        _fullscreenAutoApplied ||
        _isFullscreen) {
      return;
    }
    final status = playerState?.status ?? PlaybackStatus.idle;
    if (status != PlaybackStatus.ready &&
        status != PlaybackStatus.playing &&
        status != PlaybackStatus.buffering) {
      return;
    }
    _fullscreenAutoApplied = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isFullscreen) {
        return;
      }
      unawaited(_enterFullscreen());
    });
  }

  @override
  Widget build(BuildContext context) {
    final descriptor =
        widget.bootstrap.providerRegistry.findDescriptor(widget.providerId);
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
          await _leaveRoom();
        }
      },
      child: Scaffold(
        appBar: fullscreenSessionActive
            ? null
            : AppBar(
                leading: IconButton(
                  key: const Key('room-leave-button'),
                  tooltip: '返回',
                  onPressed: _leaveRoom,
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                title: FutureBuilder<_RoomPageState>(
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
                    onPressed: _showQuickActionsSheet,
                    icon: const Icon(Icons.more_horiz_rounded),
                  ),
                ],
              ),
        body: FutureBuilder<_RoomPageState>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.hasError && !snapshot.hasData) {
              _resolveFullscreenBootstrap(
                roomLoaded: true,
                playbackAvailable: false,
              );
              final presentation = _describeRoomLoadError(snapshot.error);
              return _RoomErrorState(
                title: presentation.$1,
                message: presentation.$2,
                detail: '${snapshot.error}',
                onRetry: () => _refreshRoom(showFeedback: false),
                onOpenSettings: _openPlayerSettings,
              );
            }
            if (!snapshot.hasData) {
              return _buildLoadingRoomShell(
                context: context,
                descriptor: descriptor,
              );
            }

            final state = snapshot.data!;
            final room = state.snapshot.detail;
            final isRefreshing =
                snapshot.connectionState != ConnectionState.done;
            final selectedQuality = _requestedQualityOf(state);
            final effectiveQuality = _effectiveQualityOf(state);
            final playbackSource =
                _playbackSource ?? state.resolved?.playbackSource;
            final playUrls =
                _playUrls.isEmpty ? state.snapshot.playUrls : _playUrls;
            final hasPlayback = playbackSource != null && playUrls.isNotEmpty;
            _schedulePlaybackBootstrap(
              playbackSource: playbackSource,
              hasPlayback: hasPlayback,
              autoPlay: state.preferences.autoPlayEnabled,
            );
            _scheduleTwitchPlaybackRecovery(
              snapshot: state.snapshot,
              playbackSource: playbackSource,
              playUrls: playUrls,
              qualities: state.snapshot.qualities,
              selectedQuality: selectedQuality,
            );
            _resolveFullscreenBootstrap(
              roomLoaded: snapshot.connectionState == ConnectionState.done,
              playbackAvailable: hasPlayback,
            );
            final availableBackends =
                widget.bootstrap.player is SwitchablePlayer
                    ? (widget.bootstrap.player as SwitchablePlayer)
                        .supportedBackends
                        .where((backend) =>
                            !widget.bootstrap.isLiveMode ||
                            backend != PlayerBackend.memory)
                        .toList(growable: false)
                    : [widget.bootstrap.player.backend];

            return StreamBuilder<PlayerState>(
              initialData: widget.bootstrap.player.currentState,
              stream: widget.bootstrap.player.states,
              builder: (context, playerSnapshot) {
                final playerState = playerSnapshot.data;
                _maybeApplyAutoFullscreen(
                  playerState,
                  playbackAvailable: hasPlayback,
                );
                return Stack(
                  children: [
                    _buildRoomBody(
                      context: context,
                      state: state,
                      room: room,
                      fullscreenActive: fullscreenSessionActive,
                      descriptor: descriptor,
                      selectedQuality: selectedQuality,
                      effectiveQuality: effectiveQuality,
                      playbackSource: playbackSource,
                      playUrls: playUrls,
                      hasPlayback: hasPlayback,
                      availableBackends: availableBackends,
                      playerState: playerState,
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
                        child: _buildFullscreenOverlay(
                          context: context,
                          state: state,
                          room: room,
                          descriptor: descriptor,
                          playerState: playerState,
                          playbackSource: playbackSource,
                          playUrls: playUrls,
                        ),
                      ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );

    if (!Platform.isAndroid) {
      return page;
    }

    return PiPSwitcher(
      floating: _floating,
      duration: Duration.zero,
      childWhenDisabled: page,
      childWhenEnabled: _buildPictureInPictureChild(),
    );
  }
}
