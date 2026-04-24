import 'dart:async';

import 'package:floating/floating.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';
import 'package:nolive_app/src/features/room/application/load_room_use_case.dart';
import 'package:nolive_app/src/features/room/application/resolve_play_source_use_case.dart';
import 'package:nolive_app/src/features/room/application/room_ancillary_controller.dart';
import 'package:nolive_app/src/features/room/application/room_preview_dependencies.dart';
import 'package:nolive_app/src/features/room/application/room_session_controller.dart';
import 'package:nolive_app/src/features/room/application/twitch_playback_recovery.dart';
import 'package:nolive_app/src/features/room/presentation/room_danmaku_controller.dart';
import 'package:nolive_app/src/features/room/presentation/room_fullscreen_runtime_context.dart';
import 'package:nolive_app/src/features/room/presentation/room_fullscreen_session_controller.dart';
import 'package:nolive_app/src/features/room/presentation/room_fullscreen_session_platforms.dart';
import 'package:nolive_app/src/features/room/presentation/room_page_session_coordinator.dart';
import 'package:nolive_app/src/features/room/presentation/room_playback_controller.dart';
import 'package:nolive_app/src/features/room/presentation/room_runtime_helper_contexts.dart';
import 'package:nolive_app/src/features/room/presentation/room_twitch_recovery_controller.dart';
import 'package:nolive_app/src/features/settings/application/manage_danmaku_preferences_use_case.dart';
import 'package:nolive_app/src/features/settings/application/manage_player_preferences_use_case.dart';
import 'package:nolive_app/src/features/settings/application/manage_room_ui_preferences_use_case.dart';
import 'package:nolive_app/src/shared/application/player_runtime_controller.dart';

import 'room_fullscreen_test_fakes.dart';

