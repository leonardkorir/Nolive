import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:nolive_app/src/features/room/presentation/room_preview_page_player_surface.dart';
import 'package:nolive_app/src/features/room/presentation/room_preview_page_section_widgets.dart';
import 'package:nolive_app/src/shared/presentation/widgets/persisted_network_image.dart';

void main() {
  RoomPlayerSurfaceViewData buildViewData({
    required bool hasPlayback,
    required bool fullscreen,
    required bool supportsEmbeddedView,
    RoomChaturbateStatusPresentation? statusPresentation,
  }) {
    return RoomPlayerSurfaceViewData(
      room: const LiveRoomDetail(
        providerId: 'bilibili',
        roomId: '1000',
        title: '测试直播间',
        streamerName: '测试主播',
        coverUrl: 'https://example.com/poster.jpg',
        isLive: true,
      ),
      hasPlayback: hasPlayback,
      embedPlayer: true,
      fullscreen: fullscreen,
      suspendEmbeddedPlayer: false,
      supportsEmbeddedView: supportsEmbeddedView,
      showDanmakuOverlay: true,
      showPlayerSuperChat: true,
      showInlinePlayerChrome: true,
      playerBindingInFlight: false,
      backendLabel: 'MDK',
      liveDurationLabel: '00:10:00',
      unavailableReason:
          statusPresentation?.description ?? '当前房间暂时没有公开播放流，请稍后刷新重试。',
      statusPresentation: statusPresentation,
      inlineQualityLabel: '蓝光',
      inlineLineLabel: '线路 1',
    );
  }

  testWidgets(
      'player surface renders embedded player view when playback is available',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoomPlayerSurfaceSection(
            data: buildViewData(
              hasPlayback: true,
              fullscreen: false,
              supportsEmbeddedView: true,
            ),
            buildEmbeddedPlayerView: (_) => const ColoredBox(
              key: Key('embedded-player-view'),
              color: Colors.blue,
            ),
            onToggleInlineChrome: () {},
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('embedded-player-view')), findsOneWidget);
    expect(
        find.byKey(const Key('room-inline-player-tap-target')), findsOneWidget);
  });

  testWidgets(
      'player surface shows poster and unavailable overlay when playback is missing',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoomPlayerSurfaceSection(
            data: buildViewData(
              hasPlayback: false,
              fullscreen: false,
              supportsEmbeddedView: false,
              statusPresentation: const RoomChaturbateStatusPresentation(
                label: '私密表演中',
                description: '主播当前正在 Private Show 中，暂时没有公开播放流。',
              ),
            ),
            buildEmbeddedPlayerView: (_) => const SizedBox.shrink(),
            onToggleInlineChrome: () {},
          ),
        ),
      ),
    );

    expect(find.byType(PersistedNetworkImage), findsOneWidget);
    expect(find.text('私密表演中'), findsOneWidget);
    expect(find.text('主播当前正在 Private Show 中，暂时没有公开播放流。'), findsOneWidget);
  });

  testWidgets('player surface renders fullscreen overlays when provided',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoomPlayerSurfaceSection(
            data: buildViewData(
              hasPlayback: true,
              fullscreen: true,
              supportsEmbeddedView: false,
            ),
            buildEmbeddedPlayerView: (_) => const SizedBox.shrink(),
            danmakuOverlay: const ColoredBox(
              key: Key('danmaku-overlay'),
              color: Colors.transparent,
            ),
            playerSuperChatOverlay: const ColoredBox(
              key: Key('player-super-chat-overlay'),
              color: Colors.transparent,
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('danmaku-overlay')), findsOneWidget);
    expect(find.byKey(const Key('player-super-chat-overlay')), findsOneWidget);
  });
}
