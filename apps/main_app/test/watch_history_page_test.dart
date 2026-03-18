import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_storage/live_storage.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';
import 'package:nolive_app/src/app/routing/app_routes.dart';
import 'package:nolive_app/src/features/library/presentation/watch_history_page.dart';
import 'package:nolive_app/src/features/settings/application/manage_history_preferences_use_case.dart';

void main() {
  testWidgets('watch history page shows records and clear action', (
    tester,
  ) async {
    final bootstrap = await _createBootstrapWithHistory([
      HistoryRecord(
        providerId: 'bilibili',
        roomId: '1001',
        title: '早间技术分享',
        streamerName: '主播甲',
        viewedAt: DateTime(2026, 3, 13, 9, 30),
      ),
      HistoryRecord(
        providerId: 'douyu',
        roomId: '1002',
        title: '',
        streamerName: '主播乙',
        viewedAt: DateTime(2026, 3, 12, 22, 45),
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(home: WatchHistoryPage(bootstrap: bootstrap)),
    );
    await tester.pumpAndSettle();

    expect(find.text('观看记录'), findsOneWidget);
    expect(find.byKey(const Key('watch-history-clear-button')), findsOneWidget);
    expect(find.text('主播甲'), findsOneWidget);
    expect(find.text('主播乙'), findsOneWidget);
    expect(find.text('早间技术分享'), findsOneWidget);
    expect(find.text('房间号 1002'), findsOneWidget);
    expect(find.text('哔哩哔哩 · 房间号 1001'), findsOneWidget);
    expect(find.text('斗鱼 · 房间号 1002'), findsOneWidget);
    expect(find.byKey(const Key('watch-history-recording-switch')),
        findsOneWidget);
  });

  testWidgets('watch history page toggles recording preference', (
    tester,
  ) async {
    final bootstrap = await _createBootstrapWithHistory(const []);

    await tester.pumpWidget(
      MaterialApp(home: WatchHistoryPage(bootstrap: bootstrap)),
    );
    await tester.pumpAndSettle();

    expect(find.text('暂无观看记录'), findsOneWidget);

    await tester.tap(find.byKey(const Key('watch-history-recording-switch')));
    await tester.pumpAndSettle();

    final preferences = await bootstrap.loadHistoryPreferences();
    expect(preferences, const HistoryPreferences(recordWatchHistory: false));
    expect(find.text('观看记录已关闭'), findsOneWidget);
  });

  testWidgets('watch history page deletes single record', (tester) async {
    final bootstrap = await _createBootstrapWithHistory([
      HistoryRecord(
        providerId: 'bilibili',
        roomId: '1001',
        title: '早间技术分享',
        streamerName: '主播甲',
        viewedAt: DateTime(2026, 3, 13, 9, 30),
      ),
      HistoryRecord(
        providerId: 'douyu',
        roomId: '1002',
        title: '晚间游戏直播',
        streamerName: '主播乙',
        viewedAt: DateTime(2026, 3, 12, 22, 45),
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(home: WatchHistoryPage(bootstrap: bootstrap)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('watch-history-delete-douyu-1002')));
    await tester.pumpAndSettle();

    expect(find.text('主播乙'), findsNothing);
    expect(find.text('主播甲'), findsOneWidget);

    final snapshot = await bootstrap.listLibrarySnapshot();
    expect(snapshot.history, hasLength(1));
    expect(snapshot.history.single.roomId, '1001');
  });

  testWidgets('watch history page clears all records', (tester) async {
    final bootstrap = await _createBootstrapWithHistory([
      HistoryRecord(
        providerId: 'bilibili',
        roomId: '1001',
        title: '早间技术分享',
        streamerName: '主播甲',
        viewedAt: DateTime(2026, 3, 13, 9, 30),
      ),
      HistoryRecord(
        providerId: 'huya',
        roomId: '1003',
        title: '周末赛事',
        streamerName: '主播丙',
        viewedAt: DateTime(2026, 3, 11, 20, 10),
      ),
    ]);

    await tester.pumpWidget(
      MaterialApp(home: WatchHistoryPage(bootstrap: bootstrap)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('watch-history-clear-button')));
    await tester.pumpAndSettle();
    expect(find.text('清空全部观看记录'), findsOneWidget);

    await tester.tap(find.text('确认清空'));
    await tester.pumpAndSettle();

    expect(find.text('暂无观看记录'), findsOneWidget);

    final snapshot = await bootstrap.listLibrarySnapshot();
    expect(snapshot.history, isEmpty);
  });

  testWidgets('watch history page opens room route on tap', (tester) async {
    final bootstrap = await _createBootstrapWithHistory([
      HistoryRecord(
        providerId: 'bilibili',
        roomId: '1001',
        title: '早间技术分享',
        streamerName: '主播甲',
        viewedAt: DateTime(2026, 3, 13, 9, 30),
      ),
    ]);
    RouteSettings? pushedSettings;

    await tester.pumpWidget(
      MaterialApp(
        home: WatchHistoryPage(bootstrap: bootstrap),
        onGenerateRoute: (settings) {
          if (settings.name == AppRoutes.room) {
            pushedSettings = settings;
            return MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => const Scaffold(body: Text('房间页')),
            );
          }
          return null;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('watch-history-item-bilibili-1001')));
    await tester.pumpAndSettle();

    expect(find.text('房间页'), findsOneWidget);
    expect(pushedSettings?.name, AppRoutes.room);
    final arguments = pushedSettings?.arguments as RoomRouteArguments?;
    expect(arguments, isNotNull);
    expect(arguments!.providerId.value, 'bilibili');
    expect(arguments.roomId, '1001');
  });
}

Future<AppBootstrap> _createBootstrapWithHistory(
  List<HistoryRecord> records,
) async {
  final bootstrap = createAppBootstrap(mode: AppRuntimeMode.preview);
  for (final record in records) {
    await bootstrap.historyRepository.add(record);
  }
  return bootstrap;
}
