import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_async/fake_async.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:nolive_app/src/features/room/application/load_room_use_case.dart';
import 'package:nolive_app/src/features/room/application/resolve_play_source_use_case.dart';
import 'package:nolive_app/src/features/room/application/room_session_controller.dart';
import 'package:nolive_app/src/features/room/application/twitch_playback_recovery.dart';
import 'package:nolive_app/src/features/room/presentation/room_controls_action_coordinator.dart';
import 'package:nolive_app/src/features/room/presentation/room_runtime_helper_contexts.dart';
import 'package:nolive_app/src/features/settings/application/manage_danmaku_preferences_use_case.dart';
import 'package:nolive_app/src/features/settings/application/manage_player_preferences_use_case.dart';
import 'package:nolive_app/src/features/settings/application/manage_room_ui_preferences_use_case.dart';
import 'package:nolive_app/src/shared/application/player_runtime_controller.dart';

import 'room_fullscreen_test_fakes.dart';

void main() {
  const autoQuality = LivePlayQuality(
    id: 'auto',
    label: '自动',
    isDefault: true,
    sortOrder: 100,
  );
  const highQuality = LivePlayQuality(
    id: '1080',
    label: '原画',
    sortOrder: 1080,
  );
  const fallbackQuality = LivePlayQuality(
    id: '720',
    label: '高清',
    sortOrder: 720,
  );

  PlaybackSource source(String path) => PlaybackSource(
        url: Uri.parse('https://example.com/$path.m3u8'),
      );

  LivePlayUrl playUrl(
    String path, {
    String? lineLabel,
    Map<String, Object?>? metadata,
  }) {
    return LivePlayUrl(
      url: 'https://example.com/$path.m3u8',
      lineLabel: lineLabel,
      metadata: metadata,
    );
  }

  LoadedRoomSnapshot snapshot({
    required ProviderId providerId,
    required LiveRoomDetail detail,
    LivePlayQuality selectedQuality = autoQuality,
    List<LivePlayUrl> playUrls = const <LivePlayUrl>[],
    List<LivePlayQuality> qualities = const <LivePlayQuality>[
      autoQuality,
      highQuality,
      fallbackQuality,
    ],
  }) {
    return LoadedRoomSnapshot(
      providerId: providerId,
      detail: detail,
      qualities: qualities,
      selectedQuality: selectedQuality,
      playUrls: playUrls,
    );
  }

  PlayerPreferences playerPreferences({
    PlayerBackend backend = PlayerBackend.mpv,
    bool autoPlayEnabled = true,
    bool preferHighestQuality = false,
    bool forceHttpsEnabled = false,
  }) {
    return PlayerPreferences(
      autoPlayEnabled: autoPlayEnabled,
      preferHighestQuality: preferHighestQuality,
      backend: backend,
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
      forceHttpsEnabled: forceHttpsEnabled,
      androidAutoFullscreenEnabled: true,
      androidBackgroundAutoPauseEnabled: true,
      androidPipHideDanmakuEnabled: true,
      scaleMode: PlayerScaleMode.contain,
    );
  }

  RoomSessionLoadResult latestState({
    required ProviderId providerId,
    required LiveRoomDetail detail,
    required LoadedRoomSnapshot snapshot,
    PlayerPreferences? preferences,
  }) {
    final resolved = ResolvedPlaySource(
      quality: snapshot.selectedQuality,
      effectiveQuality: snapshot.selectedQuality,
      playUrls: snapshot.playUrls,
      playbackSource: source('latest'),
    );
    return RoomSessionLoadResult(
      snapshot: snapshot,
      resolved: resolved,
      playerPreferences: preferences ?? playerPreferences(),
      danmakuPreferences: DanmakuPreferences.defaults,
      roomUiPreferences: RoomUiPreferences.defaults,
      blockedKeywords: const ['spoiler'],
      playbackQuality: snapshot.selectedQuality,
      startupPlan: TwitchStartupPlan(startupQuality: snapshot.selectedQuality),
    );
  }

  test(
      'room controls action coordinator switches quality and reschedules twitch recovery',
      () async {
    final harness = _CoordinatorHarness(providerId: ProviderId.twitch);
    final stateSnapshot = snapshot(
      providerId: ProviderId.twitch,
      detail: harness.detail,
      selectedQuality: autoQuality,
      playUrls: [playUrl('initial', lineLabel: '主线路')],
    );
    harness.latestLoadedState = latestState(
      providerId: ProviderId.twitch,
      detail: harness.detail,
      snapshot: stateSnapshot,
    );
    harness.selectedQuality = autoQuality;
    harness.effectiveQuality = autoQuality;
    harness.activeRoomDetail = harness.detail;
    harness.nextResolved = ResolvedPlaySource(
      quality: highQuality,
      effectiveQuality: fallbackQuality,
      playUrls: [playUrl('fallback', lineLabel: '降档线路')],
      playbackSource: source('fallback'),
    );
    final coordinator = harness.createCoordinator();
    addTearDown(coordinator.dispose);
    addTearDown(harness.dispose);

    await coordinator.switchQuality(stateSnapshot, highQuality);

    expect(
      harness.boundPlaybackSource?.url.toString(),
      'https://example.com/fallback.m3u8',
    );
    expect(harness.replacedSession?.effectiveQuality, fallbackQuality);
    expect(harness.twitchResolvedPrepares, 1);
    expect(harness.twitchRecoverySchedules, hasLength(1));
    expect(harness.messages.last, contains('当前源实际返回 高清'));
  });

  test(
      'room controls action coordinator skips equivalent chaturbate proxy rebind',
      () async {
    PlaybackSource chaturbateProxy(String token) => PlaybackSource(
          url: Uri.parse(
            'http://127.0.0.1:9999/chaturbate-llhls/$token/stream.m3u8',
          ),
          bufferProfile: PlaybackBufferProfile.chaturbateLlHlsProxyStable,
        );

    final harness = _CoordinatorHarness(providerId: ProviderId.chaturbate);
    final currentSource = chaturbateProxy('current');
    final nextSource = chaturbateProxy('next');
    final stateSnapshot = snapshot(
      providerId: ProviderId.chaturbate,
      detail: harness.detail,
      selectedQuality: highQuality,
      playUrls: [playUrl('current', lineLabel: '主线路')],
    );
    harness.latestLoadedState = latestState(
      providerId: ProviderId.chaturbate,
      detail: harness.detail,
      snapshot: stateSnapshot,
    );
    harness.selectedQuality = highQuality;
    harness.effectiveQuality = highQuality;
    harness.activeRoomDetail = harness.detail;
    harness.runtime.player.emit(
      PlayerState(
        status: PlaybackStatus.playing,
        source: currentSource,
        backend: PlayerBackend.mpv,
      ),
    );
    harness.nextResolved = ResolvedPlaySource(
      quality: highQuality,
      effectiveQuality: highQuality,
      playUrls: [playUrl('next', lineLabel: '主线路')],
      playbackSource: nextSource,
    );
    final coordinator = harness.createCoordinator();
    addTearDown(coordinator.dispose);
    addTearDown(harness.dispose);

    await coordinator.switchQuality(stateSnapshot, highQuality);

    expect(harness.boundPlaybackSource, isNull);
    expect(harness.replacedSession?.playbackSource, currentSource);
    expect(
      harness.traces,
      contains(
          contains('manual apply source skipped equivalent chaturbate proxy')),
    );
  });

  test(
      'room controls action coordinator switches line with current session semantics',
      () async {
    final harness = _CoordinatorHarness(providerId: ProviderId.twitch);
    final stateSnapshot = snapshot(
      providerId: ProviderId.twitch,
      detail: harness.detail,
      selectedQuality: highQuality,
      playUrls: [
        playUrl(
          'main',
          lineLabel: '主线路',
          metadata: const {'playerType': 'web_hls'},
        ),
      ],
    );
    harness.latestLoadedState = latestState(
      providerId: ProviderId.twitch,
      detail: harness.detail,
      snapshot: stateSnapshot,
    );
    harness.selectedQuality = highQuality;
    harness.effectiveQuality = highQuality;
    harness.playbackAvailable = true;
    final coordinator = harness.createCoordinator();
    addTearDown(coordinator.dispose);
    addTearDown(harness.dispose);

    await coordinator.switchLine(
      playUrl(
        'backup',
        lineLabel: '备用线路',
        metadata: const {'playerType': 'ttvnw'},
      ),
    );

    expect(harness.twitchLinePrepares, 1);
    expect(harness.lineSwitchUpdate?.hasPlayback, isTrue);
    expect(
      harness.lineSwitchUpdate?.playbackSource.url.toString(),
      'https://example.com/backup.m3u8',
    );
    expect(harness.twitchRecoverySchedules, hasLength(1));
  });

  test(
      'room controls action coordinator uses current playback urls when rescheduling line-switch recovery',
      () async {
    final harness = _CoordinatorHarness(providerId: ProviderId.twitch);
    final stateSnapshot = snapshot(
      providerId: ProviderId.twitch,
      detail: harness.detail,
      selectedQuality: highQuality,
      playUrls: [playUrl('stale', lineLabel: '旧线路')],
    );
    harness.latestLoadedState = latestState(
      providerId: ProviderId.twitch,
      detail: harness.detail,
      snapshot: stateSnapshot,
    );
    harness.currentPlayUrls = [
      playUrl('fresh', lineLabel: '新线路'),
    ];
    harness.selectedQuality = highQuality;
    harness.effectiveQuality = highQuality;
    harness.playbackAvailable = true;
    final coordinator = harness.createCoordinator();
    addTearDown(coordinator.dispose);
    addTearDown(harness.dispose);

    await coordinator.switchLine(
      playUrl('backup', lineLabel: '备用线路'),
    );

    expect(
      harness.twitchRecoverySchedules.single.playUrls.single.url,
      'https://example.com/fresh.m3u8',
    );
  });

  test(
      'room controls action coordinator refreshes room when player settings change playback policy',
      () async {
    final harness = _CoordinatorHarness();
    harness.nextPlayerPreferences = playerPreferences(
      backend: PlayerBackend.mpv,
      preferHighestQuality: true,
    );
    final coordinator = harness.createCoordinator();
    addTearDown(coordinator.dispose);
    addTearDown(harness.dispose);

    await coordinator.handlePlayerSettingsReturn(
      previousPreferences: playerPreferences(
        backend: PlayerBackend.mpv,
        preferHighestQuality: false,
      ),
    );

    expect(harness.refreshRoomCalls, 1);
    expect(harness.scheduledBootstraps, isEmpty);
  });

  test(
      'room controls action coordinator enforces backend and schedules same-source bootstrap when room reload is unnecessary',
      () async {
    final harness = _CoordinatorHarness(runtimeBackend: PlayerBackend.mpv);
    harness.currentPlaybackSource = source('same');
    harness.playbackAvailable = true;
    harness.nextPlayerPreferences = playerPreferences(
      backend: PlayerBackend.mdk,
      autoPlayEnabled: false,
    );
    harness.runtime.player.emit(
      PlayerState(
        status: PlaybackStatus.error,
        source: source('same'),
        errorMessage: 'broken',
      ),
    );
    final coordinator = harness.createCoordinator();
    addTearDown(coordinator.dispose);
    addTearDown(harness.dispose);

    await coordinator.handlePlayerSettingsReturn(
      previousPreferences: playerPreferences(backend: PlayerBackend.mpv),
    );

    expect(harness.runtime.ensuredBackends, <PlayerBackend>[PlayerBackend.mdk]);
    expect(harness.appliedPlayerPreferences, harness.nextPlayerPreferences);
    expect(harness.scheduledBootstraps, hasLength(1));
    expect(harness.scheduledBootstraps.single.force, isTrue);
    expect(harness.scheduledBootstraps.single.autoPlay, isFalse);
  });

  test(
      'room controls action coordinator stops player-settings return side effects after unmount during backend enforce',
      () async {
    final harness = _CoordinatorHarness(runtimeBackend: PlayerBackend.mpv);
    harness.currentPlaybackSource = source('same');
    harness.playbackAvailable = true;
    harness.nextPlayerPreferences = playerPreferences(
      backend: PlayerBackend.mdk,
      preferHighestQuality: true,
    );
    harness.onEnsureBackendWithoutPlaybackState = () {
      harness.mounted = false;
    };
    final coordinator = harness.createCoordinator();
    addTearDown(coordinator.dispose);
    addTearDown(harness.dispose);

    await coordinator.handlePlayerSettingsReturn(
      previousPreferences: playerPreferences(backend: PlayerBackend.mpv),
    );

    expect(harness.runtime.ensuredBackends, <PlayerBackend>[PlayerBackend.mdk]);
    expect(harness.appliedPlayerPreferences, isNull);
    expect(harness.refreshRoomCalls, 0);
    expect(harness.scheduledBootstraps, isEmpty);
  });

  test(
      'room controls action coordinator reloads danmaku preferences and rebinds danmaku session',
      () async {
    final harness = _CoordinatorHarness();
    final stateSnapshot = snapshot(
      providerId: ProviderId.bilibili,
      detail: harness.detail,
      playUrls: [playUrl('live')],
    );
    harness.latestLoadedState = latestState(
      providerId: ProviderId.bilibili,
      detail: harness.detail,
      snapshot: stateSnapshot,
    );
    harness.nextBlockedKeywords = const ['剧透', '广告'];
    harness.nextDanmakuPreferences = DanmakuPreferences.defaults.copyWith(
      enabledByDefault: false,
      nativeBatchMaskEnabled: false,
    );
    harness.openedDanmakuSession = _TestDanmakuSession();
    final coordinator = harness.createCoordinator();
    addTearDown(coordinator.dispose);
    addTearDown(harness.dispose);

    await coordinator.handleDanmakuSettingsReturn();

    expect(harness.appliedDanmakuPreferences, harness.nextDanmakuPreferences);
    expect(harness.appliedBlockedKeywords, harness.nextBlockedKeywords);
    expect(harness.boundDanmakuSession, same(harness.openedDanmakuSession));
  });

  test(
      'room controls action coordinator reloads danmaku against the current room future instead of stale latest state',
      () async {
    final harness = _CoordinatorHarness();
    const staleDetail = LiveRoomDetail(
      providerId: 'bilibili',
      roomId: 'stale',
      title: 'Stale Room',
      streamerName: '旧主播',
      sourceUrl: 'https://example.com/stale',
    );
    const currentDetail = LiveRoomDetail(
      providerId: 'bilibili',
      roomId: 'current',
      title: 'Current Room',
      streamerName: '新主播',
      sourceUrl: 'https://example.com/current',
    );
    harness.latestLoadedState = latestState(
      providerId: ProviderId.bilibili,
      detail: staleDetail,
      snapshot: snapshot(
        providerId: ProviderId.bilibili,
        detail: staleDetail,
        playUrls: [playUrl('live')],
      ),
    );
    harness.currentRoomDetailForDanmaku = currentDetail;
    harness.openedDanmakuSession = _TestDanmakuSession();
    final coordinator = harness.createCoordinator();
    addTearDown(coordinator.dispose);
    addTearDown(harness.dispose);

    await coordinator.handleDanmakuSettingsReturn();

    expect(harness.openRoomDanmakuCalls.single.roomId, 'current');
    expect(harness.boundDanmakuSession, same(harness.openedDanmakuSession));
  });

  test(
      'room controls action coordinator reschedules auto close and leaves once',
      () {
    final harness = _CoordinatorHarness();
    final coordinator = harness.createCoordinator();
    addTearDown(coordinator.dispose);
    addTearDown(harness.dispose);

    fakeAsync((async) {
      coordinator.setAutoCloseTimer(const Duration(minutes: 15));
      final firstScheduled = coordinator.scheduledCloseAt;
      coordinator.setAutoCloseTimer(const Duration(seconds: 3));

      expect(coordinator.scheduledCloseAt, isNotNull);
      expect(coordinator.scheduledCloseAt, isNot(firstScheduled));

      async.elapse(const Duration(seconds: 4));
      async.flushMicrotasks();

      expect(coordinator.scheduledCloseAt, isNull);
    });

    expect(harness.leaveRoomCalls, 1);
  });

  test(
      'room controls action coordinator reports screenshot unsupported, failure, and success',
      () async {
    final unsupportedHarness = _CoordinatorHarness(
      screenshotSupported: false,
    );
    final unsupportedCoordinator = unsupportedHarness.createCoordinator();
    addTearDown(unsupportedCoordinator.dispose);
    addTearDown(unsupportedHarness.dispose);

    await unsupportedCoordinator.captureScreenshot();
    expect(unsupportedHarness.messages.single, '当前版本暂不支持截图');

    final failingHarness = _CoordinatorHarness();
    failingHarness.runtime.screenshotBytes = null;
    final failingCoordinator = failingHarness.createCoordinator();
    addTearDown(failingCoordinator.dispose);
    addTearDown(failingHarness.dispose);

    await failingCoordinator.captureScreenshot();
    expect(failingHarness.messages.single, startsWith('截图失败：'));

    final fallbackHarness = _CoordinatorHarness();
    fallbackHarness.runtime.screenshotBytes = null;
    fallbackHarness.renderedSurfaceScreenshotBytes =
        Uint8List.fromList([4, 5, 6]);
    final fallbackCoordinator = fallbackHarness.createCoordinator(
      persistScreenshot: ({
        required bytes,
        required fileName,
      }) async {
        expect(bytes, orderedEquals(const [4, 5, 6]));
        return '/tmp/rendered-surface.png';
      },
    );
    addTearDown(fallbackCoordinator.dispose);
    addTearDown(fallbackHarness.dispose);

    await fallbackCoordinator.captureScreenshot();
    expect(fallbackHarness.messages.single, '已保存截图到 /tmp/rendered-surface.png');

    final successHarness = _CoordinatorHarness();
    successHarness.runtime.screenshotBytes = Uint8List.fromList([1, 2, 3]);
    final successCoordinator = successHarness.createCoordinator(
      persistScreenshot: ({
        required bytes,
        required fileName,
      }) async {
        expect(bytes, isNotEmpty);
        expect(fileName, startsWith('nolive-bilibili-6-'));
        return '/tmp/demo.png';
      },
    );
    addTearDown(successCoordinator.dispose);
    addTearDown(successHarness.dispose);

    await successCoordinator.captureScreenshot();
    expect(successHarness.messages.single, '已保存截图到 /tmp/demo.png');
  });
}

