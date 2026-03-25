import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_providers/live_providers.dart';
import 'package:nolive_app/src/features/room/application/resolve_play_source_use_case.dart';
import 'package:nolive_app/src/features/room/application/twitch_ad_guard_proxy.dart';

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

  test('resolve play source maps external audio metadata into playback source',
      () async {
    final registry = ProviderRegistry()
      ..register(
        ProviderRegistration(
          descriptor: const ProviderDescriptor(
            id: ProviderId.youtube,
            displayName: 'YouTube',
            capabilities: {ProviderCapability.playUrls},
            supportedPlatforms: {ProviderPlatform.android},
            maturity: ProviderMaturity.ready,
          ),
          builder: _FakeYouTubeExternalAudioProvider.new,
        ),
      );
    const detail = LiveRoomDetail(
      providerId: 'youtube',
      roomId: '@NBCNews/live',
      title: 'NBC News',
      streamerName: 'NBC News',
      isLive: true,
      sourceUrl: 'https://www.youtube.com/watch?v=test',
    );
    const quality = LivePlayQuality(
      id: '1080',
      label: '1080p',
      sortOrder: 1080,
    );
    final useCase = ResolvePlaySourceUseCase(registry);

    final resolved = await useCase(
      providerId: ProviderId.youtube,
      detail: detail,
      quality: quality,
    );

    expect(
      resolved.playbackSource.url.toString(),
      'https://video.example.com/1080p60.m3u8',
    );
    expect(
      resolved.playbackSource.externalAudio?.url.toString(),
      'https://audio.example.com/track.m4a',
    );
    expect(
      resolved.playbackSource.externalAudio?.headers['referer'],
      'https://m.youtube.com/watch?v=test',
    );
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

  test('resolve play source proxies twitch playlists through ad guard',
      () async {
    final registry = ProviderRegistry()
      ..register(
        ProviderRegistration(
          descriptor: const ProviderDescriptor(
            id: ProviderId.twitch,
            displayName: 'Twitch',
            capabilities: {ProviderCapability.playUrls},
            supportedPlatforms: {ProviderPlatform.android},
            maturity: ProviderMaturity.ready,
          ),
          builder: _FakeTwitchPlayUrlProvider.new,
        ),
      );
    const detail = LiveRoomDetail(
      providerId: 'twitch',
      roomId: 'xqc',
      title: 'Twitch Room',
      streamerName: 'Tester',
      isLive: true,
      sourceUrl: 'https://www.twitch.tv/xqc',
    );
    final quality = LivePlayQuality(
      id: 'auto',
      label: 'Auto',
      isDefault: true,
      metadata: {
        'twitchPlaybackGroups': [
          TwitchPlaybackQualityGroup(
            id: '720p',
            label: '720p',
            sortOrder: 720,
            bandwidth: 3200000,
            width: 1280,
            height: 720,
            frameRate: 60,
            codecs: 'avc1.640020,mp4a.40.2',
            candidates: [
              TwitchPlaybackCandidate(
                playlistUrl: 'https://usher.ttvnw.net/720p.m3u8',
                headers: {},
                playerType: 'embed',
                platform: 'web',
                lineLabel: '优选 Embed',
              ),
            ],
          ).toJson(),
        ],
        'twitchPlaybackCandidates': [
          TwitchPlaybackCandidate(
            playlistUrl: 'https://usher.ttvnw.net/master.m3u8',
            headers: {},
            playerType: 'embed',
            platform: 'web',
            lineLabel: '优选 Embed',
          ).toJson(),
        ],
      },
    );
    final proxy = TwitchAdGuardProxy(enabledOverride: true);
    addTearDown(proxy.dispose);
    final useCase = ResolvePlaySourceUseCase(
      registry,
      twitchAdGuardProxy: proxy,
    );

    final resolved = await useCase(
      providerId: ProviderId.twitch,
      detail: detail,
      quality: quality,
    );

    expect(
      resolved.playbackSource.url.toString(),
      contains('127.0.0.1'),
    );
    expect(resolved.playbackSource.url.path, contains('twitch-ad-guard'));
    expect(resolved.playUrls.first.metadata?['proxied'], isTrue);
  });

  test('resolve play source prefers twitch popout line before site', () async {
    final registry = ProviderRegistry()
      ..register(
        ProviderRegistration(
          descriptor: const ProviderDescriptor(
            id: ProviderId.twitch,
            displayName: 'Twitch',
            capabilities: {ProviderCapability.playUrls},
            supportedPlatforms: {ProviderPlatform.android},
            maturity: ProviderMaturity.ready,
          ),
          builder: _FakeTwitchPreferredLineProvider.new,
        ),
      );
    const detail = LiveRoomDetail(
      providerId: 'twitch',
      roomId: 'xqc',
      title: 'Twitch Room',
      streamerName: 'Tester',
      isLive: true,
      sourceUrl: 'https://www.twitch.tv/xqc',
    );
    const quality = LivePlayQuality(
      id: 'auto',
      label: 'Auto',
      isDefault: true,
    );
    final useCase = ResolvePlaySourceUseCase(registry);

    final resolved = await useCase(
      providerId: ProviderId.twitch,
      detail: detail,
      quality: quality,
    );

    expect(resolved.playbackSource.url.toString(), contains('popout.m3u8'));
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

class _FakeYouTubeExternalAudioProvider extends LiveProvider
    implements SupportsPlayUrls {
  @override
  ProviderDescriptor get descriptor => const ProviderDescriptor(
        id: ProviderId.youtube,
        displayName: 'YouTube',
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
        url: 'https://video.example.com/1080p60.m3u8',
        headers: {'referer': 'https://m.youtube.com/watch?v=test'},
        metadata: {
          'audioUrl': 'https://audio.example.com/track.m4a',
          'audioHeaders': {'referer': 'https://m.youtube.com/watch?v=test'},
          'audioMimeType': 'audio/mp4',
          'audioLineLabel': 'iOS Audio',
        },
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

class _FakeTwitchPlayUrlProvider extends LiveProvider
    implements SupportsPlayUrls {
  @override
  ProviderDescriptor get descriptor => const ProviderDescriptor(
        id: ProviderId.twitch,
        displayName: 'Twitch',
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
        url: 'https://usher.ttvnw.net/master.m3u8',
        lineLabel: '优选 Embed',
        metadata: {'playerType': 'embed'},
      ),
    ];
  }
}

class _FakeTwitchPreferredLineProvider extends LiveProvider
    implements SupportsPlayUrls {
  @override
  ProviderDescriptor get descriptor => const ProviderDescriptor(
        id: ProviderId.twitch,
        displayName: 'Twitch',
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
        url: 'https://usher.ttvnw.net/popout.m3u8',
        lineLabel: '默认 Popout',
        metadata: {'playerType': 'popout'},
      ),
      LivePlayUrl(
        url: 'https://usher.ttvnw.net/site.m3u8',
        lineLabel: '备用 Site',
        metadata: {'playerType': 'site'},
      ),
      LivePlayUrl(
        url: 'https://usher.ttvnw.net/embed.m3u8',
        lineLabel: '备用 Embed',
        metadata: {'playerType': 'embed'},
      ),
    ];
  }
}
