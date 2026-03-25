import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:live_storage/live_storage.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';
import 'package:nolive_app/src/app/routing/app_routes.dart';
import 'package:nolive_app/src/features/library/application/load_follow_watchlist_use_case.dart';
import 'package:nolive_app/src/features/room/presentation/room_preview_page.dart';
import 'package:nolive_app/src/shared/presentation/widgets/app_surface_card.dart';

void main() {
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
          bootstrap: bootstrap,
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
    expect(find.text('截图'), findsOneWidget);
    expect(find.text('播放信息'), findsOneWidget);
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
  });

  testWidgets('room preview mounts player view before initial source binding', (
    tester,
  ) async {
    final base = createAppBootstrap(mode: AppRuntimeMode.preview);
    final player = _RecordingPlayer();
    addTearDown(player.dispose);
    final bootstrap = _copyBootstrapWithPlayer(base, player);

    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: RoomPreviewPage(
          bootstrap: bootstrap,
          providerId: ProviderId.bilibili,
          roomId: '66666',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
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
          bootstrap: bootstrap,
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
          bootstrap: bootstrap,
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
          bootstrap: bootstrap,
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
              bootstrap: bootstrap,
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
          bootstrap: bootstrap,
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
          bootstrap: bootstrap,
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
          bootstrap: bootstrap,
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
                        bootstrap: bootstrap,
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

    expect(bootstrap.player.currentState.status, PlaybackStatus.playing);

    await tester.tap(find.byKey(const Key('room-leave-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(bootstrap.player.currentState.status, PlaybackStatus.ready);
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
          bootstrap: bootstrap,
          providerId: ProviderId.chaturbate,
          roomId: 'consuelabrasington',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('私密表演中'), findsWidgets);
    expect(find.textContaining('Private Show'), findsOneWidget);
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
          bootstrap: bootstrap,
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
          bootstrap: bootstrap,
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
          bootstrap: bootstrap,
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

  final DanmakuSession Function() createSession;

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
    return createSession();
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

AppBootstrap _copyBootstrapWithPlayer(
  AppBootstrap base,
  BasePlayer player,
) {
  return AppBootstrap(
    mode: base.mode,
    themeMode: base.themeMode,
    layoutPreferences: base.layoutPreferences,
    providerCatalogRevision: base.providerCatalogRevision,
    followDataRevision: base.followDataRevision,
    followWatchlistSnapshot: base.followWatchlistSnapshot,
    providerRegistry: base.providerRegistry,
    player: player,
    settingsRepository: base.settingsRepository,
    historyRepository: base.historyRepository,
    followRepository: base.followRepository,
    tagRepository: base.tagRepository,
    listAvailableProviders: base.listAvailableProviders,
    loadLayoutPreferences: base.loadLayoutPreferences,
    updateLayoutPreferences: base.updateLayoutPreferences,
    loadReferenceRoomPreview: base.loadReferenceRoomPreview,
    loadHomeDashboard: base.loadHomeDashboard,
    loadProviderHighlights: base.loadProviderHighlights,
    loadProviderRecommendRooms: base.loadProviderRecommendRooms,
    loadProviderCategories: base.loadProviderCategories,
    loadCategoryRooms: base.loadCategoryRooms,
    loadRoom: base.loadRoom,
    openRoomDanmaku: base.openRoomDanmaku,
    resolvePlaySource: base.resolvePlaySource,
    searchProviderRooms: base.searchProviderRooms,
    listLibrarySnapshot: base.listLibrarySnapshot,
    loadLibraryDashboard: base.loadLibraryDashboard,
    loadFollowWatchlist: base.loadFollowWatchlist,
    loadFollowPreferences: base.loadFollowPreferences,
    updateFollowPreferences: base.updateFollowPreferences,
    loadHistoryPreferences: base.loadHistoryPreferences,
    updateHistoryPreferences: base.updateHistoryPreferences,
    exportFollowListJson: base.exportFollowListJson,
    importFollowListJson: base.importFollowListJson,
    toggleFollowRoom: base.toggleFollowRoom,
    isFollowedRoom: base.isFollowedRoom,
    listTags: base.listTags,
    createTag: base.createTag,
    removeTag: base.removeTag,
    clearTags: base.clearTags,
    updateFollowTags: base.updateFollowTags,
    removeFollowRoom: base.removeFollowRoom,
    removeHistoryRecord: base.removeHistoryRecord,
    clearHistory: base.clearHistory,
    loadSyncSnapshot: base.loadSyncSnapshot,
    loadSyncPreferences: base.loadSyncPreferences,
    updateSyncPreferences: base.updateSyncPreferences,
    verifyWebDavConnection: base.verifyWebDavConnection,
    uploadWebDavSnapshot: base.uploadWebDavSnapshot,
    restoreWebDavSnapshot: base.restoreWebDavSnapshot,
    pushLocalSyncSnapshot: base.pushLocalSyncSnapshot,
    loadProviderAccountSettings: base.loadProviderAccountSettings,
    updateProviderAccountSettings: base.updateProviderAccountSettings,
    loadProviderAccountDashboard: base.loadProviderAccountDashboard,
    createBilibiliQrLoginSession: base.createBilibiliQrLoginSession,
    pollBilibiliQrLoginSession: base.pollBilibiliQrLoginSession,
    clearProviderAccount: base.clearProviderAccount,
    localDiscoveryService: base.localDiscoveryService,
    localSyncServer: base.localSyncServer,
    localSyncClient: base.localSyncClient,
    exportLegacyConfigJson: base.exportLegacyConfigJson,
    exportSyncSnapshotJson: base.exportSyncSnapshotJson,
    importSyncSnapshotJson: base.importSyncSnapshotJson,
    resetAppData: base.resetAppData,
    updateThemeMode: base.updateThemeMode,
    loadBlockedKeywords: base.loadBlockedKeywords,
    addBlockedKeyword: base.addBlockedKeyword,
    removeBlockedKeyword: base.removeBlockedKeyword,
    loadDanmakuPreferences: base.loadDanmakuPreferences,
    updateDanmakuPreferences: base.updateDanmakuPreferences,
    clearFollows: base.clearFollows,
    loadRoomUiPreferences: base.loadRoomUiPreferences,
    updateRoomUiPreferences: base.updateRoomUiPreferences,
    loadPlayerPreferences: base.loadPlayerPreferences,
    updatePlayerPreferences: base.updatePlayerPreferences,
    parseRoomInput: base.parseRoomInput,
    inspectParsedRoom: base.inspectParsedRoom,
  );
}

class _RecordingPlayer implements BasePlayer {
  final List<String> events = <String>[];
  final StreamController<PlayerState> _states =
      StreamController<PlayerState>.broadcast();

  PlayerState _currentState = const PlayerState(backend: PlayerBackend.mpv);

  @override
  PlayerBackend get backend => PlayerBackend.mpv;

  @override
  Stream<PlayerState> get states => _states.stream;

  @override
  PlayerState get currentState => _currentState;

  @override
  bool get supportsEmbeddedView => true;

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
  }

  void _emit(PlayerState next) {
    _currentState = next.copyWith(backend: backend);
    if (!_states.isClosed) {
      _states.add(_currentState);
    }
  }
}