class _CoordinatorHarness {
  _CoordinatorHarness({
    this.providerId = ProviderId.bilibili,
    PlayerBackend runtimeBackend = PlayerBackend.mpv,
    bool screenshotSupported = true,
  })  : detail = roomDetail(providerId: providerId),
        runtime = _TestCoordinatorRuntime(
          TestRecordingPlayer(playerBackend: runtimeBackend),
          backendOverride: runtimeBackend,
          screenshotSupported: screenshotSupported,
        ) {
    currentPlaybackSource = source('current');
    playbackAvailable = true;
    selectedQuality = autoQuality;
    effectiveQuality = autoQuality;
    activeRoomDetail = detail;
    currentRoomDetailForDanmaku = detail;
    nextResolved = ResolvedPlaySource(
      quality: autoQuality,
      effectiveQuality: autoQuality,
      playUrls: [playUrl('current', lineLabel: '主线路')],
      playbackSource: source('current'),
    );
    nextPlayerPreferences = _CoordinatorHarness.playerPreferences(
      backend: runtimeBackend,
    );
    nextDanmakuPreferences = DanmakuPreferences.defaults;
  }

  static const autoQuality = LivePlayQuality(
    id: 'auto',
    label: '自动',
    isDefault: true,
    sortOrder: 100,
  );

