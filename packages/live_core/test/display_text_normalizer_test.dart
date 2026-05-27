import 'dart:io';

import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

void main() {
  test('normalizeDisplayText decodes html entities and trims spaces', () {
    expect(
      normalizeDisplayText(' PUBG&nbsp;9周年快乐（7点见） '),
      'PUBG 9周年快乐（7点见）',
    );
    expect(
      normalizeDisplayText('Tom &amp;amp; Jerry &#x1F600; &copy;'),
      'Tom & Jerry 😀 ©',
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

  test('traditional simplification table has no duplicate or identity entries',
      () {
    final source = File(
      'lib/src/text/display_text_normalizer.dart',
    ).readAsStringSync();
    final entries = RegExp(
      r"MapEntry\('([^']+)', '([^']+)'\)",
    ).allMatches(source);
    final seen = <String>{};
    for (final entry in entries) {
      final key = entry.group(1)!;
      final value = entry.group(2)!;
      expect(value, isNot(key), reason: 'identity mapping for $key');
      expect(seen.add(key), isTrue, reason: 'duplicate mapping for $key');
    }
  });
}
