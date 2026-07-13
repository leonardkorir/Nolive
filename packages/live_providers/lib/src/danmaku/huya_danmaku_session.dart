import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:live_core/live_core.dart';
import 'package:web_socket_channel/io.dart';

import 'danmaku_activity_watchdog.dart';
import 'danmaku_web_socket.dart';
import 'isolate_danmaku_session.dart';
import 'tars/codec/tars_output_stream.dart';

typedef HuyaDanmakuSocketConnector =
    Future<IOWebSocketChannel> Function(
      Uri uri, {
      Map<String, dynamic>? headers,
      Iterable<String>? protocols,
      Duration connectTimeout,
    });

class HuyaDanmakuSession extends IsolateDanmakuSession {
  HuyaDanmakuSession({
    required this.ayyuid,
    required this.topSid,
    required this.subSid,
    Duration inactivityTimeout = const Duration(minutes: 3),
    HuyaDanmakuSocketConnector? channelConnector,
  }) : _inactivityTimeout = inactivityTimeout,
       _channelConnector = channelConnector ?? connectDanmakuWebSocket;

  static const _serverUrl = 'wss://cdnws.api.huya.com';
  static final Uint8List _heartbeatData = Uint8List.fromList(
    base64.decode('ABQdAAwsNgBM'),
  );

  final int ayyuid;
  final int topSid;
  final int subSid;
  final Duration _inactivityTimeout;
  final HuyaDanmakuSocketConnector _channelConnector;

  IOWebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _heartbeatTimer;
  DanmakuActivityWatchdog? _activityWatchdog;
  bool _connected = false;

  @override
  Future<void> connect() async {
    if (_connected) {
      return;
    }
    final channel = await _channelConnector(Uri.parse(_serverUrl));
    try {
      _channel = channel;
      _connected = true;
      _activityWatchdog = DanmakuActivityWatchdog(
        timeout: _inactivityTimeout,
        onTimeout: _handleActivityTimeout,
      )..start();
      StreamSubscription<dynamic>? subscription;
      subscription = channel.stream.listen(
        _handleRawMessage,
        onError: (error) {
          unawaited(
            _teardownRemoteDisconnect(
              channel: channel,
              subscription: subscription,
              notice: '虎牙弹幕连接异常：$error',
            ),
          );
        },
        onDone: () {
          unawaited(
            _teardownRemoteDisconnect(
              channel: channel,
              subscription: subscription,
              notice: '虎牙弹幕连接已断开',
            ),
          );
        },
        cancelOnError: false,
      );
      _subscription = subscription;
      _channel?.sink.add(_buildJoinData());
      _heartbeatTimer = Timer.periodic(
        const Duration(seconds: 60),
        (_) => _channel?.sink.add(_heartbeatData),
      );
      emit(
        LiveMessage(
          type: LiveMessageType.notice,
          content: '虎牙实时弹幕已连接',
          timestamp: DateTime.now(),
        ),
      );
    } catch (_) {
      _connected = false;
      _activityWatchdog?.stop();
      _activityWatchdog = null;
      await _subscription?.cancel();
      _subscription = null;
      await channel.sink.close();
      if (identical(_channel, channel)) {
        _channel = null;
      }
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _activityWatchdog?.stop();
    _activityWatchdog = null;
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
    await closeIsolateDanmakuSession();
  }

  Future<void> _teardownRemoteDisconnect({
    required IOWebSocketChannel channel,
    required StreamSubscription<dynamic>? subscription,
    required String notice,
  }) async {
    if (!identical(_channel, channel) ||
        !identical(_subscription, subscription)) {
      return;
    }
    _connected = false;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _activityWatchdog?.stop();
    _activityWatchdog = null;
    _subscription = null;
    _channel = null;
    emit(
      LiveMessage(
        type: LiveMessageType.notice,
        content: notice,
        timestamp: DateTime.now(),
      ),
    );
    try {
      await subscription?.cancel();
    } catch (_) {}
    try {
      await channel.sink.close();
    } catch (_) {}
  }

  List<int> _buildJoinData() {
    final payload = TarsOutputStream();
    payload.write(ayyuid, 0);
    payload.write(true, 1);
    payload.write('', 2);
    payload.write('', 3);
    payload.write(topSid, 4);
    payload.write(subSid, 5);
    payload.write(0, 6);
    payload.write(0, 7);

    final frame = TarsOutputStream();
    frame.write(1, 0);
    frame.write(payload.toUint8List(), 1);
    return frame.toUint8List();
  }

  void _handleRawMessage(dynamic raw) {
    final bytes = switch (raw) {
      Uint8List data => data,
      List<int> data => Uint8List.fromList(data),
      String data => Uint8List.fromList(utf8.encode(data)),
      _ => Uint8List(0),
    };
    if (bytes.isEmpty) {
      return;
    }
    _activityWatchdog?.ping();
    unawaited(
      parseInWorker(DanmakuIsolateParserIds.huya, bytes, emitParsedMessages),
    );
  }

  Future<void> _handleActivityTimeout() async {
    if (!_connected) {
      return;
    }
    _connected = false;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _activityWatchdog?.stop();
    _activityWatchdog = null;
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
    emit(
      LiveMessage(
        type: LiveMessageType.notice,
        content: '虎牙弹幕连接活动超时',
        timestamp: DateTime.now(),
      ),
    );
  }
}
