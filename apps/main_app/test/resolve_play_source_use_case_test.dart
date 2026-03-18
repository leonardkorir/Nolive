import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_providers/live_providers.dart';
import 'package:nolive_app/src/features/room/application/resolve_play_source_use_case.dart';

void main() {
  test('resolve play source prefers https when enabled', () async {
    final registry = ProviderRegistry()
      ..register(
        ProviderRegistration(
          descriptor: const ProviderDescriptor(
            id: ProviderId('test'),
            displayName: 'Test Provider',
            capabilities: {ProviderCapability.playUrls},
            supportedPlatforms: {ProviderPlatform.android},
            maturity: ProviderMaturity.ready,
          ),
          builder: _FakePlayUrlProvider.new,
        ),
      );
    const detail = LiveRoomDetail(
      providerId: 'test',
      roomId: '1',
      title: 'Test Room',
      streamerName: 'Tester',
      isLive: true,
      sourceUrl: 'https://example.com/room/1',
    );
    const quality = LivePlayQuality(
      id: 'origin',
      label: '原画',
      sortOrder: 100,
      isDefault: true,
    );
    final useCase = ResolvePlaySourceUseCase(registry);

    final plain = await useCase(
      providerId: const ProviderId('test'),
      detail: detail,
      quality: quality,
    );
    final secure = await useCase(
      providerId: const ProviderId('test'),
      detail: detail,
      quality: quality,
      preferHttps: true,
    );

    expect(plain.playbackSource.url.scheme, 'http');
    expect(secure.playbackSource.url.scheme, 'https');
    expect(secure.effectiveQuality, same(quality));
  });

  test('resolve play source exposes effective bilibili quality from url',
      () async {
    final registry = ProviderRegistry()
      ..register(
        ProviderRegistration(
          descriptor: const ProviderDescriptor(
            id: ProviderId.bilibili,
            displayName: '哔哩哔哩',
            capabilities: {ProviderCapability.playUrls},
            supportedPlatforms: {ProviderPlatform.android},
            maturity: ProviderMaturity.ready,
          ),
          builder: _FakeBilibiliPlayUrlProvider.new,
        ),
      );
    const detail = LiveRoomDetail(
      providerId: 'bilibili',
      roomId: '1',
      title: 'Test Room',
      streamerName: 'Tester',
      isLive: true,
      sourceUrl: 'https://live.bilibili.com/1',
    );
    const quality = LivePlayQuality(
      id: '10000',
      label: '原画',
      sortOrder: 10000,
      metadata: {
        'qualityMap': {150: '高清', 250: '超清', 400: '蓝光', 10000: '原画'},
      },
    );
    final useCase = ResolvePlaySourceUseCase(registry);

    final resolved = await useCase(
      providerId: ProviderId.bilibili,
      detail: detail,
      quality: quality,
    );

    expect(resolved.isQualityFallback, isTrue);
    expect(resolved.effectiveQuality.id, '250');
    expect(resolved.effectiveQuality.label, '超清');
  });

  test('resolve play source prefers douyu line that keeps requested quality',
      () async {
    final registry = ProviderRegistry()
      ..register(
        ProviderRegistration(
          descriptor: const ProviderDescriptor(
            id: ProviderId.douyu,
            displayName: '斗鱼',
            capabilities: {ProviderCapability.playUrls},
            supportedPlatforms: {ProviderPlatform.android},
            maturity: ProviderMaturity.ready,
          ),
          builder: _FakeDouyuPreferredLineProvider.new,
        ),
      );
    const detail = LiveRoomDetail(
      providerId: 'douyu',
      roomId: '5526219',
      title: 'Test Room',
      streamerName: 'Tester',
      isLive: true,
      sourceUrl: 'https://www.douyu.com/5526219',
    );
    const quality = LivePlayQuality(
      id: '0',
      label: '原画2K30',
      sortOrder: 6191,
      metadata: {
        'qualityMap': {0: '原画2K30', 2: '高清', 4: '蓝光4M'},
      },
    );
    final useCase = ResolvePlaySourceUseCase(registry);

    final resolved = await useCase(
      providerId: ProviderId.douyu,
      detail: detail,
      quality: quality,
    );

    expect(resolved.playbackSource.url.toString(), contains('origin.flv'));
    expect(resolved.effectiveQuality, same(quality));
    expect(resolved.isQualityFallback, isFalse);
  });

  test('resolve play source exposes douyu fallback quality from metadata',
      () async {
    final registry = ProviderRegistry()
      ..register(
        ProviderRegistration(
          descriptor: const ProviderDescriptor(
            id: ProviderId.douyu,
            displayName: '斗鱼',
            capabilities: {ProviderCapability.playUrls},
            supportedPlatforms: {ProviderPlatform.android},
            maturity: ProviderMaturity.ready,
          ),
          builder: _FakeDouyuFallbackProvider.new,
        ),
      );
    const detail = LiveRoomDetail(
      providerId: 'douyu',
      roomId: '5526219',
      title: 'Test Room',
      streamerName: 'Tester',
      isLive: true,
      sourceUrl: 'https://www.douyu.com/5526219',
    );
    const quality = LivePlayQuality(
      id: '0',
      label: '原画2K30',
      sortOrder: 6191,
      metadata: {
        'qualityMap': {0: '原画2K30', 2: '高清'},
      },
    );
    final useCase = ResolvePlaySourceUseCase(registry);

    final resolved = await useCase(
      providerId: ProviderId.douyu,
      detail: detail,
      quality: quality,
    );

    expect(resolved.isQualityFallback, isTrue);
    expect(resolved.effectiveQuality.id, '2');
    expect(resolved.effectiveQuality.label, '高清');
  });
}

