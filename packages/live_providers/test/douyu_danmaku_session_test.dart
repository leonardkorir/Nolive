import 'dart:async';
import 'dart:typed_data';

import 'package:live_providers/src/danmaku/douyu_danmaku_session.dart';
import 'package:test/test.dart';

void main() {
  test('douyu danmaku session races both endpoints with browser headers',
      () async {
    final attempts =
        <({Uri uri, Map<String, dynamic> headers, Duration timeout})>[];
    final primaryClient = _FakeDouyuSocketClient();
    final fallbackClient = _FakeDouyuSocketClient();
    final session = DouyuDanmakuSession(
      roomId: '3125893',
      socketConnector: (uri,
          {required headers, required connectTimeout}) async {
        attempts.add((uri: uri, headers: headers, timeout: connectTimeout));
        return uri.port == 8502 ? primaryClient : fallbackClient;
      },
    );

    await session.connect();

    expect(attempts, hasLength(2));
    expect(
      attempts.map((item) => item.uri.toString()),
      containsAll(<String>[
        'wss://danmuproxy.douyu.com:8502/',
        'wss://danmuproxy.douyu.com:8506/',
      ]),
    );
    for (final attempt in attempts) {
      expect(attempt.headers['origin'], 'https://www.douyu.com');
      expect(attempt.headers['referer'], 'https://www.douyu.com/');
      expect(attempt.headers['user-agent'], contains('Mozilla/5.0'));
      expect(attempt.timeout, const Duration(seconds: 4));
    }
    expect(primaryClient.outgoingFrames, hasLength(2));
    expect(fallbackClient.closed, isTrue);

    await session.disconnect();
  });

  test('douyu danmaku session succeeds when 8502 fails but 8506 connects',
      () async {
    final attemptedUrls = <String>[];
    final session = DouyuDanmakuSession(
      roomId: '3125893',
      socketConnector: (uri,
          {required headers, required connectTimeout}) async {
        attemptedUrls.add(uri.toString());
        if (uri.port == 8502) {
          throw StateError('primary down');
        }
        return _FakeDouyuSocketClient();
      },
    );

    await session.connect();

    expect(
      attemptedUrls,
      containsAll(<String>[
        'wss://danmuproxy.douyu.com:8502/',
        'wss://danmuproxy.douyu.com:8506/',
      ]),
    );

    await session.disconnect();
  });
}

class _FakeDouyuSocketClient implements DouyuSocketClient {
  final StreamController<dynamic> _controller =
      StreamController<dynamic>.broadcast();
  final List<Uint8List> outgoingFrames = <Uint8List>[];
  bool closed = false;

  @override
  Stream<dynamic> get stream => _controller.stream;

  @override
  void add(dynamic data) {
    if (data is Uint8List) {
      outgoingFrames.add(data);
      return;
    }
    if (data is List<int>) {
      outgoingFrames.add(Uint8List.fromList(data));
    }
  }

  @override
  Future<void> close() async {
    closed = true;
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }
}
