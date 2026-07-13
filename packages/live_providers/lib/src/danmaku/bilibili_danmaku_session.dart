import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:live_core/live_core.dart';
import 'package:web_socket_channel/io.dart';

import 'danmaku_activity_watchdog.dart';
import 'danmaku_web_socket.dart';
import 'isolate_danmaku_session.dart';

typedef BilibiliDanmakuSocketConnector =
    Future<IOWebSocketChannel> Function(
      Uri uri, {
      Map<String, dynamic>? headers,
      Iterable<String>? protocols,
      Duration connectTimeout,
    });

class BilibiliDanmakuSession extends IsolateDanmakuSession {
  BilibiliDanmakuSession({
    required BilibiliDanmakuToken danmakuToken,
    BilibiliDanmakuSocketConnector? channelConnector,
    Duration inactivityTimeout = const Duration(minutes: 2),
  }) : _channelConnector = channelConnector ?? connectDanmakuWebSocket,
       _inactivityTimeout = inactivityTimeout,
       roomId = danmakuToken.roomId,
       uid = _resolveUid(
         rawUid: danmakuToken.uid,
         rawCookie: danmakuToken.cookie,
       ),
       token = danmakuToken.token,
       serverHost = danmakuToken.serverHost.trim().isNotEmpty
           ? danmakuToken.serverHost
           : 'broadcastlv.chat.bilibili.com',
       buvid = danmakuToken.buvid,
       cookie = danmakuToken.cookie;

  static const String _origin = 'https://live.bilibili.com';
  static const String _referer = 'https://live.bilibili.com/';
  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36 Edg/126.0.0.0';
  final BilibiliDanmakuSocketConnector _channelConnector;
  final int roomId;
  final int uid;
  final String token;
  final String serverHost;
  final String buvid;
  final String cookie;
  final Duration _inactivityTimeout;

  IOWebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _heartbeatTimer;
  DanmakuActivityWatchdog? _activityWatchdog;
  bool _connected = false;
  bool _handshakeReady = false;
  bool _joinAckSucceeded = false;
  Completer<void>? _connectReady;

