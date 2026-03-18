import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';
import 'package:nolive_app/src/features/settings/application/manage_history_preferences_use_case.dart';

void main() {
  test('history preferences load defaults and persist updates', () async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);

    expect(
      await bootstrap.loadHistoryPreferences(),
      const HistoryPreferences(recordWatchHistory: true),
    );

    const next = HistoryPreferences(recordWatchHistory: false);
    await bootstrap.updateHistoryPreferences(next);

    expect(await bootstrap.loadHistoryPreferences(), next);
  });

  test('load room honors disabled history recording preference', () async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    bootstrap.providerRegistry.register(
      ProviderRegistration(
        descriptor: _kHistoryPreferenceDescriptor,
        builder: () => _HistoryPreferenceProvider(),
      ),
    );
    bootstrap.providerRegistry.clearCache();

    await bootstrap.updateHistoryPreferences(
      const HistoryPreferences(recordWatchHistory: false),
    );
    await bootstrap.loadRoom(
      providerId: _kHistoryPreferenceProviderId,
      roomId: 'demo-room',
    );

    expect((await bootstrap.listLibrarySnapshot()).history, isEmpty);

    await bootstrap.updateHistoryPreferences(
      const HistoryPreferences(recordWatchHistory: true),
    );
    await bootstrap.loadRoom(
      providerId: _kHistoryPreferenceProviderId,
      roomId: 'demo-room',
    );

    expect((await bootstrap.listLibrarySnapshot()).history, hasLength(1));
  });
}

const _kHistoryPreferenceProviderId = ProviderId('history_preference_test');

const _kHistoryPreferenceDescriptor = ProviderDescriptor(
  id: _kHistoryPreferenceProviderId,
  displayName: 'History Preference Test',
  capabilities: {
    ProviderCapability.roomDetail,
    ProviderCapability.playQualities,
    ProviderCapability.playUrls,
  },
  supportedPlatforms: {ProviderPlatform.android},
  maturity: ProviderMaturity.ready,
);

class _HistoryPreferenceProvider extends LiveProvider
    implements SupportsRoomDetail, SupportsPlayQualities, SupportsPlayUrls {
  @override
  ProviderDescriptor get descriptor => _kHistoryPreferenceDescriptor;

  @override
  Future<LiveRoomDetail> fetchRoomDetail(String roomId) async {
    return LiveRoomDetail(
      providerId: _kHistoryPreferenceProviderId.value,
      roomId: roomId,
      title: 'demo-title',
      streamerName: 'demo-streamer',
      sourceUrl: 'https://example.com/$roomId',
      isLive: true,
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
    return const [
      LivePlayUrl(url: 'https://example.com/live.m3u8'),
    ];
  }
}
