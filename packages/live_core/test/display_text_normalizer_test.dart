import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

void main() {
  test('normalizeDisplayText decodes html entities and trims spaces', () {
    expect(
      normalizeDisplayText(' PUBG&nbsp;9周年快乐（7点见） '),
      'PUBG 9周年快乐（7点见）',
    );
  });

  test('normalizeDisplayText simplifies common traditional characters', () {
    expect(normalizeDisplayText('小溫dududu'), '小温dududu');
    expect(normalizeDisplayText('熱門遊戲'), '热门游戏');
  });
}