  @override
  Future<void> connect() async {
    if (_connected) {
      return;
    }
    final headers = _buildConnectionHeaders();
    final channel = await _channelConnector(
      Uri.parse('wss://$serverHost/sub'),
      headers: headers.isEmpty ? null : headers,
    );
    try {
      _channel = channel;
      _connected = true;
      _handshakeReady = false;
      _joinAckSucceeded = false;
      _connectReady = Completer<void>();
      _activityWatchdog = DanmakuActivityWatchdog(
        timeout: _inactivityTimeout,
        onTimeout: _handleActivityTimeout,
      )..start();
      StreamSubscription<dynamic>? subscription;
      subscription = channel.stream.listen(
        _handleRawMessage,
        onError: (error) {
          if (!_handshakeReady) {
            _failConnectReady(error);
            unawaited(
              _teardownRemoteDisconnect(
                channel: channel,
                subscription: subscription,
              ),
            );
            return;
          }
          if (_connected) {
            unawaited(
              _teardownRemoteDisconnect(
                channel: channel,
                subscription: subscription,
                notice: 'Bilibili 弹幕连接异常：$error',
              ),
            );
          }
        },
        onDone: () {
          if (!_handshakeReady) {
            _failConnectReady(_buildConnectFailure('Bilibili 弹幕连接在握手完成前已断开。'));
            unawaited(
              _teardownRemoteDisconnect(
                channel: channel,
                subscription: subscription,
              ),
            );
            return;
          }
          if (_connected) {
            unawaited(
              _teardownRemoteDisconnect(
                channel: channel,
                subscription: subscription,
                notice: 'Bilibili 弹幕连接已断开',
              ),
            );
          }
        },
        cancelOnError: false,
      );
      _subscription = subscription;
      _sendJoinRoom();
      _heartbeatTimer = Timer.periodic(
        const Duration(seconds: 30),
        (_) => _sendHeartbeat(),
      );
      await _connectReady!.future;
      emit(
        LiveMessage(
          type: LiveMessageType.notice,
          content: 'Bilibili 实时弹幕已连接',
          timestamp: DateTime.now(),
        ),
      );
    } catch (_) {
      _connected = false;
      _handshakeReady = false;
      _connectReady = null;
      _heartbeatTimer?.cancel();
      _heartbeatTimer = null;
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
    _handshakeReady = false;
    _connectReady = null;
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

  void _sendJoinRoom() {
    final payload = jsonEncode({
      'uid': uid,
      'roomid': roomId,
      'protover': 3,
      'buvid': buvid,
      'platform': 'web',
      'type': 2,
      'key': token,
    });
    _channel?.sink.add(_encodePacket(payload, 7));
  }

  void _sendHeartbeat() {
    _channel?.sink.add(_encodePacket('', 2));
  }

  List<int> _encodePacket(String body, int operation) {
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
      parseInWorker(
        DanmakuIsolateParserIds.bilibili,
        bytes,
        _handleParsedRawMessage,
      ),
    );
  }

  Future<void> _handleActivityTimeout() async {
    if (!_connected) {
      return;
    }
    _connected = false;
    _handshakeReady = false;
    _connectReady = null;
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
        content: 'Bilibili 弹幕连接活动超时',
        timestamp: DateTime.now(),
      ),
    );
  }

  Map<String, dynamic> _buildConnectionHeaders() {
    final headers = <String, dynamic>{
      'origin': _origin,
      'referer': _referer,
      'user-agent': _userAgent,
      'accept-language': 'zh-CN,zh;q=0.9',
      'cache-control': 'no-cache',
      'pragma': 'no-cache',
    };
    if (cookie.isNotEmpty) {
      headers['cookie'] = cookie;
    }
    return headers;
  }

  Future<void> _teardownRemoteDisconnect({
    IOWebSocketChannel? channel,
    StreamSubscription<dynamic>? subscription,
    String? notice,
  }) async {
    if (channel != null && !identical(_channel, channel)) {
      return;
    }
    if (subscription != null && !identical(_subscription, subscription)) {
      return;
    }
    _connected = false;
    _handshakeReady = false;
    _connectReady = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _activityWatchdog?.stop();
    _activityWatchdog = null;
    _subscription = null;
    _channel = null;
    if (notice != null) {
      emit(
        LiveMessage(
          type: LiveMessageType.notice,
          content: notice,
          timestamp: DateTime.now(),
        ),
      );
    }
    try {
      await subscription?.cancel();
    } catch (_) {}
    try {
      await channel?.sink.close();
    } catch (_) {}
  }

  void _handleParsedRawMessage(DanmakuIsolateParseOutput output) {
    for (final command in output.commands) {
      switch (command.kind) {
        case DanmakuIsolateCommands.bilibiliJoinAckOk:
          _joinAckSucceeded = true;
          _completeConnectReady();
        case DanmakuIsolateCommands.bilibiliJoinAckFailed:
          _failConnectReady(
            _buildConnectFailure(command.message ?? 'Bilibili 弹幕鉴权失败'),
          );
        case DanmakuIsolateCommands.bilibiliAuthorized:
          _completeConnectReadyIfAuthorized();
      }
    }
    emitParsedMessages(output);
  }

  void _completeConnectReady() {
    if (_handshakeReady) {
      return;
    }
    _handshakeReady = true;
    final ready = _connectReady;
    if (ready != null && !ready.isCompleted) {
      ready.complete();
    }
  }

  void _completeConnectReadyIfAuthorized() {
    if (!_joinAckSucceeded) {
      return;
    }
    _completeConnectReady();
  }

  void _failConnectReady(Object error, [StackTrace? stackTrace]) {
    final ready = _connectReady;
    if (ready == null || ready.isCompleted) {
      return;
    }
    ready.completeError(error, stackTrace);
  }

  ProviderParseException _buildConnectFailure(String message) {
    return ProviderParseException(
      providerId: ProviderId.bilibili,
      message: message,
    );
  }

  static int _toInt(Object? value) {
    if (value is int) {
      return value;
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static int _resolveUid({
    required Object? rawUid,
    required Object? rawCookie,
  }) {
    final cookie = rawCookie?.toString() ?? '';
    if (!_hasAuthenticatedCookie(cookie)) {
      return 0;
    }
    final cookieUid = _extractCookieUid(cookie);
    if (cookieUid != null && cookieUid > 0) {
      return cookieUid;
    }
    final uid = _toInt(rawUid);
    return uid > 0 ? uid : 0;
  }

  static bool _hasAuthenticatedCookie(String cookie) {
    return RegExp(r'(?:^|;\s*)SESSDATA=').hasMatch(cookie);
  }

  static int? _extractCookieUid(String cookie) {
    final match = RegExp(r'(?:^|;\s*)DedeUserID=(\d+)').firstMatch(cookie);
    return int.tryParse(match?.group(1) ?? '');
  }
}
