import 'package:flutter_test/flutter_test.dart';
import 'package:nolive_app/src/app/runtime_bridges/linux_async_js.dart';

void main() {
  group('LinuxAsyncJsJobCodec', () {
    test('start script returns "started" and never returns the Promise', () {
      final script = LinuxAsyncJsJobCodec.buildStartScript(
        jobId: 'job_1',
        functionBody: 'return await Promise.resolve(42);',
        arguments: const {'x': 1},
      );
      // Job bookkeeping is required for poll completion.
      expect(script, contains('__noliveAsyncJobs'));
      expect(script, contains('done: true'));
      expect(script, contains('return "started"'));
      // Must not be a bare async IIFE as the outer return value (old bug).
      expect(
        script.trimLeft().startsWith('(async function'),
        isFalse,
        reason: 'outer expression must not be an async IIFE Promise',
      );
    });

    test(
      'parsePollPayload returns null while pending (no false completion)',
      () {
        expect(LinuxAsyncJsJobCodec.parsePollPayload(null), isNull);
        expect(LinuxAsyncJsJobCodec.parsePollPayload('{"done":false}'), isNull);
        expect(
          LinuxAsyncJsJobCodec.parsePollPayload('{"done":false,"value":99}'),
          isNull,
          reason: 'value must be ignored until done=true',
        );
      },
    );

    test('parsePollPayload returns value only after done:true', () {
      final result = LinuxAsyncJsJobCodec.parsePollPayload(
        '{"done":true,"ok":true,"value":{"sig":"abc"}}',
      );
      expect(result, isNotNull);
      expect(result!.error, isNull);
      expect(result.value, isA<Map>());
      expect((result.value as Map)['sig'], 'abc');
    });

    test('parsePollPayload surfaces async errors when done', () {
      final result = LinuxAsyncJsJobCodec.parsePollPayload(
        '{"done":true,"ok":false,"error":"boom"}',
      );
      expect(result!.error, 'boom');
      expect(result.value, isNull);
    });

    test('resolveFromPollSequence fails if only pending samples exist', () {
      expect(
        () => LinuxAsyncJsJobCodec.resolveFromPollSequence(const [
          '{"done":false}',
          '{"done":false,"value":1}',
        ]),
        throwsA(isA<StateError>()),
      );
    });

    test(
      'resolveFromPollSequence waits for completion across poll samples',
      () {
        // This is the behavior shipped callAsyncJavaScript must implement:
        // first polls are pending; only a later done:true yields the value.
        final result = LinuxAsyncJsJobCodec.resolveFromPollSequence(const [
          '{"done":false}',
          '{"done":false}',
          '{"done":true,"ok":true,"value":{"n":"solved"}}',
        ]);
        expect(result.error, isNull);
        expect((result.value as Map)['n'], 'solved');
      },
    );

    test('poll script reads job by id', () {
      final poll = LinuxAsyncJsJobCodec.buildPollScript('job_xyz');
      expect(poll, contains('job_xyz'));
      expect(poll, contains('JSON.stringify'));
    });
  });
}
