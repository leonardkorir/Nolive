import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_providers/live_providers.dart';
import 'package:live_storage/live_storage.dart';
import 'package:nolive_app/src/features/library/application/load_follow_watchlist_use_case.dart';

const _kTestDescriptor = ProviderDescriptor(
  id: ProviderId.bilibili,
  displayName: '测试平台',
  capabilities: {ProviderCapability.roomDetail},
  supportedPlatforms: {ProviderPlatform.android},
  maturity: ProviderMaturity.ready,
);

class _FakeDetailProvider extends LiveProvider implements SupportsRoomDetail {
  _FakeDetailProvider(this._loader, {ProviderDescriptor? descriptor})
      : _descriptor = descriptor ?? _kTestDescriptor;

  final Future<LiveRoomDetail> Function(String roomId) _loader;
  final ProviderDescriptor _descriptor;

  @override
  ProviderDescriptor get descriptor => _descriptor;

  @override
  Future<LiveRoomDetail> fetchRoomDetail(String roomId) => _loader(roomId);
}

void main() {
  test('load follow watchlist keeps slow providers from blocking forever',
      () async {
    final followRepository = InMemoryFollowRepository();
    await followRepository.upsert(
      const FollowRecord(
        providerId: 'bilibili',
        roomId: '6',
        streamerName: '本地主播',
        lastTitle: '本地标题',
        lastAreaName: '本地分区',
        lastCoverUrl: 'https://example.com/local-cover.png',
        lastKeyframeUrl: 'https://example.com/local-keyframe.png',
      ),
    );

    final registry = ProviderRegistry()
      ..register(
        ProviderRegistration(
          descriptor: _kTestDescriptor,
          builder: () => _FakeDetailProvider(
            (roomId) => Future<LiveRoomDetail>.delayed(
              const Duration(milliseconds: 30),
              () => LiveRoomDetail(
                providerId: 'bilibili',
                roomId: roomId,
                title: '远程房间',
                streamerName: '远程主播',
              ),
            ),
          ),
        ),
      );

    final watchlist = await LoadFollowWatchlistUseCase(
      followRepository: followRepository,
      registry: registry,
      detailTimeout: const Duration(milliseconds: 1),
      maxConcurrent: 1,
    ).call();

    expect(watchlist.entries, hasLength(1));
    expect(watchlist.entries.single.error, isA<TimeoutException>());
    expect(watchlist.entries.single.detail, isNull);
    expect(watchlist.entries.single.hasError, isTrue);
    expect(watchlist.entries.single.isUnavailable, isTrue);
    expect(watchlist.entries.single.isOffline, isFalse);
    expect(watchlist.entries.single.record.streamerName, '本地主播');
    expect(watchlist.entries.single.title, '本地标题');
    expect(watchlist.entries.single.displayAreaName, '本地分区');
    expect(
      watchlist.entries.single.displayCoverUrl,
      'https://example.com/local-cover.png',
    );
    expect(
      watchlist.entries.single.displayKeyframeUrl,
      'https://example.com/local-keyframe.png',
    );
    expect(watchlist.offlineCount, 0);
  });

  test('load follow watchlist maps resolved room detail into entries',
      () async {
    final followRepository = InMemoryFollowRepository();
    await followRepository.upsert(
      const FollowRecord(
        providerId: 'bilibili',
        roomId: '7',
        streamerName: '本地主播',
      ),
    );

    final registry = ProviderRegistry()
      ..register(
        ProviderRegistration(
          descriptor: _kTestDescriptor,
          builder: () => _FakeDetailProvider(
            (roomId) async => LiveRoomDetail(
              providerId: 'bilibili',
              roomId: roomId,
              title: '远程房间',
              streamerName: '远程主播',
              areaName: '远程分区',
              coverUrl: 'https://example.com/remote-cover.png',
              keyframeUrl: 'https://example.com/remote-keyframe.png',
              streamerAvatarUrl: 'https://example.com/remote-avatar.png',
              isLive: true,
            ),
          ),
        ),
      );

    final watchlist = await LoadFollowWatchlistUseCase(
      followRepository: followRepository,
      registry: registry,
    ).call();

    expect(watchlist.entries, hasLength(1));
    expect(watchlist.entries.single.error, isNull);
    expect(watchlist.entries.single.detail?.roomId, '7');
    expect(watchlist.entries.single.displayStreamerName, '远程主播');
    expect(
      watchlist.entries.single.displayStreamerAvatarUrl,
      'https://example.com/remote-avatar.png',
    );
    expect(
      (await followRepository.listAll()).single.streamerAvatarUrl,
      'https://example.com/remote-avatar.png',
    );
    expect((await followRepository.listAll()).single.lastTitle, '远程房间');
    expect((await followRepository.listAll()).single.lastAreaName, '远程分区');
    expect(
      (await followRepository.listAll()).single.lastCoverUrl,
      'https://example.com/remote-cover.png',
    );
    expect(
      (await followRepository.listAll()).single.lastKeyframeUrl,
      'https://example.com/remote-keyframe.png',
    );
    expect(watchlist.liveCount, 1);
  });

  test('load follow watchlist uses injected room detail override first',
      () async {
    final followRepository = InMemoryFollowRepository();
    await followRepository.upsert(
      const FollowRecord(
        providerId: 'chaturbate',
        roomId: 'milabunny_',
        streamerName: '本地主播',
      ),
    );

    var fetchCalls = 0;
    final registry = ProviderRegistry()
      ..register(
        ProviderRegistration(
          descriptor: const ProviderDescriptor(
            id: ProviderId.chaturbate,
            displayName: 'Chaturbate',
            capabilities: {ProviderCapability.roomDetail},
            supportedPlatforms: {ProviderPlatform.android},
            maturity: ProviderMaturity.inMigration,
          ),
          builder: () => _FakeDetailProvider(
            (roomId) {
              fetchCalls += 1;
              throw StateError('provider fetchRoomDetail should not be called');
            },
            descriptor: const ProviderDescriptor(
              id: ProviderId.chaturbate,
              displayName: 'Chaturbate',
              capabilities: {ProviderCapability.roomDetail},
              supportedPlatforms: {ProviderPlatform.android},
              maturity: ProviderMaturity.inMigration,
            ),
          ),
        ),
      );

    final watchlist = await LoadFollowWatchlistUseCase(
      followRepository: followRepository,
      registry: registry,
      loadRoomDetailOverride: ({
        required providerId,
        required roomId,
      }) async {
        if (providerId != ProviderId.chaturbate) {
          return null;
        }
        return LiveRoomDetail(
          providerId: providerId.value,
          roomId: roomId,
          title: 'override room',
          streamerName: roomId,
          isLive: true,
        );
      },
    ).call();

    expect(watchlist.entries.single.detail?.title, 'override room');
    expect(fetchCalls, 0);
  });

  test('load follow watchlist falls back to persisted metadata when offline',
      () async {
    final followRepository = InMemoryFollowRepository();
    await followRepository.upsert(
      const FollowRecord(
        providerId: 'bilibili',
        roomId: '8',
        streamerName: '离线主播',
        streamerAvatarUrl: 'https://example.com/local-avatar.png',
        lastTitle: '上次标题',
        lastAreaName: '上次分区',
        lastCoverUrl: 'https://example.com/local-cover.png',
        lastKeyframeUrl: 'https://example.com/local-keyframe.png',
      ),
    );

    final registry = ProviderRegistry()
      ..register(
        ProviderRegistration(
          descriptor: _kTestDescriptor,
          builder: () => _FakeDetailProvider(
            (_) async => throw StateError('network unavailable'),
          ),
        ),
      );

    final watchlist = await LoadFollowWatchlistUseCase(
      followRepository: followRepository,
      registry: registry,
    ).call();

    final entry = watchlist.entries.single;
    expect(entry.error, isA<StateError>());
    expect(entry.title, '上次标题');
    expect(entry.displayAreaName, '上次分区');
    expect(
      entry.displayStreamerAvatarUrl,
      'https://example.com/local-avatar.png',
    );
    expect(entry.displayCoverUrl, 'https://example.com/local-cover.png');
    expect(
      entry.displayKeyframeUrl,
      'https://example.com/local-keyframe.png',
    );
    expect(entry.isUnavailable, isTrue);
    expect(entry.isOffline, isFalse);

    final room = entry.toLiveRoom();
    expect(room.title, '上次标题');
    expect(room.areaName, '上次分区');
    expect(room.coverUrl, 'https://example.com/local-cover.png');
    expect(room.keyframeUrl, 'https://example.com/local-keyframe.png');
    expect(room.isLive, isFalse);
    expect(watchlist.offlineCount, 0);
  });

  test('load follow watchlist reports progress before all rooms complete',
      () async {
    final followRepository = InMemoryFollowRepository();
    await followRepository.upsert(
      const FollowRecord(
        providerId: 'bilibili',
        roomId: 'fast-room',
        streamerName: '快速主播',
      ),
    );
    await followRepository.upsert(
      const FollowRecord(
        providerId: 'bilibili',
        roomId: 'slow-room',
        streamerName: '慢速主播',
      ),
    );

    final slowDetail = Completer<LiveRoomDetail>();
    final registry = ProviderRegistry()
      ..register(
        ProviderRegistration(
          descriptor: _kTestDescriptor,
          builder: () => _FakeDetailProvider((roomId) {
            if (roomId == 'slow-room') {
              return slowDetail.future;
            }
            return Future.value(
              LiveRoomDetail(
                providerId: 'bilibili',
                roomId: roomId,
                title: '快速房间',
                streamerName: '快速主播',
                isLive: true,
              ),
            );
          }),
        ),
      );

    final resolvedRooms = <String>[];
    final pending = LoadFollowWatchlistUseCase(
      followRepository: followRepository,
      registry: registry,
    ).call(
      onEntryResolved: (index, entry) {
        resolvedRooms.add(entry.roomId);
      },
    );

    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(resolvedRooms, contains('fast-room'));
    expect(resolvedRooms, isNot(contains('slow-room')));

    slowDetail.complete(
      LiveRoomDetail(
        providerId: 'bilibili',
        roomId: 'slow-room',
        title: '慢速房间',
        streamerName: '慢速主播',
      ),
    );
    final watchlist = await pending;

    expect(watchlist.entries, hasLength(2));
    expect(resolvedRooms, containsAll(['fast-room', 'slow-room']));
  });

  test('load follow watchlist batches snapshot persistence updates', () async {
    final followRepository = _RecordingFollowRepository(
      records: const [
        FollowRecord(
          providerId: 'bilibili',
          roomId: '9',
          streamerName: '本地主播',
        ),
      ],
    );

    final registry = ProviderRegistry()
      ..register(
        ProviderRegistration(
          descriptor: _kTestDescriptor,
          builder: () => _FakeDetailProvider(
            (roomId) async => LiveRoomDetail(
              providerId: 'bilibili',
              roomId: roomId,
              title: '远程房间',
              streamerName: '远程主播',
              isLive: true,
            ),
          ),
        ),
      );

    await LoadFollowWatchlistUseCase(
      followRepository: followRepository,
      registry: registry,
    ).call();

    expect(followRepository.upsertCalls, 0);
    expect(followRepository.upsertAllCalls, 1);
    expect(followRepository.lastUpsertAll, hasLength(1));
    expect(followRepository.lastUpsertAll.single.lastTitle, '远程房间');
  });
}

