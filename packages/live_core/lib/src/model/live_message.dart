enum LiveMessageType {
  chat,
  notice,
  gift,
  member,
  superChat,
  online,
}

class LiveMessage {
  const LiveMessage({
    required this.type,
    required this.content,
    this.userName,
    this.timestamp,
    this.payload,
  });

  final LiveMessageType type;
  final String content;
  final String? userName;
  final DateTime? timestamp;
  final Object? payload;
}