class _FakePlayUrlProvider extends LiveProvider implements SupportsPlayUrls {
  @override
  ProviderDescriptor get descriptor => const ProviderDescriptor(
        id: ProviderId('test'),
        displayName: 'Test Provider',
        capabilities: {ProviderCapability.playUrls},
        supportedPlatforms: {ProviderPlatform.android},
        maturity: ProviderMaturity.ready,
      );

  @override
  Future<List<LivePlayUrl>> fetchPlayUrls({
    required LiveRoomDetail detail,
    required LivePlayQuality quality,
  }) async {
    return const [
      LivePlayUrl(url: 'http://example.com/live.flv'),
      LivePlayUrl(url: 'https://example.com/live.flv'),
    ];
  }
}

class _FakeBilibiliPlayUrlProvider extends LiveProvider
    implements SupportsPlayUrls {
  @override
  ProviderDescriptor get descriptor => const ProviderDescriptor(
        id: ProviderId.bilibili,
        displayName: '哔哩哔哩',
        capabilities: {ProviderCapability.playUrls},
        supportedPlatforms: {ProviderPlatform.android},
        maturity: ProviderMaturity.ready,
      );

  @override
  Future<List<LivePlayUrl>> fetchPlayUrls({
    required LiveRoomDetail detail,
    required LivePlayQuality quality,
  }) async {
    return const [
      LivePlayUrl(
        url: 'https://example.com/live.flv?qn=250&expected_qn=250',
      ),
    ];
  }
}

class _FakeDouyuPreferredLineProvider extends LiveProvider
    implements SupportsPlayUrls {
  @override
  ProviderDescriptor get descriptor => const ProviderDescriptor(
        id: ProviderId.douyu,
        displayName: '斗鱼',
        capabilities: {ProviderCapability.playUrls},
        supportedPlatforms: {ProviderPlatform.android},
        maturity: ProviderMaturity.ready,
      );

  @override
  Future<List<LivePlayUrl>> fetchPlayUrls({
    required LiveRoomDetail detail,
    required LivePlayQuality quality,
  }) async {
    return const [
      LivePlayUrl(
        url: 'https://example.com/fallback.flv',
        metadata: {'rate': 2},
      ),
      LivePlayUrl(
        url: 'https://example.com/origin.flv',
        metadata: {'rate': 0},
      ),
    ];
  }
}

class _FakeDouyuFallbackProvider extends LiveProvider
    implements SupportsPlayUrls {
  @override
  ProviderDescriptor get descriptor => const ProviderDescriptor(
        id: ProviderId.douyu,
        displayName: '斗鱼',
        capabilities: {ProviderCapability.playUrls},
        supportedPlatforms: {ProviderPlatform.android},
        maturity: ProviderMaturity.ready,
      );

  @override
  Future<List<LivePlayUrl>> fetchPlayUrls({
    required LiveRoomDetail detail,
    required LivePlayQuality quality,
  }) async {
    return const [
      LivePlayUrl(
        url: 'https://example.com/fallback-only.flv',
        metadata: {'rate': 2},
      ),
    ];
  }
}
