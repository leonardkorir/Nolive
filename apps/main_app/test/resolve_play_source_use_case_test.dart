import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
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

  test('resolve play source prefers bilibili url matching requested qn',
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
          builder: _FakeBilibiliMixedQnPlayUrlProvider.new,
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
        'qualityMap': {250: '超清', 10000: '原画'},
      },
    );
    final useCase = ResolvePlaySourceUseCase(registry);

    final resolved = await useCase(
      providerId: ProviderId.bilibili,
      detail: detail,
      quality: quality,
    );

    expect(resolved.isQualityFallback, isFalse);
    expect(
        resolved.playbackSource.url.toString(), contains('expected_qn=10000'));
    expect(resolved.effectiveQuality.id, '10000');
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

  test('playback source maps preferred hls bitrate metadata', () {
    const playUrl = LivePlayUrl(
      url:
          'https://edge11-lax.live.mmcdn.com/v1/edge/streams/origin.demo/llhls.m3u8?token=test',
      metadata: {
        'masterPlaylistUrl':
            'https://edge11-lax.live.mmcdn.com/v1/edge/streams/origin.demo/master.m3u8?token=test',
        'hlsBitrate': '5128000',
      },
    );

    final source = playbackSourceFromLivePlayUrl(
      playUrl,
      quality: const LivePlayQuality(
        id: '5128000',
        label: '1080p',
        sortOrder: 1080,
      ),
    );

    expect(source.url.toString(), playUrl.url);
    expect(
      source.masterPlaylistUrl?.toString(),
      'https://edge11-lax.live.mmcdn.com/v1/edge/streams/origin.demo/master.m3u8?token=test',
    );
    expect(source.hlsBitrate, '5128000');
    expect(source.externalAudio, isNull);
  });

  test('resolve play source marks 1440p stream as heavy stable', () async {
    final registry = ProviderRegistry()
      ..register(
        ProviderRegistration(
          descriptor: const ProviderDescriptor(
            id: ProviderId('heavy-resolution'),
            displayName: 'Heavy Resolution',
            capabilities: {ProviderCapability.playUrls},
            supportedPlatforms: {ProviderPlatform.android},
            maturity: ProviderMaturity.ready,
          ),
          builder: _FakeHeavyResolutionProvider.new,
        ),
      );
    const detail = LiveRoomDetail(
      providerId: 'heavy-resolution',
      roomId: '1',
      title: 'Test Room',
      streamerName: 'Tester',
      isLive: true,
      sourceUrl: 'https://example.com/room/1',
    );
    const quality = LivePlayQuality(
      id: 'hd',
      label: '高清',
      sortOrder: 100,
    );
    final useCase = ResolvePlaySourceUseCase(registry);

    final resolved = await useCase(
      providerId: const ProviderId('heavy-resolution'),
      detail: detail,
      quality: quality,
    );

    expect(
      resolved.playbackSource.bufferProfile,
      PlaybackBufferProfile.heavyStreamStable,
    );
  });

  test('resolve play source marks high bandwidth stream as heavy stable',
      () async {
    final registry = ProviderRegistry()
      ..register(
        ProviderRegistration(
          descriptor: const ProviderDescriptor(
            id: ProviderId('heavy-bandwidth'),
            displayName: 'Heavy Bandwidth',
            capabilities: {ProviderCapability.playUrls},
            supportedPlatforms: {ProviderPlatform.android},
            maturity: ProviderMaturity.ready,
          ),
          builder: _FakeHeavyBandwidthProvider.new,
        ),
      );
    const detail = LiveRoomDetail(
      providerId: 'heavy-bandwidth',
      roomId: '1',
      title: 'Test Room',
      streamerName: 'Tester',
      isLive: true,
      sourceUrl: 'https://example.com/room/1',
    );
    const quality = LivePlayQuality(
      id: 'origin',
      label: '流畅',
      sortOrder: 100,
    );
    final useCase = ResolvePlaySourceUseCase(registry);

    final resolved = await useCase(
      providerId: const ProviderId('heavy-bandwidth'),
      detail: detail,
      quality: quality,
    );

    expect(
      resolved.playbackSource.bufferProfile,
      PlaybackBufferProfile.heavyStreamStable,
    );
  });

  test('resolve play source marks blue-ray quality label as heavy stable',
      () async {
    final registry = ProviderRegistry()
      ..register(
        ProviderRegistration(
          descriptor: const ProviderDescriptor(
            id: ProviderId('heavy-label'),
            displayName: 'Heavy Label',
            capabilities: {ProviderCapability.playUrls},
            supportedPlatforms: {ProviderPlatform.android},
            maturity: ProviderMaturity.ready,
          ),
          builder: _FakeHeavyLabelProvider.new,
        ),
      );
    const detail = LiveRoomDetail(
      providerId: 'heavy-label',
      roomId: '1',
      title: 'Test Room',
      streamerName: 'Tester',
      isLive: true,
      sourceUrl: 'https://example.com/room/1',
    );
    const quality = LivePlayQuality(
      id: 'origin',
      label: '蓝光30M',
      sortOrder: 100,
    );
    final useCase = ResolvePlaySourceUseCase(registry);

    final resolved = await useCase(
      providerId: const ProviderId('heavy-label'),
      detail: detail,
      quality: quality,
    );

    expect(
      resolved.playbackSource.bufferProfile,
      PlaybackBufferProfile.heavyStreamStable,
    );
  });

  test(
      'resolve play source maps mmcdn edge ll-hls onto dedicated low latency profile',
      () async {
    const playUrl = LivePlayUrl(
      url:
          'https://edge2-lax.live.mmcdn.com/v1/edge/streams/origin.demo/chunklist_4_video_1816682507370709677_llhls.m3u8',
      metadata: {
        'audioUrl':
            'https://edge2-lax.live.mmcdn.com/v1/edge/streams/origin.demo/chunklist_6_audio_1816682507370709677_llhls.m3u8',
      },
    );
    const quality = LivePlayQuality(
      id: '1080',
      label: '1080p',
      sortOrder: 1080,
    );

    expect(
      resolvePlaybackBufferProfile(playUrl: playUrl, quality: quality),
      PlaybackBufferProfile.edgeLowLatencyHls,
    );
  });

  test(
      'resolve play source maps mmcdn live-hls chunklist onto dedicated low latency profile',
      () async {
    const playUrl = LivePlayUrl(
      url:
          'https://edge19-phx.live.mmcdn.com/live-hls/amlst:maca_hugo-sd-demo/chunklist_w525982405_b2796000_t64RlBTOjI5.m3u8',
    );
    const quality = LivePlayQuality(
      id: '2796000',
      label: '720p',
      sortOrder: 720,
    );

    expect(
      resolvePlaybackBufferProfile(playUrl: playUrl, quality: quality),
      PlaybackBufferProfile.edgeLowLatencyHls,
    );
  });

  test('resolve play source keeps default low latency profile for plain stream',
      () async {
    final registry = ProviderRegistry()
      ..register(
        ProviderRegistration(
          descriptor: const ProviderDescriptor(
            id: ProviderId('plain-profile'),
            displayName: 'Plain Profile',
            capabilities: {ProviderCapability.playUrls},
            supportedPlatforms: {ProviderPlatform.android},
            maturity: ProviderMaturity.ready,
          ),
          builder: _FakePlainPlayUrlProvider.new,
        ),
      );
    const detail = LiveRoomDetail(
      providerId: 'plain-profile',
      roomId: '1',
      title: 'Test Room',
      streamerName: 'Tester',
      isLive: true,
      sourceUrl: 'https://example.com/room/1',
    );
    const quality = LivePlayQuality(
      id: '1080',
      label: '1080p',
      sortOrder: 100,
    );
    final useCase = ResolvePlaySourceUseCase(registry);

    final resolved = await useCase(
      providerId: const ProviderId('plain-profile'),
      detail: detail,
      quality: quality,
    );

    expect(
      resolved.playbackSource.bufferProfile,
      PlaybackBufferProfile.defaultLowLatency,
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
    var wrapCalls = 0;
    final useCase = ResolvePlaySourceUseCase(
      registry,
      wrapTwitchPlayUrls: ({
        required quality,
        required playUrls,
      }) async {
        wrapCalls += 1;
        return [
          LivePlayUrl(
            url: 'http://127.0.0.1:9999/twitch-ad-guard/session/stream.m3u8',
            headers: const {},
            lineLabel: playUrls.first.lineLabel,
            metadata: {
              ...?playUrls.first.metadata,
              'proxied': true,
              'upstreamUrl': playUrls.first.url,
            },
          ),
        ];
      },
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
    expect(wrapCalls, 1);
  });

  test('resolve play source keeps chaturbate mmcdn fallback on stable profile',
      () async {
    final registry = ProviderRegistry()
      ..register(
        ProviderRegistration(
          descriptor: const ProviderDescriptor(
            id: ProviderId.chaturbate,
            displayName: 'Chaturbate',
            capabilities: {ProviderCapability.playUrls},
            supportedPlatforms: {ProviderPlatform.android},
            maturity: ProviderMaturity.ready,
          ),
          builder: _FakeChaturbateMasterHlsProvider.new,
        ),
      );
    const detail = LiveRoomDetail(
      providerId: 'chaturbate',
      roomId: 'xdreamangel',
      title: 'Chaturbate Room',
      streamerName: 'Tester',
      isLive: true,
      sourceUrl: 'https://chaturbate.com/xdreamangel/',
    );
    const quality = LivePlayQuality(
      id: '1830000',
      label: '540p',
      sortOrder: 540,
    );
    final useCase = ResolvePlaySourceUseCase(
      registry,
      wrapChaturbatePlayUrls: ({
        required quality,
        required playUrls,
      }) async =>
          playUrls,
    );

    final resolved = await useCase(
      providerId: ProviderId.chaturbate,
      detail: detail,
      quality: quality,
    );

    expect(
      resolved.playbackSource.bufferProfile,
      PlaybackBufferProfile.chaturbateLlHlsProxyStable,
    );
    expect(
      resolved.playUrls.first.metadata?['chaturbateStableFallback'],
      isTrue,
    );
    expect(
      resolved.playUrls.first.metadata?['chaturbateProxyFallbackReason'],
      'proxy-unavailable',
    );
  });

  test('resolve play source wraps chaturbate ll-hls when proxy is available',
      () async {
    final registry = ProviderRegistry()
      ..register(
        ProviderRegistration(
          descriptor: const ProviderDescriptor(
            id: ProviderId.chaturbate,
            displayName: 'Chaturbate',
            capabilities: {ProviderCapability.playUrls},
            supportedPlatforms: {ProviderPlatform.android},
            maturity: ProviderMaturity.ready,
          ),
          builder: _FakeChaturbateSplitLlHlsProvider.new,
        ),
      );
    const detail = LiveRoomDetail(
      providerId: 'chaturbate',
      roomId: 'demo',
      title: 'Chaturbate Room',
      streamerName: 'Tester',
      isLive: true,
      sourceUrl: 'https://chaturbate.com/demo/',
    );
    const quality = LivePlayQuality(
      id: '2096000',
      label: '540p',
      sortOrder: 540,
    );
    var wrapCalls = 0;
    final useCase = ResolvePlaySourceUseCase(
      registry,
      wrapChaturbatePlayUrls: ({
        required quality,
        required playUrls,
      }) async {
        wrapCalls += 1;
        return [
          LivePlayUrl(
            url: 'http://127.0.0.1:9999/chaturbate-llhls/session/stream.m3u8',
            headers: const {},
            lineLabel: playUrls.first.lineLabel,
            metadata: {
              'proxied': true,
              'proxyKind': 'chaturbate-llhls',
              'upstreamUrl': playUrls.first.url,
            },
          ),
        ];
      },
    );

    final resolved = await useCase(
      providerId: ProviderId.chaturbate,
      detail: detail,
      quality: quality,
    );

    expect(
      resolved.playbackSource.url.toString(),
      contains('127.0.0.1'),
    );
    expect(resolved.playbackSource.url.path, contains('chaturbate-llhls'));
    expect(resolved.playbackSource.externalAudio, isNull);
    expect(
      resolved.playbackSource.bufferProfile,
      PlaybackBufferProfile.chaturbateLlHlsProxyStable,
    );
    expect(resolved.playUrls.first.metadata?['proxied'], isTrue);
    expect(wrapCalls, 1);
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

class _FakeBilibiliMixedQnPlayUrlProvider extends LiveProvider
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
        url: 'https://example.com/live-low.flv?qn=250&expected_qn=250',
        metadata: {'qn': 250, 'expectedQn': 250},
      ),
      LivePlayUrl(
        url: 'https://example.com/live-origin.flv?qn=10000&expected_qn=10000',
        metadata: {'qn': 10000, 'expectedQn': 10000},
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

class _FakeHeavyResolutionProvider extends LiveProvider
    implements SupportsPlayUrls {
  @override
  ProviderDescriptor get descriptor => const ProviderDescriptor(
        id: ProviderId('heavy-resolution'),
        displayName: 'Heavy Resolution',
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
        url: 'https://example.com/1440p.m3u8',
        metadata: {
          'width': 2560,
          'height': 1440,
        },
      ),
    ];
  }
}

class _FakeHeavyBandwidthProvider extends LiveProvider
    implements SupportsPlayUrls {
  @override
  ProviderDescriptor get descriptor => const ProviderDescriptor(
        id: ProviderId('heavy-bandwidth'),
        displayName: 'Heavy Bandwidth',
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
        url: 'https://example.com/heavy.m3u8',
        metadata: {
          'bandwidth': 15000000,
        },
      ),
    ];
  }
}

