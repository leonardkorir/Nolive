import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_providers/live_providers.dart';
import 'package:live_storage/live_storage.dart';
import 'package:nolive_app/src/features/library/application/load_follow_watchlist_use_case.dart';
import 'package:nolive_app/src/shared/domain/follow_watch_entry.dart';

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
  test(
    'load follow watchlist keeps slow providers from blocking forever',
    () async {
      final followRepository = InMemoryFollowRepository();
      await followRepository.upsert(
        const FollowRecord(
          providerId: ProviderId.bilibili,
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
                  providerId: ProviderId.bilibili,
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
    },
  );

  test(
    'load follow watchlist maps resolved room detail into entries',
    () async {
      final followRepository = InMemoryFollowRepository();
      await followRepository.upsert(
        const FollowRecord(
          providerId: ProviderId.bilibili,
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
                providerId: ProviderId.bilibili,
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
    },
  );

  test(
    'load follow watchlist prefers provider detail before room detail override',
    () async {
      final followRepository = InMemoryFollowRepository();
      await followRepository.upsert(
        const FollowRecord(
          providerId: ProviderId.chaturbate,
          roomId: 'milabunny_',
          streamerName: '本地主播',
        ),
      );

      var fetchCalls = 0;
      var overrideCalls = 0;
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
                return Future.value(
                  LiveRoomDetail(
                    providerId: ProviderId.chaturbate,
                    roomId: roomId,
                    title: 'provider room',
                    streamerName: roomId,
                    isLive: true,
                  ),
                );
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
        roomDetailOverride: ({required providerId, required roomId}) async {
          overrideCalls += 1;
          if (providerId != ProviderId.chaturbate) {
            return null;
          }
          return LiveRoomDetail(
            providerId: providerId,
            roomId: roomId,
            title: 'override room',
            streamerName: roomId,
            isLive: true,
          );
        },
      ).call();

      expect(watchlist.entries.single.detail?.title, 'provider room');
      expect(fetchCalls, 1);
      expect(overrideCalls, 0);
    },
  );

  test(
    'load follow watchlist does not use room detail override for chaturbate after provider failure',
    () async {
      final followRepository = InMemoryFollowRepository();
      await followRepository.upsert(
        const FollowRecord(
          providerId: ProviderId.chaturbate,
          roomId: 'milabunny_',
          streamerName: '本地主播',
        ),
      );

      var fetchCalls = 0;
      var overrideCalls = 0;
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
                throw StateError('provider fetchRoomDetail failed');
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
        roomDetailOverride: ({required providerId, required roomId}) async {
          overrideCalls += 1;
          if (providerId != ProviderId.chaturbate) {
            return null;
          }
          return LiveRoomDetail(
            providerId: providerId,
            roomId: roomId,
            title: 'override room',
            streamerName: roomId,
            isLive: true,
          );
        },
      ).call();

      expect(watchlist.entries.single.detail, isNull);
      expect(watchlist.entries.single.error, isA<StateError>());
      expect(fetchCalls, 1);
      expect(overrideCalls, 0);
    },
  );

  test(
    'load follow watchlist still uses room detail override for other providers after provider failure',
    () async {
      final followRepository = InMemoryFollowRepository();
      await followRepository.upsert(
        const FollowRecord(
          providerId: ProviderId.bilibili,
          roomId: '7',
          streamerName: '本地主播',
        ),
      );

      var fetchCalls = 0;
      var overrideCalls = 0;
      final registry = ProviderRegistry()
        ..register(
          ProviderRegistration(
            descriptor: _kTestDescriptor,
            builder: () => _FakeDetailProvider((roomId) {
              fetchCalls += 1;
              throw StateError('provider fetchRoomDetail failed');
            }),
          ),
        );

      final watchlist = await LoadFollowWatchlistUseCase(
        followRepository: followRepository,
        registry: registry,
        roomDetailOverride: ({required providerId, required roomId}) async {
          overrideCalls += 1;
          return LiveRoomDetail(
            providerId: providerId,
            roomId: roomId,
            title: 'override room',
            streamerName: roomId,
            isLive: true,
          );
        },
      ).call();

      expect(watchlist.entries.single.detail?.title, 'override room');
      expect(fetchCalls, 1);
      expect(overrideCalls, 1);
    },
  );

  test(
    'load follow watchlist falls back to persisted metadata when offline',
    () async {
      final followRepository = InMemoryFollowRepository();
      await followRepository.upsert(
        const FollowRecord(
          providerId: ProviderId.bilibili,
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
    },
  );

  test(
    'load follow watchlist reports progress before all rooms complete',
    () async {
      final followRepository = InMemoryFollowRepository();
      await followRepository.upsert(
        const FollowRecord(
          providerId: ProviderId.bilibili,
          roomId: 'fast-room',
          streamerName: '快速主播',
        ),
      );
      await followRepository.upsert(
        const FollowRecord(
          providerId: ProviderId.bilibili,
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
                  providerId: ProviderId.bilibili,
                  roomId: roomId,
                  title: '快速房间',
                  streamerName: '快速主播',
                  isLive: true,
                ),
              );
            }),
          ),
        );

      final detailedRooms = <String>[];
      final pending =
          LoadFollowWatchlistUseCase(
            followRepository: followRepository,
            registry: registry,
          ).call(
            onEntryResolved: (index, entry) {
              // Local-first publishes both rows immediately; track remote detail.
              if (entry.detail != null) {
                detailedRooms.add(entry.roomId);
              }
            },
          );

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(detailedRooms, contains('fast-room'));
      expect(detailedRooms, isNot(contains('slow-room')));

      slowDetail.complete(
        LiveRoomDetail(
          providerId: ProviderId.bilibili,
          roomId: 'slow-room',
          title: '慢速房间',
          streamerName: '慢速主播',
        ),
      );
      final watchlist = await pending;

      expect(watchlist.entries, hasLength(2));
      expect(detailedRooms, containsAll(['fast-room', 'slow-room']));
    },
  );

  test('load follow watchlist batches snapshot persistence updates', () async {
    final followRepository = _RecordingFollowRepository(
      records: const [
        FollowRecord(
          providerId: ProviderId.bilibili,
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
              providerId: ProviderId.bilibili,
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

  test(
    'load follow watchlist caps concurrent Chaturbate detail fetches',
    () async {
      final followRepository = InMemoryFollowRepository();
      for (var i = 0; i < 6; i += 1) {
        await followRepository.upsert(
          FollowRecord(
            providerId: ProviderId.chaturbate,
            roomId: 'cb-$i',
            streamerName: 'CB $i',
          ),
        );
      }

      var inFlight = 0;
      var peakInFlight = 0;
      const cbDescriptor = ProviderDescriptor(
        id: ProviderId.chaturbate,
        displayName: 'Chaturbate',
        capabilities: {ProviderCapability.roomDetail},
        supportedPlatforms: {ProviderPlatform.android},
        maturity: ProviderMaturity.ready,
      );
      final registry = ProviderRegistry()
        ..register(
          ProviderRegistration(
            descriptor: cbDescriptor,
            builder: () => _FakeDetailProvider(
              (roomId) async {
                inFlight += 1;
                if (inFlight > peakInFlight) {
                  peakInFlight = inFlight;
                }
                await Future<void>.delayed(const Duration(milliseconds: 40));
                inFlight -= 1;
                return LiveRoomDetail(
                  providerId: ProviderId.chaturbate,
                  roomId: roomId,
                  title: roomId,
                  streamerName: roomId,
                  isLive: true,
                );
              },
              descriptor: cbDescriptor,
            ),
          ),
        );

      final watchlist = await LoadFollowWatchlistUseCase(
        followRepository: followRepository,
        registry: registry,
        maxConcurrent: 6,
        maxConcurrentChaturbate: 2,
        maxChaturbatePerRefresh: 20,
        chaturbateSpacing: Duration.zero,
      ).call(scope: FollowWatchlistRefreshScope.allProviders);

      expect(watchlist.entries, hasLength(6));
      expect(peakInFlight, lessThanOrEqualTo(2));
      expect(watchlist.entries.every((e) => e.detail != null), isTrue);
    },
  );

  test(
    'non-Chaturbate phase completes before Chaturbate and does not share the CB gate',
    () async {
      final followRepository = InMemoryFollowRepository();
      await followRepository.upsert(
        const FollowRecord(
          providerId: ProviderId.bilibili,
          roomId: 'bili-1',
          streamerName: 'B站1',
        ),
      );
      await followRepository.upsert(
        const FollowRecord(
          providerId: ProviderId.douyu,
          roomId: 'dy-1',
          streamerName: '斗鱼1',
        ),
      );
      for (var i = 0; i < 3; i += 1) {
        await followRepository.upsert(
          FollowRecord(
            providerId: ProviderId.chaturbate,
            roomId: 'cb-$i',
            streamerName: 'CB $i',
          ),
        );
      }

      final order = <String>[];
      var nonCbPhaseDone = false;
      const biliDescriptor = ProviderDescriptor(
        id: ProviderId.bilibili,
        displayName: 'Bilibili',
        capabilities: {ProviderCapability.roomDetail},
        supportedPlatforms: {ProviderPlatform.android},
        maturity: ProviderMaturity.ready,
      );
      const douyuDescriptor = ProviderDescriptor(
        id: ProviderId.douyu,
        displayName: 'Douyu',
        capabilities: {ProviderCapability.roomDetail},
        supportedPlatforms: {ProviderPlatform.android},
        maturity: ProviderMaturity.ready,
      );
      const cbDescriptor = ProviderDescriptor(
        id: ProviderId.chaturbate,
        displayName: 'Chaturbate',
        capabilities: {ProviderCapability.roomDetail},
        supportedPlatforms: {ProviderPlatform.android},
        maturity: ProviderMaturity.ready,
      );

      final registry = ProviderRegistry()
        ..register(
          ProviderRegistration(
            descriptor: biliDescriptor,
            builder: () => _FakeDetailProvider(
              (roomId) async {
                order.add('bili');
                return LiveRoomDetail(
                  providerId: ProviderId.bilibili,
                  roomId: roomId,
                  title: roomId,
                  streamerName: roomId,
                  isLive: true,
                );
              },
              descriptor: biliDescriptor,
            ),
          ),
        )
        ..register(
          ProviderRegistration(
            descriptor: douyuDescriptor,
            builder: () => _FakeDetailProvider(
              (roomId) async {
                order.add('douyu');
                return LiveRoomDetail(
                  providerId: ProviderId.douyu,
                  roomId: roomId,
                  title: roomId,
                  streamerName: roomId,
                  isLive: true,
                );
              },
              descriptor: douyuDescriptor,
            ),
          ),
        )
        ..register(
          ProviderRegistration(
            descriptor: cbDescriptor,
            builder: () => _FakeDetailProvider(
              (roomId) async {
                expect(
                  nonCbPhaseDone,
                  isTrue,
                  reason: 'Chaturbate must not run before non-CB phase completes',
                );
                order.add('cb');
                await Future<void>.delayed(const Duration(milliseconds: 20));
                return LiveRoomDetail(
                  providerId: ProviderId.chaturbate,
                  roomId: roomId,
                  title: roomId,
                  streamerName: roomId,
                  isLive: true,
                );
              },
              descriptor: cbDescriptor,
            ),
          ),
        );

      final watchlist = await LoadFollowWatchlistUseCase(
        followRepository: followRepository,
        registry: registry,
        maxConcurrent: 4,
        maxConcurrentChaturbate: 1,
        maxChaturbatePerRefresh: 20,
        chaturbateSpacing: Duration.zero,
      ).call(
        scope: FollowWatchlistRefreshScope.allProviders,
        onNonChaturbateComplete: () {
          nonCbPhaseDone = true;
          expect(order, containsAll(<String>['bili', 'douyu']));
          expect(order.where((item) => item == 'cb'), isEmpty);
        },
      );

      expect(nonCbPhaseDone, isTrue);
      expect(order.where((item) => item == 'cb'), hasLength(3));
      expect(watchlist.entries, hasLength(5));
    },
  );

  test('Chaturbate follow crawl caps batch size and rotates by cycle', () async {
    final followRepository = InMemoryFollowRepository();
    for (var i = 0; i < 12; i += 1) {
      await followRepository.upsert(
        FollowRecord(
          providerId: ProviderId.chaturbate,
          roomId: 'cb-$i',
          streamerName: 'CB $i',
        ),
      );
    }
    const cbDescriptor = ProviderDescriptor(
      id: ProviderId.chaturbate,
      displayName: 'Chaturbate',
      capabilities: {ProviderCapability.roomDetail},
      supportedPlatforms: {ProviderPlatform.android},
      maturity: ProviderMaturity.ready,
    );
    final fetched = <String>[];
    final registry = ProviderRegistry()
      ..register(
        ProviderRegistration(
          descriptor: cbDescriptor,
          builder: () => _FakeDetailProvider(
            (roomId) async {
              fetched.add(roomId);
              return LiveRoomDetail(
                providerId: ProviderId.chaturbate,
                roomId: roomId,
                title: roomId,
                streamerName: roomId,
                isLive: true,
              );
            },
            descriptor: cbDescriptor,
          ),
        ),
      );

    final useCase = LoadFollowWatchlistUseCase(
      followRepository: followRepository,
      registry: registry,
      maxChaturbatePerRefresh: 4,
      chaturbateSpacing: Duration.zero,
    );
    await useCase.call(
      scope: FollowWatchlistRefreshScope.allProviders,
      refreshCycle: 0,
    );
    expect(fetched, hasLength(4));
    final firstBatch = List<String>.from(fetched);

    fetched.clear();
    await useCase.call(
      scope: FollowWatchlistRefreshScope.allProviders,
      refreshCycle: 1,
    );
    expect(fetched, hasLength(4));
    // Rotating batches should not be identical for a 12-item list.
    expect(fetched, isNot(orderedEquals(firstBatch)));
  });

  test('Chaturbate follow crawl stops after first 429-like error', () async {
    final followRepository = InMemoryFollowRepository();
    for (var i = 0; i < 6; i += 1) {
      await followRepository.upsert(
        FollowRecord(
          providerId: ProviderId.chaturbate,
          roomId: 'cb-$i',
          streamerName: 'CB $i',
        ),
      );
    }
    const cbDescriptor = ProviderDescriptor(
      id: ProviderId.chaturbate,
      displayName: 'Chaturbate',
      capabilities: {ProviderCapability.roomDetail},
      supportedPlatforms: {ProviderPlatform.android},
      maturity: ProviderMaturity.ready,
    );
    var calls = 0;
    final registry = ProviderRegistry()
      ..register(
        ProviderRegistration(
          descriptor: cbDescriptor,
          builder: () => _FakeDetailProvider(
            (roomId) async {
              calls += 1;
              if (calls == 1) {
                throw Exception('Chaturbate context failed with status 429.');
              }
              return LiveRoomDetail(
                providerId: ProviderId.chaturbate,
                roomId: roomId,
                title: roomId,
                streamerName: roomId,
                isLive: true,
              );
            },
            descriptor: cbDescriptor,
          ),
        ),
      );

    await LoadFollowWatchlistUseCase(
      followRepository: followRepository,
      registry: registry,
      maxChaturbatePerRefresh: 6,
      chaturbateSpacing: Duration.zero,
    ).call(scope: FollowWatchlistRefreshScope.allProviders);

    // First call hits 429 → abort remaining crawl this cycle.
    expect(calls, 1);
  });

  test('takeRotatingFollowBatch wraps around ranked list', () {
    expect(
      takeRotatingFollowBatch([0, 1, 2, 3, 4, 5], cycle: 0, maxTake: 3),
      [0, 1, 2],
    );
    expect(
      takeRotatingFollowBatch([0, 1, 2, 3, 4, 5], cycle: 1, maxTake: 3),
      [3, 4, 5],
    );
    expect(
      takeRotatingFollowBatch([0, 1, 2, 3, 4, 5], cycle: 2, maxTake: 3),
      [0, 1, 2],
    );
  });

  test('isChaturbateFollowRateLimitError detects 429 wording', () {
    expect(
      isChaturbateFollowRateLimitError(
        Exception('Chaturbate room failed with status 429.'),
      ),
      isTrue,
    );
    expect(isChaturbateFollowRateLimitError(Exception('timeout')), isFalse);
  });

  test(
    'excludeChaturbate scope never calls Chaturbate room detail',
    () async {
      final followRepository = InMemoryFollowRepository();
      await followRepository.upsert(
        const FollowRecord(
          providerId: ProviderId.chaturbate,
          roomId: 'cb-1',
          streamerName: '本地CB',
          lastTitle: '缓存标题',
        ),
      );
      await followRepository.upsert(
        const FollowRecord(
          providerId: ProviderId.bilibili,
          roomId: '6',
          streamerName: 'B站',
        ),
      );

      var cbDetailCalls = 0;
      var biliDetailCalls = 0;
      const cbDescriptor = ProviderDescriptor(
        id: ProviderId.chaturbate,
        displayName: 'Chaturbate',
        capabilities: {ProviderCapability.roomDetail},
        supportedPlatforms: {ProviderPlatform.android},
        maturity: ProviderMaturity.ready,
      );
      final registry = ProviderRegistry()
        ..register(
          ProviderRegistration(
            descriptor: cbDescriptor,
            builder: () => _FakeDetailProvider(
              (roomId) async {
                cbDetailCalls += 1;
                return LiveRoomDetail(
                  providerId: ProviderId.chaturbate,
                  roomId: roomId,
                  title: '远程CB',
                  streamerName: '远程CB',
                  isLive: true,
                );
              },
              descriptor: cbDescriptor,
            ),
          ),
        )
        ..register(
          ProviderRegistration(
            descriptor: _kTestDescriptor,
            builder: () => _FakeDetailProvider((roomId) async {
              biliDetailCalls += 1;
              return LiveRoomDetail(
                providerId: ProviderId.bilibili,
                roomId: roomId,
                title: '远程B站',
                streamerName: '远程B站',
                isLive: true,
              );
            }),
          ),
        );

      final watchlist = await LoadFollowWatchlistUseCase(
        followRepository: followRepository,
        registry: registry,
      ).call(scope: FollowWatchlistRefreshScope.excludeChaturbate);

      expect(cbDetailCalls, 0);
      expect(biliDetailCalls, 1);
      final cbEntry = watchlist.entries.singleWhere(
        (e) => e.record.providerId == ProviderId.chaturbate,
      );
      expect(cbEntry.detail, isNull);
      expect(cbEntry.record.streamerName, '本地CB');
      final biliEntry = watchlist.entries.singleWhere(
        (e) => e.record.providerId == ProviderId.bilibili,
      );
      expect(biliEntry.detail?.title, '远程B站');
    },
  );

  test('localOnly scope never hits any provider network', () async {
    final followRepository = InMemoryFollowRepository();
    await followRepository.upsert(
      const FollowRecord(
        providerId: ProviderId.chaturbate,
        roomId: 'cb-1',
        streamerName: '本地CB',
      ),
    );
    var calls = 0;
    const cbDescriptor = ProviderDescriptor(
      id: ProviderId.chaturbate,
      displayName: 'Chaturbate',
      capabilities: {ProviderCapability.roomDetail},
      supportedPlatforms: {ProviderPlatform.android},
      maturity: ProviderMaturity.ready,
    );
    final registry = ProviderRegistry()
      ..register(
        ProviderRegistration(
          descriptor: cbDescriptor,
          builder: () => _FakeDetailProvider(
            (roomId) async {
              calls += 1;
              return LiveRoomDetail(
                providerId: ProviderId.chaturbate,
                roomId: roomId,
                title: '远程',
                streamerName: '远程',
              );
            },
            descriptor: cbDescriptor,
          ),
        ),
      );

    final watchlist = await LoadFollowWatchlistUseCase(
      followRepository: followRepository,
      registry: registry,
    ).call(scope: FollowWatchlistRefreshScope.localOnly);

    expect(calls, 0);
    expect(watchlist.entries.single.detail, isNull);
    expect(watchlist.entries.single.record.streamerName, '本地CB');
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
    final normalizedProviderId = ProviderId.from(providerId);
    return _records.any(
      (item) =>
          item.providerId == normalizedProviderId && item.roomId == roomId,
    );
  }

  @override
  Future<List<FollowRecord>> listAll() async {
    return List<FollowRecord>.from(_records, growable: false);
  }

  @override
  Future<void> remove(String providerId, String roomId) async {
    final normalizedProviderId = ProviderId.from(providerId);
    _records.removeWhere(
      (item) =>
          item.providerId == normalizedProviderId && item.roomId == roomId,
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
