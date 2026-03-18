import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nolive_app/src/shared/presentation/widgets/streamer_avatar.dart';

void main() {
  testWidgets('live avatar renders red ring', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: StreamerAvatar(
              size: 40,
              fallbackText: '主播',
              isLive: true,
            ),
          ),
        ),
      ),
    );

    final decoratedBox = tester.widget<DecoratedBox>(find.byType(DecoratedBox));
    final decoration = decoratedBox.decoration as BoxDecoration;
    final border = decoration.border as Border;

    expect(border.top.color, const Color(0xFFFF4D4F));
  });

  testWidgets('offline avatar keeps plain circle without border', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: StreamerAvatar(
              size: 40,
              fallbackText: '主播',
            ),
          ),
        ),
      ),
    );

    final decoratedBox = tester.widget<DecoratedBox>(find.byType(DecoratedBox));
    final decoration = decoratedBox.decoration as BoxDecoration;

    expect(decoration.border, isNull);
  });

  testWidgets('fallback avatar uses white background with brown text', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: StreamerAvatar(
              size: 40,
              fallbackText: '主播',
            ),
          ),
        ),
      ),
    );

    final fallbackBox = tester.widget<ColoredBox>(
      find.descendant(
        of: find.byType(StreamerAvatar),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is ColoredBox && widget.color == const Color(0xFFFFFFFF),
        ),
      ),
    );
    final fallbackText = tester.widget<Text>(find.text('主'));

    expect(fallbackBox.color, const Color(0xFFFFFFFF));
    expect(fallbackText.style?.color, const Color(0xFF7A5230));
  });

  testWidgets('ascii fallback avatar uses uppercase initial', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: StreamerAvatar(
              size: 40,
              fallbackText: 'milabunny_',
            ),
          ),
        ),
      ),
    );

    expect(find.text('M'), findsOneWidget);
  });
}
