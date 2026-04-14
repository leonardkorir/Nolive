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

  test('normalizeDisplayText strips malformed utf16 surrogate code units', () {
    final badText =
        '游${String.fromCharCode(0xD800)}戏${String.fromCharCode(0xDC00)}厅';
    expect(normalizeDisplayText(badText), '游戏厅');
  });
}