  static PlaybackSource source(String path) => PlaybackSource(
        url: Uri.parse('https://example.com/$path.m3u8'),
      );

  static LivePlayUrl playUrl(
    String path, {
    String? lineLabel,
    Map<String, Object?>? metadata,
  }) {
    return LivePlayUrl(
      url: 'https://example.com/$path.m3u8',
      lineLabel: lineLabel,
      metadata: metadata,
    );
  }

  static LiveRoomDetail roomDetail({required ProviderId providerId}) {
    return LiveRoomDetail(
      providerId: providerId.value,
      roomId: '6',
      title: 'Demo Room',
      streamerName: '主播',
      sourceUrl: 'https://example.com/source',
    );
  }

  static PlayerPreferences playerPreferences({
    PlayerBackend backend = PlayerBackend.mpv,
    bool autoPlayEnabled = true,
    bool preferHighestQuality = false,
    bool forceHttpsEnabled = false,
  }) {
    return PlayerPreferences(
      autoPlayEnabled: autoPlayEnabled,
      preferHighestQuality: preferHighestQuality,
      backend: backend,
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
      forceHttpsEnabled: forceHttpsEnabled,
      androidAutoFullscreenEnabled: true,
      androidBackgroundAutoPauseEnabled: true,
      androidPipHideDanmakuEnabled: true,
      scaleMode: PlayerScaleMode.contain,
    );
  }

