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
}
