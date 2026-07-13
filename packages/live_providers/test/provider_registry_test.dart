import 'dart:async';

import 'package:live_core/live_core.dart';
import 'package:live_providers/live_providers.dart';
import 'package:live_providers/src/providers/youtube/youtube_api_client.dart';
import 'package:test/test.dart';

void main() {
  test('default catalog exposes migrated provider descriptors', () {
    final registry = ReferenceProviderCatalog.buildDefaultRegistry();
    final ids = registry.descriptors.map((item) => item.id.value).toSet();

    expect(
      ids,
      containsAll({
        'bilibili',
        'chaturbate',
        'douyu',
        'huya',
        'douyin',
        'twitch',
        'youtube',
        'stripchat',
      }),
    );
    expect(
      registry
          .findDescriptor(ProviderId.bilibili)
          ?.supports(ProviderCapability.playUrls),
      isTrue,
    );
    expect(
      registry
          .findDescriptor(ProviderId.chaturbate)
          ?.supports(ProviderCapability.searchRooms),
      isTrue,
    );
    expect(
      registry
          .findDescriptor(ProviderId.chaturbate)
          ?.supports(ProviderCapability.categories),
      isTrue,
    );
    expect(
      registry
          .findDescriptor(ProviderId.chaturbate)
          ?.supports(ProviderCapability.danmaku),
      isTrue,
    );
    expect(
      registry
          .findDescriptor(ProviderId.youtube)
          ?.supports(ProviderCapability.categories),
      isTrue,
    );
    expect(
      registry
          .findDescriptor(ProviderId.youtube)
          ?.supports(ProviderCapability.recommendRooms),
      isTrue,
    );
    expect(
      registry
          .findDescriptor(ProviderId.twitch)
          ?.supports(ProviderCapability.categories),
      isTrue,
    );
    expect(
      registry
          .findDescriptor(ProviderId.twitch)
          ?.supports(ProviderCapability.recommendRooms),
      isTrue,
    );
    expect(
      registry
          .findDescriptor(ProviderId.youtube)
          ?.supports(ProviderCapability.danmaku),
      isTrue,
    );
    expect(registry.hasImplementation(ProviderId.bilibili), isTrue);
    expect(registry.hasImplementation(ProviderId.chaturbate), isTrue);
    expect(registry.hasImplementation(ProviderId.douyu), isTrue);
    expect(registry.hasImplementation(ProviderId.huya), isTrue);
    expect(registry.hasImplementation(ProviderId.douyin), isTrue);
    expect(registry.hasImplementation(ProviderId.twitch), isTrue);
    expect(registry.hasImplementation(ProviderId.youtube), isTrue);
    expect(registry.hasImplementation(ProviderId.stripchat), isTrue);
  });

  test('registry creates chaturbate provider runtime', () {
    final registry = ReferenceProviderCatalog.buildDefaultRegistry();

    final provider = registry.create(ProviderId.chaturbate);

    expect(provider, isA<ChaturbateProvider>());
  });

  test('registry creates bilibili provider runtime', () {
    final registry = ReferenceProviderCatalog.buildDefaultRegistry();

    final provider = registry.create(ProviderId.bilibili);

    expect(provider, isA<BilibiliProvider>());
  });

  test('registry creates douyu provider runtime', () {
    final registry = ReferenceProviderCatalog.buildDefaultRegistry();

    final provider = registry.create(ProviderId.douyu);

    expect(provider, isA<DouyuProvider>());
  });

  test('registry creates huya provider runtime', () {
    final registry = ReferenceProviderCatalog.buildDefaultRegistry();

    final provider = registry.create(ProviderId.huya);

    expect(provider, isA<HuyaProvider>());
  });

  test('registry creates douyin provider runtime', () {
    final registry = ReferenceProviderCatalog.buildDefaultRegistry();

    final provider = registry.create(ProviderId.douyin);

    expect(provider, isA<DouyinProvider>());
  });

  test('registry creates twitch provider runtime', () {
    final registry = ReferenceProviderCatalog.buildDefaultRegistry();

    final provider = registry.create(ProviderId.twitch);

    expect(provider, isA<TwitchProvider>());
  });

  test('registry creates youtube provider runtime', () {
    final registry = ReferenceProviderCatalog.buildDefaultRegistry();

    final provider = registry.create(ProviderId.youtube);

    expect(provider, isA<YouTubeProvider>());
  });

  test('registry creates stripchat provider runtime', () {
    final registry = ReferenceProviderCatalog.buildDefaultRegistry();

    final provider = registry.create(ProviderId.stripchat);

    expect(provider, isA<StripchatProvider>());
  });

  test('live registry creates chaturbate provider runtime', () {
    final registry = ReferenceProviderCatalog.buildLiveRegistry();

    final provider = registry.create(ProviderId.chaturbate);

    expect(provider, isA<ChaturbateProvider>());
  });

  test('registry reuses provider instance until invalidated', () {
    var created = 0;
    final registry = ProviderRegistry()
      ..register(
        ProviderRegistration(
          descriptor: BilibiliProvider.kDescriptor,
          builder: () {
            created += 1;
            return BilibiliProvider.preview();
          },
        ),
      );

    final first = registry.create(ProviderId.bilibili);
    final second = registry.create(ProviderId.bilibili);

    expect(identical(first, second), isTrue);
    expect(created, 1);

    registry.invalidate(ProviderId.bilibili);

    final third = registry.create(ProviderId.bilibili);
    expect(identical(first, third), isFalse);
    expect(created, 2);
  });

  test('registry invalidation disposes cached providers', () {
    final provider = _DisposableTestProvider(BilibiliProvider.kDescriptor);
    final registry = ProviderRegistry()
      ..register(
        ProviderRegistration(
          descriptor: BilibiliProvider.kDescriptor,
          builder: () => provider,
        ),
      );

    registry.create(ProviderId.bilibili);
    registry.invalidate(ProviderId.bilibili);

    expect(provider.disposeCalls, 1);
  });

  test('registry clearCache disposes all cached providers', () {
    final bilibili = _DisposableTestProvider(BilibiliProvider.kDescriptor);
    final douyin = _DisposableTestProvider(DouyinProvider.kDescriptor);
    final registry = ProviderRegistry()
      ..register(
        ProviderRegistration(
          descriptor: BilibiliProvider.kDescriptor,
          builder: () => bilibili,
        ),
      )
      ..register(
        ProviderRegistration(
          descriptor: DouyinProvider.kDescriptor,
          builder: () => douyin,
        ),
      );

    registry.create(ProviderId.bilibili);
    registry.create(ProviderId.douyin);
    registry.clearCache();

    expect(bilibili.disposeCalls, 1);
    expect(douyin.disposeCalls, 1);
  });

  test(
    'register replacing an existing descriptor disposes cached provider',
    () {
      final original = _DisposableTestProvider(BilibiliProvider.kDescriptor);
      final replacement = _DisposableTestProvider(BilibiliProvider.kDescriptor);
      final registry = ProviderRegistry()
        ..register(
          ProviderRegistration(
            descriptor: BilibiliProvider.kDescriptor,
            builder: () => original,
          ),
        );

      registry.create(ProviderId.bilibili);
      registry.register(
        ProviderRegistration(
          descriptor: BilibiliProvider.kDescriptor,
          builder: () => replacement,
        ),
      );

      expect(original.disposeCalls, 1);
      expect(
        identical(registry.create(ProviderId.bilibili), replacement),
        isTrue,
      );
    },
  );

  test(
    'invalidating a youtube provider does not close active danmaku client',
    () async {
      final createdClients = <_ClosableYouTubeApiClient>[];
      final registry = ProviderRegistry()
        ..register(
          ProviderRegistration(
            descriptor: YouTubeProvider.kDescriptor,
            builder: () => YouTubeProvider.live(
              apiClientBuilder: () {
                final client = _ClosableYouTubeApiClient();
                createdClients.add(client);
                return client;
              },
              apiClientDisposer: (apiClient) {
                (apiClient as _ClosableYouTubeApiClient).close();
              },
            ),
          ),
        );

      final provider = registry.create(ProviderId.youtube) as YouTubeProvider;
      final detail = LiveRoomDetail(
        providerId: ProviderId.youtube,
        roomId: '@demo/live',
        title: 'test',
        streamerName: 'tester',
        danmakuToken: const YouTubeDanmakuToken(
          apiKey: 'AIzaTest',
          clientVersion: YouTubeApiClient.defaultWebClientVersion,
          continuation: 'test-continuation',
          liveChatPageUrl: 'https://www.youtube.com/live_chat?continuation=1',
          visitorData: 'visitor-data',
        ),
      );

      final session = await provider.createDanmakuSession(detail);
      expect(createdClients, hasLength(2));

      registry.clearCache();
      expect(createdClients.where((client) => client.closed), hasLength(1));

      await session.connect();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await session.disconnect();

      final sessionClient = createdClients.singleWhere(
        (client) => client.postLiveChatCalls > 0,
      );
      final providerClient = createdClients.singleWhere(
        (client) => !identical(client, sessionClient),
      );

      expect(sessionClient.closeCalls, 1);
      expect(providerClient.closeCalls, 1);
    },
  );
}

