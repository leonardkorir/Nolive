import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nolive_app/src/app/app.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpForUi(
    WidgetTester tester, {
    Duration duration = const Duration(milliseconds: 600),
    Duration step = const Duration(milliseconds: 100),
  }) async {
    final ticks = (duration.inMilliseconds / step.inMilliseconds).ceil();
    for (var tick = 0; tick < ticks; tick++) {
      await tester.pump(step);
    }
  }

  Future<void> popRoute(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await pumpForUi(tester);
  }

  Future<void> pumpUntilVisible(
    WidgetTester tester,
    Finder finder, {
    Duration timeout = const Duration(seconds: 8),
    Duration step = const Duration(milliseconds: 250),
  }) async {
    final maxTicks = timeout.inMilliseconds ~/ step.inMilliseconds;
    for (var tick = 0; tick < maxTicks; tick++) {
      if (finder.evaluate().isNotEmpty) {
        return;
      }
      await tester.pump(step);
    }
    expect(finder.evaluate().isNotEmpty, isTrue);
  }

  Finder findScreenshotResultMessage() {
    return find.byWidgetPredicate((widget) {
      if (widget is! Text) {
        return false;
      }
      final data = widget.data ?? '';
      return data == '已保存截图到系统相册' || data.startsWith('系统相册保存失败，已备份截图到 ');
    });
  }

  Future<void> showInlinePlayerControls(WidgetTester tester) async {
    await tester.tap(
      find.byKey(const Key('room-inline-player-tap-target')),
      warnIfMissed: false,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
  }

  Future<void> completeFullscreenRoundTrip(WidgetTester tester) async {
    final exitFullscreenButton = find.byKey(
      const Key('room-exit-fullscreen-button'),
    );
    final fullscreenOverlay = find.byKey(const Key('room-fullscreen-overlay'));
    final inlineFullscreenButton = find.byKey(
      const Key('room-inline-fullscreen-button'),
    );
    final leaveButton = find.byKey(const Key('room-leave-button'));
    var sawFullscreen = false;

    for (var attempt = 0; attempt < 24; attempt++) {
      if (exitFullscreenButton.evaluate().isNotEmpty) {
        sawFullscreen = true;
        await tester.tap(exitFullscreenButton, warnIfMissed: false);
      } else if (fullscreenOverlay.evaluate().isNotEmpty) {
        sawFullscreen = true;
        await tester.tap(fullscreenOverlay, warnIfMissed: false);
      } else if (leaveButton.evaluate().isNotEmpty) {
        if (sawFullscreen) {
          return;
        }
        await showInlinePlayerControls(tester);
        if (inlineFullscreenButton.evaluate().isNotEmpty) {
          await tester.tap(inlineFullscreenButton, warnIfMissed: false);
        }
      }
      await tester.pump(const Duration(milliseconds: 250));
    }

    expect(sawFullscreen, isTrue);
    expect(leaveButton, findsOneWidget);
  }

  Future<void> ensureInlineRoomChrome(WidgetTester tester) async {
    final leaveButton = find.byKey(const Key('room-leave-button'));
    final exitFullscreenButton = find.byKey(
      const Key('room-exit-fullscreen-button'),
    );

    await pumpUntilVisible(
      tester,
      find.byWidgetPredicate((widget) {
        final key = widget.key;
        return key == const Key('room-leave-button') ||
            key == const Key('room-exit-fullscreen-button');
      }),
    );

    if (leaveButton.evaluate().isNotEmpty) {
      return;
    }
    if (exitFullscreenButton.evaluate().isNotEmpty) {
      await tester.tap(exitFullscreenButton, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 250));
    }
    await pumpUntilVisible(tester, leaveButton);
  }

  bool shellVisible(WidgetTester tester) {
    return find.byType(NavigationBar).evaluate().isNotEmpty ||
        find.byKey(const Key('shell-tab-home')).evaluate().isNotEmpty ||
        find.byKey(const Key('shell-tab-label-home')).evaluate().isNotEmpty;
  }

  bool shellTabVisible(String id) {
    return find.byKey(Key('shell-tab-$id')).evaluate().isNotEmpty ||
        find.byKey(Key('shell-tab-label-$id')).evaluate().isNotEmpty;
  }

  Future<void> leaveRoomToShell(WidgetTester tester) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      if (shellVisible(tester)) {
        return;
      }
      final fullscreenOverlay = find.byKey(
        const Key('room-fullscreen-overlay'),
      );
      final exitFullscreenButton = find.byKey(
        const Key('room-exit-fullscreen-button'),
      );
      if (fullscreenOverlay.evaluate().isNotEmpty &&
          exitFullscreenButton.evaluate().isNotEmpty) {
        await tester.tap(exitFullscreenButton, warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 250));
        continue;
      }
      await popRoute(tester);
    }

    expect(find.byType(NavigationBar), findsOneWidget);
  }

  Future<void> selectShellTab(
    WidgetTester tester, {
    required String id,
    required String label,
  }) async {
    final keyedTab = find.byKey(Key('shell-tab-$id'));
    if (keyedTab.evaluate().isNotEmpty) {
      await tester.tap(keyedTab, warnIfMissed: false);
    } else {
      await tester.tap(find.text(label).first, warnIfMissed: false);
    }
    await pumpForUi(tester);
  }

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      NoliveApp(appBootstrap: createAppBootstrap(mode: AppRuntimeMode.preview)),
    );
    await pumpUntilVisible(tester, find.byKey(const Key('shell-tab-home')));
    expect(shellVisible(tester), isTrue);
    expect(shellTabVisible('home'), isTrue);
    expect(shellTabVisible('browse'), isTrue);
    expect(shellTabVisible('library'), isTrue);
    expect(shellTabVisible('profile'), isTrue);
  }

  testWidgets('android smoke covers room, search, and library flows', (
    tester,
  ) async {
    await pumpApp(tester);

    await selectShellTab(tester, id: 'browse', label: '发现');
    expect(find.text('知识区'), findsOneWidget);

    await tester.tap(find.text('知识区').first, warnIfMissed: false);
    await pumpUntilVisible(tester, find.text('新项目参考直播间'));

    await tester.tap(find.text('新项目参考直播间').first);
    await tester.pump();
    await ensureInlineRoomChrome(tester);

    expect(find.byKey(const Key('room-leave-button')), findsOneWidget);
    expect(find.byKey(const Key('room-appbar-more-button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('room-appbar-more-button')));
    await pumpUntilVisible(
      tester,
      find.byKey(const Key('room-quick-refresh-button')),
    );
    expect(find.byKey(const Key('room-quick-refresh-button')), findsOneWidget);
    expect(find.text('切换清晰度'), findsOneWidget);
    expect(find.text('截图'), findsOneWidget);
    await tester.tap(find.text('截图').first, warnIfMissed: false);
    await pumpUntilVisible(tester, findScreenshotResultMessage());

    await showInlinePlayerControls(tester);
    expect(
      find.byKey(const Key('room-inline-fullscreen-button')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const Key('room-inline-fullscreen-button')),
      warnIfMissed: false,
    );
    await tester.pump();
    await completeFullscreenRoundTrip(tester);

    await leaveRoomToShell(tester);

    expect(find.byTooltip('搜索'), findsOneWidget);
    await tester.tap(find.byTooltip('搜索').first, warnIfMissed: false);
    await pumpUntilVisible(
      tester,
      find.byKey(const Key('search-submit-button')),
    );

    await tester.enterText(find.byType(TextField).first, '架构');
    await tester.tap(find.byKey(const Key('search-submit-button')));
    await pumpUntilVisible(tester, find.textContaining('迁移样例主播'));
    if (tester.testTextInput.isRegistered && tester.testTextInput.isVisible) {
      tester.testTextInput.hide();
      await pumpForUi(tester);
    }

    expect(find.textContaining('迁移样例主播'), findsOneWidget);
    await tester.tap(find.textContaining('架构迁移验证房间').first);
    await tester.pump();
    await ensureInlineRoomChrome(tester);
    expect(find.byKey(const Key('room-leave-button')), findsOneWidget);

    await leaveRoomToShell(tester);
    expect(shellVisible(tester), isTrue);

    await selectShellTab(tester, id: 'library', label: '关注');
    await pumpUntilVisible(tester, find.text('关注用户'));
    expect(find.text('关注用户'), findsOneWidget);
    expect(find.text('全部'), findsOneWidget);
    expect(find.text('直播中'), findsOneWidget);
    expect(find.text('未开播'), findsOneWidget);
    expect(
      find.text('暂无关注').evaluate().isNotEmpty ||
          find.text('当前筛选下没有结果').evaluate().isNotEmpty ||
          find.byType(ListTile).evaluate().isNotEmpty,
      isTrue,
    );
  });

  testWidgets('android smoke covers profile, sync, and settings tools', (
    tester,
  ) async {
    await pumpApp(tester);

    await selectShellTab(tester, id: 'profile', label: '我的');
    expect(find.text('Nolive'), findsOneWidget);
    expect(find.text('数据同步'), findsOneWidget);
    expect(find.text('关注设置'), findsOneWidget);
    expect(find.text('其他设置'), findsOneWidget);

    await tester.tap(find.text('数据同步').first, warnIfMissed: false);
    await pumpUntilVisible(tester, find.text('WebDAV 同步'));
    expect(find.text('局域网数据同步'), findsOneWidget);
    expect(find.text('导入 / 导出'), findsOneWidget);
    await popRoute(tester);

    await tester.tap(find.text('关注设置').first, warnIfMissed: false);
    await pumpUntilVisible(tester, find.text('标签管理'));
    expect(find.text('直播状态更新'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('关注导入导出'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('关注导入导出'), findsOneWidget);
    await popRoute(tester);

    await tester.tap(find.text('主页设置').first, warnIfMissed: false);
    await pumpUntilVisible(tester, find.text('导航顺序'));
    expect(find.text('平台顺序'), findsOneWidget);
    await popRoute(tester);

    await tester.tap(find.text('外观设置').first, warnIfMissed: false);
    await pumpUntilVisible(tester, find.text('主题模式'));
    await popRoute(tester);
  });
}
