import 'package:live_core/live_core.dart';

class RoomDanmakuBatchResult {
  const RoomDanmakuBatchResult({
    required this.messages,
    required this.superChats,
    required this.hasMessageUpdate,
    required this.hasSuperChatUpdate,
  });

  final List<LiveMessage> messages;
  final List<LiveMessage> superChats;
  final bool hasMessageUpdate;
  final bool hasSuperChatUpdate;
}

RoomDanmakuBatchResult mergeRoomDanmakuBatch({
  required List<LiveMessage> messages,
  required List<LiveMessage> superChats,
  required Iterable<LiveMessage> incoming,
  int messageLimit = 64,
  int superChatLimit = 24,
}) {
  final incomingMessages = <LiveMessage>[];
  final incomingSuperChats = <LiveMessage>[];

  for (final item in incoming) {
    switch (item.type) {
      case LiveMessageType.superChat:
        incomingSuperChats.add(item);
      case LiveMessageType.online:
        break;
      case LiveMessageType.chat:
      case LiveMessageType.notice:
      case LiveMessageType.gift:
      case LiveMessageType.member:
        incomingMessages.add(item);
    }
  }

  final nextMessages = incomingMessages.isEmpty
      ? messages
      : _trimTail([...messages, ...incomingMessages], messageLimit);
  final nextSuperChats = incomingSuperChats.isEmpty
      ? superChats
      : _trimTail([...superChats, ...incomingSuperChats], superChatLimit);

  return RoomDanmakuBatchResult(
    messages: nextMessages,
    superChats: nextSuperChats,
    hasMessageUpdate: incomingMessages.isNotEmpty,
    hasSuperChatUpdate: incomingSuperChats.isNotEmpty,
  );
}

List<LiveMessage> _trimTail(List<LiveMessage> messages, int limit) {
  final overflow = messages.length - limit;
  if (overflow <= 0) {
    return List<LiveMessage>.unmodifiable(messages);
  }
  return List<LiveMessage>.unmodifiable(messages.sublist(overflow));
}