class _DisposableTestProvider extends LiveProvider {
  _DisposableTestProvider(this._descriptor);

  final ProviderDescriptor _descriptor;
  int disposeCalls = 0;

  @override
  ProviderDescriptor get descriptor => _descriptor;

  @override
  void dispose() {
    disposeCalls += 1;
  }
}

class _ClosableYouTubeApiClient implements YouTubeApiClient {
  int closeCalls = 0;
  int postLiveChatCalls = 0;
  bool closed = false;

  void close() {
    closeCalls += 1;
    closed = true;
  }

  @override
  Future<String> fetchText(
    String url, {
    Map<String, String> headers = const {},
  }) {
    throw UnimplementedError();
  }

  @override
  Future<int> probeStatus(
    String url, {
    Map<String, String> headers = const {},
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, dynamic>> postLiveChat({
    required String apiKey,
    required String continuation,
    required String visitorData,
    required String referer,
    String clientVersion = YouTubeApiClient.defaultWebClientVersion,
    Duration timeout = YouTubeApiClient.liveChatRequestTimeout,
  }) async {
    if (closed) {
      throw StateError('client closed');
    }
    postLiveChatCalls += 1;
    return {
      'continuationContents': {
        'liveChatContinuation': {
          'actions': const [],
          'continuations': [
            {
              'timedContinuationData': {
                'continuation': continuation,
                'timeoutMs': 1000,
              },
            },
          ],
        },
      },
    };
  }

  @override
  Future<Map<String, dynamic>> postPlayer({
    required String apiKey,
    required String videoId,
    required String originalUrl,
    Map<String, dynamic> innertubeContext = const {},
    String rolloutToken = '',
    String poToken = '',
    YouTubePlayerClientProfile clientProfile =
        YouTubePlayerClientProfile.streamlinkAndroid,
  }) {
    throw UnimplementedError();
  }
}
