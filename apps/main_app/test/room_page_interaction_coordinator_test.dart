import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:live_storage/live_storage.dart';
import 'package:nolive_app/src/app/routing/app_routes.dart';
import 'package:nolive_app/src/features/library/application/load_follow_watchlist_use_case.dart';
import 'package:nolive_app/src/features/room/application/load_room_use_case.dart';
import 'package:nolive_app/src/features/room/application/room_session_controller.dart';
import 'package:nolive_app/src/features/room/application/twitch_playback_recovery.dart';
import 'package:nolive_app/src/features/room/presentation/room_controls_view_data.dart';
import 'package:nolive_app/src/features/room/presentation/room_page_interaction_coordinator.dart';
import 'package:nolive_app/src/features/room/presentation/room_page_session_coordinator.dart';
import 'package:nolive_app/src/features/room/presentation/room_playback_session_state.dart';
import 'package:nolive_app/src/features/settings/application/manage_danmaku_preferences_use_case.dart';
import 'package:nolive_app/src/features/settings/application/manage_player_preferences_use_case.dart';
import 'package:nolive_app/src/features/settings/application/manage_room_ui_preferences_use_case.dart';

void main() {
  test(
      'page interaction coordinator exits fullscreen before opening player settings and handles return after pop',
      () async {
    final harness = _InteractionHarness();
    final coordinator = harness.createCoordinator();

    await coordinator.openPlayerSettings();

    expect(
      harness.events,
      <String>[
        'loadPlayerPreferences',
        'exitFullscreen',
        'pushNamed:${AppRoutes.playerSettings}:false',
        'handlePlayerSettingsReturn',
      ],
    );
    expect(
      harness.handledPlayerSettingsPreviousPreferences,
      same(harness.loadedPlayerPreferences),
    );
  });

  test(
      'page interaction coordinator aborts danmaku settings return when page unmounts after navigation',
      () async {
    final harness = _InteractionHarness();
    harness.onPushNamed = ({
      required routeName,
      required rootNavigator,
    }) async {
      harness.mounted = false;
    };
    final coordinator = harness.createCoordinator();

    await coordinator.openDanmakuSettings();

    expect(
      harness.events,
      <String>[
        'exitFullscreen',
        'pushNamed:${AppRoutes.danmakuSettings}:false',
      ],
    );
    expect(harness.handleDanmakuSettingsReturnCalls, 0);
  });

  test(
      'page interaction coordinator shows message when quick actions open before room is ready',
      () async {
    final harness = _InteractionHarness()
      ..roomFuture = Future<RoomSessionLoadResult>.error(
        StateError('not ready'),
      );
    final coordinator = harness.createCoordinator();

    await coordinator.showQuickActionsSheet();

    expect(harness.messages, <String>['房间尚未准备完成，请稍后再试']);
    expect(harness.quickActionsPresented, isFalse);
  });

  test(
      'page interaction coordinator refresh keeps success and failure feedback semantics',
      () async {
    final successHarness = _InteractionHarness();
    final successCoordinator = successHarness.createCoordinator();

    await successCoordinator.refreshRoom(
      showFeedback: true,
      reloadPlayer: true,
      forcePlaybackRebind: false,
    );

    expect(
      successHarness.lastRefreshCall,
      (
        showFeedback: true,
        reloadPlayer: true,
        forcePlaybackRebind: false,
      ),
    );
    expect(successHarness.messages, <String>['房间信息已刷新']);

    final failureHarness = _InteractionHarness()
      ..refreshError = StateError('refresh failed');
    final failureCoordinator = failureHarness.createCoordinator();

    await failureCoordinator.refreshRoom(showFeedback: true);

    expect(failureHarness.messages, <String>['房间刷新失败，请稍后重试']);
  });

  test(
      'page interaction coordinator leaves room by exiting fullscreen then cleanup then popping page',
      () async {
    final harness = _InteractionHarness();
    final coordinator = harness.createCoordinator();

    await coordinator.leaveRoom();

    expect(
      harness.events,
      <String>[
        'exitFullscreen',
        'leaveRoomCleanup',
        'popPage',
      ],
    );
    expect(harness.popCalls, 1);
  });

  test(
      'page interaction coordinator uses replacement room route for follow-room navigation and forwards messages',
      () async {
    final harness = _InteractionHarness()
      ..followTransitionPreserveFullscreen = true
      ..followTransitionMessage = '已在当前房间';
    final coordinator = harness.createCoordinator();
    final entry = FollowWatchEntry(
      record: const FollowRecord(
        providerId: 'douyu',
        roomId: '3125893',
        streamerName: '斗鱼样例主播',
      ),
      detail: const LiveRoomDetail(
        providerId: 'douyu',
        roomId: '3125893',
        title: '斗鱼样例直播间',
        streamerName: '斗鱼样例主播',
        isLive: true,
      ),
    );

    await coordinator.commitFollowRoomNavigation(entry);

    expect(harness.followTransitionEntry, same(entry));
    expect(harness.replacedRoomArgs?.providerId, ProviderId.douyu);
    expect(harness.replacedRoomArgs?.roomId, '3125893');
    expect(harness.replacedRoomArgs?.startInFullscreen, isTrue);
    expect(harness.messages, <String>['已在当前房间']);
  });
}

