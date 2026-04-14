import 'dart:async';
import 'dart:typed_data';

import 'package:floating/floating.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:live_storage/live_storage.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';
import 'package:nolive_app/src/app/routing/app_routes.dart';
import 'package:nolive_app/src/features/library/application/load_follow_watchlist_use_case.dart';
import 'package:nolive_app/src/features/room/application/open_room_danmaku_use_case.dart';
import 'package:nolive_app/src/features/room/application/room_preview_dependencies.dart';
import 'package:nolive_app/src/features/room/presentation/room_fullscreen_session_platforms.dart';
import 'package:nolive_app/src/features/room/presentation/room_preview_page.dart';
import 'package:nolive_app/src/shared/application/player_runtime_controller.dart';
import 'package:nolive_app/src/shared/presentation/gestures/responsive_page_swipe_physics.dart';
import 'package:nolive_app/src/shared/presentation/widgets/app_surface_card.dart';

import 'room_fullscreen_test_fakes.dart';

void main() {
  test('fullscreen embedded playback hides poster backdrop', () {
    expect(
      resolveRoomPlayerPosterBackdropVisibility(
        fullscreen: true,
        hasPlayback: true,
        embedPlayer: true,
      ),
      isFalse,
    );
    expect(
      resolveRoomPlayerPosterBackdropVisibility(
        fullscreen: false,
        hasPlayback: true,
        embedPlayer: true,
      ),
      isTrue,
    );
    expect(
      resolveRoomPlayerPosterBackdropVisibility(
        fullscreen: true,
        hasPlayback: false,
        embedPlayer: true,
      ),
      isTrue,
    );
  });

  test('embedded player lifecycle view flags defer Android lifecycle control',
      () {
    expect(
      resolveEmbeddedPlayerLifecycleViewFlags(
        androidPlaybackBridgeSupported: true,
        backgroundAutoPauseEnabled: true,
      ),
      (
        pauseUponEnteringBackgroundMode: false,
        resumeUponEnteringForegroundMode: false,
      ),
    );
    expect(
      resolveEmbeddedPlayerLifecycleViewFlags(
        androidPlaybackBridgeSupported: false,
        backgroundAutoPauseEnabled: true,
      ),
      (
        pauseUponEnteringBackgroundMode: true,
        resumeUponEnteringForegroundMode: true,
      ),
    );
    expect(
      resolveEmbeddedPlayerLifecycleViewFlags(
        androidPlaybackBridgeSupported: false,
        backgroundAutoPauseEnabled: false,
      ),
      (
        pauseUponEnteringBackgroundMode: false,
        resumeUponEnteringForegroundMode: false,
      ),
    );
  });

  test('room panel sync detects fullscreen return desync', () {
    expect(
      shouldSynchronizeRoomPanelPage(
        selectedPanelIndex: 3,
        controllerPage: 0,
        isScrollInProgress: false,
      ),
      isTrue,
    );
    expect(
      shouldSynchronizeRoomPanelPage(
        selectedPanelIndex: 1,
        controllerPage: 1,
        isScrollInProgress: false,
      ),
      isFalse,
    );
    expect(
      shouldSynchronizeRoomPanelPage(
        selectedPanelIndex: 2,
        controllerPage: 1.4,
        isScrollInProgress: true,
      ),
      isFalse,
    );
  });

  testWidgets('room preview exposes quick actions and settings tab', (
    tester,
  ) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    await bootstrap.followRepository.upsert(
      const FollowRecord(
        providerId: 'bilibili',
        roomId: '6',
        streamerName: '系统演示主播',
        tags: ['常看'],
      ),
    );
    await bootstrap.followRepository.upsert(
      const FollowRecord(
        providerId: 'douyu',
        roomId: '3125893',
        streamerName: '斗鱼样例主播',
      ),
    );
    await bootstrap.followRepository.upsert(
      const FollowRecord(
        providerId: 'huya',
        roomId: 'offline-demo',
        streamerName: '虎牙未开播主播',
      ),
    );
    bootstrap.followWatchlistSnapshot.value = FollowWatchlist(
      entries: const [
        FollowWatchEntry(
          record: FollowRecord(
            providerId: 'bilibili',
            roomId: '6',
            streamerName: '系统演示主播',
            tags: ['常看'],
          ),
          detail: LiveRoomDetail(
            providerId: 'bilibili',
            roomId: '6',
            title: '系统演示直播间',
            streamerName: '系统演示主播',
            isLive: true,
          ),
        ),
        FollowWatchEntry(
          record: FollowRecord(
            providerId: 'douyu',
            roomId: '3125893',
            streamerName: '斗鱼样例主播',
          ),
          detail: LiveRoomDetail(
            providerId: 'douyu',
            roomId: '3125893',
            title: '斗鱼样例直播间',
            streamerName: '斗鱼样例主播',
            isLive: true,
          ),
        ),
        FollowWatchEntry(
          record: FollowRecord(
            providerId: 'huya',
            roomId: 'offline-demo',
            streamerName: '虎牙未开播主播',
          ),
          detail: LiveRoomDetail(
            providerId: 'huya',
            roomId: 'offline-demo',
            title: '虎牙未开播房间',
            streamerName: '虎牙未开播主播',
            isLive: false,
          ),
        ),
      ],
    );

    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: RoomPreviewPage(
          dependencies: _roomDependencies(bootstrap),
          providerId: ProviderId.bilibili,
          roomId: '66666',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(find.byKey(const Key('room-appbar-more-button')), findsOneWidget);
    expect(find.byKey(const Key('room-danmaku-overlay')), findsNothing);

    await tester.tap(find.byKey(const Key('room-inline-player-tap-target')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(
        find.byKey(const Key('room-inline-fullscreen-button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('room-appbar-more-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('切换清晰度'), findsOneWidget);
    expect(find.text('切换线路'), findsOneWidget);
    expect(find.text('截图'), findsNothing);
    expect(find.text('调试面板'), findsOneWidget);
    expect(
      find.byKey(const Key('room-quick-force-https-switch')),
      findsNothing,
    );

    await tester.tapAt(const Offset(20, 20));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.byKey(const Key('room-panel-tab-settings')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('播放器中显示SC'), findsOneWidget);
    expect(find.text('关键词屏蔽'), findsOneWidget);
    expect(find.text('弹幕设置'), findsOneWidget);
    expect(find.text('定时关闭'), findsOneWidget);

    await tester.tap(find.byKey(const Key('room-panel-tab-follow')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('关注列表'), findsOneWidget);
    expect(
        find.byKey(const Key('room-follow-entry-bilibili-6')), findsOneWidget);
    expect(find.byKey(const Key('room-follow-entry-douyu-3125893')),
        findsOneWidget);
    expect(find.byKey(const Key('room-follow-entry-huya-offline-demo')),
        findsNothing);
    expect(
        find.byKey(const Key('room-follow-settings-button')), findsOneWidget);
    expect(find.byKey(const Key('room-follow-refresh-button')), findsOneWidget);
    expect(
      tester
          .widget<PageView>(find.byKey(const Key('room-panel-page-view')))
          .physics,
      isA<ResponsivePageSwipePhysics>(),
    );
  });

  testWidgets(
      'returning from player settings without changes does not reload playback',
      (tester) async {
    final base = createAppBootstrap(mode: AppRuntimeMode.preview);
    final player = _RecordingPlayer();
    addTearDown(player.dispose);

    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        routes: {
          AppRoutes.playerSettings: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('dummy-player-settings'),
                  ),
                ),
              ),
        },
        home: RoomPreviewPage(
          dependencies: _roomDependencies(base, player: player),
          providerId: ProviderId.bilibili,
          roomId: '66666',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    final initializeCount =
        player.events.where((event) => event == 'initialize').length;
    final setSourceCount =
        player.events.where((event) => event == 'setSource').length;
    final playCount = player.events.where((event) => event == 'play').length;

    await tester.tap(find.byKey(const Key('room-panel-tab-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('播放器设置'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('dummy-player-settings'));
    await tester.pumpAndSettle();

    expect(
      player.events.where((event) => event == 'initialize').length,
      initializeCount,
    );
    expect(
      player.events.where((event) => event == 'setSource').length,
      setSourceCount,
    );
    expect(
      player.events.where((event) => event == 'play').length,
      playCount,
    );
  });

  testWidgets(
      'returning from player settings rebinds same source when playback is errored',
      (tester) async {
    final base = createAppBootstrap(mode: AppRuntimeMode.preview);
    final player = _FailOnceMdkPlayer(failFirstSetSource: false);
    final runtime = _RefreshTrackingMdkPlayerRuntime(player);
    addTearDown(player.dispose);

    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        routes: {
          AppRoutes.playerSettings: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('dummy-player-settings'),
                  ),
                ),
              ),
        },
        home: RoomPreviewPage(
          dependencies: _roomDependencies(base, playerRuntime: runtime),
          providerId: ProviderId.bilibili,
          roomId: '66666',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    player.emitStickySourceError();
    player.armNextSetSourceFailure(retainSource: true);
    await tester.pump();

    final initialEventCount = player.events.length;

    await tester.tap(find.byKey(const Key('room-panel-tab-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('播放器设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('dummy-player-settings'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));

    final replayEvents = player.events.sublist(initialEventCount);
    expect(
      replayEvents,
      containsAllInOrder(<String>[
        'refreshBackend',
        'setSource',
        'stop',
        'setSource',
        'play',
      ]),
    );
    expect(runtime.refreshCount, 1);
    expect(runtime.currentState.status, PlaybackStatus.playing);
  });

  testWidgets(
      'manual room refresh rebinds same playback source while already playing',
      (tester) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    final player = _FailOnceMdkPlayer(failFirstSetSource: false);
    final runtime = _RefreshTrackingMdkPlayerRuntime(player);
    final openRoomDanmaku = _NullDanmakuUseCase(bootstrap.providerRegistry);
    addTearDown(player.dispose);

    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: RoomPreviewPage(
          dependencies: _roomDependencies(
            bootstrap,
            playerRuntime: runtime,
            openRoomDanmaku: openRoomDanmaku,
          ),
          providerId: ProviderId.bilibili,
          roomId: '66666',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    await tester.tap(find.byKey(const Key('room-appbar-more-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    player.events.clear();

    await tester.tap(find.byKey(const Key('room-quick-refresh-button')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(
      player.events,
      containsAllInOrder(<String>[
        'refreshBackend',
        'buildView',
        'setSource',
        'play',
      ]),
    );
    expect(runtime.refreshCount, 1);
    expect(runtime.currentState.status, PlaybackStatus.playing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets(
      'manual fullscreen refresh rebinds same playback source while already playing',
      (tester) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    final player = _FailOnceMdkPlayer(failFirstSetSource: false);
    final runtime = _RefreshTrackingMdkPlayerRuntime(player);
    final openRoomDanmaku = _NullDanmakuUseCase(bootstrap.providerRegistry);
    addTearDown(player.dispose);

    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: RoomPreviewPage(
          dependencies: _roomDependencies(
            bootstrap,
            playerRuntime: runtime,
            openRoomDanmaku: openRoomDanmaku,
          ),
          providerId: ProviderId.bilibili,
          roomId: '66666',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    await tester.tap(find.byKey(const Key('room-inline-player-tap-target')));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tap(find.byKey(const Key('room-inline-player-tap-target')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    player.events.clear();

    await tester.tap(find.byKey(const Key('room-fullscreen-refresh-button')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(
      player.events,
      containsAllInOrder(<String>[
        'refreshBackend',
        'buildView',
        'setSource',
        'play',
      ]),
    );
    expect(runtime.refreshCount, 1);
    expect(runtime.currentState.status, PlaybackStatus.playing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets('fullscreen danmaku toggle updates immediately', (tester) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    final openRoomDanmaku = _NullDanmakuUseCase(bootstrap.providerRegistry);

    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: RoomPreviewPage(
          dependencies: _roomDependencies(
            bootstrap,
            openRoomDanmaku: openRoomDanmaku,
          ),
          providerId: ProviderId.bilibili,
          roomId: '66666',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    await tester.tap(find.byKey(const Key('room-inline-player-tap-target')));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tap(find.byKey(const Key('room-inline-player-tap-target')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final fullscreenDanmakuToggle =
        find.byKey(const Key('room-fullscreen-danmaku-toggle-button'));
    expect(
      find.descendant(
        of: fullscreenDanmakuToggle,
        matching: find.byIcon(Icons.subtitles_outlined),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: fullscreenDanmakuToggle,
        matching: find.byIcon(Icons.subtitles_off_outlined),
      ),
      findsNothing,
    );

    await tester.tap(fullscreenDanmakuToggle);
    await tester.pump();

    expect(
      find.descendant(
        of: fullscreenDanmakuToggle,
        matching: find.byIcon(Icons.subtitles_outlined),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: fullscreenDanmakuToggle,
        matching: find.byIcon(Icons.subtitles_off_outlined),
      ),
      findsOneWidget,
    );
  });

  testWidgets('fullscreen exit waits for in-flight playback rebind', (
    tester,
  ) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    final player = _BlockingSetSourceMdkPlayer();
    final runtime = _RefreshTrackingMdkPlayerRuntime(player);
    final openRoomDanmaku = _NullDanmakuUseCase(bootstrap.providerRegistry);
    addTearDown(player.dispose);

    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: RoomPreviewPage(
          dependencies: _roomDependencies(
            bootstrap,
            playerRuntime: runtime,
            openRoomDanmaku: openRoomDanmaku,
          ),
          providerId: ProviderId.bilibili,
          roomId: '66666',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    await tester.tap(find.byKey(const Key('room-inline-player-tap-target')));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tap(find.byKey(const Key('room-inline-player-tap-target')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    player.events.clear();
    player.blockNextSetSource();

    await tester.tap(find.byKey(const Key('room-fullscreen-refresh-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));

    expect(player.events, contains('refreshBackend'));

    await tester.tap(find.byKey(const Key('room-exit-fullscreen-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('room-fullscreen-overlay')), findsOneWidget);
    expect(player.events.where((event) => event == 'stop'), isEmpty);

    player.completeBlockedSetSource();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byKey(const Key('room-fullscreen-overlay')), findsNothing);
    expect(find.byKey(const Key('room-leave-button')), findsOneWidget);
  });

  testWidgets('room preview mounts player view before initial source binding', (
    tester,
  ) async {
    final base = createAppBootstrap(mode: AppRuntimeMode.preview);
    final player = _RecordingPlayer();
    addTearDown(player.dispose);
    final dependencies = _roomDependencies(base, player: player);

    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: RoomPreviewPage(
          dependencies: dependencies,
          providerId: ProviderId.bilibili,
          roomId: '66666',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(
      resolveMdkTextureRecoveryRetryDelay(0) + const Duration(milliseconds: 40),
    );
    await tester.pump();

    final buildIndex = player.events.indexOf('buildView');
    final setSourceIndex = player.events.indexOf('setSource');
    final playIndex = player.events.indexOf('play');

    expect(buildIndex, isNonNegative);
    expect(setSourceIndex, isNonNegative);
    expect(playIndex, isNonNegative);
    expect(buildIndex, lessThan(setSourceIndex));
    expect(setSourceIndex, lessThan(playIndex));
  });

  test('MDK texture init failures trigger staged recovery detection', () {
    expect(
      shouldForcePlaybackBootstrap(
        const PlayerState(status: PlaybackStatus.error),
      ),
      isTrue,
    );
    expect(
      shouldForcePlaybackBootstrap(
        const PlayerState(status: PlaybackStatus.playing),
      ),
      isFalse,
    );
    expect(
      shouldAttemptMdkBackendRefreshAfterSetSource(
        const PlayerState(
          backend: PlayerBackend.mdk,
          status: PlaybackStatus.error,
          errorMessage: 'MDK texture initialization timed out after 3000ms',
        ),
      ),
      isTrue,
    );
    expect(
      shouldAttemptMdkBackendRefreshAfterSetSource(
        const PlayerState(
          backend: PlayerBackend.mdk,
          status: PlaybackStatus.error,
          errorMessage: 'other error',
        ),
      ),
      isFalse,
    );
    expect(
      shouldAttemptMdkBackendRefreshAfterSetSource(
        const PlayerState(
          backend: PlayerBackend.mpv,
          status: PlaybackStatus.error,
          errorMessage: 'MDK texture initialization timed out after 3000ms',
        ),
      ),
      isFalse,
    );
    expect(
      resolveMdkTextureRecoveryRetryDelay(0),
      const Duration(milliseconds: 180),
    );
    expect(
      resolveMdkTextureRecoveryRetryDelay(1),
      const Duration(milliseconds: 320),
    );
    expect(resolveMdkTextureRecoveryRetryDelay(2), Duration.zero);
    expect(
      shouldPreRefreshMdkBackendBeforeSameSourceRebind(
        state: PlayerState(
          backend: PlayerBackend.mdk,
        ),
        playbackSource: PlaybackSource(
          url: Uri.parse('https://example.com/live.m3u8'),
          headers: const {'referer': 'https://new.example.com/'},
        ),
        runtimeBackend: PlayerBackend.mdk,
        currentPlaybackSource: PlaybackSource(
          url: Uri.parse('https://example.com/live.m3u8'),
          headers: const {'referer': 'https://old.example.com/'},
        ),
      ),
      isTrue,
    );
    expect(
      shouldPreRefreshMdkBackendBeforeSameSourceRebind(
        state: PlayerState(
          backend: PlayerBackend.mdk,
          source: PlaybackSource(
            url: Uri.parse('https://example.com/live.m3u8'),
          ),
        ),
        playbackSource: PlaybackSource(
          url: Uri.parse('https://example.com/other.m3u8'),
        ),
        runtimeBackend: PlayerBackend.mdk,
      ),
      isFalse,
    );
    expect(
      shouldPreRefreshMdkBackendBeforeSameSourceRebind(
        state: PlayerState(
          backend: PlayerBackend.mpv,
          source: PlaybackSource(
            url: Uri.parse('https://example.com/live.m3u8'),
          ),
        ),
        playbackSource: PlaybackSource(
          url: Uri.parse('https://example.com/live.m3u8'),
        ),
        runtimeBackend: PlayerBackend.mpv,
      ),
      isFalse,
    );
    expect(
      shouldPreRefreshMdkBackendBeforeSameSourceRebind(
        state: PlayerState(
          backend: PlayerBackend.mdk,
          source: PlaybackSource(
            url: Uri.parse('https://example.com/live.m3u8'),
            externalAudio: PlaybackExternalMedia(
              url: Uri.parse('https://example.com/audio-a.m3u8'),
            ),
          ),
        ),
        playbackSource: PlaybackSource(
          url: Uri.parse('https://example.com/live.m3u8'),
          externalAudio: PlaybackExternalMedia(
            url: Uri.parse('https://example.com/audio-b.m3u8'),
          ),
        ),
        runtimeBackend: PlayerBackend.mdk,
      ),
      isFalse,
    );
  });

  test('fullscreen follow-room switch resets MDK route transition only', () {
    expect(
      shouldResetMdkBeforeFullscreenFollowRoomSwitch(
        fullscreenSessionActive: true,
        playerState: const PlayerState(
          backend: PlayerBackend.mdk,
          status: PlaybackStatus.playing,
        ),
        runtimeBackend: PlayerBackend.mdk,
      ),
      isTrue,
    );
    expect(
      shouldResetMdkBeforeFullscreenFollowRoomSwitch(
        fullscreenSessionActive: true,
        playerState: const PlayerState(
          backend: PlayerBackend.mpv,
          status: PlaybackStatus.playing,
        ),
        runtimeBackend: PlayerBackend.mpv,
      ),
      isFalse,
    );
    expect(
      shouldResetMdkBeforeFullscreenFollowRoomSwitch(
        fullscreenSessionActive: false,
        playerState: const PlayerState(
          backend: PlayerBackend.mdk,
          status: PlaybackStatus.playing,
        ),
        runtimeBackend: PlayerBackend.mdk,
      ),
      isFalse,
    );
  });

  test('player diagnostics summary includes buffer profile and rebuffer data',
      () {
    final summary = formatPlayerDiagnosticsSummary(
      diagnostics: const PlayerDiagnostics(
        backend: PlayerBackend.mdk,
        width: 2560,
        height: 1440,
        rebufferCount: 2,
        lastRebufferDuration: Duration(milliseconds: 480),
        videoParams: <String, String>{
          'codec': 'AMediaCodec',
          'frame_rate': '60.0',
        },
      ),
      source: PlaybackSource(
        url: Uri.parse('https://example.com/live.m3u8'),
        bufferProfile: PlaybackBufferProfile.heavyStreamStable,
      ),
    );

    expect(summary, contains('backend=mdk'));
    expect(summary, contains('decoder=AMediaCodec'));
    expect(summary, contains('size=2560x1440'));
    expect(summary, contains('frameRate=60.0'));
    expect(summary, contains('bufferProfile=heavyStreamStable'));
    expect(summary, contains('rebufferCount=2'));
    expect(summary, contains('lastRebufferMs=480'));
  });

  test('player diagnostics source signature tracks active media identity', () {
    expect(resolvePlayerDiagnosticsSourceSignature(null), isNull);

    final base = PlaybackSource(
      url: Uri.parse('https://example.com/live.m3u8'),
      bufferProfile: PlaybackBufferProfile.heavyStreamStable,
    );
    final withExternalAudio = PlaybackSource(
      url: Uri.parse('https://example.com/live.m3u8'),
      externalAudio: PlaybackExternalMedia(
        url: Uri.parse('https://example.com/audio.m3u8'),
      ),
      bufferProfile: PlaybackBufferProfile.heavyStreamStable,
    );

    expect(
      resolvePlayerDiagnosticsSourceSignature(base),
      isNot(resolvePlayerDiagnosticsSourceSignature(withExternalAudio)),
    );
    expect(
      resolvePlayerDiagnosticsSourceSignature(base),
      contains('heavyStreamStable'),
    );
  });

  testWidgets('room preview retries source once before refreshing MDK backend',
      (tester) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    final player = _FailOnceMdkPlayer();
    final runtime = _RefreshTrackingMdkPlayerRuntime(player);
    addTearDown(player.dispose);

    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: RoomPreviewPage(
          dependencies: _roomDependencies(bootstrap, playerRuntime: runtime),
          providerId: ProviderId.bilibili,
          roomId: '66666',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(
      resolveMdkTextureRecoveryRetryDelay(0) + const Duration(milliseconds: 40),
    );
    await tester.pump();
    await tester.pump(
      resolveMdkTextureRecoveryRetryDelay(1) + const Duration(milliseconds: 40),
    );
    await tester.pump();

    expect(
      player.events,
      containsAllInOrder(<String>[
        'buildView',
        'setSource',
        'stop',
        'setSource',
        'play',
      ]),
    );
    expect(runtime.refreshCount, 0);
    expect(runtime.currentState.status, PlaybackStatus.playing);
  });

  testWidgets(
      'room preview refreshes MDK backend after second texture init failure',
      (tester) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    final player = _FailOnceMdkPlayer(initialSetSourceFailures: 2);
    final runtime = _RefreshTrackingMdkPlayerRuntime(player);
    addTearDown(player.dispose);

    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: RoomPreviewPage(
          dependencies: _roomDependencies(bootstrap, playerRuntime: runtime),
          providerId: ProviderId.bilibili,
          roomId: '66666',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(
      resolveMdkTextureRecoveryRetryDelay(0) + const Duration(milliseconds: 40),
    );
    await tester.pump();
    await tester.pump(
      resolveMdkTextureRecoveryRetryDelay(1) + const Duration(milliseconds: 40),
    );
    await tester.pump();

    expect(
      player.events,
      containsAllInOrder(<String>[
        'buildView',
        'setSource',
        'stop',
        'setSource',
        'stop',
        'refreshBackend',
        'buildView',
        'setSource',
        'play',
      ]),
    );
    expect(runtime.refreshCount, 1);
    expect(runtime.currentState.status, PlaybackStatus.playing);
  });

  testWidgets(
      'manual quality switch refreshes MDK backend and retries source after second texture init failure',
      (tester) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    final player = _FailOnceMdkPlayer(failFirstSetSource: false);
    final runtime = _RefreshTrackingMdkPlayerRuntime(player);
    addTearDown(player.dispose);

    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: RoomPreviewPage(
          dependencies: _roomDependencies(bootstrap, playerRuntime: runtime),
          providerId: ProviderId.bilibili,
          roomId: '66666',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    player.armNextSetSourceFailure(times: 2);
    final initialEventCount = player.events.length;

    await tester.tap(find.byKey(const Key('room-appbar-more-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('切换清晰度'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('高清'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));

    final switchEvents = player.events.sublist(initialEventCount);
    expect(
      switchEvents,
      containsAllInOrder(<String>[
        'setSource',
        'stop',
        'setSource',
        'stop',
        'refreshBackend',
        'setSource',
        'play',
      ]),
    );
    expect(runtime.refreshCount, 1);
    expect(runtime.currentState.status, PlaybackStatus.playing);
    expect(
      runtime.currentState.source?.url.toString(),
      contains('/150.m3u8'),
    );
  });

  testWidgets(
      'room preview stops retries after backend refresh retry is exhausted',
      (tester) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    final player = _FailOnceMdkPlayer(initialSetSourceFailures: 3);
    final runtime = _RefreshTrackingMdkPlayerRuntime(player);
    addTearDown(player.dispose);

    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: RoomPreviewPage(
          dependencies: _roomDependencies(bootstrap, playerRuntime: runtime),
          providerId: ProviderId.bilibili,
          roomId: '66666',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(
      resolveMdkTextureRecoveryRetryDelay(0) + const Duration(milliseconds: 40),
    );
    await tester.pump();
    await tester.pump(
      resolveMdkTextureRecoveryRetryDelay(1) + const Duration(milliseconds: 40),
    );
    await tester.pump();

    expect(
      player.events,
      containsAllInOrder(<String>[
        'buildView',
        'setSource',
        'stop',
        'setSource',
        'stop',
        'refreshBackend',
        'buildView',
        'setSource',
      ]),
    );
    expect(player.events.where((event) => event == 'refreshBackend'),
        hasLength(1));
    expect(player.events.where((event) => event == 'play'), isEmpty);
    expect(runtime.refreshCount, 1);
    expect(runtime.currentState.status, PlaybackStatus.error);
  });

  testWidgets(
      'room preview debug sheet renders current diagnostics immediately',
      (tester) async {
    final base = createAppBootstrap(mode: AppRuntimeMode.preview);
    final player = _RecordingPlayer(
      currentDiagnostics: const PlayerDiagnostics(
        backend: PlayerBackend.mpv,
        width: 1920,
        height: 1080,
        buffered: Duration(milliseconds: 2048),
        lowLatencyMode: true,
        rebufferCount: 2,
        lastRebufferDuration: Duration(milliseconds: 333),
      ),
    );
    addTearDown(player.dispose);
    final dependencies = _roomDependencies(base, player: player);

    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: RoomPreviewPage(
          dependencies: dependencies,
          providerId: ProviderId.bilibili,
          roomId: '66666',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    await tester.tap(find.byKey(const Key('room-appbar-more-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('调试面板'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('1920 x 1080'), findsOneWidget);
    expect(find.text('2048 ms'), findsOneWidget);
    expect(find.text('低延迟模式'), findsOneWidget);
    expect(find.text('重缓冲次数'), findsOneWidget);
    expect(find.text('最近卡顿'), findsOneWidget);
    expect(find.text('333 ms'), findsOneWidget);
  });

  testWidgets('room preview panels can switch by horizontal swipe', (
    tester,
  ) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    await bootstrap.followRepository.upsert(
      const FollowRecord(
        providerId: 'bilibili',
        roomId: '6',
        streamerName: '系统演示主播',
      ),
    );
    bootstrap.followWatchlistSnapshot.value = FollowWatchlist(
      entries: const [
        FollowWatchEntry(
          record: FollowRecord(
            providerId: 'bilibili',
            roomId: '6',
            streamerName: '系统演示主播',
          ),
          detail: LiveRoomDetail(
            providerId: 'bilibili',
            roomId: '6',
            title: '系统演示直播间',
            streamerName: '系统演示主播',
            isLive: true,
          ),
        ),
      ],
    );

    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: RoomPreviewPage(
          dependencies: _roomDependencies(bootstrap),
          providerId: ProviderId.bilibili,
          roomId: '66666',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    await tester.fling(
      find.byType(PageView).first,
      const Offset(-800, 0),
      1600,
    );
    await tester.pumpAndSettle();

    await tester.fling(
      find.byType(PageView).first,
      const Offset(-800, 0),
      1600,
    );
    await tester.pumpAndSettle();

    await tester.fling(
      find.byType(PageView).first,
      const Offset(-800, 0),
      1600,
    );
    await tester.pumpAndSettle();

    expect(find.text('播放器中显示SC'), findsOneWidget);
    expect(find.text('关键词屏蔽'), findsOneWidget);
  });

  testWidgets('fullscreen long press on right edge opens live follow drawer', (
    tester,
  ) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    bootstrap.followWatchlistSnapshot.value = FollowWatchlist(
      entries: const [
        FollowWatchEntry(
          record: FollowRecord(
            providerId: 'bilibili',
            roomId: '6',
            streamerName: '系统演示主播',
          ),
          detail: LiveRoomDetail(
            providerId: 'bilibili',
            roomId: '6',
            title: '系统演示直播间',
            streamerName: '系统演示主播',
            isLive: true,
          ),
        ),
        FollowWatchEntry(
          record: FollowRecord(
            providerId: 'douyu',
            roomId: '3125893',
            streamerName: '斗鱼样例主播',
          ),
          detail: LiveRoomDetail(
            providerId: 'douyu',
            roomId: '3125893',
            title: '斗鱼样例直播间',
            streamerName: '斗鱼样例主播',
            isLive: true,
          ),
        ),
      ],
    );

    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: RoomPreviewPage(
          dependencies: _roomDependencies(bootstrap),
          providerId: ProviderId.bilibili,
          roomId: '66666',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    await tester.tap(find.byKey(const Key('room-inline-player-tap-target')));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tap(find.byKey(const Key('room-inline-player-tap-target')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final drawerFinder = find.byKey(const Key('room-fullscreen-follow-drawer'));
    final hiddenDrawerDx = tester.getTopLeft(drawerFinder).dx;

    await tester.longPressAt(const Offset(1040, 960));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(drawerFinder, findsOneWidget);
    expect(tester.getTopLeft(drawerFinder).dx, lessThan(hiddenDrawerDx));
    expect(
      find.byKey(const Key('room-fullscreen-follow-entry-bilibili-6')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('room-fullscreen-follow-entry-douyu-3125893')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('room-fullscreen-follow-close-button')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.getTopLeft(drawerFinder).dx,
        greaterThanOrEqualTo(hiddenDrawerDx));
  });

  testWidgets('fullscreen follow drawer keeps fullscreen when switching room',
      (tester) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    bootstrap.followWatchlistSnapshot.value = FollowWatchlist(
      entries: const [
        FollowWatchEntry(
          record: FollowRecord(
            providerId: 'bilibili',
            roomId: '6',
            streamerName: '系统演示主播',
          ),
          detail: LiveRoomDetail(
            providerId: 'bilibili',
            roomId: '6',
            title: '系统演示直播间',
            streamerName: '系统演示主播',
            isLive: true,
          ),
        ),
      ],
    );
    RouteSettings? pushedSettings;

    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: RoomPreviewPage(
          dependencies: _roomDependencies(bootstrap),
          providerId: ProviderId.bilibili,
          roomId: '66666',
        ),
        onGenerateRoute: (settings) {
          if (settings.name != AppRoutes.room) {
            return null;
          }
          pushedSettings = settings;
          final arguments = settings.arguments as RoomRouteArguments;
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => RoomPreviewPage(
              dependencies: _roomDependencies(bootstrap),
              providerId: arguments.providerId,
              roomId: arguments.roomId,
              startInFullscreen: arguments.startInFullscreen,
            ),
          );
        },
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    await tester.tap(find.byKey(const Key('room-inline-player-tap-target')));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tap(find.byKey(const Key('room-inline-player-tap-target')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.longPressAt(const Offset(1040, 960));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(
      find.byKey(const Key('room-fullscreen-follow-entry-bilibili-6')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(seconds: 2));

    expect(pushedSettings?.name, AppRoutes.room);
    final arguments = pushedSettings?.arguments as RoomRouteArguments?;
    expect(arguments, isNotNull);
    expect(arguments!.providerId, ProviderId.bilibili);
    expect(arguments.roomId, '6');
    expect(arguments.startInFullscreen, isTrue);
    expect(find.byKey(const Key('room-fullscreen-overlay')), findsOneWidget);
    expect(find.byKey(const Key('room-leave-button')), findsNothing);
  });

  testWidgets(
      'fullscreen follow drawer pre-cleans MDK runtime before switching room',
      (tester) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    final player = _FailOnceMdkPlayer(failFirstSetSource: false);
    final runtime = _RefreshTrackingMdkPlayerRuntime(player);
    addTearDown(player.dispose);
    bootstrap.followWatchlistSnapshot.value = FollowWatchlist(
      entries: const [
        FollowWatchEntry(
          record: FollowRecord(
            providerId: 'bilibili',
            roomId: '6',
            streamerName: '系统演示主播',
          ),
          detail: LiveRoomDetail(
            providerId: 'bilibili',
            roomId: '6',
            title: '系统演示直播间',
            streamerName: '系统演示主播',
            isLive: true,
          ),
        ),
      ],
    );

    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: RoomPreviewPage(
          dependencies: _roomDependencies(bootstrap, playerRuntime: runtime),
          providerId: ProviderId.bilibili,
          roomId: '66666',
        ),
        onGenerateRoute: (settings) {
          if (settings.name != AppRoutes.room) {
            return null;
          }
          final arguments = settings.arguments as RoomRouteArguments;
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => RoomPreviewPage(
              dependencies: _roomDependencies(
                bootstrap,
                playerRuntime: runtime,
              ),
              providerId: arguments.providerId,
              roomId: arguments.roomId,
              startInFullscreen: arguments.startInFullscreen,
            ),
          );
        },
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    await tester.tap(find.byKey(const Key('room-inline-player-tap-target')));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tap(find.byKey(const Key('room-inline-player-tap-target')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    player.events.clear();

    await tester.longPressAt(const Offset(1040, 960));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(
      find.byKey(const Key('room-fullscreen-follow-entry-bilibili-6')),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(seconds: 2));

    expect(
      player.events,
      containsAllInOrder(<String>[
        'stop',
        'refreshBackend',
        'setSource',
        'play',
      ]),
    );
    expect(runtime.refreshCount, 1);
    expect(find.byKey(const Key('room-fullscreen-overlay')), findsOneWidget);
    expect(find.byKey(const Key('room-leave-button')), findsNothing);
  });

  testWidgets(
      'fullscreen follow drawer shows message and stays in room when MDK cleanup fails',
      (tester) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    final player = _FailOnceMdkPlayer(failFirstSetSource: false);
    final runtime = _ThrowingRefreshMdkPlayerRuntime(player);
    addTearDown(player.dispose);
    bootstrap.followWatchlistSnapshot.value = FollowWatchlist(
      entries: const [
        FollowWatchEntry(
          record: FollowRecord(
            providerId: 'bilibili',
            roomId: '6',
            streamerName: '系统演示主播',
          ),
          detail: LiveRoomDetail(
            providerId: 'bilibili',
            roomId: '6',
            title: '系统演示直播间',
            streamerName: '系统演示主播',
            isLive: true,
          ),
        ),
      ],
    );

    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: RoomPreviewPage(
          dependencies: _roomDependencies(bootstrap, playerRuntime: runtime),
          providerId: ProviderId.bilibili,
          roomId: '66666',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    await tester.tap(find.byKey(const Key('room-inline-player-tap-target')));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tap(find.byKey(const Key('room-inline-player-tap-target')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.longPressAt(const Offset(1040, 960));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(
      find.byKey(const Key('room-fullscreen-follow-entry-bilibili-6')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('切换直播间失败，请稍后重试'), findsOneWidget);
    expect(runtime.refreshCount, 1);
    expect(
      player.events,
      containsAllInOrder(<String>[
        'stop',
        'refreshBackend',
        'setSource',
        'play',
      ]),
    );
    expect(find.byKey(const Key('room-fullscreen-overlay')), findsOneWidget);
  });

  testWidgets(
      'fullscreen follow drawer ignores repeated taps while transition is active',
      (tester) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    final player = _FailOnceMdkPlayer(failFirstSetSource: false);
    final runtime = _DelayedRefreshMdkPlayerRuntime(player);
    addTearDown(player.dispose);
    bootstrap.followWatchlistSnapshot.value = FollowWatchlist(
      entries: const [
        FollowWatchEntry(
          record: FollowRecord(
            providerId: 'bilibili',
            roomId: '6',
            streamerName: '系统演示主播',
          ),
          detail: LiveRoomDetail(
            providerId: 'bilibili',
            roomId: '6',
            title: '系统演示直播间',
            streamerName: '系统演示主播',
            isLive: true,
          ),
        ),
      ],
    );

    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: RoomPreviewPage(
          dependencies: _roomDependencies(bootstrap, playerRuntime: runtime),
          providerId: ProviderId.bilibili,
          roomId: '66666',
        ),
        onGenerateRoute: (settings) {
          if (settings.name != AppRoutes.room) {
            return null;
          }
          final arguments = settings.arguments as RoomRouteArguments;
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => RoomPreviewPage(
              dependencies: _roomDependencies(
                bootstrap,
                playerRuntime: runtime,
              ),
              providerId: arguments.providerId,
              roomId: arguments.roomId,
              startInFullscreen: arguments.startInFullscreen,
            ),
          );
        },
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    await tester.tap(find.byKey(const Key('room-inline-player-tap-target')));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tap(find.byKey(const Key('room-inline-player-tap-target')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.longPressAt(const Offset(1040, 960));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final followEntry =
        find.byKey(const Key('room-fullscreen-follow-entry-bilibili-6'));
    await tester.tap(followEntry);
    await tester.tap(followEntry);
    await tester.pump();

    expect(player.events.where((event) => event == 'stop').length, 1);
    expect(runtime.refreshCount, 1);

    runtime.completeRefresh();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(seconds: 2));

    expect(find.byKey(const Key('room-fullscreen-overlay')), findsOneWidget);
  });

  testWidgets('room follow watchlist loads lazily after opening follow tab',
      (tester) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    var detailCalls = 0;

    bootstrap.providerRegistry.register(
      ProviderRegistration(
        descriptor: _kWidgetTestFollowDescriptor,
        builder: () => _WidgetTestFollowProvider(
          onRoomDetail: (roomId) async {
            detailCalls += 1;
            return LiveRoomDetail(
              providerId: _kWidgetTestFollowProviderId.value,
              roomId: roomId,
              title: '$roomId-title',
              streamerName: roomId,
              sourceUrl: 'https://example.com/$roomId',
              isLive: true,
            );
          },
        ),
      ),
    );
    bootstrap.providerRegistry.clearCache();

    await bootstrap.followRepository.upsert(
      const FollowRecord(
        providerId: 'widget_test_follow',
        roomId: 'follow-1',
        streamerName: '关注主播',
      ),
    );

    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: RoomPreviewPage(
          dependencies: _roomDependencies(bootstrap),
          providerId: _kWidgetTestFollowProviderId,
          roomId: 'current-1',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(detailCalls, 1);

    await tester.tap(find.byKey(const Key('room-panel-tab-follow')));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(detailCalls, 2);
    expect(
      find.byKey(const Key('room-follow-entry-widget_test_follow-follow-1')),
      findsOneWidget,
    );
  });

  testWidgets('following current room updates follow panel snapshot',
      (tester) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    bootstrap.providerRegistry.register(
      ProviderRegistration(
        descriptor: _kWidgetTestFollowDescriptor,
        builder: () => _WidgetTestFollowProvider(
          onRoomDetail: (roomId) async {
            return LiveRoomDetail(
              providerId: _kWidgetTestFollowProviderId.value,
              roomId: roomId,
              title: '$roomId-title',
              streamerName: roomId,
              sourceUrl: 'https://example.com/$roomId',
              isLive: true,
            );
          },
        ),
      ),
    );
    bootstrap.providerRegistry.clearCache();

    await bootstrap.followRepository.upsert(
      const FollowRecord(
        providerId: 'widget_test_follow',
        roomId: 'follow-1',
        streamerName: '关注主播',
      ),
    );

    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: RoomPreviewPage(
          dependencies: _roomDependencies(bootstrap),
          providerId: _kWidgetTestFollowProviderId,
          roomId: 'current-1',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    await tester.tap(find.byKey(const Key('room-panel-tab-follow')));
    await tester.pump();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('room-follow-toggle-button')));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('取消关注'), findsOneWidget);
    expect(
      bootstrap.followWatchlistSnapshot.value?.entries.any(
        (entry) => entry.roomId == 'current-1',
      ),
      isTrue,
    );
  });

  testWidgets('room page confirms before removing current room follow state',
      (tester) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    bootstrap.providerRegistry.register(
      ProviderRegistration(
        descriptor: _kWidgetTestFollowDescriptor,
        builder: () => _WidgetTestFollowProvider(
          onRoomDetail: (roomId) async {
            return LiveRoomDetail(
              providerId: _kWidgetTestFollowProviderId.value,
              roomId: roomId,
              title: '$roomId-title',
              streamerName: roomId,
              sourceUrl: 'https://example.com/$roomId',
              isLive: true,
            );
          },
        ),
      ),
    );
    bootstrap.providerRegistry.clearCache();

    await bootstrap.followRepository.upsert(
      const FollowRecord(
        providerId: 'widget_test_follow',
        roomId: 'current-1',
        streamerName: 'current-1',
      ),
    );

    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: RoomPreviewPage(
          dependencies: _roomDependencies(bootstrap),
          providerId: _kWidgetTestFollowProviderId,
          roomId: 'current-1',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('取消关注'), findsOneWidget);

    await tester.tap(find.byKey(const Key('room-follow-toggle-button')));
    await tester.pumpAndSettle();

    expect(find.text('确认取消'), findsOneWidget);
    expect(await bootstrap.followRepository.listAll(), hasLength(1));

    await tester.tap(find.text('保留关注'));
    await tester.pumpAndSettle();

    expect(find.text('取消关注'), findsOneWidget);
    expect(await bootstrap.followRepository.listAll(), hasLength(1));

    await tester.tap(find.byKey(const Key('room-follow-toggle-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认取消'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('room-follow-toggle-button')),
        matching: find.text('关注'),
      ),
      findsOneWidget,
    );
    expect(await bootstrap.followRepository.listAll(), isEmpty);
  });

  testWidgets('leaving room stops inline playback', (tester) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => RoomPreviewPage(
                        dependencies: _roomDependencies(bootstrap),
                        providerId: ProviderId.bilibili,
                        roomId: '66666',
                      ),
                    ),
                  );
                },
                child: const Text('open room'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open room'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(bootstrap.playerRuntime.currentState.status, PlaybackStatus.playing);

    await tester.tap(find.byKey(const Key('room-leave-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(bootstrap.playerRuntime.currentState.status, PlaybackStatus.ready);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('picture-in-picture failure restores fullscreen UI',
      (tester) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    final preferences = await bootstrap.loadPlayerPreferences();
    await bootstrap.updatePlayerPreferences(
      preferences.copyWith(androidAutoFullscreenEnabled: false),
    );
    final player = TestRecordingPlayer();
    final android = TestRoomAndroidPlaybackBridgeFacade();
    final pipHost = TestRoomPipHostFacade()
      ..nextEnableStatus = PiPStatus.disabled
      ..emitStatusOnEnable = false;
    final platforms = RoomFullscreenSessionPlatforms(
      androidPlaybackBridge: android,
      pipHost: pipHost,
      desktopWindow: TestRoomDesktopWindowFacade(),
      screenAwake: TestRoomScreenAwakeFacade(),
      systemUi: TestRoomSystemUiFacade(),
    );
    addTearDown(() async {
      await pipHost.dispose();
      await player.dispose();
    });

    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: RoomPreviewPage(
          dependencies: _roomDependencies(
            bootstrap,
            player: player,
            platforms: platforms,
          ),
          providerId: ProviderId.bilibili,
          roomId: '66666',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    await tester.tap(find.byKey(const Key('room-inline-player-tap-target')));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tap(find.byKey(const Key('room-inline-player-tap-target')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byKey(const Key('room-fullscreen-more-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('room-quick-pip-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('进入画中画失败，请稍后重试'), findsOneWidget);
    expect(find.byKey(const Key('room-fullscreen-refresh-button')),
        findsOneWidget);
    expect(find.byKey(const Key('room-fullscreen-overlay')), findsOneWidget);
  });

  testWidgets('picture-in-picture surface reuses embedded player host', (
    tester,
  ) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    final player = TestRecordingPlayer();
    final pipHost = TestRoomPipHostFacade();
    final platforms = RoomFullscreenSessionPlatforms(
      androidPlaybackBridge: TestRoomAndroidPlaybackBridgeFacade(),
      pipHost: pipHost,
      desktopWindow: TestRoomDesktopWindowFacade(),
      screenAwake: TestRoomScreenAwakeFacade(),
      systemUi: TestRoomSystemUiFacade(),
    );
    addTearDown(() async {
      await pipHost.dispose();
      await player.dispose();
    });

    Widget buildPage() {
      return MaterialApp(
        home: RoomPreviewPage(
          dependencies: _roomDependencies(
            bootstrap,
            player: player,
            platforms: platforms,
          ),
          providerId: ProviderId.bilibili,
          roomId: '66666',
        ),
      );
    }

    await tester.pumpWidget(buildPage());
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    player.viewKeys.clear();
    pipHost.switcherEnabled = true;
    await tester.pumpWidget(buildPage());
    await tester.pump();

    expect(find.byKey(const ValueKey('room-player-pip')), findsNothing);
    expect(
      player.viewKeys.whereType<GlobalKey>().isNotEmpty,
      isTrue,
    );
    expect(
      player.viewKeys.where((key) => key == const ValueKey('room-player-pip')),
      isEmpty,
    );
  });

  testWidgets('lifecycle pause and resume suspends then restores playback', (
    tester,
  ) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    final player = TestRecordingPlayer();
    final platforms = RoomFullscreenSessionPlatforms(
      androidPlaybackBridge: TestRoomAndroidPlaybackBridgeFacade(),
      pipHost: TestRoomPipHostFacade(),
      desktopWindow: TestRoomDesktopWindowFacade(),
      screenAwake: TestRoomScreenAwakeFacade(),
      systemUi: TestRoomSystemUiFacade(),
    );
    addTearDown(() async {
      await (platforms.pipHost as TestRoomPipHostFacade).dispose();
      await player.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: RoomPreviewPage(
          dependencies: _roomDependencies(
            bootstrap,
            player: player,
            platforms: platforms,
          ),
          providerId: ProviderId.bilibili,
          roomId: '66666',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    player.events.clear();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(player.events, contains('stop'));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(player.events, contains('play'));
  });

  testWidgets('leaving room while already in picture-in-picture keeps playback',
      (
    tester,
  ) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    final player = TestRecordingPlayer();
    final android = TestRoomAndroidPlaybackBridgeFacade()
      ..inPictureInPictureMode = true;
    final pipHost = TestRoomPipHostFacade();
    final platforms = RoomFullscreenSessionPlatforms(
      androidPlaybackBridge: android,
      pipHost: pipHost,
      desktopWindow: TestRoomDesktopWindowFacade(),
      screenAwake: TestRoomScreenAwakeFacade(),
      systemUi: TestRoomSystemUiFacade(),
    );
    addTearDown(() async {
      await pipHost.dispose();
      await player.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => RoomPreviewPage(
                        dependencies: _roomDependencies(
                          bootstrap,
                          player: player,
                          platforms: platforms,
                        ),
                        providerId: ProviderId.bilibili,
                        roomId: '66666',
                      ),
                    ),
                  );
                },
                child: const Text('open room'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open room'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    player.events.clear();

    if (find
        .byKey(const Key('room-fullscreen-overlay'))
        .evaluate()
        .isNotEmpty) {
      await tester.tap(find.byKey(const Key('room-exit-fullscreen-button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      player.events.clear();
    }

    await tester.tap(find.byKey(const Key('room-leave-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(player.events, isNot(contains('stop')));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('chaturbate private show room opens with status marker',
      (tester) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    bootstrap.providerRegistry.register(
      ProviderRegistration(
        descriptor: _kChaturbatePrivateShowDescriptor,
        builder: _ChaturbatePrivateShowProvider.new,
      ),
    );
    bootstrap.providerRegistry.clearCache();

    await tester.pumpWidget(
      MaterialApp(
        home: RoomPreviewPage(
          dependencies: _roomDependencies(bootstrap),
          providerId: ProviderId.chaturbate,
          roomId: 'consuelabrasington',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('私密表演中'), findsWidgets);
    expect(find.textContaining('Private Show'), findsWidgets);
    expect(find.textContaining('暂时没有公开播放流'), findsWidgets);
    expect(find.text('暂时打不开这个直播间'), findsNothing);
  });

  testWidgets('super chat empty state is plain text without surface card',
      (tester) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    bootstrap.providerRegistry.register(
      ProviderRegistration(
        descriptor: _kWidgetTestFollowDescriptor,
        builder: () => _WidgetTestFollowProvider(
          onRoomDetail: (roomId) async {
            return LiveRoomDetail(
              providerId: _kWidgetTestFollowProviderId.value,
              roomId: roomId,
              title: '$roomId-title',
              streamerName: roomId,
              sourceUrl: 'https://example.com/$roomId',
              isLive: true,
            );
          },
        ),
      ),
    );
    bootstrap.providerRegistry.clearCache();

    await tester.pumpWidget(
      MaterialApp(
        home: RoomPreviewPage(
          dependencies: _roomDependencies(bootstrap),
          providerId: _kWidgetTestFollowProviderId,
          roomId: 'current-1',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    await tester.tap(find.byKey(const Key('room-panel-tab-super-chat')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.byType(AppSurfaceCard),
      findsNothing,
    );
  });

  testWidgets('player super chat overlay expires after configured duration', (
    tester,
  ) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    final roomUiPreferences = await bootstrap.loadRoomUiPreferences();
    await bootstrap.updateRoomUiPreferences(
      roomUiPreferences.copyWith(playerSuperChatDisplaySeconds: 3),
    );

    bootstrap.providerRegistry.register(
      ProviderRegistration(
        descriptor: _kWidgetTestDanmakuDescriptor,
        builder: () => _WidgetTestDanmakuProvider(
          createSession: () => _ScriptedDanmakuSession(
            onConnect: (controller) async {
              controller.add(
                LiveMessage(
                  type: LiveMessageType.superChat,
                  content: '醒目留言测试',
                  userName: '测试用户',
                  timestamp: DateTime.now(),
                ),
              );
            },
          ),
        ),
      ),
    );
    bootstrap.providerRegistry.clearCache();

    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: RoomPreviewPage(
          dependencies: _roomDependencies(bootstrap),
          providerId: _kWidgetTestDanmakuProviderId,
          roomId: 'super-chat-room',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    await tester.tap(find.byKey(const Key('room-inline-player-tap-target')));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tap(find.byKey(const Key('room-inline-player-tap-target')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const Key('room-player-super-chat-overlay')),
        findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    await tester.pump();

    expect(
        find.byKey(const Key('room-player-super-chat-overlay')), findsNothing);
  });

  testWidgets('danmaku reconnects automatically after disconnect notice', (
    tester,
  ) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    var sessionCreateCount = 0;

    bootstrap.providerRegistry.register(
      ProviderRegistration(
        descriptor: _kWidgetTestDanmakuDescriptor,
        builder: () => _WidgetTestDanmakuProvider(
          createSession: () {
            sessionCreateCount += 1;
            if (sessionCreateCount == 1) {
              return _ScriptedDanmakuSession(
                onConnect: (controller) async {
                  controller.add(
                    LiveMessage(
                      type: LiveMessageType.notice,
                      content: '测试弹幕连接已断开',
                      timestamp: DateTime.now(),
                    ),
                  );
                },
              );
            }
            return _ScriptedDanmakuSession(
              onConnect: (controller) async {
                controller.add(
                  LiveMessage(
                    type: LiveMessageType.chat,
                    content: '自动重连后的弹幕',
                    userName: '测试用户',
                    timestamp: DateTime.now(),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
    bootstrap.providerRegistry.clearCache();

    await tester.pumpWidget(
      MaterialApp(
        home: RoomPreviewPage(
          dependencies: _roomDependencies(bootstrap),
          providerId: _kWidgetTestDanmakuProviderId,
          roomId: 'reconnect-room',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();

    expect(sessionCreateCount, 2);
  });

  testWidgets(
      'disposed room ignores stale danmaku reconnect completion after replacement',
      (tester) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    final staleReconnectSessionCompleter = Completer<DanmakuSession>();
    var sessionCreateCount = 0;

    bootstrap.providerRegistry.register(
      ProviderRegistration(
        descriptor: _kWidgetTestDanmakuDescriptor,
        builder: () => _WidgetTestDanmakuProvider(
          createSession: () {
            sessionCreateCount += 1;
            if (sessionCreateCount == 1) {
              return _ScriptedDanmakuSession(
                onConnect: (controller) async {
                  controller.add(
                    LiveMessage(
                      type: LiveMessageType.notice,
                      content: '测试弹幕连接已断开',
                      timestamp: DateTime.now(),
                    ),
                  );
                },
              );
            }
            if (sessionCreateCount == 2) {
              return staleReconnectSessionCompleter.future;
            }
            return _ScriptedDanmakuSession(
              onConnect: (controller) async {
                controller.add(
                  LiveMessage(
                    type: LiveMessageType.chat,
                    content: 'room-2-message',
                    userName: '测试用户',
                    timestamp: DateTime.now(),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
    bootstrap.providerRegistry.clearCache();

    await tester.pumpWidget(
      MaterialApp(
        home: RoomPreviewPage(
          dependencies: _roomDependencies(bootstrap),
          providerId: _kWidgetTestDanmakuProviderId,
          roomId: 'room-1',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();

    await tester.pumpWidget(
      MaterialApp(
        home: RoomPreviewPage(
          dependencies: _roomDependencies(bootstrap),
          providerId: _kWidgetTestDanmakuProviderId,
          roomId: 'room-2',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    staleReconnectSessionCompleter.complete(
      _ScriptedDanmakuSession(onConnect: (_) async {}),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(sessionCreateCount, 2);
    expect(find.byType(RoomPreviewPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

const _kChaturbatePrivateShowDescriptor = ProviderDescriptor(
  id: ProviderId.chaturbate,
  displayName: 'Chaturbate',
  capabilities: {
    ProviderCapability.roomDetail,
    ProviderCapability.playQualities,
    ProviderCapability.playUrls,
  },
  supportedPlatforms: {ProviderPlatform.android},
  maturity: ProviderMaturity.inMigration,
);

class _ChaturbatePrivateShowProvider extends LiveProvider
    implements SupportsRoomDetail, SupportsPlayQualities, SupportsPlayUrls {
  @override
  ProviderDescriptor get descriptor => _kChaturbatePrivateShowDescriptor;

  @override
  Future<LiveRoomDetail> fetchRoomDetail(String roomId) async {
    return LiveRoomDetail(
      providerId: ProviderId.chaturbate.value,
      roomId: roomId,
      title: roomId,
      streamerName: roomId,
      sourceUrl: 'https://chaturbate.com/$roomId/',
      isLive: false,
      metadata: const {
        'roomStatus': 'private show in progress',
      },
    );
  }

  @override
  Future<List<LivePlayQuality>> fetchPlayQualities(
    LiveRoomDetail detail,
  ) async {
    return const [
      LivePlayQuality(
        id: 'auto',
        label: 'Auto',
        isDefault: true,
      ),
    ];
  }

  @override
  Future<List<LivePlayUrl>> fetchPlayUrls({
    required LiveRoomDetail detail,
    required LivePlayQuality quality,
  }) async {
    return const [];
  }
}

const _kWidgetTestFollowProviderId = ProviderId('widget_test_follow');

const _kWidgetTestFollowDescriptor = ProviderDescriptor(
  id: _kWidgetTestFollowProviderId,
  displayName: 'Widget Test',
  capabilities: {
    ProviderCapability.roomDetail,
    ProviderCapability.playQualities,
    ProviderCapability.playUrls,
  },
  supportedPlatforms: {ProviderPlatform.android},
  maturity: ProviderMaturity.ready,
);

class _WidgetTestFollowProvider extends LiveProvider
    implements SupportsRoomDetail, SupportsPlayQualities, SupportsPlayUrls {
  _WidgetTestFollowProvider({required this.onRoomDetail});

  final Future<LiveRoomDetail> Function(String roomId) onRoomDetail;

  @override
  ProviderDescriptor get descriptor => _kWidgetTestFollowDescriptor;

  @override
  Future<LiveRoomDetail> fetchRoomDetail(String roomId) => onRoomDetail(roomId);

  @override
  Future<List<LivePlayQuality>> fetchPlayQualities(
    LiveRoomDetail detail,
  ) async {
    return const [
      LivePlayQuality(
        id: 'auto',
        label: 'Auto',
        isDefault: true,
      ),
    ];
  }

  @override
  Future<List<LivePlayUrl>> fetchPlayUrls({
    required LiveRoomDetail detail,
    required LivePlayQuality quality,
  }) async {
    return const [
      LivePlayUrl(
        url: 'https://example.com/live.m3u8',
      ),
    ];
  }
}

const _kWidgetTestDanmakuProviderId = ProviderId('widget_test_danmaku');

const _kWidgetTestDanmakuDescriptor = ProviderDescriptor(
  id: _kWidgetTestDanmakuProviderId,
  displayName: 'Widget Danmaku Test',
  capabilities: {
    ProviderCapability.roomDetail,
    ProviderCapability.playQualities,
    ProviderCapability.playUrls,
    ProviderCapability.danmaku,
  },
  supportedPlatforms: {ProviderPlatform.android},
  maturity: ProviderMaturity.ready,
);

class _WidgetTestDanmakuProvider extends LiveProvider
    implements
        SupportsRoomDetail,
        SupportsPlayQualities,
        SupportsPlayUrls,
        SupportsDanmaku {
  _WidgetTestDanmakuProvider({required this.createSession});

  final FutureOr<DanmakuSession> Function() createSession;

  @override
  ProviderDescriptor get descriptor => _kWidgetTestDanmakuDescriptor;

  @override
  Future<LiveRoomDetail> fetchRoomDetail(String roomId) async {
    return LiveRoomDetail(
      providerId: _kWidgetTestDanmakuProviderId.value,
      roomId: roomId,
      title: '$roomId-title',
      streamerName: roomId,
      sourceUrl: 'https://example.com/$roomId',
      isLive: true,
    );
  }

  @override
  Future<List<LivePlayQuality>> fetchPlayQualities(
    LiveRoomDetail detail,
  ) async {
    return const [
      LivePlayQuality(
        id: 'auto',
        label: 'Auto',
        isDefault: true,
      ),
    ];
  }

  @override
  Future<List<LivePlayUrl>> fetchPlayUrls({
    required LiveRoomDetail detail,
    required LivePlayQuality quality,
  }) async {
    return const [
      LivePlayUrl(
        url: 'https://example.com/live.m3u8',
      ),
    ];
  }

  @override
  Future<DanmakuSession> createDanmakuSession(LiveRoomDetail detail) async {
    return Future<DanmakuSession>.value(createSession());
  }
}

class _ScriptedDanmakuSession implements DanmakuSession {
  _ScriptedDanmakuSession({
    required this.onConnect,
  });

  final Future<void> Function(StreamController<LiveMessage> controller)
      onConnect;
  final StreamController<LiveMessage> _controller =
      StreamController<LiveMessage>.broadcast();

  @override
  Stream<LiveMessage> get messages => _controller.stream;

  @override
  Future<void> connect() => onConnect(_controller);

  @override
  Future<void> disconnect() async {
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }
}

RoomPreviewDependencies _roomDependencies(
  AppBootstrap bootstrap, {
  BasePlayer? player,
  PlayerRuntimeController? playerRuntime,
  RoomFullscreenSessionPlatforms? platforms,
  OpenRoomDanmakuUseCase? openRoomDanmaku,
}) {
  return RoomPreviewDependencies(
    followWatchlistSnapshot: bootstrap.followWatchlistSnapshot,
    playerRuntime: playerRuntime ??
        (player == null
            ? bootstrap.playerRuntime
            : PlayerRuntimeController(player)),
    loadRoom: bootstrap.loadRoom,
    openRoomDanmaku: openRoomDanmaku ?? bootstrap.openRoomDanmaku,
    resolvePlaySource: bootstrap.resolvePlaySource,
    loadFollowWatchlist: bootstrap.loadFollowWatchlist,
    listFollowRecords: bootstrap.listFollowRecords,
    toggleFollowRoom: bootstrap.toggleFollowRoom,
    isFollowedRoom: bootstrap.isFollowedRoom,
    findProviderDescriptorById: bootstrap.findProviderDescriptorById,
    loadBlockedKeywords: bootstrap.loadBlockedKeywords,
    loadDanmakuPreferences: bootstrap.loadDanmakuPreferences,
    loadRoomUiPreferences: bootstrap.loadRoomUiPreferences,
    updateRoomUiPreferences: bootstrap.updateRoomUiPreferences,
    loadPlayerPreferences: bootstrap.loadPlayerPreferences,
    updatePlayerPreferences: bootstrap.updatePlayerPreferences,
    fullscreenSessionPlatforms: platforms ?? _defaultTestPlatforms(),
    isLiveMode: bootstrap.isLiveMode,
  );
}

class _NullDanmakuUseCase extends OpenRoomDanmakuUseCase {
  _NullDanmakuUseCase(super.registry);

  @override
  Future<DanmakuSession?> call({
    required ProviderId providerId,
    required LiveRoomDetail detail,
  }) async {
    return null;
  }
}

RoomFullscreenSessionPlatforms _defaultTestPlatforms() {
  final android = TestRoomAndroidPlaybackBridgeFacade()..supported = false;
  return RoomFullscreenSessionPlatforms(
    androidPlaybackBridge: android,
    pipHost: TestRoomPipHostFacade()..pipAvailable = false,
    desktopWindow: TestRoomDesktopWindowFacade(),
    screenAwake: TestRoomScreenAwakeFacade(),
    systemUi: TestRoomSystemUiFacade(),
  );
}

class _RecordingPlayer implements BasePlayer {
  _RecordingPlayer({
    PlayerDiagnostics? currentDiagnostics,
  }) : _currentDiagnostics = currentDiagnostics ??
            const PlayerDiagnostics(backend: PlayerBackend.mpv);

  final List<String> events = <String>[];
  final StreamController<PlayerState> _states =
      StreamController<PlayerState>.broadcast();
  final StreamController<PlayerDiagnostics> _diagnostics =
      StreamController<PlayerDiagnostics>.broadcast();

  PlayerState _currentState = const PlayerState(backend: PlayerBackend.mpv);
  final PlayerDiagnostics _currentDiagnostics;

  @override
  PlayerBackend get backend => PlayerBackend.mpv;

  @override
  Stream<PlayerState> get states => _states.stream;

  @override
  Stream<PlayerDiagnostics> get diagnostics => _diagnostics.stream;

  @override
  PlayerState get currentState => _currentState;

  @override
  PlayerDiagnostics get currentDiagnostics => _currentDiagnostics;

  @override
  bool get supportsEmbeddedView => true;

  @override
  bool get supportsScreenshot => true;

  @override
  Future<void> initialize() async {
    events.add('initialize');
    _emit(_currentState.copyWith(status: PlaybackStatus.ready));
  }

  @override
  Future<void> setSource(PlaybackSource source) async {
    events.add('setSource');
    _emit(
      _currentState.copyWith(
        status: PlaybackStatus.ready,
        source: source,
        clearErrorMessage: true,
      ),
    );
  }

  @override
  Future<void> play() async {
    events.add('play');
    _emit(_currentState.copyWith(status: PlaybackStatus.playing));
  }

  @override
  Future<void> pause() async {
    events.add('pause');
    _emit(_currentState.copyWith(status: PlaybackStatus.paused));
  }

  @override
  Future<void> stop() async {
    events.add('stop');
    _emit(
      _currentState.copyWith(
        status: PlaybackStatus.ready,
        clearSource: true,
      ),
    );
  }

  @override
  Future<void> setVolume(double value) async {
    events.add('setVolume');
    _emit(_currentState.copyWith(volume: value));
  }

  @override
  Future<Uint8List?> captureScreenshot() async =>
      Uint8List.fromList(<int>[1, 2, 3]);

  @override
  Widget buildView({
    Key? key,
    double? aspectRatio,
    BoxFit fit = BoxFit.contain,
    bool pauseUponEnteringBackgroundMode = true,
    bool resumeUponEnteringForegroundMode = false,
  }) {
    events.add('buildView');
    return SizedBox.expand(key: key);
  }

  @override
  Future<void> dispose() async {
    await _states.close();
    await _diagnostics.close();
  }

  void _emit(PlayerState next) {
    _currentState = next.copyWith(backend: backend);
    if (!_states.isClosed) {
      _states.add(_currentState);
    }
  }
}

class _FailOnceMdkPlayer extends _RecordingPlayer {
  _FailOnceMdkPlayer({
    bool failFirstSetSource = true,
    int initialSetSourceFailures = 1,
  })  : _pendingSetSourceFailures =
            failFirstSetSource ? initialSetSourceFailures : 0,
        super(
          currentDiagnostics: const PlayerDiagnostics(
            backend: PlayerBackend.mdk,
          ),
        );

  int _pendingSetSourceFailures;
  bool _retainSourceOnFailure = false;

  @override
  PlayerBackend get backend => PlayerBackend.mdk;

  void armNextSetSourceFailure({
    bool retainSource = false,
    int times = 1,
  }) {
    _pendingSetSourceFailures = times;
    _retainSourceOnFailure = retainSource;
  }

  void emitStickySourceError() {
    final source = _currentState.source;
    if (source == null) {
      return;
    }
    _emit(
      _currentState.copyWith(
        status: PlaybackStatus.error,
        source: source,
        errorMessage: 'MDK texture initialization timed out after 3000ms',
      ),
    );
  }

  @override
  Future<void> setSource(PlaybackSource source) async {
    events.add('setSource');
    if (_pendingSetSourceFailures > 0) {
      _pendingSetSourceFailures -= 1;
      final retainSource = _retainSourceOnFailure;
      _retainSourceOnFailure = false;
      _emit(
        _currentState.copyWith(
          status: PlaybackStatus.error,
          source: retainSource ? source : null,
          errorMessage: 'MDK texture initialization timed out after 3000ms',
          clearSource: !retainSource,
        ),
      );
      return;
    }
    await super.setSource(source);
  }

  void handleBackendRefresh() {
    events.add('refreshBackend');
    _emit(
      _currentState.copyWith(
        status: PlaybackStatus.ready,
        clearSource: true,
        clearErrorMessage: true,
      ),
    );
  }
}

class _BlockingSetSourceMdkPlayer extends _FailOnceMdkPlayer {
  _BlockingSetSourceMdkPlayer() : super(failFirstSetSource: false);

  Completer<void>? _blockedSetSourceCompleter;

  void blockNextSetSource() {
    _blockedSetSourceCompleter = Completer<void>();
  }

  void completeBlockedSetSource() {
    final completer = _blockedSetSourceCompleter;
    if (completer == null || completer.isCompleted) {
      return;
    }
    completer.complete();
  }

  @override
  Future<void> setSource(PlaybackSource source) async {
    final completer = _blockedSetSourceCompleter;
    if (completer == null) {
      await super.setSource(source);
      return;
    }
    events.add('setSource');
    await completer.future;
    _blockedSetSourceCompleter = null;
    _emit(
      _currentState.copyWith(
        status: PlaybackStatus.ready,
        source: source,
        clearErrorMessage: true,
      ),
    );
  }
}

class _RefreshTrackingMdkPlayerRuntime extends PlayerRuntimeController {
  _RefreshTrackingMdkPlayerRuntime(this.player) : super(player);

  final _FailOnceMdkPlayer player;
  int refreshCount = 0;

  @override
  Future<void> refreshBackend() async {
    refreshCount += 1;
    player.handleBackendRefresh();
  }
}

class _ThrowingRefreshMdkPlayerRuntime extends PlayerRuntimeController {
  _ThrowingRefreshMdkPlayerRuntime(this.player) : super(player);

  final _FailOnceMdkPlayer player;
  int refreshCount = 0;

  @override
  Future<void> refreshBackend() async {
    refreshCount += 1;
    player.events.add('refreshBackend');
    throw StateError('refresh failed');
  }
}

class _DelayedRefreshMdkPlayerRuntime extends PlayerRuntimeController {
  _DelayedRefreshMdkPlayerRuntime(this.player) : super(player);

  final _FailOnceMdkPlayer player;
  final Completer<void> _refreshCompleter = Completer<void>();
  int refreshCount = 0;

  void completeRefresh() {
    if (_refreshCompleter.isCompleted) {
      return;
    }
    _refreshCompleter.complete();
  }

  @override
  Future<void> refreshBackend() async {
    refreshCount += 1;
    player.events.add('refreshBackend');
    await _refreshCompleter.future;
    player.handleBackendRefresh();
  }
}