void main() {
  test(
      'page session coordinator initial load applies session and schedules playback bootstrap and ancillary load',
      () async {
    final harness = _RoomPageSessionHarness();
    addTearDown(harness.dispose);
    final coordinator = harness.createCoordinator();
    addTearDown(coordinator.dispose);
    harness.sessionController.nextLoadResult = harness.primaryResult;
    harness.ancillaryController.nextLoadResult = RoomAncillaryLoadResult(
      danmakuSession: harness.primaryDanmakuSession,
      isFollowed: true,
    );

    await coordinator.startInitialLoad();
    await _flushAsyncWork();

    expect(coordinator.state.latestLoadedState, same(harness.primaryResult));
    expect(
      coordinator.state.playbackSession.activeRoomDetail?.roomId,
      harness.primaryRoom.roomId,
    );
    expect(coordinator.state.isFollowed, isTrue);
    expect(coordinator.state.ancillaryLoading, isFalse);
    expect(coordinator.state.showDanmakuOverlay, isTrue);
    expect(coordinator.state.volume,
        harness.primaryResult.playerPreferences.volume);
    expect(harness.playbackController.scheduledBootstraps, hasLength(1));
    expect(harness.playbackController.scheduledBootstraps.single.hasPlayback,
        isTrue);
    expect(harness.ancillaryController.loadCalls, 1);
    expect(harness.danmakuController.configureCalls, hasLength(1));
    expect(harness.danmakuController.boundSession,
        same(harness.primaryDanmakuSession));
    expect(harness.fullscreenController.resolvedStates,
        <(bool, bool)>[(true, true)]);
    expect(harness.syncPlayerRuntimeCalls, 1);
    expect(harness.twitchRecoverySchedules, hasLength(1));
    expect(harness.fullscreenController.resetAutoFullscreenAppliedCalls, 1);
  });

  test(
      'page session coordinator load failure clears current session and playback availability',
      () async {
    final harness = _RoomPageSessionHarness();
    addTearDown(harness.dispose);
    final coordinator = harness.createCoordinator();
    addTearDown(coordinator.dispose);
    harness.sessionController.nextLoadError = StateError('load failed');

    await expectLater(
      coordinator.startInitialLoad(),
      throwsA(isA<StateError>()),
    );
    await _flushAsyncWork();

    expect(coordinator.state.latestLoadedState, isNull);
    expect(coordinator.state.playbackSession.playbackAvailable, isFalse);
    expect(harness.sessionController.clearCurrentCalls, 1);
    expect(harness.playbackController.resetRecoveryStateCalls, 1);
    expect(harness.fullscreenController.resolvedStates,
        <(bool, bool)>[(true, false)]);
    expect(harness.syncPlayerRuntimeCalls, 1);
  });

  test(
      'page session coordinator drops stale ancillary result after load failure',
      () async {
    final harness = _RoomPageSessionHarness();
    addTearDown(harness.dispose);
    final coordinator = harness.createCoordinator();
    addTearDown(coordinator.dispose);
    final ancillaryCompleter = Completer<RoomAncillaryLoadResult>();
    harness.sessionController.nextLoadResult = harness.primaryResult;
    harness.ancillaryController.onLoad = ({
      required snapshot,
      required fallbackIsFollowed,
    }) {
      return ancillaryCompleter.future;
    };

    await coordinator.startInitialLoad();
    await _flushAsyncWork();
    expect(coordinator.state.ancillaryLoading, isTrue);

    harness.sessionController.nextReloadError = StateError('refresh failed');
    await expectLater(
      coordinator.refreshRoom(),
      throwsA(isA<StateError>()),
    );
    await _flushAsyncWork();

    expect(coordinator.state.latestLoadedState, isNull);
    expect(coordinator.state.ancillaryLoading, isFalse);

    ancillaryCompleter.complete(
      RoomAncillaryLoadResult(
        danmakuSession: harness.primaryDanmakuSession,
        isFollowed: true,
      ),
    );
    await _flushAsyncWork();

    expect(harness.primaryDanmakuSession.disconnectCalls, 1);
    expect(harness.danmakuController.boundSession, isNull);
    expect(coordinator.state.isFollowed, isFalse);
  });

  test(
      'page session coordinator refresh skips when playback rebind is running or refresh already in flight',
      () async {
    final harness = _RoomPageSessionHarness();
    addTearDown(harness.dispose);
    final coordinator = harness.createCoordinator();
    addTearDown(coordinator.dispose);
    harness.sessionController.nextLoadResult = harness.primaryResult;
    harness.ancillaryController.nextLoadResult = const RoomAncillaryLoadResult(
      danmakuSession: null,
      isFollowed: false,
    );
    await coordinator.startInitialLoad();
    await _flushAsyncWork();

    harness.playbackController.rebindInFlightOverride = true;
    await coordinator.refreshRoom();
    expect(harness.sessionController.reloadCalls, 0);
    expect(harness.danmakuController.clearFeedCalls, 0);

    harness.playbackController.rebindInFlightOverride = false;
    final reloadCompleter = Completer<RoomSessionLoadResult>();
    harness.sessionController.nextReloadFuture = reloadCompleter.future;
    final firstRefresh = coordinator.refreshRoom();
    await _flushAsyncWork();
    await coordinator.refreshRoom();
    expect(harness.sessionController.reloadCalls, 1);
    expect(coordinator.state.refreshInFlight, isTrue);

    reloadCompleter.complete(harness.secondaryResult);
    await firstRefresh;
    await _flushAsyncWork();
    expect(coordinator.state.refreshInFlight, isFalse);
  });

  test(
      'page session coordinator drops stale ancillary result and disconnects extra danmaku session',
      () async {
    final harness = _RoomPageSessionHarness();
    addTearDown(harness.dispose);
    final coordinator = harness.createCoordinator();
    addTearDown(coordinator.dispose);
    final firstAncillary = Completer<RoomAncillaryLoadResult>();
    final secondAncillary = Completer<RoomAncillaryLoadResult>();
    harness.sessionController.nextLoadResult = harness.primaryResult;
    harness.sessionController.nextReloadResult = harness.secondaryResult;
    harness.ancillaryController.onLoad = ({
      required snapshot,
      required fallbackIsFollowed,
    }) {
      if (snapshot.detail.roomId == harness.primaryRoom.roomId) {
        return firstAncillary.future;
      }
      return secondAncillary.future;
    };

    await coordinator.startInitialLoad();
    await _flushAsyncWork();

    final refreshFuture = coordinator.refreshRoom();
    await _flushAsyncWork();
    secondAncillary.complete(
      RoomAncillaryLoadResult(
        danmakuSession: harness.secondaryDanmakuSession,
        isFollowed: true,
      ),
    );
    await refreshFuture;
    await _flushAsyncWork();

    firstAncillary.complete(
      RoomAncillaryLoadResult(
        danmakuSession: harness.primaryDanmakuSession,
        isFollowed: false,
      ),
    );
    await _flushAsyncWork();

    expect(harness.primaryDanmakuSession.disconnectCalls, 1);
    expect(harness.danmakuController.boundSession,
        same(harness.secondaryDanmakuSession));
    expect(coordinator.state.isFollowed, isTrue);
  });

  test(
      'page session coordinator clears ancillary loading before danmaku bind finishes',
      () async {
    final harness = _RoomPageSessionHarness();
    addTearDown(harness.dispose);
    final coordinator = harness.createCoordinator();
    addTearDown(coordinator.dispose);
    final bindCompleter = Completer<void>();
    harness.sessionController.nextLoadResult = harness.primaryResult;
    harness.ancillaryController.nextLoadResult = RoomAncillaryLoadResult(
      danmakuSession: harness.primaryDanmakuSession,
      isFollowed: true,
    );
    harness.danmakuController.onBind = ({
      required activeRoomDetail,
      required session,
    }) {
      return bindCompleter.future;
    };

    final loadFuture = coordinator.startInitialLoad();
    await _flushAsyncWork();

    expect(coordinator.state.ancillaryLoading, isFalse);
    expect(coordinator.state.isFollowed, isTrue);
    expect(harness.danmakuController.boundSession,
        same(harness.primaryDanmakuSession));

    bindCompleter.complete();
    await loadFuture;
  });

  test(
      'page session coordinator leave-room cleanup waits for playback rebind before fullscreen cleanup',
      () async {
    final harness = _RoomPageSessionHarness();
    addTearDown(harness.dispose);
    final coordinator = harness.createCoordinator();
    addTearDown(coordinator.dispose);
    final waitCompleter = Completer<void>();
    harness.playbackController.waitCompleter = waitCompleter;

    final leavingFuture = coordinator.leaveRoom();
    expect(coordinator.state.isLeavingRoom, isTrue);
    expect(
        harness.playbackController.waitReasons, <String>['cleanup playback']);
    expect(harness.fullscreenController.cleanupCalls, 0);

    waitCompleter.complete();
    await leavingFuture;

    expect(harness.danmakuController.closeSessionCalls, 1);
    expect(harness.fullscreenController.cleanupCalls, 1);
  });

  test('page session coordinator initial load waits for queued runtime cleanup',
      () async {
    final harness = _RoomPageSessionHarness();
    addTearDown(harness.dispose);
    final coordinator = harness.createCoordinator();
    addTearDown(coordinator.dispose);
    harness.sessionController.nextLoadResult = harness.primaryResult;
    final cleanupCompleter = Completer<void>();

    final queuedCleanup = harness.sessionController.dependencies.playerRuntime
        .serializeRoomTeardown(() async {
      await cleanupCompleter.future;
    });

    final loadFuture = coordinator.startInitialLoad();
    await _flushAsyncWork();

    expect(harness.sessionController.loadCalls, 0);
    expect(
      harness.traces,
      containsAllInOrder(<String>[
        'load waiting for pending cleanup',
      ]),
    );

    cleanupCompleter.complete();
    await queuedCleanup;
    await loadFuture;
    await _flushAsyncWork();

    expect(harness.sessionController.loadCalls, 1);
    expect(
      harness.traces,
      containsAllInOrder(<String>[
        'load waiting for pending cleanup',
        'load pending cleanup released',
      ]),
    );
  });

  test('page session coordinator resets leaving state when cleanup fails',
      () async {
    final harness = _RoomPageSessionHarness();
    addTearDown(harness.dispose);
    final coordinator = harness.createCoordinator();
    addTearDown(coordinator.dispose);
    harness.fullscreenController.cleanupError = StateError('cleanup failed');

    await expectLater(
      coordinator.leaveRoom(),
      throwsA(isA<StateError>()),
    );

    expect(coordinator.state.isLeavingRoom, isFalse);
    expect(harness.fullscreenController.cleanupCalls, 1);
    expect(harness.danmakuController.closeSessionCalls, 0);
  });

  test('page session coordinator refreshes lifecycle restore playback source',
      () async {
    final harness = _RoomPageSessionHarness();
    addTearDown(harness.dispose);
    final coordinator = harness.createCoordinator();
    addTearDown(coordinator.dispose);
    harness.sessionController.nextLoadResult = harness.primaryResult;
    harness.sessionController.nextResolvedPlaybackRefresh = ResolvedPlaySource(
      quality: _RoomPageSessionHarness.primaryQuality,
      effectiveQuality: _RoomPageSessionHarness.secondaryQuality,
      playUrls: <LivePlayUrl>[
        LivePlayUrl(
          url: 'https://example.com/restored.m3u8',
          lineLabel: '恢复线路',
        ),
      ],
      playbackSource: PlaybackSource(
        url: Uri.parse('https://example.com/restored.m3u8'),
      ),
    );

    await coordinator.startInitialLoad();
    await _flushAsyncWork();

    final playbackSource =
        await coordinator.resolvePlaybackSourceForLifecycleRestore();

    expect(harness.sessionController.resolvePlaybackRefreshCalls, 1);
    expect(
      playbackSource?.url.toString(),
      'https://example.com/restored.m3u8',
    );
    expect(
      coordinator.state.playbackSession.playbackSource?.url.toString(),
      'https://example.com/restored.m3u8',
    );
    expect(
      coordinator.state.playbackSession.effectiveQuality?.id,
      _RoomPageSessionHarness.secondaryQuality.id,
    );
  });

  test(
      'page session coordinator applies player danmaku and room-ui preferences into coordinator state',
      () async {
    final harness = _RoomPageSessionHarness();
    addTearDown(harness.dispose);
    final coordinator = harness.createCoordinator();
    addTearDown(coordinator.dispose);
    const nextRoomUiPreferences = RoomUiPreferences(
      chatTextSize: 18,
      chatTextGap: 6,
      chatBubbleStyle: false,
      showPlayerSuperChat: false,
      playerSuperChatDisplaySeconds: 12,
    );
    final nextPlayerPreferences =
        harness.primaryResult.playerPreferences.copyWith(
      scaleMode: PlayerScaleMode.cover,
      volume: 0.4,
      autoPlayEnabled: false,
    );
    final nextDanmakuPreferences = DanmakuPreferences.defaults.copyWith(
      enabledByDefault: false,
      nativeBatchMaskEnabled: true,
    );

    coordinator.applyPlayerPreferences(nextPlayerPreferences);
    coordinator.applyDanmakuPreferences(
      preferences: nextDanmakuPreferences,
      blockedKeywords: const ['spoiler', 'mute'],
    );
    await coordinator.updateRoomUiPreferences(nextRoomUiPreferences);

    expect(coordinator.state.playerPreferences, nextPlayerPreferences);
    expect(coordinator.state.volume, 0.4);
    expect(coordinator.state.danmakuPreferences, nextDanmakuPreferences);
    expect(coordinator.state.blockedKeywords, const ['spoiler', 'mute']);
    expect(coordinator.state.showDanmakuOverlay, isFalse);
    expect(coordinator.state.roomUiPreferences, nextRoomUiPreferences);
    expect(harness.persistedRoomUiPreferences, nextRoomUiPreferences);
    expect(harness.danmakuController.configureCalls, hasLength(2));
    expect(
      harness
          .danmakuController.configureCalls.last.playerSuperChatDisplaySeconds,
      12,
    );
  });
}

