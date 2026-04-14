import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:nolive_app/src/features/room/presentation/room_preview_page_chat_panels.dart';
import 'package:nolive_app/src/features/room/presentation/room_preview_page_section_widgets.dart';

void main() {
  testWidgets('room chat panel shows ancillary loading empty state',
      (tester) async {
    final messages = ValueNotifier<List<LiveMessage>>(const []);
    final scrollController = ScrollController();
    addTearDown(messages.dispose);
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoomChatPanel(
            messagesListenable: messages,
            ancillaryLoading: true,
            hasDanmakuSession: false,
            room: const LiveRoomDetail(
              providerId: 'bilibili',
              roomId: '1000',
              title: '测试直播间',
              streamerName: '测试主播',
              isLive: true,
            ),
            scrollController: scrollController,
            chatTextSize: 14,
            chatTextGap: 4,
            chatBubbleStyle: false,
            onRefreshRoom: () {},
          ),
        ),
      ),
    );

    expect(find.text('房间页已进入，正在补齐聊天数据'), findsOneWidget);
    expect(find.text('正在连接弹幕服务器'), findsOneWidget);
    expect(find.text('视频和关注状态会继续在后台加载'), findsOneWidget);
  });

  testWidgets('room chat panel shows chaturbate status card and refresh action',
      (tester) async {
    final messages = ValueNotifier<List<LiveMessage>>(const []);
    final scrollController = ScrollController();
    var refreshCount = 0;
    addTearDown(messages.dispose);
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoomChatPanel(
            messagesListenable: messages,
            ancillaryLoading: false,
            hasDanmakuSession: false,
            room: const LiveRoomDetail(
              providerId: 'chaturbate',
              roomId: 'cb-room',
              title: 'cb-title',
              streamerName: 'cb-streamer',
              isLive: true,
              metadata: <String, dynamic>{'roomStatus': 'private show'},
            ),
            scrollController: scrollController,
            chatTextSize: 14,
            chatTextGap: 4,
            chatBubbleStyle: false,
            onRefreshRoom: () {
              refreshCount += 1;
            },
          ),
        ),
      ),
    );

    expect(find.text('私密表演中'), findsOneWidget);
    expect(find.textContaining('Private Show'), findsOneWidget);
    await tester.tap(find.text('刷新房间状态'));
    expect(refreshCount, 1);
  });

  testWidgets('room chat panel sorts visible messages by timestamp',
      (tester) async {
    final messages = ValueNotifier<List<LiveMessage>>([
      LiveMessage(
        type: LiveMessageType.chat,
        content: 'third',
        userName: 'user-3',
        timestamp: DateTime(2026, 1, 1, 0, 0, 3),
      ),
      LiveMessage(
        type: LiveMessageType.chat,
        content: 'first',
        userName: 'user-1',
        timestamp: DateTime(2026, 1, 1, 0, 0, 1),
      ),
      LiveMessage(
        type: LiveMessageType.chat,
        content: 'second',
        userName: 'user-2',
        timestamp: DateTime(2026, 1, 1, 0, 0, 2),
      ),
    ]);
    final scrollController = ScrollController();
    addTearDown(messages.dispose);
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoomChatPanel(
            messagesListenable: messages,
            ancillaryLoading: false,
            hasDanmakuSession: true,
            room: const LiveRoomDetail(
              providerId: 'bilibili',
              roomId: '1000',
              title: '测试直播间',
              streamerName: '测试主播',
              isLive: true,
            ),
            scrollController: scrollController,
            chatTextSize: 14,
            chatTextGap: 4,
            chatBubbleStyle: false,
            onRefreshRoom: () {},
          ),
        ),
      ),
    );

    final tiles = tester
        .widgetList<RoomChatMessageTile>(find.byType(RoomChatMessageTile));
    expect(tiles.map((tile) => tile.message.content).toList(),
        ['first', 'second', 'third']);
  });

  testWidgets('room super chat panel shows plain empty state text',
      (tester) async {
    final messages = ValueNotifier<List<LiveMessage>>(const []);
    addTearDown(messages.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoomSuperChatPanel(
            messagesListenable: messages,
            hasDanmakuSession: false,
          ),
        ),
      ),
    );

    expect(find.text('当前没有 SC 会话。'), findsOneWidget);
  });

  testWidgets('room super chat panel caps output at 24 entries',
      (tester) async {
    final messages = ValueNotifier<List<LiveMessage>>([
      for (var index = 0; index < 30; index += 1)
        LiveMessage(
          type: LiveMessageType.superChat,
          content: 'sc-$index',
          userName: 'u-$index',
          timestamp: DateTime(2026, 1, 1, 0, 0, index),
        ),
    ]);
    addTearDown(messages.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RoomSuperChatPanel(
              messagesListenable: messages,
              hasDanmakuSession: true,
            ),
          ),
        ),
      ),
    );

    expect(find.byType(DanmakuFeedTile), findsNWidgets(24));
    expect(find.text('sc-0'), findsOneWidget);
    expect(find.text('sc-23'), findsOneWidget);
    expect(find.text('sc-24'), findsNothing);
  });
}
