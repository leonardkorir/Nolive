import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_player/live_player.dart';
import 'package:nolive_app/src/features/room/presentation/room_controls_presentation_helpers.dart';
import 'package:nolive_app/src/features/room/presentation/room_controls_view_data.dart';
import 'package:nolive_app/src/features/room/presentation/room_preview_page_controls_actions.dart';

void main() {
  test('auto close option selection matches only the nearest duration', () {
    final now = DateTime(2026, 4, 13, 20, 0);
    final scheduledCloseAt = now.add(const Duration(minutes: 120));

    expect(
      isRoomAutoCloseOptionSelected(
        minutes: 120,
        scheduledCloseAt: scheduledCloseAt,
        now: now,
      ),
      isTrue,
    );
    expect(
      isRoomAutoCloseOptionSelected(
        minutes: 60,
        scheduledCloseAt: scheduledCloseAt,
        now: now,
      ),
      isFalse,
    );
  });

  testWidgets('quick actions reflect capabilities and refresh scale label', (
    tester,
  ) async {
    var latestViewData = const RoomControlsViewData(
      hasPlayback: false,
      playbackUnavailableReason: '当前房间暂无可用播放流',
      requestedQualityLabel: '原画',
      effectiveQualityLabel: '高清',
      currentLineLabel: '主线路',
      scaleModeLabel: '适应',
      pipSupported: true,
      supportsDesktopMiniWindow: true,
      desktopMiniWindowActive: false,
      supportsPlayerCapture: false,
      scheduledCloseAt: null,
      chatTextSize: 14,
      chatTextGap: 4,
      chatBubbleStyle: false,
      showPlayerSuperChat: true,
      playerSuperChatDisplaySeconds: 8,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () {
                  unawaited(
                    showRoomQuickActionsSheet(
                      context: context,
                      wrapFlatTileScope: wrapRoomFlatTileScope,
                      viewData: latestViewData,
                      onRefresh: () async {},
                      onShowQuality: () async {},
                      onShowLine: () async {},
                      onCycleScaleMode: () async {
                        latestViewData = const RoomControlsViewData(
                          hasPlayback: false,
                          playbackUnavailableReason: '当前房间暂无可用播放流',
                          requestedQualityLabel: '原画',
                          effectiveQualityLabel: '高清',
                          currentLineLabel: '主线路',
                          scaleModeLabel: '填充',
                          pipSupported: true,
                          supportsDesktopMiniWindow: true,
                          desktopMiniWindowActive: false,
                          supportsPlayerCapture: false,
                          scheduledCloseAt: null,
                          chatTextSize: 14,
                          chatTextGap: 4,
                          chatBubbleStyle: false,
                          showPlayerSuperChat: true,
                          playerSuperChatDisplaySeconds: 8,
                        );
                        return latestViewData;
                      },
                      onEnterPictureInPicture: () async {},
                      onToggleDesktopMiniWindow: () async {},
                      onCaptureScreenshot: () async {},
                      onShowAutoCloseSheet: () async {},
                      onShowDebugPanel: () async {},
                    ),
                  );
                },
                child: const Text('open'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('切换清晰度'), findsOneWidget);
    expect(find.text('切换线路'), findsOneWidget);
    expect(find.text('小窗播放'), findsOneWidget);
    expect(find.text('桌面小窗'), findsOneWidget);
    expect(find.text('截图'), findsNothing);
    expect(find.text('适应'), findsOneWidget);
    expect(find.text('当前房间暂无可用播放流'), findsWidgets);

    await tester.tap(find.text('画面尺寸'));
    await tester.pumpAndSettle();

    expect(find.text('填充'), findsOneWidget);
  });

  testWidgets('player debug sheet renders metadata and updates diagnostics', (
    tester,
  ) async {
    final diagnostics = StreamController<PlayerDiagnostics>.broadcast();
    addTearDown(diagnostics.close);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () {
                  unawaited(
                    showRoomPlayerDebugSheet(
                      context: context,
                      wrapFlatTileScope: wrapRoomFlatTileScope,
                      debugViewData: const RoomPlayerDebugViewData(
                        backendLabel: 'MPV',
                        currentStatusLabel: 'playing',
                        requestedQualityLabel: '原画',
                        effectiveQualityLabel: '高清',
                        currentLineLabel: '主线路',
                        scaleModeLabel: '适应',
                        usingNativeDanmakuBatchMask: true,
                      ),
                      diagnosticsStream: diagnostics.stream,
                      initialDiagnostics: const PlayerDiagnostics(
                        backend: PlayerBackend.mpv,
                        width: 1920,
                        height: 1080,
                        buffering: false,
                        buffered: Duration(milliseconds: 800),
                        lowLatencyMode: true,
                      ),
                    ),
                  );
                },
                child: const Text('open'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('MPV'), findsOneWidget);
    expect(find.text('playing'), findsOneWidget);
    expect(find.text('主线路'), findsOneWidget);
    expect(find.text('1920 x 1080'), findsOneWidget);

    diagnostics.add(
      const PlayerDiagnostics(
        backend: PlayerBackend.mpv,
        width: 1280,
        height: 720,
        buffering: true,
        buffered: Duration(milliseconds: 1500),
        rebufferCount: 2,
        recentLogs: ['A', 'B'],
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('1280 x 720', skipOffstage: false), findsOneWidget);
    expect(find.text('buffering', skipOffstage: false), findsOneWidget);
    expect(find.text('1500 ms', skipOffstage: false), findsOneWidget);
    expect(find.text('2', skipOffstage: false), findsWidgets);
    expect(find.text('A\nB', skipOffstage: false), findsOneWidget);
  });
}
