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
    expect(find.text('正在进入 Bilibili 房间'), findsOneWidget);
    expect(find.text('房间号 1000'), findsOneWidget);
    expect(find.text('测试主播'), findsOneWidget);
  });

  testWidgets('room preview sections renders surface, pager and bottom actions',
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
                child: ColoredBox(
                  color: Colors.black,
                ),
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
    expect(find.byKey(const Key('room-follow-toggle-button')), findsOneWidget);
    expect(find.text('原画 · 实际蓝光'), findsOneWidget);
    expect(find.text('私密表演中'), findsOneWidget);
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
                child: ColoredBox(
                  color: Colors.black,
                ),
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
  });
}
