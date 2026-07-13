import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_storage/live_storage.dart';
import 'package:nolive_app/src/shared/domain/follow_watch_entry.dart';
import 'package:nolive_app/src/shared/presentation/widgets/follow_watch_row.dart';

void main() {
  const descriptor = ProviderDescriptor(
    id: ProviderId('demo'),
    displayName: 'Demo Live',
    capabilities: <ProviderCapability>{},
    supportedPlatforms: <ProviderPlatform>{ProviderPlatform.android},
  );

  testWidgets(
    'follow watch row stays stable in narrow fullscreen drawer width',
    (tester) async {
      final entry = FollowWatchEntry(
        record: const FollowRecord(
          providerId: ProviderId('demo'),
          roomId: 'room-1',
          streamerName:
              'A very long streamer name for fullscreen drawer layout',
          lastTitle: 'A long room title that should still stay inside the row',
          lastAreaName: '超长分区标签用于测试窄抽屉布局',
          tags: <String>['标签一', '标签二', '标签三', '标签四'],
        ),
        detail: LiveRoomDetail(
          providerId: const ProviderId('demo'),
          roomId: 'room-1',
          title: 'A long room title that should still stay inside the row',
          streamerName:
              'A very long streamer name for fullscreen drawer layout',
          areaName: '超长分区标签用于测试窄抽屉布局',
          startedAt: DateTime.now().subtract(
            const Duration(hours: 1, minutes: 23, seconds: 45),
          ),
        ),
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
    },
  );

  testWidgets(
    'offline unfollow icon is grey and user tags left-align with area chips',
    (tester) async {
      final entry = FollowWatchEntry(
        record: const FollowRecord(
          providerId: ProviderId('demo'),
          roomId: 'room-offline',
          streamerName: '离线主播',
          lastTitle: '未开播房间',
          lastAreaName: '吃鸡行动',
          tags: <String>['主机', '其他', 'fps'],
          lastLiveStatus: 1,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              child: FollowWatchRow(
                entry: entry,
                providerDescriptor: descriptor,
                showSurface: false,
                onTap: () {},
                onRemove: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      // Measured chip alignment applies on the next frame.
      await tester.pump();
      await tester.pump();

      expect(find.text('未开播'), findsOneWidget);
      expect(find.text('吃鸡行动'), findsOneWidget);
      expect(find.text('主机 · 其他 · fps'), findsOneWidget);

      // Same meta row as provider.
      final tagsTop = tester.getTopLeft(find.text('主机 · 其他 · fps')).dy;
      final providerTop = tester.getTopLeft(find.text('Demo Live')).dy;
      expect((tagsTop - providerTop).abs(), lessThan(2));

      final tagsLeft = tester.getTopLeft(find.text('主机 · 其他 · fps')).dx;
      final areaLeft = tester.getTopLeft(find.text('吃鸡行动')).dx;
      // Should match area label text start (chip box + 6px pill padding).
      expect((tagsLeft - areaLeft).abs(), lessThan(2));
      final providerRight = tester.getBottomRight(find.text('Demo Live')).dx;
      expect(tagsLeft, greaterThan(providerRight));

      final icon = tester.widget<Icon>(
        find.descendant(
          of: find.byTooltip('取消关注'),
          matching: find.byIcon(Icons.heart_broken_rounded),
        ),
      );
      expect(icon.color, const Color(0xFF667085));
    },
  );

  testWidgets('live unfollow icon stays red', (tester) async {
    final entry = FollowWatchEntry(
      record: const FollowRecord(
        providerId: ProviderId('demo'),
        roomId: 'room-live',
        streamerName: '在线主播',
        lastLiveStatus: 2,
      ),
      detail: LiveRoomDetail(
        providerId: const ProviderId('demo'),
        roomId: 'room-live',
        title: '直播中',
        streamerName: '在线主播',
        isLive: true,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FollowWatchRow(
            entry: entry,
            providerDescriptor: descriptor,
            showSurface: false,
            onTap: () {},
            onRemove: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    final icon = tester.widget<Icon>(
      find.descendant(
        of: find.byTooltip('取消关注'),
        matching: find.byIcon(Icons.heart_broken_rounded),
      ),
    );
    expect(icon.color, isNot(const Color(0xFF667085)));
  });
}
