import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:live_hls_proxy/src/aes_worker.dart';
import 'package:test/test.dart';

void main() {
  test('HLS AES worker reuses one isolate for multiple segments', () async {
    const pdkey = 'pdkey-session-reuse';
    final session = HlsAesWorkerSession(debugLabel: 'test-reuse');
    addTearDown(session.dispose);

    final clearSegments = <String>[
      'segment_001.mp4',
      'path/to/segment_002.m4s',
      'https://cdn.example.test/segment_003.mp4',
    ];
    final results = await Future.wait(
      clearSegments.map(
        (segment) => session.decryptStripchatMouflonSegment(
          encryptedSegment: _encryptSegmentForTest(segment, pdkey),
          pdkey: pdkey,
        ),
      ),
    );

    expect(results, clearSegments);
    expect(session.debugSpawnCount, 1);
    expect(session.debugHasActiveWorker, isTrue);
  });

  test('HLS AES worker closes when session is disposed', () async {
    const pdkey = 'pdkey-dispose';
    final session = HlsAesWorkerSession(debugLabel: 'test-dispose');

    final result = await session.decryptStripchatMouflonSegment(
      encryptedSegment: _encryptSegmentForTest('segment_dispose.mp4', pdkey),
      pdkey: pdkey,
    );
    expect(result, 'segment_dispose.mp4');
    expect(session.debugHasActiveWorker, isTrue);

    await session.dispose();

    expect(session.debugHasActiveWorker, isFalse);
    await expectLater(
      session.decryptStripchatMouflonSegment(
        encryptedSegment: _encryptSegmentForTest('segment_late.mp4', pdkey),
        pdkey: pdkey,
      ),
      throwsA(isA<StateError>()),
    );
  });

  test(
    'HLS AES worker propagates command errors and keeps decrypting',
    () async {
      const pdkey = 'pdkey-error-recovery';
      final session = HlsAesWorkerSession(debugLabel: 'test-error');
      addTearDown(session.dispose);

      final first = await session.decryptStripchatMouflonSegment(
        encryptedSegment: _encryptSegmentForTest('segment_before.mp4', pdkey),
        pdkey: pdkey,
      );
      expect(first, 'segment_before.mp4');

      await expectLater(
        session.sendUnsupportedCommandForTesting(),
        throwsA(isA<StateError>()),
      );

      final second = await session.decryptStripchatMouflonSegment(
        encryptedSegment: _encryptSegmentForTest('segment_after.mp4', pdkey),
        pdkey: pdkey,
      );
      expect(second, 'segment_after.mp4');
      expect(session.debugSpawnCount, 1);
    },
  );
}

String _encryptSegmentForTest(String value, String pdkey) {
  final input = utf8.encode(value);
  final hashBytes = sha256.convert(utf8.encode(pdkey)).bytes;
  final output = List<int>.generate(
    input.length,
    (index) => input[index] ^ hashBytes[index % hashBytes.length],
  );
  return base64.encode(output).split('').reversed.join();
}
