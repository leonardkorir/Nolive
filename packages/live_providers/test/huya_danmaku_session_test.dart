import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:live_core/live_core.dart';
import 'package:live_providers/src/danmaku/huya_danmaku_session.dart';
import 'package:live_providers/src/danmaku/tars/codec/tars_output_stream.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/io.dart';

enum TarsStructType {
  byte,
  short,
  int,
  long,
  float,
  double,
  string1,
  string4,
  map,
  list,
  structBegin,
  structEnd,
  zeroTag,
  simpleList,
}

Uint8List encodeHuyaFrame({required int type, required Uint8List payload}) {
  final out = TarsOutputStream();
  out.writeInt(type, 0); // Tag 0
  out.writeUint8List(payload, 1); // Tag 1
  return out.toUint8List();
}

Uint8List encodeHYPushMessage({required int uri, required Uint8List msg}) {
  final out = TarsOutputStream();
  out.writeInt(0, 0); // pushType
  out.writeInt(uri, 1); // uri
  out.writeUint8List(msg, 2); // msg
  out.writeInt(0, 3); // protocolType
  return out.toUint8List();
}

Uint8List encodeHYMessage({required String nickName, required String content}) {
  final out = TarsOutputStream();

  // Tag 0: HYSender userInfo
  out.writeHead(TarsStructType.structBegin.index, 0);
  out.writeInt(12345, 0); // uid
  out.writeInt(67890, 1); // lMid
  out.writeString(nickName, 2); // nickName
  out.writeInt(1, 3); // gender
  out.writeHead(TarsStructType.structEnd.index, 0);

  // Tag 3: content
  out.writeString(content, 3);

  // Tag 6: HYBulletFormat bulletFormat
  out.writeHead(TarsStructType.structBegin.index, 6);
  out.writeInt(0, 0);
  out.writeInt(4, 1);
  out.writeInt(0, 2);
  out.writeInt(1, 3);
  out.writeHead(TarsStructType.structEnd.index, 0);

  return out.toUint8List();
}

Uint8List encodeHuyaOnline(int online) {
  final out = TarsOutputStream();
  out.writeInt(online, 0);
  return out.toUint8List();
}

