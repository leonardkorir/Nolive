import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:nolive_app/src/features/room/presentation/room_danmaku_batch.dart';

void main() {
  test('mergeRoomDanmakuBatch partitions and trims incoming messages', () {
    final currentMessages = List<LiveMessage>.generate(
      63,
      (index) => LiveMessage(
        type: LiveMessageType.chat,
        content: 'message-$index',
      ),
    );
    final currentSuperChats = List<LiveMessage>.generate(
      23,
      (index) => LiveMessage(
        type: LiveMessageType.superChat,
        content: 'super-$index',
      ),
    );

    final result = mergeRoomDanmakuBatch(
      messages: currentMessages,
      superChats: currentSuperChats,
      incoming: const [
        LiveMessage(type: LiveMessageType.online, content: '1000'),
        LiveMessage(type: LiveMessageType.chat, content: 'message-63'),
        LiveMessage(type: LiveMessageType.notice, content: 'notice-1'),
        LiveMessage(type: LiveMessageType.superChat, content: 'super-23'),
        LiveMessage(type: LiveMessageType.superChat, content: 'super-24'),
      ],
    );

    expect(result.hasMessageUpdate, isTrue);
    expect(result.hasSuperChatUpdate, isTrue);
    expect(result.messages, hasLength(64));
    expect(result.superChats, hasLength(24));
    expect(result.messages.first.content, 'message-1');
    expect(result.messages.last.content, 'notice-1');
    expect(result.superChats.first.content, 'super-1');
    expect(result.superChats.last.content, 'super-24');
  });

  test('mergeRoomDanmakuBatch keeps snapshots unchanged for ignored items', () {
    final currentMessages = const [
      LiveMessage(type: LiveMessageType.chat, content: 'message-1'),
    ];
    final currentSuperChats = const [
      LiveMessage(type: LiveMessageType.superChat, content: 'super-1'),
    ];

    final result = mergeRoomDanmakuBatch(
      messages: currentMessages,
      superChats: currentSuperChats,
      incoming: const [
        LiveMessage(type: LiveMessageType.online, content: '1000'),
      ],
    );

    expect(result.hasMessageUpdate, isFalse);
    expect(result.hasSuperChatUpdate, isFalse);
    expect(result.messages, same(currentMessages));
    expect(result.superChats, same(currentSuperChats));
  });
}
