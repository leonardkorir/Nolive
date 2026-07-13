import 'package:live_core/live_core.dart';

class HistoryRecord {
  const HistoryRecord({
    required this.providerId,
    required this.roomId,
    required this.title,
    required this.streamerName,
    required this.viewedAt,
    this.watchDurationSec = 0,
    this.syncDurationSec = 0,
    this.updatedAt,
  });

  final ProviderId providerId;
  final String roomId;
  final String title;
  final String streamerName;
  final DateTime viewedAt;

  /// Cumulative watch seconds stored as sync baseline.
  final int watchDurationSec;

  /// Local unsent watch-seconds increment since last merge.
  final int syncDurationSec;

  /// Last mutation time for LWW field picks (falls back to [viewedAt]).
  final DateTime? updatedAt;

  String get identityKey => '${providerId.value}_$roomId';

  DateTime get effectiveUpdatedAt => updatedAt ?? viewedAt;

  HistoryRecord copyWith({
    ProviderId? providerId,
    String? roomId,
    String? title,
    String? streamerName,
    DateTime? viewedAt,
    int? watchDurationSec,
    int? syncDurationSec,
    DateTime? updatedAt,
    bool clearUpdatedAt = false,
  }) {
    return HistoryRecord(
      providerId: providerId ?? this.providerId,
      roomId: roomId ?? this.roomId,
      title: title ?? this.title,
      streamerName: streamerName ?? this.streamerName,
      viewedAt: viewedAt ?? this.viewedAt,
      watchDurationSec: watchDurationSec ?? this.watchDurationSec,
      syncDurationSec: syncDurationSec ?? this.syncDurationSec,
      updatedAt: clearUpdatedAt ? null : (updatedAt ?? this.updatedAt),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is HistoryRecord &&
        other.providerId == providerId &&
        other.roomId == roomId &&
        other.title == title &&
        other.streamerName == streamerName &&
        other.viewedAt == viewedAt &&
        other.watchDurationSec == watchDurationSec &&
        other.syncDurationSec == syncDurationSec &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode {
    return Object.hash(
      providerId,
      roomId,
      title,
      streamerName,
      viewedAt,
      watchDurationSec,
      syncDurationSec,
      updatedAt,
    );
  }
}
