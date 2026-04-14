import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nolive_app/src/features/room/presentation/room_chat_viewport_coordinator.dart';
import 'package:nolive_app/src/features/room/presentation/room_panel_controller.dart';

void main() {
  Future<void> pumpScrollableHarness(
    WidgetTester tester,
    RoomChatViewportCoordinator coordinator,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 120,
            child: ListView.builder(
              controller: coordinator.controller,
              itemExtent: 40,
              itemCount: 40,
              itemBuilder: (context, index) => Text('row-$index'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('entering chat panel scrolls to bottom forcibly', (tester) async {
    final coordinator = RoomChatViewportCoordinator();
    addTearDown(coordinator.dispose);

    await pumpScrollableHarness(tester, coordinator);

    coordinator.scrollToBottom(force: true);
    await tester.pump();
    await tester.pump();

    expect(
      coordinator.controller.position.pixels,
      coordinator.controller.position.maxScrollExtent,
    );
  });

  testWidgets('new messages do not steal scroll when user is far from bottom',
      (tester) async {
    final coordinator = RoomChatViewportCoordinator();
    addTearDown(coordinator.dispose);

    await pumpScrollableHarness(tester, coordinator);
    coordinator.controller.jumpTo(0);

    coordinator.handleMessagesChanged(selectedPanel: RoomPanel.chat);
    await tester.pump();
    await tester.pump();

    expect(coordinator.controller.position.pixels, 0);
  });

  testWidgets('disposed viewport coordinator ignores pending scroll work',
      (tester) async {
    final coordinator = RoomChatViewportCoordinator();

    await pumpScrollableHarness(tester, coordinator);
    coordinator.scrollToBottom(force: true);
    coordinator.dispose();

    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
