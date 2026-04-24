import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:nolive_app/src/features/room/presentation/room_preview_page_chat_panels.dart';
import 'package:nolive_app/src/features/room/presentation/room_preview_page_section_widgets.dart';

class _RoomChatPanelStatus extends ChangeNotifier {
  bool ancillaryLoading;
  bool hasDanmakuSession;

  _RoomChatPanelStatus({
    required this.ancillaryLoading,
    required this.hasDanmakuSession,
  });

  void update({
    bool? ancillaryLoading,
    bool? hasDanmakuSession,
  }) {
    this.ancillaryLoading = ancillaryLoading ?? this.ancillaryLoading;
    this.hasDanmakuSession = hasDanmakuSession ?? this.hasDanmakuSession;
    notifyListeners();
  }
}

void main() {
  testWidgets('room chat panel shows ancillary loading empty state',
      (tester) async {
    final messages = ValueNotifier<List<LiveMessage>>(const []);
    final status = _RoomChatPanelStatus(
      ancillaryLoading: true,
      hasDanmakuSession: false,
    );
    final scrollController = ScrollController();
    addTearDown(messages.dispose);
    addTearDown(status.dispose);
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoomChatPanel(
            messagesListenable: messages,
            statusListenable: status,
            resolveAncillaryLoading: () => status.ancillaryLoading,
            resolveHasDanmakuSession: () => status.hasDanmakuSession,
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
    final status = _RoomChatPanelStatus(
      ancillaryLoading: false,
      hasDanmakuSession: false,
    );
    final scrollController = ScrollController();
    var refreshCount = 0;
    addTearDown(messages.dispose);
    addTearDown(status.dispose);
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoomChatPanel(
            messagesListenable: messages,
            statusListenable: status,
            resolveAncillaryLoading: () => status.ancillaryLoading,
            resolveHasDanmakuSession: () => status.hasDanmakuSession,
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
    final status = _RoomChatPanelStatus(
      ancillaryLoading: false,
      hasDanmakuSession: true,
    );
    final scrollController = ScrollController();
    addTearDown(messages.dispose);
    addTearDown(status.dispose);
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoomChatPanel(
            messagesListenable: messages,
            statusListenable: status,
            resolveAncillaryLoading: () => status.ancillaryLoading,
            resolveHasDanmakuSession: () => status.hasDanmakuSession,
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

  testWidgets('room chat panel normalizes malformed UTF-16 message text',
      (tester) async {
    final messages = ValueNotifier<List<LiveMessage>>([
      LiveMessage(
        type: LiveMessageType.chat,
        content: '内\uD800容',
        userName: '用\uD800户',
        timestamp: DateTime(2026, 1, 1, 0, 0, 1),
      ),
    ]);
    final status = _RoomChatPanelStatus(
      ancillaryLoading: false,
      hasDanmakuSession: true,
    );
    final scrollController = ScrollController();
    addTearDown(messages.dispose);
    addTearDown(status.dispose);
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoomChatPanel(
            messagesListenable: messages,
            statusListenable: status,
            resolveAncillaryLoading: () => status.ancillaryLoading,
            resolveHasDanmakuSession: () => status.hasDanmakuSession,
            room: const LiveRoomDetail(
              providerId: 'douyin',
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

    expect(tester.takeException(), isNull);
    expect(find.textContaining('用户：'), findsOneWidget);
    expect(find.textContaining('内容'), findsOneWidget);
  });

  testWidgets(
      'room chat panel exits loading copy once danmaku session is ready even without messages',
      (tester) async {
    final messages = ValueNotifier<List<LiveMessage>>(const []);
    final status = _RoomChatPanelStatus(
      ancillaryLoading: true,
      hasDanmakuSession: false,
    );
    final scrollController = ScrollController();
    addTearDown(messages.dispose);
    addTearDown(status.dispose);
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoomChatPanel(
            messagesListenable: messages,
            statusListenable: status,
            resolveAncillaryLoading: () => status.ancillaryLoading,
            resolveHasDanmakuSession: () => status.hasDanmakuSession,
            room: const LiveRoomDetail(
              providerId: 'douyu',
              roomId: '2140934',
              title: '单机王中王',
              streamerName: '老皮历险记',
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

    status.update(
      ancillaryLoading: true,
      hasDanmakuSession: true,
    );
    await tester.pump();

    expect(find.text('房间页已进入，正在补齐聊天数据'), findsNothing);
    expect(find.text('当前还没有聊天消息'), findsOneWidget);
    expect(find.text('弹幕连接已建立，等待新消息'), findsOneWidget);
    expect(find.text('新消息到达后会在这里继续滚动'), findsOneWidget);
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