class _InteractionHarness {
  bool mounted = true;
  final List<String> events = <String>[];
  final List<String> messages = <String>[];
  final List<({String routeName, bool rootNavigator})> pushedRoutes =
      <({String routeName, bool rootNavigator})>[];

  Future<void> Function({
    required String routeName,
    required bool rootNavigator,
  })? onPushNamed;

  RoomRouteArguments? replacedRoomArgs;
  int popCalls = 0;
  int handleDanmakuSettingsReturnCalls = 0;
  PlayerPreferences loadedPlayerPreferences = _playerPreferences();
  PlayerPreferences? handledPlayerSettingsPreviousPreferences;
  Future<RoomSessionLoadResult> roomFuture =
      Future<RoomSessionLoadResult>.value(_roomState());
  RoomPageSessionState pageSessionState = const RoomPageSessionState.initial();
  RoomPlaybackSessionState playbackSession = const RoomPlaybackSessionState();
  PlaybackSource? currentPlaybackSource;
  List<LivePlayUrl> currentPlayUrls = const <LivePlayUrl>[];
  RoomControlsViewData controlsViewData = _controlsViewData();
  RoomPlayerDebugViewData debugViewData = _debugViewData();
  bool quickActionsPresented = false;
  DateTime? scheduledCloseAt;
  ({bool showFeedback, bool reloadPlayer, bool forcePlaybackRebind})?
      lastRefreshCall;
  Object? refreshError;
  FollowWatchEntry? followTransitionEntry;
  bool? followTransitionPreserveFullscreen;
  String? followTransitionMessage;

  RoomPageInteractionCoordinator createCoordinator() {
    return RoomPageInteractionCoordinator(
      context: RoomPageInteractionContext(
        isMounted: () => mounted,
        exitFullscreenIfNeeded: () async {
          events.add('exitFullscreen');
        },
        showMessage: (message) {
          messages.add(message);
        },
        pushNamed: (routeName, {rootNavigator = false}) async {
          events.add('pushNamed:$routeName:$rootNavigator');
          pushedRoutes.add(
            (routeName: routeName, rootNavigator: rootNavigator),
          );
          await onPushNamed?.call(
            routeName: routeName,
            rootNavigator: rootNavigator,
          );
        },
        pushReplacementToRoom: (args) async {
          events.add('pushReplacementToRoom');
          replacedRoomArgs = args;
        },
        popPage: () {
          events.add('popPage');
          popCalls += 1;
        },
        loadPlayerPreferences: () async {
          events.add('loadPlayerPreferences');
          return loadedPlayerPreferences;
        },
        handlePlayerSettingsReturn: (previousPreferences) async {
          events.add('handlePlayerSettingsReturn');
          handledPlayerSettingsPreviousPreferences = previousPreferences;
        },
        handleDanmakuSettingsReturn: () async {
          events.add('handleDanmakuSettingsReturn');
          handleDanmakuSettingsReturnCalls += 1;
        },
        resolveRoomFuture: () => roomFuture,
        resolveIsLeavingRoom: () => pageSessionState.isLeavingRoom,
        resolveCurrentPlaybackSource: () => currentPlaybackSource,
        resolveCurrentPlayUrls: () => currentPlayUrls,
        resolveRequestedQuality: (state) => state.snapshot.selectedQuality,
        resolveControlsViewData: ({
          required state,
          required playUrls,
          required playbackSource,
          required hasPlayback,
        }) {
          return controlsViewData;
        },
        resolvePlayerDebugViewData: ({
          required state,
          required playbackSource,
        }) {
          return debugViewData;
        },
        cycleScaleModeAndResolveControlsViewData: ({
          required state,
          required playUrls,
          required playbackSource,
          required hasPlayback,
        }) async {
          return controlsViewData;
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
        }) async {
          events.add('presentQuickActionsSheet');
          quickActionsPresented = true;
        },
        presentQualitySheet: ({
          required selectedQuality,
          required qualities,
          required onSelected,
        }) async {
          events.add('presentQualitySheet');
        },
        presentLineSheet: ({
          required playUrls,
          required playbackSource,
          required onSelected,
        }) async {
          events.add('presentLineSheet');
        },
        presentAutoCloseSheet: ({
          required scheduledCloseAt,
          required onSelectDuration,
        }) async {
          events.add('presentAutoCloseSheet');
        },
        presentPlayerDebugSheet: ({required debugViewData}) async {
          events.add('presentPlayerDebugSheet');
        },
        enterPictureInPicture: () async {
          events.add('enterPictureInPicture');
        },
        toggleDesktopMiniWindow: () async {
          events.add('toggleDesktopMiniWindow');
        },
        captureScreenshot: () async {
          events.add('captureScreenshot');
        },
        refreshRoom: ({
          bool showFeedback = false,
          bool reloadPlayer = false,
          bool forcePlaybackRebind = true,
        }) async {
          events.add('refreshRoom');
          lastRefreshCall = (
            showFeedback: showFeedback,
            reloadPlayer: reloadPlayer,
            forcePlaybackRebind: forcePlaybackRebind,
          );
          final error = refreshError;
          if (error != null) {
            throw error;
          }
        },
        leaveRoomCleanup: () async {
          events.add('leaveRoomCleanup');
        },
        switchQuality: (snapshot, quality) async {
          events.add('switchQuality:${quality.id}');
        },
        switchLine: (playUrl) async {
          events.add('switchLine:${playUrl.url}');
        },
        resolveScheduledCloseAt: () => scheduledCloseAt,
        setAutoCloseTimer: (duration) {
          events.add('setAutoCloseTimer:${duration?.inSeconds ?? 'null'}');
        },
        openFollowRoomTransition: (
          entry, {
          required commitNavigation,
          required showMessage,
        }) async {
          events.add('openFollowRoomTransition');
          followTransitionEntry = entry;
          final preserveFullscreen = followTransitionPreserveFullscreen;
          if (preserveFullscreen != null) {
            await commitNavigation(preserveFullscreen);
          }
          final message = followTransitionMessage;
          if (message != null) {
            showMessage(message);
          }
        },
      ),
    );
  }
}

