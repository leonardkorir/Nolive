import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_providers/live_providers.dart';
import 'package:live_storage/live_storage.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';
import 'package:nolive_app/src/features/room/application/load_room_use_case.dart';

void main() {
  test('load room skips history writes when recordHistory is false', () async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);

    await bootstrap.loadRoom(
      providerId: ProviderId.bilibili,
      roomId: '6',
    );
    final firstRecord = (await bootstrap.historyRepository.listRecent()).single;

    await Future<void>.delayed(const Duration(milliseconds: 10));
    await bootstrap.loadRoom(
      providerId: ProviderId.bilibili,
      roomId: '6',
      recordHistory: false,
    );

    final history = await bootstrap.historyRepository.listRecent();
    expect(history, hasLength(1));
    expect(history.single.viewedAt, firstRecord.viewedAt);
  });

  test(
      'load room falls back to injected room detail override on provider failure',
      () async {
    _OverrideRoomProvider.fetchRoomDetailCalls = 0;
    final registry = ProviderRegistry()
      ..register(
        ProviderRegistration(
          descriptor: _kOverrideDescriptor,
          builder: _OverrideRoomProvider.new,
        ),
      );
    final historyRepository = InMemoryHistoryRepository();
    final useCase = LoadRoomUseCase(
      registry,
      historyRepository: historyRepository,
      roomDetailOverride: ({
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
          metadata: const {'hlsSource': 'https://example.com/live.m3u8'},
        );
      },
    );

    final snapshot = await useCase(
      providerId: ProviderId.chaturbate,
      roomId: 'milabunny_',
    );

    expect(snapshot.detail.roomId, 'milabunny_');
    expect(snapshot.detail.title, 'override room');
    expect(snapshot.playUrls.single.url, 'https://example.com/live.m3u8');
    expect(_OverrideRoomProvider.fetchRoomDetailCalls, 1);
  });

  test('load room prefers provider detail before injected override', () async {
    final registry = ProviderRegistry()
      ..register(
        ProviderRegistration(
          descriptor: _kStableChaturbateDescriptor,
          builder: _StableChaturbateProvider.new,
        ),
      );
    final useCase = LoadRoomUseCase(
      registry,
      historyRepository: InMemoryHistoryRepository(),
      roomDetailOverride: ({
        required providerId,
        required roomId,
      }) async {
        return LiveRoomDetail(
          providerId: providerId.value,
          roomId: roomId,
          title: 'override room',
          streamerName: roomId,
          isLive: true,
          metadata: const {'hlsSource': 'https://example.com/override.m3u8'},
        );
      },
    );

    final snapshot = await useCase(
      providerId: ProviderId.chaturbate,
      roomId: 'dewdropdoll',
      preferHighestQuality: true,
    );

    expect(snapshot.detail.title, isNot('override room'));
    expect(snapshot.playUrls.single.url, contains('/480p.m3u8'));
  });

  test('load room keeps chaturbate private show rooms openable', () async {
    final registry = ProviderRegistry()
      ..register(
        ProviderRegistration(
          descriptor: _kPrivateShowDescriptor,
          builder: _PrivateShowProvider.new,
        ),
      );
    final useCase = LoadRoomUseCase(
      registry,
      historyRepository: InMemoryHistoryRepository(),
    );

    final snapshot = await useCase(
      providerId: ProviderId.chaturbate,
      roomId: 'consuelabrasington',
    );

    expect(snapshot.detail.roomId, 'consuelabrasington');
    expect(snapshot.detail.isLive, isFalse);
    expect(snapshot.hasPlayback, isFalse);
    expect(snapshot.playUrls, isEmpty);
    expect(
      snapshot.playbackUnavailableReason,
      contains('private show in progress'),
    );
  });

  test('load room keeps generic offline rooms openable without qualities',
      () async {
    final registry = ProviderRegistry()
      ..register(
        ProviderRegistration(
          descriptor: _kOfflineDescriptor,
          builder: _OfflineProvider.new,
        ),
      );
    final useCase = LoadRoomUseCase(
      registry,
      historyRepository: InMemoryHistoryRepository(),
    );

    final snapshot = await useCase(
      providerId: _kOfflineProviderId,
      roomId: 'offline-room',
    );

    expect(snapshot.detail.isLive, isFalse);
    expect(snapshot.hasPlayback, isFalse);
    expect(snapshot.qualities.single.id, 'unavailable');
    expect(snapshot.selectedQuality.id, 'unavailable');
    expect(snapshot.playbackUnavailableReason, contains('暂未开播'));
  });

  test('load room keeps restricted rooms openable without playback urls',
      () async {
    final registry = ProviderRegistry()
      ..register(
        ProviderRegistration(
          descriptor: _kRestrictedDescriptor,
          builder: _RestrictedProvider.new,
        ),
      );
    final useCase = LoadRoomUseCase(
      registry,
      historyRepository: InMemoryHistoryRepository(),
    );

    final snapshot = await useCase(
      providerId: _kRestrictedProviderId,
      roomId: 'member-only-room',
    );

    expect(snapshot.detail.isLive, isTrue);
    expect(snapshot.hasPlayback, isFalse);
    expect(snapshot.selectedQuality.id, 'high');
    expect(snapshot.playbackUnavailableReason, contains('需要额外权限'));
  });

  test('load room keeps auto quality as default for twitch startup', () async {
    final registry = ProviderRegistry()
      ..register(
        ProviderRegistration(
          descriptor: _kTwitchDescriptor,
          builder: _TwitchDefaultQualityProvider.new,
        ),
      );
    final useCase = LoadRoomUseCase(
      registry,
      historyRepository: InMemoryHistoryRepository(),
    );

    final snapshot = await useCase(
      providerId: ProviderId.twitch,
      roomId: 'ow_esports_jp',
    );

    expect(snapshot.hasPlayback, isTrue);
    expect(snapshot.selectedQuality.id, 'auto');
    expect(snapshot.selectedQuality.label, 'Auto');
    expect(snapshot.playUrls.single.url, contains('auto.m3u8'));
  });

  test('load room still honors prefer highest quality for twitch', () async {
    final registry = ProviderRegistry()
      ..register(
        ProviderRegistration(
          descriptor: _kTwitchDescriptor,
          builder: _TwitchDefaultQualityProvider.new,
        ),
      );
    final useCase = LoadRoomUseCase(
      registry,
      historyRepository: InMemoryHistoryRepository(),
    );

    final snapshot = await useCase(
      providerId: ProviderId.twitch,
      roomId: 'ow_esports_jp',
      preferHighestQuality: true,
    );

    expect(snapshot.hasPlayback, isTrue);
    expect(snapshot.selectedQuality.id, '1080p60');
    expect(snapshot.playUrls.single.url, contains('1080p60'));
  });

  test('load room caps chaturbate startup quality to a safer fixed tier',
      () async {
    final registry = ProviderRegistry()
      ..register(
        ProviderRegistration(
          descriptor: _kStableChaturbateDescriptor,
          builder: _StableChaturbateProvider.new,
        ),
      );
    final useCase = LoadRoomUseCase(
      registry,
      historyRepository: InMemoryHistoryRepository(),
    );

    final snapshot = await useCase(
      providerId: ProviderId.chaturbate,
      roomId: 'dewdropdoll',
      preferHighestQuality: true,
    );

    expect(snapshot.hasPlayback, isTrue);
    expect(snapshot.selectedQuality.id, '1296000');
    expect(snapshot.selectedQuality.label, '480p');
    expect(snapshot.playUrls.single.url, contains('/480p.m3u8'));
  });
}

