import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:live_core/live_core.dart';
import 'package:web_socket_channel/io.dart';

import '../providers/douyin/douyin_request_params.dart';
import 'danmaku_web_socket.dart';
import 'proto/douyin.pb.dart';

typedef DouyinWebsocketSignatureBuilder = Future<String> Function(
  String roomId,
  String userUniqueId,
);

class DouyinDanmakuSession implements DanmakuSession {
  DouyinDanmakuSession({
    required this.roomId,
    required this.userUniqueId,
    required this.cookie,
    required this.signatureBuilder,
  });

  static const _serverUrl =
      'wss://webcast3-ws-web-lq.douyin.com/webcast/im/push/v2/';

  final String roomId;
  final String userUniqueId;
  final String cookie;
  final DouyinWebsocketSignatureBuilder signatureBuilder;

  final StreamController<LiveMessage> _controller =
      StreamController<LiveMessage>.broadcast();

  IOWebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _heartbeatTimer;
  bool _connected = false;

  @override
  Stream<LiveMessage> get messages => _controller.stream;

  @override
  Future<void> connect() async {
    if (_connected) {
      return;
    }
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final baseUri = Uri.parse(_serverUrl).replace(queryParameters: {
      'app_name': 'douyin_web',
      'version_code': DouyinRequestParams.versionCodeValue,
      'webcast_sdk_version': DouyinRequestParams.sdkVersion,
      'update_version_code': DouyinRequestParams.sdkVersion,
      'compress': 'gzip',
      'cursor': 'h-1_t-${timestamp}_r-1_d-1_u-1',
      'host': 'https://live.douyin.com',
      'aid': DouyinRequestParams.aidValue,
      'live_id': '1',
      'did_rule': '3',
      'debug': 'false',
      'maxCacheMessageNumber': '20',
      'endpoint': 'live_pc',
      'support_wrds': '1',
      'im_path': '/webcast/im/fetch/',
      'user_unique_id': userUniqueId,
      'device_platform': 'web',
      'cookie_enabled': 'true',
      'screen_width': '1080',
      'screen_height': '2400',
      'browser_language': 'zh-CN',
      'browser_platform': 'Win32',
      'browser_name': 'Mozilla',
      'browser_version':
          DouyinRequestParams.kDefaultUserAgent.replaceAll('Mozilla/', ''),
      'browser_online': 'true',
      'tz_name': 'Asia/Shanghai',
      'identity': 'audience',
      'room_id': roomId,
      'heartbeatDuration': '0',
    });
    final signature = await signatureBuilder(roomId, userUniqueId);
    final uri = Uri.parse('$baseUri&signature=$signature');
    final backupUri = Uri.parse(
        uri.toString().replaceAll('webcast3-ws-web-lq', 'webcast5-ws-web-lf'));
    final headers = <String, dynamic>{
      'user-agent': DouyinRequestParams.kDefaultUserAgent,
      'origin': 'https://live.douyin.com',
      if (cookie.isNotEmpty) 'cookie': cookie,
    };
    final channel = await _connectSocketWithFallback(
      primaryUri: uri,
      backupUri: backupUri,
      headers: headers,
    );
    try {
      _channel = channel;
      _connected = true;
      _subscription = _channel!.stream.listen(
        _handleRawMessage,
        onError: (error) {
          _emit(
            LiveMessage(
              type: LiveMessageType.notice,
              content: '抖音弹幕连接异常：$error',
              timestamp: DateTime.now(),
            ),
          );
        },
        onDone: () {
          if (_connected) {
            _emit(
              LiveMessage(
                type: LiveMessageType.notice,
                content: '抖音弹幕连接已断开',
                timestamp: DateTime.now(),
              ),
            );
          }
        },
        cancelOnError: false,
      );
      _sendJoinHeartbeat();
      _heartbeatTimer = Timer.periodic(
        const Duration(seconds: 10),
        (_) => _sendJoinHeartbeat(),
      );
      _emit(
        LiveMessage(
          type: LiveMessageType.notice,
          content: '抖音实时弹幕已连接',
          timestamp: DateTime.now(),
        ),
      );
    } catch (_) {
      _connected = false;
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
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }

  void _sendJoinHeartbeat() {
    final frame = PushFrame()..payloadType = 'hb';
    _channel?.sink.add(frame.writeToBuffer());
  }

  Future<IOWebSocketChannel> _connectSocketWithFallback({
    required Uri primaryUri,
    required Uri backupUri,
    required Map<String, dynamic> headers,
  }) async {
    try {
      return await connectDanmakuWebSocket(
        primaryUri,
        headers: headers,
        protocols: const [],
      );
    } catch (_) {
      if (primaryUri == backupUri) {
        rethrow;
      }
      return connectDanmakuWebSocket(
        backupUri,
        headers: headers,
        protocols: const [],
      );
    }
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
    try {
      final frame = PushFrame.fromBuffer(bytes);
      final payload = gzip.decode(frame.payload);
      final response = Response.fromBuffer(payload);
      if (response.needAck) {
        _sendAck(frame.logId, response.internalExt);
      }
      for (final message in response.messagesList) {
        switch (message.method) {
          case 'WebcastChatMessage':
            _handleChatMessage(message.payload);
          case 'WebcastRoomUserSeqMessage':
            _handleUserSeqMessage(message.payload);
        }
      }
    } catch (error) {
      _emit(
        LiveMessage(
          type: LiveMessageType.notice,
          content: '抖音弹幕解析失败：$error',
          timestamp: DateTime.now(),
        ),
      );
    }
  }

  void _handleChatMessage(List<int> payload) {
    final message = ChatMessage.fromBuffer(payload);
    final content = message.content;
    if (content.isEmpty) {
      return;
    }
    _emit(
      LiveMessage(
        type: LiveMessageType.chat,
        content: content,
        userName: message.user.nickName,
        timestamp: DateTime.now(),
      ),
    );
  }

  void _handleUserSeqMessage(List<int> payload) {
    final message = RoomUserSeqMessage.fromBuffer(payload);
    _emit(
      LiveMessage(
        type: LiveMessageType.online,
        content: '当前人气 ${message.totalUser}',
        payload: message.totalUser,
        timestamp: DateTime.now(),
      ),
    );
  }

  void _sendAck($fixnum.Int64 logId, String internalExt) {
    final frame = PushFrame()
      ..payloadType = 'ack'
      ..logId = logId
      ..payloadType = internalExt;
    _channel?.sink.add(frame.writeToBuffer());
  }

  void _emit(LiveMessage message) {
    if (_controller.isClosed) {
      return;
    }
    _controller.add(message);
  }
}
