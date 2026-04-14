import 'dart:async';

import 'package:web_socket_channel/io.dart';

const Duration defaultDanmakuWebSocketConnectTimeout = Duration(seconds: 10);

Future<IOWebSocketChannel> connectDanmakuWebSocket(
  Uri uri, {
  Map<String, dynamic>? headers,
  Iterable<String>? protocols,
  Duration connectTimeout = defaultDanmakuWebSocketConnectTimeout,
}) async {
  final channel = IOWebSocketChannel.connect(
    uri,
    headers: headers,
    protocols: protocols,
    connectTimeout: connectTimeout,
  );
  try {
    await waitForDanmakuSocketReady(
      channel.ready,
      connectTimeout: connectTimeout,
    );
    return channel;
  } catch (_) {
    await channel.sink.close();
    rethrow;
  }
}

Future<void> waitForDanmakuSocketReady(
  Future<void> ready, {
  Duration connectTimeout = defaultDanmakuWebSocketConnectTimeout,
}) {
  return ready.timeout(connectTimeout);
}