Future<void> _flushAsyncWork() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

class _RoomPageSessionHarness {
  _RoomPageSessionHarness() {
    bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    dependencies = RoomPreviewDependencies.fromBootstrap(bootstrap);
    runtime = PlayerRuntimeController(player);
    sessionController = _TestRoomSessionController(
      RoomSessionDependencies.fromPreviewDependencies(dependencies),
    );
    ancillaryController = _TestRoomAncillaryController(
      RoomAncillaryDependencies.fromPreviewDependencies(dependencies),
    );
    danmakuController = _TestRoomDanmakuController(
      RoomDanmakuDependencies.fromPreviewDependencies(dependencies),
    );
    playbackController = _TestRoomPlaybackController(runtime);
    fullscreenController = _TestRoomFullscreenSessionController(runtime);
    twitchRecoveryController = RoomTwitchRecoveryController(
      runtime: RoomRuntimeInspectionContext.fromPlayerRuntime(runtime),
      trace: traces.add,
    );
  }

  final TestRecordingPlayer player = TestRecordingPlayer();
  late final AppBootstrap bootstrap;
  late final RoomPreviewDependencies dependencies;
  late final PlayerRuntimeController runtime;
  late final _TestRoomSessionController sessionController;
  late final _TestRoomAncillaryController ancillaryController;
  late final _TestRoomDanmakuController danmakuController;
  late final _TestRoomPlaybackController playbackController;
  late final _TestRoomFullscreenSessionController fullscreenController;
  late final RoomTwitchRecoveryController twitchRecoveryController;

