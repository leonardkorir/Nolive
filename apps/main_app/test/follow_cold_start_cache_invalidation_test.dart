import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:live_core/live_core.dart';
import 'package:live_providers/live_providers.dart';
import 'package:live_storage/live_storage.dart';
import 'package:nolive_app/src/features/library/application/load_follow_watchlist_use_case.dart';

/// Regression guard for the cold-start race that produced
/// `ClientException: Client is already closed` on the follow tab.
///
/// The chain on a device with a slow Keystore:
///
///   Keystore read stalls
///     -> the secure credential store can only promote in the background
///     -> promotion fires `onSnapshotChanged`
///     -> `AppBootstrap` calls `ProviderRegistry.clearCache()`
///     -> every cached provider is disposed, closing its `http.Client`
///     -> the follow status crawl that is mid-flight dies
///
/// How slow the Keystore is only decides *when* the invalidation lands, so this
/// cannot be reproduced on demand from the UI. It is reproduced here directly:
/// invalidate the cache while a crawl is in flight and assert the in-flight
/// request still completes.
void main() {
  const descriptor = ProviderDescriptor(
    id: ProviderId.bilibili,
    displayName: '测试平台',
    capabilities: {ProviderCapability.roomDetail},
    supportedPlatforms: {ProviderPlatform.android},
    maturity: ProviderMaturity.ready,
  );

  test(
    'clearCache during an in-flight follow crawl does not close its client',
    () async {
      final followRepository = InMemoryFollowRepository();
      await followRepository.upsert(
        const FollowRecord(
          providerId: ProviderId.bilibili,
          roomId: '6',
          streamerName: '本地主播',
        ),
      );

      final requestReached = Completer<void>();
      final releaseRequest = Completer<void>();
      final built = <_ClosableDetailProvider>[];

      final registry = ProviderRegistry()
        ..register(
          ProviderRegistration(
            descriptor: descriptor,
            builder: () {
              final provider = _ClosableDetailProvider(
                descriptor: descriptor,
                onFetch: () async {
                  if (!requestReached.isCompleted) {
                    requestReached.complete();
                  }
                  await releaseRequest.future;
                },
              );
              built.add(provider);
              return provider;
            },
          ),
        );

      final crawl = LoadFollowWatchlistUseCase(
        followRepository: followRepository,
        registry: registry,
        detailTimeout: const Duration(seconds: 5),
        detailRetryCount: 0,
        maxConcurrent: 1,
      ).call();

      // Wait until the crawl is genuinely inside fetchRoomDetail, then fire the
      // invalidation exactly the way the secure-store promotion does.
      await requestReached.future;
      registry.clearCache();

      expect(
        built.single.closed,
        isFalse,
        reason: 'the borrowed provider must outlive the request it is serving',
      );

      releaseRequest.complete();
      final watchlist = await crawl;

      expect(watchlist.entries.single.error, isNull);
      expect(watchlist.entries.single.detail?.roomId, '6');
      expect(watchlist.entries.single.detail?.isLive, isTrue);

      // Once the request is done the retired instance is disposed for real, and
      // the next caller gets a rebuilt one.
      expect(built.single.closed, isTrue);
      registry.create(ProviderId.bilibili);
      expect(built, hasLength(2));
    },
  );

  test('a client closed mid-request is still classified as transient', () {
    // Belt and braces: if some other path ever closes a client mid-flight, the
    // follow crawl must retry rather than render the row as a hard failure.
    expect(
      isTransientFollowDetailError(
        ProviderParseException(
          providerId: ProviderId.bilibili,
          message: 'Bilibili request failed before response.',
          cause: http.ClientException('Client is already closed.'),
        ),
      ),
      isTrue,
    );
  });
}

/// A provider that fails the way a real one does once its client is closed.
class _ClosableDetailProvider extends LiveProvider
    implements SupportsRoomDetail {
  _ClosableDetailProvider({
    required ProviderDescriptor descriptor,
    required Future<void> Function() onFetch,
  }) : _descriptor = descriptor,
       _onFetch = onFetch;

  final ProviderDescriptor _descriptor;
  final Future<void> Function() _onFetch;
  bool closed = false;

  @override
  ProviderDescriptor get descriptor => _descriptor;

  @override
  void dispose() {
    closed = true;
  }

  @override
  Future<LiveRoomDetail> fetchRoomDetail(String roomId) async {
    await _onFetch();
    if (closed) {
      throw ProviderParseException(
        providerId: ProviderId.bilibili,
        message: 'Bilibili request failed before response.',
        cause: http.ClientException('Client is already closed.'),
      );
    }
    return LiveRoomDetail(
      providerId: ProviderId.bilibili,
      roomId: roomId,
      title: '远程房间',
      streamerName: '远程主播',
      isLive: true,
    );
  }
}
