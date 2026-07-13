import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:live_core/live_core.dart';
import 'package:web_socket_channel/io.dart';

import 'danmaku_activity_watchdog.dart';
import '../providers/douyin/douyin_request_params.dart';
import 'danmaku_web_socket.dart';
import 'isolate_danmaku_session.dart';
import 'proto/douyin.pb.dart';

typedef DouyinWebsocketSignatureBuilder =
    Future<String> Function(String roomId, String userUniqueId);

PushFrame buildDouyinAckFrame($fixnum.Int64 logId, String internalExt) {
  return PushFrame()
    ..payloadType = 'ack'
    ..logId = logId
    ..payload = utf8.encode(internalExt);
}

class DouyinDanmakuSession extends IsolateDanmakuSession {
  DouyinDanmakuSession({
    required this.roomId,
    required this.userUniqueId,
    required this.cookie,
    required this.signatureBuilder,
    List<Uri>? serverUris,
    Duration inactivityTimeout = const Duration(minutes: 2),
  }) : _serverUris = serverUris ?? _defaultServerUris,
       _inactivityTimeout = inactivityTimeout;

  static final List<Uri> _defaultServerUris = <Uri>[
    Uri.parse('wss://webcast3-ws-web-lq.douyin.com/webcast/im/push/v2/'),
    Uri.parse('wss://webcast5-ws-web-lf.douyin.com/webcast/im/push/v2/'),
  ];

  final String roomId;
  final String userUniqueId;
  final String cookie;
  final DouyinWebsocketSignatureBuilder signatureBuilder;
  final List<Uri> _serverUris;
  final Duration _inactivityTimeout;

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
    if (_serverUris.isEmpty) {
      throw StateError('DouyinDanmakuSession: serverUris must not be empty');
    }
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final baseUri = _serverUris.first.replace(
      queryParameters: {
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
        'browser_platform': DouyinRequestParams.browserPlatformValue,
        'browser_name': DouyinRequestParams.browserNameValue,
        'browser_version': DouyinRequestParams.browserVersionValue,
        'browser_online': 'true',
        'tz_name': 'Asia/Shanghai',
        'identity': 'audience',
        'room_id': roomId,
        'heartbeatDuration': '0',
      },
    );
    final signature = await signatureBuilder(roomId, userUniqueId);
    final uri = baseUri.replace(
      queryParameters: {...baseUri.queryParameters, 'signature': signature},
    );
    final backupUri = _serverUris.length > 1
        ? _serverUris[1].replace(queryParameters: uri.queryParameters)
        : uri.replace(host: 'webcast5-ws-web-lf.douyin.com');
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
              notice: '抖音弹幕连接异常：$error',
            ),
          );
        },
        onDone: () {
          unawaited(
            _teardownRemoteDisconnect(
              channel: channel,
              subscription: subscription,
              notice: '抖音弹幕连接已断开',
            ),
          );
        },
        cancelOnError: false,
      );
      _subscription = subscription;
      _sendJoinHeartbeat();
      _heartbeatTimer = Timer.periodic(
        const Duration(seconds: 10),
        (_) => _sendJoinHeartbeat(),
      );
      emit(
        LiveMessage(
          type: LiveMessageType.notice,
          content: '抖音实时弹幕已连接',
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
    _activityWatchdog?.ping();
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
      unawaited(
        parseInWorker(DanmakuIsolateParserIds.douyin, bytes, (output) {
          for (final command in output.commands) {
            if (command.kind == DanmakuIsolateCommands.douyinAck &&
                command.bytes != null) {
              _channel?.sink.add(command.bytes!);
            }
          }
          emitParsedMessages(output);
        }),
      );
    } catch (error) {
      emitNotice('抖音弹幕解析失败：$error');
    }
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
        content: '抖音弹幕连接活动超时',
        timestamp: DateTime.now(),
      ),
    );
  }
}
