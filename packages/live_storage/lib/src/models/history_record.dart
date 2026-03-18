class HistoryRecord {
  const HistoryRecord({
    required this.providerId,
    required this.roomId,
    required this.title,
    required this.streamerName,
    required this.viewedAt,
  });

  final String providerId;
  final String roomId;
  final String title;
  final String streamerName;
  final DateTime viewedAt;
}