const LivePlayQuality _defaultQuality = LivePlayQuality(
  id: 'auto',
  label: '自动',
  isDefault: true,
);

PlayerPreferences _playerPreferences() {
  return const PlayerPreferences(
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
}

RoomControlsViewData _controlsViewData() {
  return const RoomControlsViewData(
    hasPlayback: true,
    playbackUnavailableReason: '当前房间暂无可用播放流',
    requestedQualityLabel: '自动',
    effectiveQualityLabel: '自动',
    currentLineLabel: '主线路',
    scaleModeLabel: '适应',
    pipSupported: true,
    supportsDesktopMiniWindow: true,
    desktopMiniWindowActive: false,
    supportsPlayerCapture: true,
    scheduledCloseAt: null,
    chatTextSize: 16,
    chatTextGap: 4,
    chatBubbleStyle: false,
    showPlayerSuperChat: true,
    playerSuperChatDisplaySeconds: 6,
  );
}

RoomPlayerDebugViewData _debugViewData() {
  return const RoomPlayerDebugViewData(
    backendLabel: 'MPV',
    currentStatusLabel: 'playing',
    requestedQualityLabel: '自动',
    effectiveQualityLabel: '自动',
    currentLineLabel: '主线路',
    scaleModeLabel: '适应',
    usingNativeDanmakuBatchMask: false,
  );
}

RoomSessionLoadResult _roomState() {
  return RoomSessionLoadResult(
    snapshot: const LoadedRoomSnapshot(
      providerId: ProviderId.bilibili,
      detail: LiveRoomDetail(
        providerId: 'bilibili',
        roomId: '6',
        title: '系统演示直播间',
        streamerName: '系统演示主播',
        isLive: true,
      ),
      qualities: <LivePlayQuality>[_defaultQuality],
      selectedQuality: _defaultQuality,
      playUrls: <LivePlayUrl>[
        LivePlayUrl(
          url: 'https://example.com/live.m3u8',
          lineLabel: '主线路',
        ),
      ],
    ),
    resolved: null,
    playerPreferences: _playerPreferences(),
    danmakuPreferences: DanmakuPreferences.defaults,
    roomUiPreferences: RoomUiPreferences.defaults,
    blockedKeywords: const <String>[],
    playbackQuality: _defaultQuality,
    startupPlan: const TwitchStartupPlan(startupQuality: _defaultQuality),
  );
}
