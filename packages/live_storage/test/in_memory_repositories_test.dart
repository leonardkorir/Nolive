import 'package:live_storage/live_storage.dart';
import 'package:test/test.dart';

void main() {
  test('in-memory history keeps most recent records first', () async {
    final repository = InMemoryHistoryRepository();
    await repository.add(
      HistoryRecord(
        providerId: 'bilibili',
        roomId: '1',
        title: 'A',
        streamerName: '主播A',
        viewedAt: DateTime(2026, 3, 10, 10),
      ),
    );
    await repository.add(
      HistoryRecord(
        providerId: 'douyu',
        roomId: '2',
        title: 'B',
        streamerName: '主播B',
        viewedAt: DateTime(2026, 3, 10, 11),
      ),
    );

    final records = await repository.listRecent();
    expect(records.map((item) => item.roomId), ['2', '1']);
  });

  test('in-memory follow repository upserts removes and clears records',
      () async {
    final repository = InMemoryFollowRepository();
    await repository.upsert(
      const FollowRecord(
        providerId: 'huya',
        roomId: 'yy/123',
        streamerName: '主播C',
      ),
    );

    expect(await repository.exists('huya', 'yy/123'), isTrue);
    await repository.remove('huya', 'yy/123');
    expect(await repository.exists('huya', 'yy/123'), isFalse);

    await repository.upsert(
      const FollowRecord(
        providerId: 'bilibili',
        roomId: '100',
        streamerName: '主播D',
      ),
    );
    await repository.clear();
    expect(await repository.listAll(), isEmpty);
  });

  test('in-memory follow repository keeps order when updating existing record',
      () async {
    final repository = InMemoryFollowRepository();
    await repository.upsert(
      const FollowRecord(
        providerId: 'bilibili',
        roomId: '1',
        streamerName: '主播A',
      ),
    );
    await repository.upsert(
      const FollowRecord(
        providerId: 'douyu',
        roomId: '2',
        streamerName: '主播B',
      ),
    );
    await repository.upsert(
      const FollowRecord(
        providerId: 'bilibili',
        roomId: '1',
        streamerName: '主播A',
        streamerAvatarUrl: 'https://example.com/avatar-a.png',
      ),
    );

    final follows = await repository.listAll();
    expect(
      follows.map((item) => '${item.providerId}:${item.roomId}').toList(),
      ['douyu:2', 'bilibili:1'],
    );
    expect(follows.last.streamerAvatarUrl, 'https://example.com/avatar-a.png');
  });
}
