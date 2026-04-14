import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:nolive_app/src/features/room/presentation/room_preview_page_fullscreen.dart';
import 'package:nolive_app/src/features/room/presentation/room_preview_page_player_surface.dart';
import 'package:nolive_app/src/features/settings/application/manage_danmaku_preferences_use_case.dart';

void main() {
  void configureTestViewport(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  RoomPlayerSurfaceViewData buildPlayerSurfaceViewData() {
    return const RoomPlayerSurfaceViewData(
      room: LiveRoomDetail(
        providerId: 'bilibili',
        roomId: '1000',
        title: '测试直播间',
        streamerName: '测试主播',
        coverUrl: 'https://example.com/poster.jpg',
        isLive: true,
      ),
      hasPlayback: true,
      embedPlayer: true,
      fullscreen: true,
      suspendEmbeddedPlayer: false,
      supportsEmbeddedView: false,
      showDanmakuOverlay: true,
      showPlayerSuperChat: true,
      showInlinePlayerChrome: false,
      playerBindingInFlight: false,
      backendLabel: 'MDK',
      liveDurationLabel: '00:10:00',
      unavailableReason: '当前房间暂时没有公开播放流，请稍后刷新重试。',
    );
  }

  RoomFullscreenOverlayViewData buildViewData({
    bool showDanmakuOverlay = true,
  }) {
    return RoomFullscreenOverlayViewData(
      playerSurfaceData: buildPlayerSurfaceViewData(),
      danmakuPreferences: DanmakuPreferences.defaults.copyWith(strokeWidth: 0),
      title: '测试直播间 - 测试主播',
      liveDuration: '00:10:00',
      qualityLabel: '蓝光',
      lineLabel: '线路 1',
      showChrome: true,
      showLockButton: true,
      lockControls: false,
      gestureTipText: null,
      pipSupported: true,
      supportsDesktopMiniWindow: true,
      desktopMiniWindowActive: false,
      supportsPlayerCapture: true,
      showDanmakuOverlay: showDanmakuOverlay,
    );
  }

  LiveMessage buildMessage(
    LiveMessageType type,
    String content, {
    required DateTime timestamp,
  }) {
    return LiveMessage(
      type: type,
      content: content,
      timestamp: timestamp,
    );
  }

  testWidgets('fullscreen overlay section renders follow drawer and overlays',
      (tester) async {
    configureTestViewport(tester, const Size(1080, 1920));
    final messages = ValueNotifier<List<LiveMessage>>(
      [
        buildMessage(
          LiveMessageType.chat,
          'fullscreen-bubble',
          timestamp: DateTime(2026, 1, 1, 0, 0, 1),
        ),
      ],
    );
    final playerSuperChats = ValueNotifier<List<LiveMessage>>(
      [
        buildMessage(
          LiveMessageType.superChat,
          'super-chat',
          timestamp: DateTime(2026, 1, 1, 0, 0, 2),
        ),
      ],
    );
    addTearDown(messages.dispose);
    addTearDown(playerSuperChats.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoomFullscreenOverlaySection(
            data: buildViewData(),
            messagesListenable: messages,
            playerSuperChatMessagesListenable: playerSuperChats,
            followDrawer: const ColoredBox(
              key: Key('follow-drawer'),
              color: Colors.transparent,
            ),
            buildEmbeddedPlayerView: (_) => const SizedBox.shrink(),
            onToggleChrome: () {},
            onOpenFollowDrawer: () {},
            onToggleFullscreen: () {},
            onVerticalDragStart: (_) {},
            onVerticalDragUpdate: (_) {},
            onVerticalDragEnd: (_) {},
            onExitFullscreen: () {},
            onEnterPictureInPicture: () {},
            onToggleDesktopMiniWindow: () {},
            onCapture: () {},
            onShowDebug: () {},
            onShowMore: () {},
            onToggleFullscreenLock: () {},
            onRefresh: () {},
            onToggleDanmakuOverlay: () {},
            onOpenDanmakuSettings: () {},
            onShowQuality: () {},
            onShowLine: () {},
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('room-fullscreen-overlay')), findsOneWidget);
    expect(find.byKey(const Key('follow-drawer')), findsOneWidget);
    expect(find.byKey(const Key('room-danmaku-overlay')), findsOneWidget);
    expect(find.byKey(const Key('room-player-super-chat-overlay')),
        findsOneWidget);
  });

  testWidgets('fullscreen overlay section forwards chrome actions',
      (tester) async {
    configureTestViewport(tester, const Size(1080, 1920));
    final messages = ValueNotifier<List<LiveMessage>>(const <LiveMessage>[]);
    final playerSuperChats =
        ValueNotifier<List<LiveMessage>>(const <LiveMessage>[]);
    addTearDown(messages.dispose);
    addTearDown(playerSuperChats.dispose);

    var exitTapped = 0;
    var refreshTapped = 0;
    var toggleDanmakuTapped = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoomFullscreenOverlaySection(
            data: buildViewData(showDanmakuOverlay: false),
            messagesListenable: messages,
            playerSuperChatMessagesListenable: playerSuperChats,
            followDrawer: const SizedBox.shrink(),
            buildEmbeddedPlayerView: (_) => const SizedBox.shrink(),
            onToggleChrome: () {},
            onOpenFollowDrawer: () {},
            onToggleFullscreen: () {},
            onVerticalDragStart: (_) {},
            onVerticalDragUpdate: (_) {},
            onVerticalDragEnd: (_) {},
            onExitFullscreen: () {
              exitTapped += 1;
            },
            onEnterPictureInPicture: () {},
            onToggleDesktopMiniWindow: () {},
            onCapture: () {},
            onShowDebug: () {},
            onShowMore: () {},
            onToggleFullscreenLock: () {},
            onRefresh: () {
              refreshTapped += 1;
            },
            onToggleDanmakuOverlay: () {
              toggleDanmakuTapped += 1;
            },
            onOpenDanmakuSettings: () {},
            onShowQuality: () {},
            onShowLine: () {},
          ),
        ),
      ),
    );

    tester
        .widget<IconButton>(
          find.descendant(
            of: find.byKey(const Key('room-exit-fullscreen-button')),
            matching: find.byType(IconButton),
          ),
        )
        .onPressed!();
    tester
        .widget<IconButton>(
          find.descendant(
            of: find.byKey(const Key('room-fullscreen-refresh-button')),
            matching: find.byType(IconButton),
          ),
        )
        .onPressed!();
    tester
        .widget<IconButton>(
          find.descendant(
            of: find.byKey(const Key('room-fullscreen-danmaku-toggle-button')),
            matching: find.byType(IconButton),
          ),
        )
        .onPressed!();

    expect(exitTapped, 1);
    expect(refreshTapped, 1);
    expect(toggleDanmakuTapped, 1);
  });

  testWidgets(
      'fullscreen overlay section normalizes danmaku visibility from outer view data',
      (tester) async {
    configureTestViewport(tester, const Size(1080, 1920));
    final messages = ValueNotifier<List<LiveMessage>>(
      [
        buildMessage(
          LiveMessageType.chat,
          'should-not-render',
          timestamp: DateTime(2026, 1, 1, 0, 0, 1),
        ),
      ],
    );
    final playerSuperChats =
        ValueNotifier<List<LiveMessage>>(const <LiveMessage>[]);
    addTearDown(messages.dispose);
    addTearDown(playerSuperChats.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoomFullscreenOverlaySection(
            data: buildViewData(showDanmakuOverlay: false).copyWith(
              playerSurfaceData: buildPlayerSurfaceViewData(),
            ),
            messagesListenable: messages,
            playerSuperChatMessagesListenable: playerSuperChats,
            followDrawer: const SizedBox.shrink(),
            buildEmbeddedPlayerView: (_) => const SizedBox.shrink(),
            onToggleChrome: () {},
            onOpenFollowDrawer: () {},
            onToggleFullscreen: () {},
            onVerticalDragStart: (_) {},
            onVerticalDragUpdate: (_) {},
            onVerticalDragEnd: (_) {},
            onExitFullscreen: () {},
            onEnterPictureInPicture: () {},
            onToggleDesktopMiniWindow: () {},
            onCapture: () {},
            onShowDebug: () {},
            onShowMore: () {},
            onToggleFullscreenLock: () {},
            onRefresh: () {},
            onToggleDanmakuOverlay: () {},
            onOpenDanmakuSettings: () {},
            onShowQuality: () {},
            onShowLine: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('room-danmaku-overlay')), findsNothing);
  });
}