  final ProviderId providerId;
  final LiveRoomDetail detail;
  final _TestCoordinatorRuntime runtime;
  final List<String> messages = <String>[];
  final List<String> traces = <String>[];
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

  RoomSessionLoadResult? latestLoadedState;
  PlaybackSource? currentPlaybackSource;
  PlaybackSource? playbackReferenceSource;
  List<LivePlayUrl> currentPlayUrls = const <LivePlayUrl>[];
  LivePlayQuality? selectedQuality;
  LivePlayQuality? effectiveQuality;
  LiveRoomDetail? activeRoomDetail;
  LiveRoomDetail? currentRoomDetailForDanmaku;
  bool playbackAvailable = false;
  bool bindSucceeds = true;
  bool mounted = true;
  late ResolvedPlaySource nextResolved;
  late PlayerPreferences nextPlayerPreferences;
  PlayerPreferences? appliedPlayerPreferences;
  late DanmakuPreferences nextDanmakuPreferences;
  DanmakuPreferences? appliedDanmakuPreferences;
  List<String> nextBlockedKeywords = const <String>[];
  List<String>? appliedBlockedKeywords;
  int refreshRoomCalls = 0;
  int leaveRoomCalls = 0;
  int twitchResolvedPrepares = 0;
  int twitchLinePrepares = 0;
  ({
    LiveRoomDetail activeRoomDetail,
    LivePlayQuality selectedQuality,
    LivePlayQuality effectiveQuality,
    PlaybackSource? playbackSource,
    List<LivePlayUrl> playUrls,
  })? replacedSession;
  ({PlaybackSource playbackSource, bool hasPlayback})? lineSwitchUpdate;
  PlaybackSource? boundPlaybackSource;
  DanmakuSession? openedDanmakuSession;
  DanmakuSession? boundDanmakuSession;
  Uint8List? renderedSurfaceScreenshotBytes;
  final List<LiveRoomDetail> openRoomDanmakuCalls = <LiveRoomDetail>[];
  VoidCallback? onEnsureBackendWithoutPlaybackState;

