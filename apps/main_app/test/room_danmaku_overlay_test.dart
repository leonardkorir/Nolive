import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:nolive_app/src/features/room/presentation/room_preview_page_danmaku.dart';
import 'package:nolive_app/src/features/settings/application/manage_danmaku_preferences_use_case.dart';

void main() {
  DanmakuPreferences buildPreferences() =>
      DanmakuPreferences.defaults.copyWith(strokeWidth: 0);

  LiveMessage buildChatMessage(
    String content, {
    required DateTime timestamp,
  }) {
    return LiveMessage(
      type: LiveMessageType.chat,
      content: content,
      timestamp: timestamp,
    );
  }

  testWidgets('room danmaku overlay renders inline track bubble',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoomDanmakuOverlay(
            messages: [
              buildChatMessage(
                'inline-bubble',
                timestamp: DateTime(2026, 1, 1, 0, 0, 1),
              ),
            ],
            fullscreen: false,
            preferences: buildPreferences(),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('room-danmaku-overlay')), findsOneWidget);
    expect(find.text('inline-bubble'), findsOneWidget);
  });

  testWidgets('room danmaku overlay does not enqueue duplicate messages',
      (tester) async {
    final duplicated = buildChatMessage(
      'duplicate-bubble',
      timestamp: DateTime(2026, 1, 1, 0, 0, 2),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoomDanmakuOverlay(
            messages: [duplicated, duplicated],
            fullscreen: false,
            preferences: buildPreferences(),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(find.text('duplicate-bubble'), findsOneWidget);
  });

  testWidgets('room danmaku overlay also renders in fullscreen mode',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoomDanmakuOverlay(
            messages: [
              buildChatMessage(
                'fullscreen-bubble',
                timestamp: DateTime(2026, 1, 1, 0, 0, 3),
              ),
            ],
            fullscreen: true,
            preferences: buildPreferences().copyWith(topMargin: 12),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(find.text('fullscreen-bubble'), findsOneWidget);
  });

  testWidgets('room player super chat overlay keeps compact text style',
      (tester) async {
    final messages = ValueNotifier<List<LiveMessage>>(
      [
        LiveMessage(
          type: LiveMessageType.superChat,
          content: 'sc-message',
          timestamp: DateTime(2026, 1, 1, 0, 0, 4),
        ),
      ],
    );
    addTearDown(messages.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RoomPlayerSuperChatOverlay(
            messagesListenable: messages,
            visible: true,
          ),
        ),
      ),
    );

    final text = tester.widget<Text>(find.text('sc-message'));
    expect(text.style?.fontSize, 13);
  });
}