class _RecordingFollowRepository implements FollowRepository {
  _RecordingFollowRepository({required List<FollowRecord> records})
      : _records = List<FollowRecord>.from(records);

  final List<FollowRecord> _records;
  int upsertCalls = 0;
  int upsertAllCalls = 0;
  List<FollowRecord> lastUpsertAll = const <FollowRecord>[];

  @override
  Future<void> clear() async {
    _records.clear();
  }

  @override
  Future<bool> exists(String providerId, String roomId) async {
    return _records.any(
      (item) => item.providerId == providerId && item.roomId == roomId,
    );
  }

  @override
  Future<List<FollowRecord>> listAll() async {
    return List<FollowRecord>.from(_records, growable: false);
  }

  @override
  Future<void> remove(String providerId, String roomId) async {
    _records.removeWhere(
      (item) => item.providerId == providerId && item.roomId == roomId,
    );
  }

  @override
  Future<void> upsert(FollowRecord record) async {
    upsertCalls += 1;
    await upsertAll([record]);
  }

  @override
  Future<void> upsertAll(Iterable<FollowRecord> records) async {
    upsertAllCalls += 1;
    lastUpsertAll = List<FollowRecord>.from(records, growable: false);
    for (final record in lastUpsertAll) {
      final existingIndex = _records.indexWhere(
        (item) =>
            item.providerId == record.providerId &&
            item.roomId == record.roomId,
      );
      if (existingIndex >= 0) {
        _records[existingIndex] = record;
      } else {
        _records.insert(0, record);
      }
    }
  }
}
