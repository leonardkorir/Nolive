import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_storage/live_storage.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';
import 'package:nolive_app/src/app/shell/app_shell_page.dart';

void main() {
  testWidgets('app shell opens the first configured bottom tab by default',
      (tester) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);

    await tester.pumpWidget(
      MaterialApp(
        home: AppShellPage(bootstrap: bootstrap),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('全部'), findsOneWidget);
    expect(find.byKey(const Key('shell-tab-library')), findsOneWidget);
  });

  testWidgets('app shell keeps library page alive across tab switches',
      (tester) async {
    final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
    var detailCalls = 0;

    bootstrap.providerRegistry.register(
      ProviderRegistration(
        descriptor: _kAppShellFollowDescriptor,
        builder: () => _AppShellTestProvider(
          onRoomDetail: (roomId) async {
            detailCalls += 1;
            return LiveRoomDetail(
              providerId: _kAppShellFollowProviderId.value,
              roomId: roomId,
              title: '壳层测试直播间',
              streamerName: '壳层测试主播',
              isLive: true,
            );
          },
        ),
      ),
    );

    await bootstrap.followRepository.upsert(
      const FollowRecord(
        providerId: 'app_shell_follow',
        roomId: 'room-1',
        streamerName: '壳层测试主播',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: AppShellPage(bootstrap: bootstrap),
      ),
    );
    await tester.pumpAndSettle();

    expect(detailCalls, 1);

    await tester.tap(find.byKey(const Key('shell-tab-profile')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('shell-tab-library')));
    await tester.pumpAndSettle();

    expect(detailCalls, 1);
    expect(
      find.byKey(const Key('library-follow-card-app_shell_follow-room-1')),
      findsOneWidget,
    );
  });
}

const _kAppShellFollowProviderId = ProviderId('app_shell_follow');

const _kAppShellFollowDescriptor = ProviderDescriptor(
  id: _kAppShellFollowProviderId,
  displayName: 'App Shell Follow',
  capabilities: {ProviderCapability.roomDetail},
  supportedPlatforms: {ProviderPlatform.android},
);

class _AppShellTestProvider extends LiveProvider implements SupportsRoomDetail {
  _AppShellTestProvider({required this.onRoomDetail});

  final Future<LiveRoomDetail> Function(String roomId) onRoomDetail;

  @override
  ProviderDescriptor get descriptor => _kAppShellFollowDescriptor;

  @override
  Future<LiveRoomDetail> fetchRoomDetail(String roomId) => onRoomDetail(roomId);
}
