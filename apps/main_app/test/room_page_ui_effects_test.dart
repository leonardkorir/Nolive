import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:nolive_app/src/app/routing/app_routes.dart';
import 'package:nolive_app/src/features/room/presentation/room_controls_presentation_helpers.dart';
import 'package:nolive_app/src/features/room/presentation/room_page_ui_effects.dart';

void main() {
  testWidgets('room page ui effects centralize snackbar and navigation', (
    tester,
  ) async {
    final observer = _RecordingNavigatorObserver();
    late RoomPageUiEffects effects;

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        onGenerateRoute: (settings) {
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (context) {
              if (settings.name == AppRoutes.settings) {
                return const Scaffold(body: Text('settings route'));
              }
              if (settings.name == AppRoutes.room) {
                return const Scaffold(body: Text('replacement room'));
              }
              return Scaffold(
                body: Builder(
                  builder: (context) {
                    effects = RoomPageUiEffects(
                      context: context,
                      isMounted: () => true,
                      wrapFlatTileScope: wrapRoomFlatTileScope,
                    );
                    return const Text('home');
                  },
                ),
              );
            },
          );
        },
      ),
    );

    effects.showMessage('房间信息已刷新');
    await tester.pump();
    expect(find.text('房间信息已刷新'), findsOneWidget);

    final settingsRoute = effects.pushNamed(AppRoutes.settings);
    await tester.pumpAndSettle();
    expect(find.text('settings route'), findsOneWidget);
    expect(observer.pushedRouteNames, contains(AppRoutes.settings));

    effects.popPage();
    await tester.pumpAndSettle();
    await settingsRoute;
    expect(find.text('home'), findsOneWidget);

    unawaited(
      effects.pushReplacementToRoom(
        const RoomRouteArguments(
          providerId: ProviderId('bilibili'),
          roomId: '66666',
          startInFullscreen: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('replacement room'), findsOneWidget);
    expect(observer.replacedRouteNames, contains(AppRoutes.room));
    expect(observer.replacedArguments.single, isA<RoomRouteArguments>());
    final arguments = observer.replacedArguments.single as RoomRouteArguments;
    expect(arguments.providerId, const ProviderId('bilibili'));
    expect(arguments.roomId, '66666');
    expect(arguments.startInFullscreen, isTrue);
  });

  testWidgets('room page ui effects ignore calls after unmount', (
    tester,
  ) async {
    late RoomPageUiEffects effects;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              effects = RoomPageUiEffects(
                context: context,
                isMounted: () => false,
                wrapFlatTileScope: wrapRoomFlatTileScope,
              );
              return const Text('home');
            },
          ),
        ),
      ),
    );

    effects.showMessage('should not show');
    await effects.pushNamed(AppRoutes.settings);
    await effects.presentAutoCloseSheet(
      scheduledCloseAt: null,
      onSelectDuration: (_) {},
    );
    effects.popPage();
    await tester.pumpAndSettle();

    expect(find.text('should not show'), findsNothing);
    expect(find.text('自动关闭'), findsNothing);
    expect(find.text('home'), findsOneWidget);
  });
}

class _RecordingNavigatorObserver extends NavigatorObserver {
  final pushedRouteNames = <String?>[];
  final replacedRouteNames = <String?>[];
  final replacedArguments = <Object?>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushedRouteNames.add(route.settings.name);
    super.didPush(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    replacedRouteNames.add(newRoute?.settings.name);
    replacedArguments.add(newRoute?.settings.arguments);
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }
}
