import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:nolive_app/src/shared/presentation/widgets/live_room_grid_card.dart';
import 'package:nolive_app/src/shared/presentation/widgets/persisted_network_image.dart';

void main() {
  testWidgets('live room grid card prefers keyframe artwork when available', (
    tester,
  ) async {
    const room = LiveRoom(
      providerId: 'douyin',
      roomId: 'room-1',
      title: '测试房间',
      streamerName: '测试主播',
      coverUrl: 'https://example.com/cover.png',
      keyframeUrl: 'https://example.com/keyframe.png',
      isLive: true,
    );

    const descriptor = ProviderDescriptor(
      id: ProviderId.douyin,
      displayName: '抖音',
      capabilities: {},
      supportedPlatforms: {ProviderPlatform.android},
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 220,
            height: 180,
            child: LiveRoomGridCard(
              room: room,
              descriptor: descriptor,
            ),
          ),
        ),
      ),
    );

    final coverImage = tester.widget<PersistedNetworkImage>(
      find.byType(PersistedNetworkImage).first,
    );
    expect(coverImage.imageUrl, room.keyframeUrl);
  });

  testWidgets('live room grid card normalizes malformed UTF-16 text fields', (
    tester,
  ) async {
    const room = LiveRoom(
      providerId: 'bilibili',
      roomId: 'room-2',
      title: '标题\uD800',
      streamerName: '主播\uD800',
      areaName: '分区\uD800',
      isLive: true,
    );

    const descriptor = ProviderDescriptor(
      id: ProviderId.bilibili,
      displayName: '哔哩哔哩',
      capabilities: {},
      supportedPlatforms: {ProviderPlatform.android},
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 220,
            height: 180,
            child: LiveRoomGridCard(
              room: room,
              descriptor: descriptor,
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('标题'), findsOneWidget);
    expect(find.text('主播'), findsOneWidget);
    expect(find.text('分区'), findsOneWidget);
  });
}