  final List<String> traces = <String>[];
  final List<
      ({
        LoadedRoomSnapshot snapshot,
        PlaybackSource? playbackSource,
        List<LivePlayUrl> playUrls,
        LivePlayQuality selectedQuality,
      })> twitchRecoverySchedules = <({
    LoadedRoomSnapshot snapshot,
    PlaybackSource? playbackSource,
    List<LivePlayUrl> playUrls,
    LivePlayQuality selectedQuality,
  })>[];
  int syncPlayerRuntimeCalls = 0;
  RoomUiPreferences? persistedRoomUiPreferences;

  static const primaryQuality = LivePlayQuality(
    id: '720',
    label: '高清',
    sortOrder: 720,
  );
  static const secondaryQuality = LivePlayQuality(
    id: '1080',
    label: '原画',
    sortOrder: 1080,
  );

  LiveRoomDetail get primaryRoom => _roomDetail('6', 'Primary Room');
  LiveRoomDetail get secondaryRoom => _roomDetail('7', 'Secondary Room');
  final _TestDanmakuSession primaryDanmakuSession = _TestDanmakuSession();
  final _TestDanmakuSession secondaryDanmakuSession = _TestDanmakuSession();

  late final RoomSessionLoadResult primaryResult = _buildResult(
    room: primaryRoom,
    quality: primaryQuality,
    linePath: 'primary',
  );

