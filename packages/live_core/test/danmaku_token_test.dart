import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

void main() {
  // Per-site tokens are owned by live_providers; see
  // provider_danmaku_token_test.dart there.
  group('site-independent DanmakuToken cases', () {
    test('PreviewDanmakuToken', () {
      const t1 = PreviewDanmakuToken();
      const t2 = PreviewDanmakuToken();
      expect(t1, equals(t2));
      expect(t1.hashCode, equals(t2.hashCode));
      expect(t1.props, isEmpty);
    });

    test('UnavailableDanmakuToken', () {
      const t1 = UnavailableDanmakuToken(reason: 'error', cause: 'socket');
      const t2 = UnavailableDanmakuToken(reason: 'error', cause: 'socket');
      const t3 = UnavailableDanmakuToken(reason: 'other');
      expect(t1, equals(t2));
      expect(t1.hashCode, equals(t2.hashCode));
      expect(t1, isNot(equals(t3)));
      expect(t1.reason, 'error');
      expect(t1.cause, 'socket');
    });
  });
}