  RoomControlsActionCoordinator createCoordinator({
    RoomPersistScreenshot? persistScreenshot,
  }) {
    runtime.onEnsureBackendWithoutPlaybackState =
        onEnsureBackendWithoutPlaybackState;
    return RoomControlsActionCoordinator(
      context: RoomControlsActionContext(
        providerId: providerId,
        roomId: '6',
        targetPlatform: TargetPlatform.android,
        isWeb: false,
        runtime: RoomRuntimeControlContext.fromPlayerRuntime(runtime),
        trace: traces.add,
        showMessage: messages.add,
        isMounted: () => mounted,
        resolveAutoPlayEnabled: () => nextPlayerPreferences.autoPlayEnabled,
        resolveForceHttpsEnabled: () => nextPlayerPreferences.forceHttpsEnabled,
        resolvePlaybackAvailable: () => playbackAvailable,
        resolveCurrentPlaybackSource: () => currentPlaybackSource,
        resolvePlaybackReferenceSource: () =>
            playbackReferenceSource ?? currentPlaybackSource,
        resolveCurrentPlayUrls: () => currentPlayUrls,
        resolveSelectedQuality: () => selectedQuality,
        resolveEffectiveQuality: () => effectiveQuality,
        resolveActiveRoomDetail: () => activeRoomDetail,
        resolveLatestLoadedState: () => latestLoadedState,
        loadCurrentRoomDetailForDanmaku: () async =>
            currentRoomDetailForDanmaku,
        resolvePlaybackRefresh: (_, __) async => nextResolved,
        playbackSourceFromLine: (playUrl, {quality}) => source(
            Uri.parse(playUrl.url).pathSegments.last.replaceAll('.m3u8', '')),
        bindPlaybackSourceWithRecovery: ({
          required playbackSource,
          required label,
          bool autoPlay = false,
          Duration autoPlayDelay = Duration.zero,
          PlaybackSource? currentPlaybackSource,
          bool preferFreshBackendBeforeFirstSetSource = false,
          bool Function()? shouldAbortRetry,
        }) async {
          boundPlaybackSource = playbackSource;
          return bindSucceeds;
        },
        replaceResolvedPlaybackSession: ({
          required activeRoomDetail,
          required selectedQuality,
          required effectiveQuality,
          required playbackSource,
          required playUrls,
        }) {
          replacedSession = (
            activeRoomDetail: activeRoomDetail,
            selectedQuality: selectedQuality,
            effectiveQuality: effectiveQuality,
            playbackSource: playbackSource,
            playUrls: playUrls,
          );
        },
        updatePlaybackSourceForLineSwitch: ({
          required playbackSource,
          required hasPlayback,
        }) {
          lineSwitchUpdate = (
            playbackSource: playbackSource,
            hasPlayback: hasPlayback,
          );
        },
        schedulePlaybackBootstrap: ({
          required playbackSource,
          required hasPlayback,
          required autoPlay,
          bool force = false,
        }) {
          scheduledBootstraps.add((
            playbackSource: playbackSource,
            hasPlayback: hasPlayback,
            autoPlay: autoPlay,
            force: force,
          ));
        },
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
        prepareTwitchForResolvedPlayback: ({
          startupPromotionQuality,
          required resetAttempts,
        }) {
          twitchResolvedPrepares += 1;
        },
        prepareTwitchForLineSwitch: ({required resetAttempts}) {
          twitchLinePrepares += 1;
        },
        loadPlayerPreferences: () async => nextPlayerPreferences,
        applyPlayerPreferences: (preferences) {
          appliedPlayerPreferences = preferences;
        },
        refreshRoom: ({
          bool showFeedback = false,
          bool reloadPlayer = false,
          bool forcePlaybackRebind = true,
        }) async {
          refreshRoomCalls += 1;
        },
        loadDanmakuPreferences: () async => nextDanmakuPreferences,
        loadBlockedKeywords: () async => nextBlockedKeywords,
        applyDanmakuPreferences: ({
          required preferences,
          required blockedKeywords,
        }) {
          appliedDanmakuPreferences = preferences;
          appliedBlockedKeywords = blockedKeywords;
        },
        openRoomDanmaku: ({required detail}) async {
          openRoomDanmakuCalls.add(detail);
          return openedDanmakuSession;
        },
        bindDanmakuSession: (session) async {
          boundDanmakuSession = session;
        },
        leaveRoom: () async {
          leaveRoomCalls += 1;
        },
        captureRenderedPlayerSurface: renderedSurfaceScreenshotBytes == null
            ? null
            : () async => renderedSurfaceScreenshotBytes,
      ),
      persistScreenshot: persistScreenshot,
    );
  }