  late final RoomSessionLoadResult secondaryResult = _buildResult(
    room: secondaryRoom,
    quality: secondaryQuality,
    linePath: 'secondary',
  );

  RoomPageSessionCoordinator createCoordinator() {
    return RoomPageSessionCoordinator(
      providerId: ProviderId.bilibili,
      sessionController: sessionController,
      ancillaryController: ancillaryController,
      danmakuController: danmakuController,
      playbackController: playbackController,
      fullscreenSessionController: fullscreenController,
      twitchRecoveryController: twitchRecoveryController,
      resolveRuntimeCurrentPlaybackSource: () => runtime.currentState.source,
      loadPlayerPreferences: () async => primaryResult.playerPreferences,
      updatePlayerPreferences: (_) async {},
      persistRoomUiPreferences: (preferences) async {
        persistedRoomUiPreferences = preferences;
      },
      trace: traces.add,
      isMounted: () => true,
      scheduleTwitchRecovery: ({
        required snapshot,
        required playbackSource,
        required playUrls,
        required selectedQuality,
      }) {
        twitchRecoverySchedules.add((
          snapshot: snapshot,
          playbackSource: playbackSource,
          playUrls: playUrls,
          selectedQuality: selectedQuality,
        ));
      },
      syncPlayerRuntimeState: () {
        syncPlayerRuntimeCalls += 1;
      },
    );
  }