const _kOverrideDescriptor = ProviderDescriptor(
  id: ProviderId.chaturbate,
  displayName: 'Chaturbate',
  capabilities: {
    ProviderCapability.roomDetail,
    ProviderCapability.playQualities,
    ProviderCapability.playUrls,
  },
  supportedPlatforms: {ProviderPlatform.android},
  maturity: ProviderMaturity.inMigration,
);

class _OverrideRoomProvider extends LiveProvider
    implements SupportsRoomDetail, SupportsPlayQualities, SupportsPlayUrls {
  static int fetchRoomDetailCalls = 0;

  @override
  ProviderDescriptor get descriptor => _kOverrideDescriptor;

  @override
  Future<LiveRoomDetail> fetchRoomDetail(String roomId) {
    fetchRoomDetailCalls += 1;
    throw StateError('provider fetchRoomDetail should not be called');
  }

  @override
  Future<List<LivePlayQuality>> fetchPlayQualities(
      LiveRoomDetail detail) async {
    return const [
      LivePlayQuality(
        id: 'auto',
        label: 'Auto',
        isDefault: true,
      ),
    ];
  }

  @override
  Future<List<LivePlayUrl>> fetchPlayUrls({
    required LiveRoomDetail detail,
    required LivePlayQuality quality,
  }) async {
    return [
      LivePlayUrl(url: detail.metadata?['hlsSource']?.toString() ?? ''),
    ];
  }
}

