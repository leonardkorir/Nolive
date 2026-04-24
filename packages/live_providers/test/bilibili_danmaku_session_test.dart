import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:live_core/live_core.dart';
import 'package:live_providers/src/danmaku/bilibili_danmaku_session.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/io.dart';

void main() {
  test('bilibili danmaku session waits for join ack before reporting connected',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));

    final requestHeaders = Completer<Map<String, String?>>();
    final upgradedSocket = Completer<WebSocket>();
    final joinPacket = Completer<Uint8List>();

    unawaited(
      server.first.then((request) async {
        requestHeaders.complete({
          'origin': request.headers.value('origin'),
          'referer': request.headers.value('referer'),
          'user-agent': request.headers.value('user-agent'),
          'cookie': request.headers.value('cookie'),
        });
        final socket = await WebSocketTransformer.upgrade(request);
        upgradedSocket.complete(socket);
        socket.listen((data) {
          if (data is List<int> && !joinPacket.isCompleted) {
            joinPacket.complete(Uint8List.fromList(data));
          }
        });
      }),
    );

    final session = BilibiliDanmakuSession(
      tokenData: {
        'roomId': 22747736,
        'uid': 445566,
        'token': 'mock-token',
        'serverHost': 'broadcastlv.chat.bilibili.com',
        'buvid': 'mock-buvid3',
        'cookie': 'SESSDATA=test-session; DedeUserID=445566;',
      },
      channelConnector: (
        _, {
        Map<String, dynamic>? headers,
        Iterable<String>? protocols,
        Duration connectTimeout = const Duration(seconds: 10),
      }) =>
          Future<IOWebSocketChannel>.value(
        IOWebSocketChannel.connect(
          'ws://127.0.0.1:${server.port}',
          headers: headers,
          protocols: protocols,
          connectTimeout: connectTimeout,
        ),
      ),
    );
    addTearDown(() => session.disconnect());

    final notices = <LiveMessage>[];
    final subscription = session.messages.listen(notices.add);
    addTearDown(subscription.cancel);

    var connectCompleted = false;
    final connectFuture = session.connect().then((_) {
      connectCompleted = true;
    });

    final firstPacket = await joinPacket.future.timeout(
      const Duration(seconds: 2),
    );
    expect(_readInt(firstPacket, 8, 4), 7);

    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(connectCompleted, isFalse);

    final socket =
        await upgradedSocket.future.timeout(const Duration(seconds: 2));
    socket.add(_encodePacket(jsonEncode({'code': 0}), 8));

    await connectFuture.timeout(const Duration(seconds: 2));

    final headers =
        await requestHeaders.future.timeout(const Duration(seconds: 2));
    expect(headers['origin'], 'https://live.bilibili.com');
    expect(headers['referer'], 'https://live.bilibili.com/');
    expect(headers['user-agent'], contains('Mozilla/5.0'));
    expect(headers['cookie'], contains('SESSDATA=test-session'));
    expect(
      notices.any((item) => item.content == 'Bilibili 实时弹幕已连接'),
      isTrue,
    );
  });

  test('bilibili danmaku session surfaces join ack failures as connect errors',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));

    final joinPacket = Completer<void>();
    final upgradedSocket = Completer<WebSocket>();

    unawaited(
      server.first.then((request) async {
        final socket = await WebSocketTransformer.upgrade(request);
        upgradedSocket.complete(socket);
        socket.listen((data) {
          if (data is List<int> && !joinPacket.isCompleted) {
            joinPacket.complete();
          }
        });
      }),
    );

    final session = BilibiliDanmakuSession(
      tokenData: {
        'roomId': 22747736,
        'uid': 445566,
        'token': 'mock-token',
        'serverHost': 'broadcastlv.chat.bilibili.com',
        'buvid': 'mock-buvid3',
        'cookie': 'SESSDATA=test-session; DedeUserID=445566;',
      },
      channelConnector: (
        _, {
        Map<String, dynamic>? headers,
        Iterable<String>? protocols,
        Duration connectTimeout = const Duration(seconds: 10),
      }) =>
          Future<IOWebSocketChannel>.value(
        IOWebSocketChannel.connect(
          'ws://127.0.0.1:${server.port}',
          headers: headers,
          protocols: protocols,
          connectTimeout: connectTimeout,
        ),
      ),
    );
    addTearDown(() => session.disconnect());

    final connectFuture = session.connect();
    await joinPacket.future.timeout(const Duration(seconds: 2));

    final socket =
        await upgradedSocket.future.timeout(const Duration(seconds: 2));
    socket.add(_encodePacket(jsonEncode({'code': -101}), 8));

    await expectLater(
      connectFuture,
      throwsA(
        isA<ProviderParseException>().having(
          (error) => error.message,
          'message',
          contains('code=-101'),
        ),
      ),
    );
  });
}

Uint8List _encodePacket(String body, int operation) {
  final bodyBytes = utf8.encode(body);
  final byteData = ByteData(16 + bodyBytes.length);
  byteData.setInt32(0, 16 + bodyBytes.length, Endian.big);
  byteData.setInt16(4, 16, Endian.big);
  byteData.setInt16(6, 0, Endian.big);
  byteData.setInt32(8, operation, Endian.big);
  byteData.setInt32(12, 1, Endian.big);
  final bytes = byteData.buffer.asUint8List();
  bytes.setRange(16, bytes.length, bodyBytes);
  return bytes;
}

int _readInt(Uint8List bytes, int offset, int length) {
  final data = ByteData.sublistView(bytes, offset, offset + length);
  return switch (length) {
    2 => data.getUint16(0, Endian.big),
    4 => data.getUint32(0, Endian.big),
    _ => 0,
  };
}
