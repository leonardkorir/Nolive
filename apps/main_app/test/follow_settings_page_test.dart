import 'package:live_core/live_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_storage/live_storage.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';
import 'package:nolive_app/src/features/settings/presentation/follow_settings_page.dart';

void main() {
  testWidgets('follow settings page shows tags and import tools only', (
    tester,
  ) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    await bootstrap.createTag('夜班');
    await bootstrap.followRepository.upsert(
      const FollowRecord(
        providerId: 'bilibili',
        roomId: '6',
        streamerName: '系统演示主播',
        tags: ['夜班'],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(home: FollowSettingsPage(bootstrap: bootstrap)),
    );
    await tester.pumpAndSettle();

    expect(find.text('关注设置'), findsWidgets);
    expect(find.text('标签管理'), findsOneWidget);
    expect(find.text('直播状态更新'), findsOneWidget);
    expect(find.text('自动更新关注直播状态'), findsOneWidget);
    expect(find.byKey(const Key('follow-settings-add-tag-button')),
        findsOneWidget);
    expect(find.text('夜班'), findsWidgets);
    await tester.scrollUntilVisible(
      find.text('列表显示'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('列表显示'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('关注导入导出'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('关注导入导出'), findsOneWidget);
    expect(find.text('数据工具'), findsNothing);
    expect(find.text('关注列表'), findsNothing);
  });

  testWidgets('follow settings page does not fetch remote room details', (
    tester,
  ) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    var detailCalls = 0;

    bootstrap.providerRegistry.register(
      ProviderRegistration(
        descriptor: _kFollowSettingsTestDescriptor,
        builder: () => _FollowSettingsTestProvider(
          onRoomDetail: (roomId) async {
            detailCalls += 1;
            return LiveRoomDetail(
              providerId: _kFollowSettingsTestProviderId.value,
              roomId: roomId,
              title: '$roomId-title',
              streamerName: roomId,
              sourceUrl: 'https://example.com/$roomId',
              isLive: true,
            );
          },
        ),
      ),
    );
    bootstrap.providerRegistry.clearCache();

    await bootstrap.followRepository.upsert(
      const FollowRecord(
        providerId: 'follow_settings_test',
        roomId: 'room-1',
        streamerName: '本地关注房间',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(home: FollowSettingsPage(bootstrap: bootstrap)),
    );
    await tester.pumpAndSettle();

    expect(detailCalls, 0);
  });
}

const _kFollowSettingsTestProviderId = ProviderId('follow_settings_test');

const _kFollowSettingsTestDescriptor = ProviderDescriptor(
  id: _kFollowSettingsTestProviderId,
  displayName: 'Follow Settings Test',
  capabilities: {
    ProviderCapability.roomDetail,
    ProviderCapability.playQualities,
    ProviderCapability.playUrls,
  },
  supportedPlatforms: {ProviderPlatform.android},
  maturity: ProviderMaturity.ready,
);

class _FollowSettingsTestProvider extends LiveProvider
    implements SupportsRoomDetail, SupportsPlayQualities, SupportsPlayUrls {
  _FollowSettingsTestProvider({required this.onRoomDetail});

  final Future<LiveRoomDetail> Function(String roomId) onRoomDetail;

  @override
  ProviderDescriptor get descriptor => _kFollowSettingsTestDescriptor;

  @override
  Future<LiveRoomDetail> fetchRoomDetail(String roomId) => onRoomDetail(roomId);

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