  Future<void> dispose() async {
    twitchRecoveryController.dispose();
    playbackController.dispose();
    fullscreenController.dispose();
    danmakuController.dispose();
    await player.dispose();
  }

  RoomSessionLoadResult _buildResult({
    required LiveRoomDetail room,
    required LivePlayQuality quality,
    required String linePath,
  }) {
    final snapshot = LoadedRoomSnapshot(
      providerId: ProviderId.bilibili,
      detail: room,
      qualities: const <LivePlayQuality>[primaryQuality, secondaryQuality],
      selectedQuality: quality,
      playUrls: <LivePlayUrl>[
        LivePlayUrl(
          url: 'https://example.com/$linePath.m3u8',
          lineLabel: '主线路',
        ),
      ],
    );
    final playbackSource = PlaybackSource(
      url: Uri.parse('https://example.com/$linePath.m3u8'),
    );
    return RoomSessionLoadResult(
      snapshot: snapshot,
      resolved: ResolvedPlaySource(
        quality: quality,
        effectiveQuality: quality,
        playUrls: snapshot.playUrls,
        playbackSource: playbackSource,
      ),
      playerPreferences: PlayerPreferences(
        autoPlayEnabled: true,
        preferHighestQuality: false,
        backend: PlayerBackend.mpv,
        volume: 0.8,
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
      ),
      danmakuPreferences: DanmakuPreferences.defaults,
      roomUiPreferences: RoomUiPreferences.defaults,
      blockedKeywords: const ['spoiler'],
      playbackQuality: quality,
      startupPlan: TwitchStartupPlan(startupQuality: quality),
    );
  }

  static LiveRoomDetail _roomDetail(String roomId, String title) {
    return LiveRoomDetail(
      providerId: ProviderId.bilibili.value,
      roomId: roomId,
      title: title,
      streamerName: '主播$roomId',
      sourceUrl: 'https://example.com/$roomId',
    );
  }
}

class _TestRoomSessionController extends RoomSessionController {
  _TestRoomSessionController(RoomSessionDependencies dependencies)
      : super(
          dependencies: dependencies,
          providerId: ProviderId.bilibili,
          roomId: '6',
          targetPlatform: TargetPlatform.android,
          isWeb: false,
        );

  RoomSessionLoadResult? nextLoadResult;
  Object? nextLoadError;
  Object? nextReloadError;
  Future<RoomSessionLoadResult>? nextReloadFuture;
  RoomSessionLoadResult? nextReloadResult;
  ResolvedPlaySource? nextResolvedPlaybackRefresh;
  int loadCalls = 0;
  int reloadCalls = 0;
  int resolvePlaybackRefreshCalls = 0;
  int clearCurrentCalls = 0;
  RoomSessionLoadResult? currentValue;

  @override
  RoomSessionLoadResult? get current => currentValue;

  @override
  void clearCurrent() {
    clearCurrentCalls += 1;
    currentValue = null;
  }

  @override
  Future<RoomSessionLoadResult> load({String? preferredQualityId}) async {
    loadCalls += 1;
    final error = nextLoadError;
    if (error != null) {
      throw error;
    }
    final result = nextLoadResult!;
    currentValue = result;
    return result;
  }