class _FakeHeavyLabelProvider extends LiveProvider implements SupportsPlayUrls {
  @override
  ProviderDescriptor get descriptor => const ProviderDescriptor(
        id: ProviderId('heavy-label'),
        displayName: 'Heavy Label',
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
        url: 'https://example.com/plain.m3u8',
      ),
    ];
  }
}

class _FakePlainPlayUrlProvider extends LiveProvider
    implements SupportsPlayUrls {
  @override
  ProviderDescriptor get descriptor => const ProviderDescriptor(
        id: ProviderId('plain-profile'),
        displayName: 'Plain Profile',
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
        url: 'https://example.com/plain.m3u8',
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

class _FakeChaturbateMasterHlsProvider extends LiveProvider
    implements SupportsPlayUrls {
  @override
  ProviderDescriptor get descriptor => const ProviderDescriptor(
        id: ProviderId.chaturbate,
        displayName: 'Chaturbate',
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
        url:
            'https://edge9-phx.live.mmcdn.com/live-hls/amlst:xdreamangel-sd-demo/playlist.m3u8',
        headers: {'referer': 'https://chaturbate.com/xdreamangel/'},
        lineLabel: 'PHX',
        metadata: {
          'bandwidth': 1830000,
          'width': 960,
          'height': 540,
        },
      ),
    ];
  }
}

class _FakeChaturbateSplitLlHlsProvider extends LiveProvider
    implements SupportsPlayUrls {
  @override
  ProviderDescriptor get descriptor => const ProviderDescriptor(
        id: ProviderId.chaturbate,
        displayName: 'Chaturbate',
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
        url:
            'https://edge11-lax.live.mmcdn.com/v1/edge/streams/origin.demo/chunklist_2_video_llhls.m3u8?session=test',
        headers: {'referer': 'https://chaturbate.com/demo/'},
        lineLabel: 'LAX',
        metadata: {
          'audioUrl':
              'https://edge11-lax.live.mmcdn.com/v1/edge/streams/origin.demo/chunklist_7_audio_llhls.m3u8?session=test',
          'audioHeaders': {'referer': 'https://chaturbate.com/demo/'},
          'bandwidth': 2096000,
          'width': 960,
          'height': 540,
        },
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
