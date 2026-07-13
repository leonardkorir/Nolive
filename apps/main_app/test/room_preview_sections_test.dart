import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nolive_app/src/features/room/presentation/room_panel_controller.dart';
import 'package:nolive_app/src/features/room/presentation/room_preview_page_section_widgets.dart';
import 'package:nolive_app/src/features/room/presentation/room_preview_page_sections.dart';

void main() {
  testWidgets('loading shell shows provider and room context', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RoomLoadingRoomShell(
            data: RoomLoadingShellViewData(
              providerLabel: 'Bilibili',
              roomTitle: '房间号 1000',
              streamerName: '测试主播',
              avatarLabel: '测',
              posterUrl: 'https://example.com/poster.jpg',
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('room-loading-shell')), findsOneWidget);
    expect(find.text('正在加载画面'), findsOneWidget);
    expect(find.text('Bilibili · 房间号 1000'), findsOneWidget);
    expect(find.text('测试主播'), findsOneWidget);
  });

  testWidgets('loading shell normalizes malformed UTF-16 labels', (
    tester,
  ) async {
    const badText = '房间\uD800标题';

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RoomLoadingRoomShell(
            data: RoomLoadingShellViewData(
              providerLabel: '平\uD800台',
              roomTitle: badText,
              streamerName: '主\uD800播',
              avatarLabel: '\uD800',
              posterUrl: null,
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('正在加载画面'), findsOneWidget);
    expect(find.text('平台 · 房间标题'), findsOneWidget);
    expect(find.text('主播'), findsOneWidget);
  });

  testWidgets('loading shell can pre-mount embedded player view', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RoomLoadingRoomShell(
            data: RoomLoadingShellViewData(
              providerLabel: 'Chaturbate',
              roomTitle: '房间号 2000',
              streamerName: '测试主播',
              avatarLabel: '测',
              posterUrl: null,
            ),
            embeddedPlayerView: ColoredBox(
              key: Key('loading-embedded-player-view'),
              color: Colors.black,
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const Key('loading-embedded-player-view')),
      findsOneWidget,
    );
  });

  testWidgets(
    'immersive loading shell hides landscape side panel chrome',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RoomLoadingRoomShell(
              immersive: true,
              data: RoomLoadingShellViewData(
                providerLabel: 'Bilibili',
                roomTitle: '房间号 3000',
                streamerName: '测试主播',
                avatarLabel: '测',
                posterUrl: null,
              ),
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('room-loading-shell-immersive')), findsOneWidget);
      expect(find.byKey(const Key('room-loading-shell')), findsOneWidget);
      expect(find.byKey(const Key('room-panel-tab-chat')), findsNothing);
      expect(find.text('房间已经进入，后台继续加载播放和聊天数据'), findsNothing);
    },
  );

  testWidgets(
    'room preview sections renders surface, pager and bottom actions',
    (tester) async {
      final pageController = PageController();
      addTearDown(pageController.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 900,
              child: RoomPreviewSections(
                data: const RoomSectionsViewData(
                  providerLabel: 'Bilibili',
                  streamerName: '测试主播',
                  streamerAvatarUrl: null,
                  roomLive: true,
                  viewerLabel: '1.2万',
                  isFollowed: true,
                  statusPresentation: RoomChaturbateStatusPresentation(
                    label: '私密表演中',
                    description: '主播当前正在 Private Show 中，暂时没有公开播放流。',
                  ),
                  qualityBadgeLabel: '原画 · 实际蓝光',
                ),
                pageController: pageController,
                selectedPanel: RoomPanel.chat,
                onSelectPanel: (_) {},
                onPageChanged: (_) {},
                chatPanel: const ColoredBox(
                  key: Key('chat-panel'),
                  color: Colors.red,
                ),
                superChatPanel: const ColoredBox(
                  key: Key('super-chat-panel'),
                  color: Colors.green,
                ),
                followPanel: const ColoredBox(
                  key: Key('follow-panel'),
                  color: Colors.blue,
                ),
                controlsPanel: const ColoredBox(
                  key: Key('controls-panel'),
                  color: Colors.orange,
                ),
                playerSurface: const SizedBox(
                  key: Key('player-surface'),
                  height: 160,
                  child: ColoredBox(color: Colors.black),
                ),
                onToggleFollow: () {},
                onRefresh: () {},
                onShareRoom: () {},
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      expect(find.byKey(const Key('player-surface')), findsOneWidget);
      expect(find.byKey(const Key('room-panel-page-view')), findsOneWidget);
      expect(
        find.byKey(const Key('room-follow-toggle-button')),
        findsOneWidget,
      );
      expect(find.text('原画 · 实际蓝光'), findsOneWidget);
      expect(find.text('私密表演中'), findsOneWidget);
    },
  );

  testWidgets('room panel pager advances later tabs with one slow swipe', (
    tester,
  ) async {
    final pageController = PageController(
      initialPage: RoomPanel.superChat.index,
    );
    var selectedPanel = RoomPanel.superChat;
    addTearDown(pageController.dispose);

    tester.view.physicalSize = const Size(390, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            return Scaffold(
              body: SizedBox(
                height: 720,
                child: RoomPreviewSections(
                  data: const RoomSectionsViewData(
                    providerLabel: 'Bilibili',
                    streamerName: '测试主播',
                    streamerAvatarUrl: null,
                    roomLive: true,
                    viewerLabel: '1.2万',
                    isFollowed: true,
                  ),
                  pageController: pageController,
                  selectedPanel: selectedPanel,
                  onSelectPanel: (panel) {
                    setState(() {
                      selectedPanel = panel;
                    });
                  },
                  onPageChanged: (index) {
                    setState(() {
                      selectedPanel = RoomPanel.values[index];
                    });
                  },
                  chatPanel: _tallPanel('chat'),
                  superChatPanel: _tallPanel('super-chat'),
                  followPanel: _tallPanel('follow'),
                  controlsPanel: _tallPanel('settings'),
                  playerSurface: const SizedBox(
                    height: 160,
                    child: ColoredBox(color: Colors.black),
                  ),
                  onToggleFollow: () {},
                  onRefresh: () {},
                  onShareRoom: () {},
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(selectedPanel, RoomPanel.superChat);

    await tester.timedDrag(
      find.byKey(const Key('room-panel-page-view')),
      const Offset(-80, 24),
      const Duration(milliseconds: 1600),
    );
    await tester.pumpAndSettle();

    expect(
      selectedPanel,
      RoomPanel.follow,
      reason:
          'page=${pageController.page} size=${tester.getSize(find.byKey(const Key("room-panel-page-view")))}',
    );
    expect(pageController.page, closeTo(RoomPanel.follow.index, 0.01));

    await tester.timedDrag(
      find.byKey(const Key('room-panel-page-view')),
      const Offset(-80, 24),
      const Duration(milliseconds: 1600),
    );
    await tester.pumpAndSettle();

    expect(selectedPanel, RoomPanel.settings);
    expect(pageController.page, closeTo(RoomPanel.settings.index, 0.01));
  });

  testWidgets(
    'room preview sections switches to compact list layout on short height',
    (tester) async {
      final pageController = PageController();
      addTearDown(pageController.dispose);
      tester.view.physicalSize = const Size(390, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 620,
              child: RoomPreviewSections(
                data: const RoomSectionsViewData(
                  providerLabel: 'Bilibili',
                  streamerName: '测试主播',
                  streamerAvatarUrl: null,
                  roomLive: true,
                  viewerLabel: '1.2万',
                  isFollowed: false,
                ),
                pageController: pageController,
                selectedPanel: RoomPanel.chat,
                onSelectPanel: (_) {},
                onPageChanged: (_) {},
                chatPanel: const SizedBox.shrink(),
                superChatPanel: const SizedBox.shrink(),
                followPanel: const SizedBox.shrink(),
                controlsPanel: const SizedBox.shrink(),
                playerSurface: const SizedBox(
                  key: Key('compact-player-surface'),
                  height: 160,
                  child: ColoredBox(color: Colors.black),
                ),
                onToggleFollow: () {},
                onRefresh: () {},
                onShareRoom: () {},
              ),
            ),
          ),
        ),
      );

      expect(find.byType(ListView), findsOneWidget);
      expect(find.byKey(const Key('compact-player-surface')), findsOneWidget);
    },
  );
}

Widget _tallPanel(String label) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: List<Widget>.generate(
      12,
      (index) => SizedBox(height: 48, child: Text('$label-$index')),
    ),
  );
}
