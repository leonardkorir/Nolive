import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nolive_app/src/features/room/presentation/room_controls_presentation_helpers.dart';
import 'package:nolive_app/src/features/room/presentation/room_controls_view_data.dart';
import 'package:nolive_app/src/features/room/presentation/room_preview_page_controls.dart';

void main() {
  testWidgets('room controls panel renders from immutable view data', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RoomControlsPanel(
              wrapFlatTileScope: wrapRoomFlatTileScope,
              viewData: RoomControlsViewData(
                hasPlayback: true,
                playbackUnavailableReason: '当前房间暂无可用播放流',
                requestedQualityLabel: '原画',
                effectiveQualityLabel: '高清',
                currentLineLabel: '主线路',
                scaleModeLabel: '适应',
                pipSupported: true,
                supportsDesktopMiniWindow: true,
                desktopMiniWindowActive: false,
                supportsPlayerCapture: true,
                scheduledCloseAt: DateTime(2026, 4, 13, 23, 15),
                chatTextSize: 15,
                chatTextGap: 6,
                chatBubbleStyle: true,
                showPlayerSuperChat: true,
                playerSuperChatDisplaySeconds: 9,
              ),
              onOpenPlayerSettings: () {},
              onShowQuality: () {},
              onShowLine: () {},
              onCycleScaleMode: () {},
              onEnterPictureInPicture: () {},
              onToggleDesktopMiniWindow: () {},
              onCaptureScreenshot: () {},
              onShowDebugPanel: () {},
              onUpdateChatTextSize: (_) {},
              onUpdateChatTextGap: (_) {},
              onUpdateChatBubbleStyle: (_) {},
              onUpdateShowPlayerSuperChat: (_) {},
              onUpdatePlayerSuperChatDisplaySeconds: (_) {},
              onOpenDanmakuShield: () {},
              onOpenDanmakuSettings: () {},
              onShowAutoCloseSheet: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('播放器设置'), findsOneWidget);
    expect(find.text('高清'), findsOneWidget);
    expect(find.text('主线路'), findsOneWidget);
    expect(find.text('适应'), findsOneWidget);
    expect(find.text('小窗播放'), findsOneWidget);
    expect(find.text('桌面小窗'), findsOneWidget);
    expect(find.text('截图'), findsOneWidget);
    expect(find.text('播放器中显示SC'), findsOneWidget);
    expect(find.text('定时关闭 · 23:15'), findsOneWidget);
  });

  testWidgets(
      'room controls panel shows unavailable reason when playback missing', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RoomControlsPanel(
              wrapFlatTileScope: wrapRoomFlatTileScope,
              viewData: const RoomControlsViewData(
                hasPlayback: false,
                playbackUnavailableReason: '当前房间暂无可用播放流',
                requestedQualityLabel: '原画',
                effectiveQualityLabel: '不可用',
                currentLineLabel: '不可用',
                scaleModeLabel: '适应',
                pipSupported: false,
                supportsDesktopMiniWindow: false,
                desktopMiniWindowActive: false,
                supportsPlayerCapture: false,
                scheduledCloseAt: null,
                chatTextSize: 14,
                chatTextGap: 4,
                chatBubbleStyle: false,
                showPlayerSuperChat: true,
                playerSuperChatDisplaySeconds: 8,
              ),
              onOpenPlayerSettings: () {},
              onShowQuality: () {},
              onShowLine: () {},
              onCycleScaleMode: () {},
              onEnterPictureInPicture: () {},
              onToggleDesktopMiniWindow: () {},
              onCaptureScreenshot: () {},
              onShowDebugPanel: () {},
              onUpdateChatTextSize: (_) {},
              onUpdateChatTextGap: (_) {},
              onUpdateChatBubbleStyle: (_) {},
              onUpdateShowPlayerSuperChat: (_) {},
              onUpdatePlayerSuperChatDisplaySeconds: (_) {},
              onOpenDanmakuShield: () {},
              onOpenDanmakuSettings: () {},
              onShowAutoCloseSheet: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('当前房间暂无可用播放流'), findsOneWidget);
    expect(find.text('小窗播放'), findsNothing);
    expect(find.text('桌面小窗'), findsNothing);
    expect(find.text('截图'), findsNothing);
  });
}
