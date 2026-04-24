import 'package:flutter_test/flutter_test.dart';
import 'package:nolive_app/src/shared/application/app_log.dart';

void main() {
  group('shouldFlushAppLogRecord', () {
    test('flushes errors immediately', () {
      expect(
        AppLog.shouldFlushAppLogRecord(
          level: 'ERROR',
          tag: 'misc',
        ),
        isTrue,
      );
    });

    test('flushes room and player diagnostics immediately', () {
      expect(
        AppLog.shouldFlushAppLogRecord(
          level: 'INFO',
          tag: 'room',
        ),
        isTrue,
      );
      expect(
        AppLog.shouldFlushAppLogRecord(
          level: 'INFO',
          tag: 'player/mdk-log',
        ),
        isTrue,
      );
    });

    test('keeps generic info logs debounced', () {
      expect(
        AppLog.shouldFlushAppLogRecord(
          level: 'INFO',
          tag: 'app',
        ),
        isFalse,
      );
    });
  });

  group('sanitizeMessageForPersistence', () {
    test('redacts sensitive playback query params and cookies', () {
      final sanitized = AppLog.sanitizeMessageForPersistence(
        'play url=https://edge.example.com/llhls.m3u8?token=abc123&session=xyz '
        'cookie=cf_clearance=demo',
      );

      expect(sanitized, contains('token=<redacted>'));
      expect(sanitized, contains('session=<redacted>'));
      expect(sanitized, contains('cookie=<redacted>'));
      expect(sanitized, isNot(contains('abc123')));
      expect(sanitized, isNot(contains('xyz')));
      expect(sanitized, isNot(contains('cf_clearance=demo')));
    });

    test('redacts full quoted cookie headers without dropping sibling fields',
        () {
      final sanitized = AppLog.sanitizeMessageForPersistence(
        'http-header-fields=["referer: https://chaturbate.com/test/",'
        '"cookie: affkey=demo; cf_clearance=secret; '
        r'tbu_room={\"source\":\"df\",\"index\":3}",'
        '"content-type: application/x-www-form-urlencoded"]',
      );

      expect(sanitized, contains('"cookie: <redacted>"'));
      expect(
        sanitized,
        contains('"content-type: application/x-www-form-urlencoded"'),
      );
      expect(sanitized, isNot(contains('cf_clearance=secret')));
      expect(sanitized, isNot(contains('tbu_room')));
    });

    test('redacts plain lavf cookie diagnostics through end of line', () {
      final sanitized = AppLog.sanitizeMessageForPersistence(
        'lavf: cookie: affkey=demo; cf_clearance=secret; __cf_bm=token',
      );

      expect(sanitized, 'lavf: cookie: <redacted>');
      expect(sanitized, isNot(contains('cf_clearance=secret')));
      expect(sanitized, isNot(contains('__cf_bm=token')));
    });

    test('keeps non-sensitive diagnostics readable', () {
      final sanitized = AppLog.sanitizeMessageForPersistence(
        'buffered=10123ms quality=720p host=edge.example.com',
      );

      expect(sanitized, 'buffered=10123ms quality=720p host=edge.example.com');
    });
  });
}