void main() {
  test('HuyaDanmakuSession sends join data on connect', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));

    final joinPacket = Completer<Uint8List>();
    unawaited(
      server.first.then((request) async {
        final socket = await WebSocketTransformer.upgrade(request);
        socket.listen((data) {
          if (data is List<int> && !joinPacket.isCompleted) {
            joinPacket.complete(Uint8List.fromList(data));
          }
        });
      }),
    );

    final session = HuyaDanmakuSession(
      ayyuid: 11111,
      topSid: 22222,
      subSid: 33333,
      channelConnector:
          (
            _, {
            headers,
            protocols,
            Duration connectTimeout = const Duration(seconds: 10),
          }) => Future<IOWebSocketChannel>.value(
            IOWebSocketChannel.connect('ws://127.0.0.1:${server.port}'),
          ),
    );
    addTearDown(() => session.disconnect());

    await session.connect();
    final joinData = await joinPacket.future.timeout(
      const Duration(seconds: 2),
    );
    expect(joinData, isNotEmpty);
  });

  test('HuyaDanmakuSession decodes chat and online messages', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));

    final upgradedSocket = Completer<WebSocket>();
    unawaited(
      server.first.then((request) async {
        final socket = await WebSocketTransformer.upgrade(request);
        upgradedSocket.complete(socket);
      }),
    );

    final session = HuyaDanmakuSession(
      ayyuid: 11111,
      topSid: 22222,
      subSid: 33333,
      channelConnector:
          (
            _, {
            headers,
            protocols,
            Duration connectTimeout = const Duration(seconds: 10),
          }) => Future<IOWebSocketChannel>.value(
            IOWebSocketChannel.connect('ws://127.0.0.1:${server.port}'),
          ),
    );
    addTearDown(() => session.disconnect());

    final messages = <LiveMessage>[];
    final sub = session.messages.listen(messages.add);
    addTearDown(sub.cancel);

    await session.connect();
    final socket = await upgradedSocket.future.timeout(
      const Duration(seconds: 2),
    );

    // Send a Chat Message (uri 1400)
    final chatMsgBytes = encodeHYMessage(
      nickName: 'Tester',
      content: 'Hello Huya',
    );
    final pushMsgBytes = encodeHYPushMessage(uri: 1400, msg: chatMsgBytes);
    final chatFrame = encodeHuyaFrame(type: 7, payload: pushMsgBytes);
    socket.add(chatFrame);

    // Send an Online Popularity Message (uri 8006)
    final onlineBytes = encodeHuyaOnline(98765);
    final pushMsgOnlineBytes = encodeHYPushMessage(uri: 8006, msg: onlineBytes);
    final onlineFrame = encodeHuyaFrame(type: 7, payload: pushMsgOnlineBytes);
    socket.add(onlineFrame);

    // Give some time for stream to deliver messages
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final chatMsg = messages.firstWhere((m) => m.type == LiveMessageType.chat);
    expect(chatMsg.content, 'Hello Huya');
    expect(chatMsg.userName, 'Tester');

    final onlineMsg = messages.firstWhere(
      (m) => m.type == LiveMessageType.online,
    );
    expect(onlineMsg.content, '当前人气 98765');
    expect(onlineMsg.payload, 98765);
  });

  test('HuyaDanmakuSession handles invalid frames gracefully', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));

    final upgradedSocket = Completer<WebSocket>();
    unawaited(
      server.first.then((request) async {
        final socket = await WebSocketTransformer.upgrade(request);
        upgradedSocket.complete(socket);
      }),
    );

    final session = HuyaDanmakuSession(
      ayyuid: 11111,
      topSid: 22222,
      subSid: 33333,
      channelConnector:
          (
            _, {
            headers,
            protocols,
            Duration connectTimeout = const Duration(seconds: 10),
          }) => Future<IOWebSocketChannel>.value(
            IOWebSocketChannel.connect('ws://127.0.0.1:${server.port}'),
          ),
    );
    addTearDown(() => session.disconnect());

    final messages = <LiveMessage>[];
    final sub = session.messages.listen(messages.add);
    addTearDown(sub.cancel);

    await session.connect();
    final socket = await upgradedSocket.future.timeout(
      const Duration(seconds: 2),
    );

    // Send a truncated frame
    socket.add(Uint8List.fromList([7, 0])); // invalid tars format

    await Future<void>.delayed(const Duration(milliseconds: 100));

    final noticeMsg = messages.firstWhere(
      (m) => m.type == LiveMessageType.notice && m.content.contains('虎牙弹幕解析失败'),
    );
    expect(noticeMsg, isNotNull);
  });

  test('HuyaDanmakuSession disconnect cancels resources', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));

    unawaited(
      server.first.then((request) async {
        await WebSocketTransformer.upgrade(request);
      }),
    );

    final session = HuyaDanmakuSession(
      ayyuid: 11111,
      topSid: 22222,
      subSid: 33333,
      channelConnector:
          (
            _, {
            headers,
            protocols,
            Duration connectTimeout = const Duration(seconds: 10),
          }) => Future<IOWebSocketChannel>.value(
            IOWebSocketChannel.connect('ws://127.0.0.1:${server.port}'),
          ),
    );

    await session.connect();
    await session.disconnect();
    // Simply verifying no active socket stream errors are thrown.
  });

  test('HuyaDanmakuSession activity timeout disconnects', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));

    unawaited(
      server.first.then((request) async {
        await WebSocketTransformer.upgrade(request);
      }),
    );

    final session = HuyaDanmakuSession(
      ayyuid: 11111,
      topSid: 22222,
      subSid: 33333,
      inactivityTimeout: const Duration(milliseconds: 50),
      channelConnector:
          (
            _, {
            headers,
            protocols,
            Duration connectTimeout = const Duration(seconds: 10),
          }) => Future<IOWebSocketChannel>.value(
            IOWebSocketChannel.connect('ws://127.0.0.1:${server.port}'),
          ),
    );
    addTearDown(() => session.disconnect());

    final messages = <LiveMessage>[];
    final sub = session.messages.listen(messages.add);
    addTearDown(sub.cancel);

    await session.connect();
    await Future<void>.delayed(const Duration(milliseconds: 150));

    final timeoutMsg = messages.firstWhere((m) => m.content.contains('活动超时'));
    expect(timeoutMsg, isNotNull);
  });
}
