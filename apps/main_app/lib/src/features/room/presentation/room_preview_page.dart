import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:floating/floating.dart';
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
import 'package:nolive_app/src/features/room/application/resolve_play_source_use_case.dart';
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
part 'room_preview_page_sections.dart';
part 'room_preview_page_panels.dart';
part 'room_preview_page_section_widgets.dart';

class RoomPreviewPage extends StatefulWidget {
  const RoomPreviewPage({
    required this.bootstrap,
    required this.providerId,
    required this.roomId,
    super.key,
  });

  final AppBootstrap bootstrap;
  final ProviderId providerId;
  final String roomId;

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
  bool _isFollowed = false;
  bool _autoPlayEnabled = true;
  bool _forceHttpsEnabled = false;
  bool _showDanmakuOverlay = true;
  DanmakuPreferences _danmakuPreferences = DanmakuPreferences.defaults;
  bool _isFullscreen = false;
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
  final ScrollController _chatScrollController = ScrollController();
  final PageController _panelPageController = PageController();
  bool _isLeavingRoom = false;
  bool _playbackCleanedUp = false;
  bool _darkThemeActive = false;
  Size? _inlinePlayerViewportSize;

  FollowWatchlist? get _runtimeFollowWatchlistSnapshot =>
      widget.bootstrap.followWatchlistSnapshot.value;

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
    _future = _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _scheduleInlineChromeAutoHide();
      }
    });
    widget.bootstrap.followWatchlistSnapshot
        .addListener(_handleFollowWatchlistSnapshotChanged);
    _followWatchlistCache = _runtimeFollowWatchlistSnapshot;
    _followWatchlistHydrated = _runtimeFollowWatchlistSnapshot != null;
    unawaited(_setScreenAwake(true));
    unawaited(_primeAndroidPlaybackState());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _darkThemeActive = Theme.of(context).brightness == Brightness.dark;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.bootstrap.followWatchlistSnapshot
        .removeListener(_handleFollowWatchlistSnapshotChanged);
    _fullscreenChromeTimer?.cancel();
    _inlineChromeTimer?.cancel();
    _autoCloseTimer?.cancel();
    unawaited(_restoreSystemUi());
    unawaited(_setScreenAwake(false));
    unawaited(_cleanupPlaybackOnLeave());
    unawaited(_pipStatusSubscription?.cancel());
    _chatScrollController.dispose();
    _panelPageController.dispose();
    _disposeDanmakuSession();
    _messagesNotifier.dispose();
    _superChatMessagesNotifier.dispose();
    super.dispose();
  }

  Future<_RoomPageState> _load({String? preferredQualityId}) async {
    final preferences = await widget.bootstrap.loadPlayerPreferences();
    final blockedKeywords = await widget.bootstrap.loadBlockedKeywords();
    final danmakuPreferences = await widget.bootstrap.loadDanmakuPreferences();
    final roomUiPreferences = await widget.bootstrap.loadRoomUiPreferences();
    final player = widget.bootstrap.player;
    if (player is SwitchablePlayer && player.backend != preferences.backend) {
      await player.switchBackend(preferences.backend);
    }
    await player.initialize();
    await player.setVolume(Platform.isAndroid ? 1.0 : preferences.volume);

    final snapshot = await widget.bootstrap.loadRoom(
      providerId: widget.providerId,
      roomId: widget.roomId,
      preferHighestQuality: preferences.preferHighestQuality,
    );
    final quality = preferredQualityId == null
        ? snapshot.selectedQuality
        : snapshot.qualities.firstWhere(
            (item) => item.id == preferredQualityId,
            orElse: () => snapshot.selectedQuality,
          );
    ResolvedPlaySource? resolved;
    if (snapshot.hasPlayback) {
      resolved = await widget.bootstrap.resolvePlaySource(
        providerId: widget.providerId,
        detail: snapshot.detail,
        quality: quality,
        preferHttps: preferences.forceHttpsEnabled,
      );
      await player.setSource(resolved.playbackSource);
      if (preferences.autoPlayEnabled) {
        await player.play();
      }
    } else {
      await player.stop();
    }

    final danmakuSession = await widget.bootstrap.openRoomDanmaku(
      providerId: widget.providerId,
      detail: snapshot.detail,
    );
    await _bindDanmakuSession(danmakuSession, blockedKeywords);

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
    _chatTextSize = roomUiPreferences.chatTextSize;
    _chatTextGap = roomUiPreferences.chatTextGap;
    _chatBubbleStyle = roomUiPreferences.chatBubbleStyle;
    _showPlayerSuperChat = roomUiPreferences.showPlayerSuperChat;
    _selectedQuality = quality;
    _effectiveQuality = resolved?.effectiveQuality ?? quality;
    _playbackSource = resolved?.playbackSource;
    _playUrls = resolved?.playUrls ?? snapshot.playUrls;
    _isFollowed = await widget.bootstrap.isFollowedRoom(
      providerId: widget.providerId.value,
      roomId: snapshot.detail.roomId,
    );
    return _RoomPageState(
      snapshot: snapshot,
      resolved: resolved,
      preferences: preferences,
    );
  }

  RoomUiPreferences get _roomUiPreferences => RoomUiPreferences(
        chatTextSize: _chatTextSize,
        chatTextGap: _chatTextGap,
        chatBubbleStyle: _chatBubbleStyle,
        showPlayerSuperChat: _showPlayerSuperChat,
      );

  Future<void> _updateRoomUiPreferences(RoomUiPreferences preferences) async {
    setState(() {
      _chatTextSize = preferences.chatTextSize;
      _chatTextGap = preferences.chatTextGap;
      _chatBubbleStyle = preferences.chatBubbleStyle;
      _showPlayerSuperChat = preferences.showPlayerSuperChat;
    });
    await widget.bootstrap.updateRoomUiPreferences(preferences);
  }

  void _handleFollowWatchlistSnapshotChanged() {
    if (!mounted) {
      return;
    }
    setState(() {
      _followWatchlistCache = _runtimeFollowWatchlistSnapshot;
      _followWatchlistHydrated = _runtimeFollowWatchlistSnapshot != null;
    });
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

  void _selectPanel(_RoomPanel panel) {
    if (_selectedPanel == panel) {
      return;
    }
    setState(() {
      _selectedPanel = panel;
    });
    if (_panelPageController.hasClients) {
      unawaited(
        _panelPageController.animateToPage(
          panel.index,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        ),
      );
    }
    if (panel == _RoomPanel.chat) {
      _scheduleChatScrollToBottom(force: true);
    }
    if (panel == _RoomPanel.follow) {
      unawaited(_ensureFollowWatchlistLoaded());
    }
  }

  void _handlePanelPageChanged(int index) {
    final nextPanel = _RoomPanel.values[index];
    if (_selectedPanel == nextPanel || !mounted) {
      return;
    }
    setState(() {
      _selectedPanel = nextPanel;
    });
    if (nextPanel == _RoomPanel.chat) {
      _scheduleChatScrollToBottom(force: true);
    }
    if (nextPanel == _RoomPanel.follow) {
      unawaited(_ensureFollowWatchlistLoaded());
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
    _messagesNotifier.value = const [];
    _superChatMessagesNotifier.value = const [];
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
    final quality = preferredQualityId == null
        ? snapshot.selectedQuality
        : snapshot.qualities.firstWhere(
            (item) => item.id == preferredQualityId,
            orElse: () => snapshot.selectedQuality,
          );
    final player = widget.bootstrap.player;
    ResolvedPlaySource? resolved;
    if (snapshot.hasPlayback) {
      resolved = await widget.bootstrap.resolvePlaySource(
        providerId: widget.providerId,
        detail: snapshot.detail,
        quality: quality,
        preferHttps: preferences.forceHttpsEnabled,
      );
      await player.setSource(resolved.playbackSource);
      if (preferences.autoPlayEnabled) {
        await player.play();
      }
    } else {
      await player.stop();
    }

    final danmakuSession = await widget.bootstrap.openRoomDanmaku(
      providerId: widget.providerId,
      detail: snapshot.detail,
    );
    await _bindDanmakuSession(danmakuSession, blockedKeywords);

    _selectedQuality = quality;
    _effectiveQuality = resolved?.effectiveQuality ?? quality;
    _playbackSource = resolved?.playbackSource;
    _playUrls = resolved?.playUrls ?? snapshot.playUrls;
    _isFollowed = await widget.bootstrap.isFollowedRoom(
      providerId: widget.providerId.value,
      roomId: snapshot.detail.roomId,
    );
    return _RoomPageState(
      snapshot: snapshot,
      resolved: resolved,
      preferences: preferences,
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

  BoxFit _fitForScaleMode() {
    return switch (_scaleMode) {
      PlayerScaleMode.contain => BoxFit.contain,
      PlayerScaleMode.cover => BoxFit.cover,
      PlayerScaleMode.fill => BoxFit.fill,
      PlayerScaleMode.fitWidth => BoxFit.fitWidth,
      PlayerScaleMode.fitHeight => BoxFit.fitHeight,
    };
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

    final page = PopScope(
      canPop: _isLeavingRoom && !_isFullscreen,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) {
          return;
        }
        if (_isFullscreen) {
          await _exitFullscreen();
          return;
        }
        if (!_isLeavingRoom) {
          await _leaveRoom();
        }
      },
      child: Scaffold(
        appBar: _isFullscreen
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
                      snapshot.data?.snapshot.detail.title ?? '直播间',
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
              return const Center(child: CircularProgressIndicator.adaptive());
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
                    if (_isFullscreen && hasPlayback)
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

enum _RoomPanel {
  chat,
  superChat,
  follow,
  settings,
}

class _RoomPageState {
  const _RoomPageState({
    required this.snapshot,
    required this.resolved,
    required this.preferences,
  });

  final LoadedRoomSnapshot snapshot;
  final ResolvedPlaySource? resolved;
  final PlayerPreferences preferences;
}

class _ChaturbateRoomStatusPresentation {
  const _ChaturbateRoomStatusPresentation({
    required this.label,
    required this.description,
  });

  final String label;
  final String description;
}