  @override
  Future<RoomSessionLoadResult> reload({String? preferredQualityId}) async {
    reloadCalls += 1;
    final error = nextReloadError;
    if (error != null) {
      throw error;
    }
    final future = nextReloadFuture;
    if (future != null) {
      final result = await future;
      currentValue = result;
      return result;
    }
    final result = nextReloadResult ?? nextLoadResult!;
    currentValue = result;
    return result;
  }

  @override
  Future<ResolvedPlaySource> resolvePlaybackRefresh({
    required LoadedRoomSnapshot snapshot,
    required LivePlayQuality quality,
    required bool preferHttps,
  }) async {
    resolvePlaybackRefreshCalls += 1;
    final resolved = nextResolvedPlaybackRefresh;
    if (resolved != null) {
      return resolved;
    }
    return super.resolvePlaybackRefresh(
      snapshot: snapshot,
      quality: quality,
      preferHttps: preferHttps,
    );
  }
}

class _TestRoomAncillaryController extends RoomAncillaryController {
  _TestRoomAncillaryController(RoomAncillaryDependencies dependencies)
      : super(
          dependencies: dependencies,
          providerId: ProviderId.bilibili,
        );

  int loadCalls = 0;
  RoomAncillaryLoadResult nextLoadResult = const RoomAncillaryLoadResult(
    danmakuSession: null,
    isFollowed: false,
  );
  Future<RoomAncillaryLoadResult> Function({
    required LoadedRoomSnapshot snapshot,
    required bool fallbackIsFollowed,
  })? onLoad;

  @override
  Future<RoomAncillaryLoadResult> load({
    required LoadedRoomSnapshot snapshot,
    required bool fallbackIsFollowed,
  }) {
    loadCalls += 1;
    final handler = onLoad;
    if (handler != null) {
      return handler(
        snapshot: snapshot,
        fallbackIsFollowed: fallbackIsFollowed,
      );
    }
    return Future<RoomAncillaryLoadResult>.value(nextLoadResult);
  }
}

class _TestRoomDanmakuController extends RoomDanmakuController {
  _TestRoomDanmakuController(RoomDanmakuDependencies dependencies)
      : super(
          dependencies: dependencies,
          providerId: ProviderId.bilibili,
        );

  final List<
      ({
        List<String> blockedKeywords,
        bool preferNativeBatchMask,
        int playerSuperChatDisplaySeconds,
      })> configureCalls = <({
    List<String> blockedKeywords,
    bool preferNativeBatchMask,
    int playerSuperChatDisplaySeconds,
  })>[];
  int clearFeedCalls = 0;
  DanmakuSession? boundSession;
  LiveRoomDetail? boundRoomDetail;
  int closeSessionCalls = 0;
  Future<void> Function({
    required LiveRoomDetail activeRoomDetail,
    required DanmakuSession? session,
  })? onBind;

  @override
  void configure({
    required List<String> blockedKeywords,
    required bool preferNativeBatchMask,
    required int playerSuperChatDisplaySeconds,
  }) {
    configureCalls.add((
      blockedKeywords: blockedKeywords,
      preferNativeBatchMask: preferNativeBatchMask,
      playerSuperChatDisplaySeconds: playerSuperChatDisplaySeconds,
    ));
  }

  @override
  void clearFeed() {
    clearFeedCalls += 1;
  }

  @override
  Future<void> bindSession({
    required LiveRoomDetail activeRoomDetail,
    required DanmakuSession? session,
  }) async {
    boundRoomDetail = activeRoomDetail;
    boundSession = session;
    await onBind?.call(
      activeRoomDetail: activeRoomDetail,
      session: session,
    );
  }

  @override
  Future<void> closeSession() async {
    closeSessionCalls += 1;
    boundRoomDetail = null;
    boundSession = null;
  }
}

