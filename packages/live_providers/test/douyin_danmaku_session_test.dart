import 'dart:convert';

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:live_providers/src/danmaku/douyin_danmaku_session.dart';
import 'package:test/test.dart';

void main() {
  test('douyin ack frame keeps ack payload type and stores internalExt', () {
    final frame =
        buildDouyinAckFrame($fixnum.Int64(42), 'internal-ext-payload');

    expect(frame.payloadType, 'ack');
    expect(frame.logId, $fixnum.Int64(42));
    expect(utf8.decode(frame.payload), 'internal-ext-payload');
  });

  test('douyin danmaku session throws on empty server URIs', () async {
    final session = DouyinDanmakuSession(
      roomId: '684885487846',
      userUniqueId: '1234567890',
      cookie: 'ttwid=demo',
      signatureBuilder: (roomId, userUniqueId) async => 'signature',
      serverUris: const [],
    );

    await expectLater(session.connect, throwsStateError);
  });
}