const _kStableChaturbateDescriptor = ProviderDescriptor(
  id: ProviderId.chaturbate,
  displayName: 'Chaturbate',
  capabilities: {
    ProviderCapability.roomDetail,
    ProviderCapability.playQualities,
    ProviderCapability.playUrls,
  },
  supportedPlatforms: {ProviderPlatform.android},
  maturity: ProviderMaturity.inMigration,
);

class _StableChaturbateProvider extends LiveProvider
    implements SupportsRoomDetail, SupportsPlayQualities, SupportsPlayUrls {
  @override
  ProviderDescriptor get descriptor => _kStableChaturbateDescriptor;

  @override
  Future<LiveRoomDetail> fetchRoomDetail(String roomId) async {
    return LiveRoomDetail(
      providerId: ProviderId.chaturbate.value,
      roomId: roomId,
      title: roomId,
      streamerName: roomId,
      isLive: true,
    );
  }

  @override
  Future<List<LivePlayQuality>> fetchPlayQualities(
    LiveRoomDetail detail,
  ) async {
    return const [
      LivePlayQuality(id: 'auto', label: 'Auto', isDefault: true),
      LivePlayQuality(
        id: '1296000',
        label: '480p',
        sortOrder: 1296000,
        metadata: {'height': 480, 'bandwidth': 1296000},
      ),
      LivePlayQuality(
        id: '3600000',
        label: '720p',
        sortOrder: 3600000,
        metadata: {'height': 720, 'bandwidth': 3600000},
      ),
      LivePlayQuality(
        id: '5200000',
        label: '1080p',
        sortOrder: 5200000,
        metadata: {'height': 1080, 'bandwidth': 5200000},
      ),
    ];
  }

  @override
  Future<List<LivePlayUrl>> fetchPlayUrls({
    required LiveRoomDetail detail,
    required LivePlayQuality quality,
  }) async {
    return [
      LivePlayUrl(url: 'https://example.com/${quality.label}.m3u8'),
    ];
  }
}

const _kPrivateShowDescriptor = ProviderDescriptor(
  id: ProviderId.chaturbate,
  displayName: 'Chaturbate',
  capabilities: {
    ProviderCapability.roomDetail,
    ProviderCapability.playQualities,
    ProviderCapability.playUrls,
  },
  supportedPlatforms: {ProviderPlatform.android},
  maturity: ProviderMaturity.inMigration,
);

class _PrivateShowProvider extends LiveProvider
    implements SupportsRoomDetail, SupportsPlayQualities, SupportsPlayUrls {
  @override
  ProviderDescriptor get descriptor => _kPrivateShowDescriptor;

  @override
  Future<LiveRoomDetail> fetchRoomDetail(String roomId) async {
    return LiveRoomDetail(
      providerId: ProviderId.chaturbate.value,
      roomId: roomId,
      title: roomId,
      streamerName: roomId,
      isLive: false,
      metadata: const {
        'roomStatus': 'private show in progress',
      },
    );
  }

  @override
  Future<List<LivePlayQuality>> fetchPlayQualities(
    LiveRoomDetail detail,
  ) async {
    return const [
      LivePlayQuality(
        id: 'auto',
        label: 'Auto',
        isDefault: true,
      ),
    ];
  }

  @override
  Future<List<LivePlayUrl>> fetchPlayUrls({
    required LiveRoomDetail detail,
    required LivePlayQuality quality,
  }) async {
    return const [];
  }
}

const _kOfflineProviderId = ProviderId('offline_fixture');

const _kOfflineDescriptor = ProviderDescriptor(
  id: _kOfflineProviderId,
  displayName: 'Offline Fixture',
  capabilities: {
    ProviderCapability.roomDetail,
    ProviderCapability.playQualities,
    ProviderCapability.playUrls,
  },
  supportedPlatforms: {ProviderPlatform.android},
  maturity: ProviderMaturity.ready,
);