  Future<void> dispose() => runtime.player.dispose();
}

class _TestCoordinatorRuntime extends PlayerRuntimeController {
  _TestCoordinatorRuntime(
    this.player, {
    required this.backendOverride,
    required this.screenshotSupported,
  }) : super(player);

  final TestRecordingPlayer player;
  final PlayerBackend backendOverride;
  final bool screenshotSupported;
  final List<PlayerBackend> ensuredBackends = <PlayerBackend>[];
  Uint8List? screenshotBytes = Uint8List.fromList(<int>[1, 2, 3]);
  VoidCallback? onEnsureBackendWithoutPlaybackState;

  @override
  PlayerBackend get backend => backendOverride;

  @override
  bool get supportsScreenshot => screenshotSupported;

  @override
  Future<void> ensureBackendWithoutPlaybackState(
      PlayerBackend nextBackend) async {
    ensuredBackends.add(nextBackend);
    onEnsureBackendWithoutPlaybackState?.call();
  }

  @override
  Future<Uint8List?> captureScreenshot() async => screenshotBytes;
}

class _TestDanmakuSession implements DanmakuSession {
  @override
  Stream<LiveMessage> get messages => const Stream<LiveMessage>.empty();

  @override
  Future<void> connect() async {}

  @override
  Future<void> disconnect() async {}
}
