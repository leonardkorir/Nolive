import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_storage/live_storage.dart';
import 'package:nolive_app/src/features/library/application/load_follow_watchlist_use_case.dart';
import 'package:nolive_app/src/shared/domain/follow_watch_entry.dart';

void main() {
  test('prioritiseFollowRefreshIndexes keeps full set under threshold', () {
    final follows = [
      for (var i = 0; i < 10; i++)
        FollowRecord(
          providerId: ProviderId.bilibili,
          roomId: '$i',
          streamerName: 'u$i',
        ),
    ];
    final indexes = List<int>.generate(follows.length, (i) => i);
    final result = prioritiseFollowRefreshIndexes(
      follows: follows,
      candidateIndexes: indexes,
      cycle: 0,
      largeListThreshold: 100,
    );
    expect(result, indexes);
  });

  test('prioritiseFollowRefreshIndexes cycle0 returns top 20% only', () {
    final follows = [
      for (var i = 0; i < 100; i++)
        FollowRecord(
          providerId: ProviderId.bilibili,
          roomId: '$i',
          streamerName: 'u$i',
          watchDurationSec: i,
          lastLiveStatus: i > 80 ? 2 : 1,
        ),
    ];
    final indexes = List<int>.generate(follows.length, (i) => i);
    final top = prioritiseFollowRefreshIndexes(
      follows: follows,
      candidateIndexes: indexes,
      cycle: 0,
      largeListThreshold: 50,
    );
    expect(top.length, 20);
    final mid = prioritiseFollowRefreshIndexes(
      follows: follows,
      candidateIndexes: indexes,
      cycle: 1,
      largeListThreshold: 50,
    );
    expect(mid.length, greaterThan(top.length));
    expect(mid.length, lessThanOrEqualTo(100));
  });

  test('FollowWatchEntry uses lastLiveStatus snapshot when detail missing', () {
    final live = FollowWatchEntry(
      record: FollowRecord(
        providerId: ProviderId.douyu,
        roomId: '1',
        streamerName: 'A',
        lastLiveStatus: 2,
        lastCoverUrl: 'https://example.com/c.png',
      ),
    );
    final offline = FollowWatchEntry(
      record: FollowRecord(
        providerId: ProviderId.douyu,
        roomId: '2',
        streamerName: 'B',
        lastLiveStatus: 1,
      ),
    );
    expect(live.isLive, isTrue);
    expect(offline.isLive, isFalse);
  });

  test('sortFollowWatchEntries orders by watch duration and recency', () {
    final short = FollowWatchEntry(
      record: FollowRecord(
        providerId: ProviderId.bilibili,
        roomId: '1',
        streamerName: 'Short',
        watchDurationSec: 10,
        updatedAt: DateTime(2026, 1, 1),
      ),
    );
    final long = FollowWatchEntry(
      record: FollowRecord(
        providerId: ProviderId.bilibili,
        roomId: '2',
        streamerName: 'Long',
        watchDurationSec: 90,
        updatedAt: DateTime(2026, 1, 2),
      ),
    );
    final byDuration = sortFollowWatchEntries(
      [short, long],
      mode: FollowWatchSortMode.watchDuration,
    );
    expect(byDuration.first.record.roomId, '2');
    final byRecency = sortFollowWatchEntries(
      [short, long],
      mode: FollowWatchSortMode.recency,
    );
    expect(byRecency.first.record.roomId, '2');
  });
}
