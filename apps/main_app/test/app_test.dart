import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nolive_app/src/app/app.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';

void main() {
  testWidgets(
    'shell navigates browse and library flows',
    (tester) async {
      await _pumpApp(tester);
      expect(find.byKey(const Key('shell-tab-label-home')), findsOneWidget);
      expect(find.byKey(const Key('shell-tab-label-browse')), findsOneWidget);
      expect(find.byKey(const Key('shell-tab-label-library')), findsOneWidget);
      expect(find.byKey(const Key('shell-tab-label-profile')), findsOneWidget);
      expect(find.text('搜索'), findsNothing);

      await tester.tap(find.byKey(const Key('shell-tab-label-browse')));
      await tester.pumpAndSettle();
      expect(find.text('分类加载失败'), findsNothing);
      expect(find.text('知识区'), findsOneWidget);

      await tester.tap(find.byKey(const Key('shell-tab-label-library')));
      await tester.pumpAndSettle();
      expect(find.text('全部'), findsOneWidget);
      expect(find.text('直播中'), findsWidgets);
      expect(find.text('未开播'), findsWidgets);
    },
  );

  testWidgets('profile tools open settings subpages', (tester) async {
    await _pumpApp(tester);

    await tester.tap(find.byKey(const Key('shell-tab-label-profile')));
    await tester.pumpAndSettle();
    expect(find.text('Nolive'), findsOneWidget);
    expect(find.text('账号管理'), findsOneWidget);
    expect(find.text('外观设置'), findsOneWidget);
    expect(find.text('直播间设置'), findsOneWidget);
    expect(find.text('链接解析'), findsOneWidget);

    await tester.tap(find.text('观看记录'));
    await tester.pumpAndSettle();
    expect(find.text('观看记录'), findsOneWidget);
    expect(find.byKey(const Key('watch-history-clear-button')), findsOneWidget);
    await _tapBackButton(tester);

    await tester.tap(find.text('直播间设置'));
    await tester.pumpAndSettle();
    expect(find.text('进入后台自动暂停'), findsOneWidget);
    expect(find.text('文字大小'), findsOneWidget);
    expect(find.text('关键词屏蔽'), findsOneWidget);
    await _tapBackButton(tester);

    await tester.tap(find.text('数据同步'));
    await tester.pumpAndSettle();
    expect(find.text('WebDAV 同步'), findsOneWidget);
    expect(find.text('局域网数据同步'), findsOneWidget);
    expect(find.text('导入 / 导出'), findsOneWidget);

    await tester.tap(find.text('WebDAV 同步'));
    await tester.pumpAndSettle();
    expect(find.text('上传快照'), findsOneWidget);
    await _tapBackButton(tester);

    await _tapBackButton(tester);

    await tester.tap(find.text('关注设置'));
    await tester.pumpAndSettle();
    expect(find.text('标签管理'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('关注导入导出'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('关注导入导出'), findsOneWidget);
    await _tapBackButton(tester);

    await tester.tap(find.text('主页设置'));
    await tester.pumpAndSettle();
    expect(find.text('导航顺序'), findsOneWidget);
    expect(find.text('平台顺序'), findsOneWidget);
    await _tapBackButton(tester);

    await tester.tap(find.text('外观设置'));
    await tester.pumpAndSettle();
    expect(find.text('主题模式'), findsOneWidget);
    await _tapBackButton(tester);

    await tester.tap(find.text('免责声明'));
    await tester.pumpAndSettle();
    expect(find.text('已阅读并同意'), findsOneWidget);
    await _tapBackButton(tester);
  });

  testWidgets('parse room tool resolves bilibili urls', (tester) async {
    await _pumpApp(tester);

    await tester.tap(find.byKey(const Key('shell-tab-label-profile')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('链接解析'));
    await tester.pumpAndSettle();
    expect(find.text('房间解析工具'), findsOneWidget);

    await tester.enterText(
      find.byType(TextField).first,
      'https://live.bilibili.com/66666',
    );
    await tester.tap(find.text('解析并检查'));
    await tester.pumpAndSettle();
    expect(find.text('解析成功'), findsOneWidget);
    expect(find.text('房间标题'), findsOneWidget);
    expect(find.text('打开房间'), findsOneWidget);
  });
}

Future<void> _pumpApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    NoliveApp(
      appBootstrap: createAppBootstrap(mode: AppRuntimeMode.preview),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapBackButton(WidgetTester tester) async {
  final finders = [
    find.byType(BackButton),
    find.byTooltip('返回'),
    find.byIcon(Icons.arrow_back_rounded),
    find.byIcon(Icons.arrow_back),
  ];
  for (final finder in finders) {
    if (finder.evaluate().isEmpty) {
      continue;
    }
    await tester.tap(finder.first);
    await tester.pumpAndSettle();
    return;
  }
  throw TestFailure('Expected a visible back button on screen.');
}