class _OfflineProvider extends LiveProvider
    implements SupportsRoomDetail, SupportsPlayQualities, SupportsPlayUrls {
  @override
  ProviderDescriptor get descriptor => _kOfflineDescriptor;

  @override
  Future<LiveRoomDetail> fetchRoomDetail(String roomId) async {
    return LiveRoomDetail(
      providerId: _kOfflineProviderId.value,
      roomId: roomId,
      title: 'offline-room',
      streamerName: 'offline-room',
      isLive: false,
    );
  }

  @override
  Future<List<LivePlayQuality>> fetchPlayQualities(
    LiveRoomDetail detail,
  ) async {
    return const [];
  }

  @override
  Future<List<LivePlayUrl>> fetchPlayUrls({
    required LiveRoomDetail detail,
    required LivePlayQuality quality,
  }) async {
    return const [];
  }
}

const _kRestrictedProviderId = ProviderId('restricted_fixture');

const _kRestrictedDescriptor = ProviderDescriptor(
  id: _kRestrictedProviderId,
  displayName: 'Restricted Fixture',
  capabilities: {
    ProviderCapability.roomDetail,
    ProviderCapability.playQualities,
    ProviderCapability.playUrls,
  },
  supportedPlatforms: {ProviderPlatform.android},
  maturity: ProviderMaturity.ready,
);

class _RestrictedProvider extends LiveProvider
    implements SupportsRoomDetail, SupportsPlayQualities, SupportsPlayUrls {
  @override
  ProviderDescriptor get descriptor => _kRestrictedDescriptor;

  @override
  Future<LiveRoomDetail> fetchRoomDetail(String roomId) async {
    return LiveRoomDetail(
      providerId: _kRestrictedProviderId.value,
      roomId: roomId,
      title: 'member-only-room',
      streamerName: 'member-only-room',
      isLive: true,
      metadata: const {
        'membersOnly': true,
      },
    );
  }

  @override
  Future<List<LivePlayQuality>> fetchPlayQualities(
    LiveRoomDetail detail,
  ) async {
    return const [
      LivePlayQuality(
        id: 'high',
        label: '高清',
        isDefault: true,
      ),
    ];
  }

  @override
  Future<List<LivePlayUrl>> fetchPlayUrls({
    required LiveRoomDetail detail,
    required LivePlayQuality quality,
  }) async {
    return const [];
  }
}

const _kTwitchDescriptor = ProviderDescriptor(
  id: ProviderId.twitch,
  displayName: 'Twitch',
  capabilities: {
    ProviderCapability.roomDetail,
    ProviderCapability.playQualities,
    ProviderCapability.playUrls,
  },
  supportedPlatforms: {ProviderPlatform.android},
  maturity: ProviderMaturity.ready,
);

class _TwitchDefaultQualityProvider extends LiveProvider
    implements SupportsRoomDetail, SupportsPlayQualities, SupportsPlayUrls {
  @override
  ProviderDescriptor get descriptor => _kTwitchDescriptor;

  @override
  Future<LiveRoomDetail> fetchRoomDetail(String roomId) async {
    return LiveRoomDetail(
      providerId: ProviderId.twitch.value,
      roomId: roomId,
      title: roomId,
      streamerName: roomId,
      isLive: true,
      sourceUrl: 'https://www.twitch.tv/$roomId',
    );
  }

  @override
  Future<List<LivePlayQuality>> fetchPlayQualities(
    LiveRoomDetail detail,
  ) async {
    return const [
      LivePlayQuality(
        id: 'auto',
        label: 'Auto',
        isDefault: true,
      ),
      LivePlayQuality(
        id: '1080p60',
        label: '1080p60',
        sortOrder: 1080,
      ),
      LivePlayQuality(
        id: '720p60',
        label: '720p60',
        sortOrder: 720,
      ),
    ];
  }

  @override
  Future<List<LivePlayUrl>> fetchPlayUrls({
    required LiveRoomDetail detail,
    required LivePlayQuality quality,
  }) async {
    return [
      LivePlayUrl(
        url: 'https://example.com/${quality.id}.m3u8',
      ),
    ];
  }
}
