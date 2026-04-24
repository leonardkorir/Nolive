import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_storage/live_storage.dart';
import 'package:nolive_app/src/features/library/application/load_follow_watchlist_use_case.dart';
import 'package:nolive_app/src/shared/presentation/widgets/follow_watch_row.dart';

void main() {
  testWidgets('follow watch row stays stable in narrow fullscreen drawer width',
      (tester) async {
    final entry = FollowWatchEntry(
      record: const FollowRecord(
        providerId: 'demo',
        roomId: 'room-1',
        streamerName: 'A very long streamer name for fullscreen drawer layout',
        lastTitle: 'A long room title that should still stay inside the row',
        lastAreaName: '超长分区标签用于测试窄抽屉布局',
        tags: <String>['标签一', '标签二', '标签三', '标签四'],
      ),
      detail: LiveRoomDetail(
        providerId: 'demo',
        roomId: 'room-1',
        title: 'A long room title that should still stay inside the row',
        streamerName: 'A very long streamer name for fullscreen drawer layout',
        areaName: '超长分区标签用于测试窄抽屉布局',
        startedAt: DateTime.now().subtract(
          const Duration(hours: 1, minutes: 23, seconds: 45),
        ),
      ),
    );

    const descriptor = ProviderDescriptor(
      id: ProviderId('demo'),
      displayName: 'Demo Live',
      capabilities: <ProviderCapability>{},
      supportedPlatforms: <ProviderPlatform>{ProviderPlatform.android},
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 222,
              child: FollowWatchRow(
                entry: entry,
                providerDescriptor: descriptor,
                isPlaying: true,
                highContrastOverlay: true,
                showSurface: false,
                showChevron: true,
                onTap: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('A very long streamer name'), findsOneWidget);
  });
}
