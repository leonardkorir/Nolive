import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:live_core/live_core.dart';
import 'package:web_socket_channel/io.dart';

import 'danmaku_activity_watchdog.dart';
import 'danmaku_web_socket.dart';
import 'tars/codec/tars_input_stream.dart';
import 'tars/codec/tars_output_stream.dart';
import 'tars/huya_danmaku.dart';

class HuyaDanmakuSession implements DanmakuSession {
  HuyaDanmakuSession({
    required this.ayyuid,
    required this.topSid,
    required this.subSid,
    Duration inactivityTimeout = const Duration(minutes: 3),
  }) : _inactivityTimeout = inactivityTimeout;

  static const _serverUrl = 'wss://cdnws.api.huya.com';
  static final Uint8List _heartbeatData =
      Uint8List.fromList(base64.decode('ABQdAAwsNgBM'));

  final int ayyuid;
  final int topSid;
  final int subSid;
  final Duration _inactivityTimeout;

  final StreamController<LiveMessage> _controller =
      StreamController<LiveMessage>.broadcast();

  IOWebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _heartbeatTimer;
  DanmakuActivityWatchdog? _activityWatchdog;
  bool _connected = false;

  @override
  Stream<LiveMessage> get messages => _controller.stream;

  @override
  Future<void> connect() async {
    if (_connected) {
      return;
    }
    final channel = await connectDanmakuWebSocket(Uri.parse(_serverUrl));
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
      _emit(
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
    if (!_controller.isClosed) {
      await _controller.close();
    }
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
    _emit(
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
    try {
      var input = TarsInputStream(bytes);
      final type = input.read(0, 0, false);
      if (type != 7) {
        return;
      }
      input = TarsInputStream(input.readBytes(1, false));
      final pushMessage = HYPushMessage()..readFrom(input);
      if (pushMessage.uri == 1400) {
        final message = HYMessage();
        message.readFrom(
          TarsInputStream(Uint8List.fromList(pushMessage.msg)),
        );
        _emit(
          LiveMessage(
            type: LiveMessageType.chat,
            content: message.content,
            userName: message.userInfo.nickName,
            timestamp: DateTime.now(),
          ),
        );
        return;
      }
      if (pushMessage.uri == 8006) {
        final onlineStream =
            TarsInputStream(Uint8List.fromList(pushMessage.msg));
        final online = onlineStream.read(0, 0, false);
        _emit(
          LiveMessage(
            type: LiveMessageType.online,
            content: '当前人气 $online',
            payload: online,
            timestamp: DateTime.now(),
          ),
        );
      }
    } catch (error) {
      _emit(
        LiveMessage(
          type: LiveMessageType.notice,
          content: '虎牙弹幕解析失败：$error',
          timestamp: DateTime.now(),
        ),
      );
    }
  }

  void _emit(LiveMessage message) {
    if (_controller.isClosed) {
      return;
    }
    _controller.add(message);
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
    _emit(
      LiveMessage(
        type: LiveMessageType.notice,
        content: '虎牙弹幕连接活动超时',
        timestamp: DateTime.now(),
      ),
    );
  }
}
