import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nolive_app/src/features/room/presentation/room_panel_controller.dart';

void main() {
  testWidgets('tab selection synchronizes PageController and side effects once',
      (tester) async {
    final pageController = PageController();
    var chatEnterCount = 0;
    var followEnterCount = 0;
    final controller = RoomPanelController(
      pageController: pageController,
      onEnterChatPanel: () {
        chatEnterCount += 1;
      },
      onEnterFollowPanel: () {
        followEnterCount += 1;
      },
    );

    addTearDown(() {
      controller.dispose();
      pageController.dispose();
    });

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: PageView(
          controller: pageController,
          onPageChanged: controller.handlePageChanged,
          children: List<Widget>.generate(
            RoomPanel.values.length,
            (index) => SizedBox(key: Key('panel-$index')),
          ),
        ),
      ),
    );

    controller.selectPanel(RoomPanel.follow);
    await tester.pumpAndSettle();

    expect(controller.selectedPanel, RoomPanel.follow);
    expect(pageController.page, 2);
    expect(followEnterCount, 1);
    expect(chatEnterCount, 0);
  });

  testWidgets(
      'programmatic select and page callbacks only trigger chat/follow hooks when entering target panels',
      (tester) async {
    final pageController = PageController();
    var chatEnterCount = 0;
    var followEnterCount = 0;
    final controller = RoomPanelController(
      pageController: pageController,
      onEnterChatPanel: () {
        chatEnterCount += 1;
      },
      onEnterFollowPanel: () {
        followEnterCount += 1;
      },
    );

    addTearDown(() {
      controller.dispose();
      pageController.dispose();
    });

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: PageView(
          controller: pageController,
          onPageChanged: controller.handlePageChanged,
          children: List<Widget>.generate(
            RoomPanel.values.length,
            (index) => SizedBox(key: Key('panel-$index')),
          ),
        ),
      ),
    );

    controller.selectPanel(RoomPanel.follow);
    await tester.pumpAndSettle();
    controller.selectPanel(RoomPanel.follow);
    await tester.pumpAndSettle();
    controller.selectPanel(RoomPanel.settings);
    await tester.pumpAndSettle();
    controller.handlePageChanged(RoomPanel.chat.index);
    await tester.pump();
    controller.handlePageChanged(RoomPanel.chat.index);
    await tester.pump();

    expect(followEnterCount, 1);
    expect(chatEnterCount, 1);
  });
}