class _TestRoomPlaybackController extends RoomPlaybackController {
  _TestRoomPlaybackController(PlayerRuntimeController runtime)
      : super(
          playerRuntime: runtime,
          providerId: ProviderId.bilibili,
          trace: (_) {},
          isMounted: () => true,
          resolveCurrentPlaybackSource: () => null,
          resetEmbeddedPlayerViewAfterBackendRefresh: (_) async {},
          schedulePostFrame: (action) {
            unawaited(action());
          },
          waitForEndOfFrame: () async {},
        );

  bool rebindInFlightOverride = false;
  final List<
      ({
        PlaybackSource? playbackSource,
        bool hasPlayback,
        bool autoPlay,
        bool force,
      })> scheduledBootstraps = <({
    PlaybackSource? playbackSource,
    bool hasPlayback,
    bool autoPlay,
    bool force,
  })>[];
  final List<String> waitReasons = <String>[];
  int resetRecoveryStateCalls = 0;
  Completer<void>? waitCompleter;

  @override
  bool get rebindInFlight => rebindInFlightOverride;

  @override
  void schedulePlaybackBootstrap({
    required PlaybackSource? playbackSource,
    required bool hasPlayback,
    required bool autoPlay,
    bool force = false,
  }) {
    scheduledBootstraps.add((
      playbackSource: playbackSource,
      hasPlayback: hasPlayback,
      autoPlay: autoPlay,
      force: force,
    ));
  }

  @override
  Future<void> waitForPlaybackRebindToFinish({
    required String reason,
  }) async {
    waitReasons.add(reason);
    final completer = waitCompleter;
    if (completer != null) {
      await completer.future;
    }
  }

  @override
  void resetRecoveryState() {
    resetRecoveryStateCalls += 1;
  }
}

class _TestRoomFullscreenSessionController
    extends RoomFullscreenSessionController {
  _TestRoomFullscreenSessionController(PlayerRuntimeController runtime)
      : super(
          bindings: RoomFullscreenSessionBindings(
            runtime: RoomFullscreenRuntimeContext.fromPlayerRuntime(runtime),
            trace: (_) {},
            showMessage: (_) {},
            ensureFollowWatchlistLoaded: () async {},
            resolveDarkThemeActive: () => false,
            resolveBackgroundAutoPauseEnabled: () => true,
            resolvePipHideDanmakuEnabled: () => true,
            resolveDanmakuOverlayVisible: () => true,
            updateDanmakuOverlayVisible: (_) {},
            resolveVolume: () => 1,
            updateVolume: (_) {},
            resolvePipAspectRatio: () => const Rational(16, 9),
            resolveScreenSize: () => const Size(1080, 1920),
            resolvePlaybackSourceForLifecycleRestore: () async => null,
          ),
          platforms: RoomFullscreenSessionPlatforms(
            androidPlaybackBridge: TestRoomAndroidPlaybackBridgeFacade(),
            pipHost: TestRoomPipHostFacade(),
            desktopWindow: TestRoomDesktopWindowFacade(),
            screenAwake: TestRoomScreenAwakeFacade(),
            systemUi: TestRoomSystemUiFacade(),
          ),
        );

  final List<(bool, bool)> resolvedStates = <(bool, bool)>[];
  int cleanupCalls = 0;
  int resetAutoFullscreenAppliedCalls = 0;
  Object? cleanupError;

  @override
  void handleResolvedRoomState({
    required bool roomLoaded,
    required bool playbackAvailable,
  }) {
    resolvedStates.add((roomLoaded, playbackAvailable));
  }

  @override
  Future<void> cleanupPlaybackOnLeave() async {
    cleanupCalls += 1;
    final error = cleanupError;
    if (error != null) {
      throw error;
    }
  }

  @override
  void resetAutoFullscreenApplied() {
    resetAutoFullscreenAppliedCalls += 1;
  }
}

class _TestDanmakuSession implements DanmakuSession {
  int disconnectCalls = 0;

  @override
  Stream<LiveMessage> get messages => const Stream<LiveMessage>.empty();

  @override
  Future<void> connect() async {}

  @override
  Future<void> disconnect() async {
    disconnectCalls += 1;
  }
}
