import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:brotli/brotli.dart';
import 'package:live_core/live_core.dart';
import 'package:web_socket_channel/io.dart';

import 'danmaku_web_socket.dart';

typedef BilibiliDanmakuSocketConnector = Future<IOWebSocketChannel> Function(
  Uri uri, {
  Map<String, dynamic>? headers,
  Iterable<String>? protocols,
  Duration connectTimeout,
});

class BilibiliDanmakuSession implements DanmakuSession {
  BilibiliDanmakuSession({
    required Map<String, Object?> tokenData,
    BilibiliDanmakuSocketConnector? channelConnector,
  })  : _channelConnector = channelConnector ?? connectDanmakuWebSocket,
        roomId = _toInt(tokenData['roomId']),
        uid = _resolveUid(
          rawUid: tokenData['uid'],
          rawCookie: tokenData['cookie'],
        ),
        token = tokenData['token']?.toString() ?? '',
        serverHost = tokenData['serverHost']?.toString().isNotEmpty == true
            ? tokenData['serverHost']!.toString()
            : 'broadcastlv.chat.bilibili.com',
        buvid = tokenData['buvid']?.toString() ?? '',
        cookie = tokenData['cookie']?.toString() ?? '';

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

  final StreamController<LiveMessage> _controller =
      StreamController<LiveMessage>.broadcast();

  IOWebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _heartbeatTimer;
  bool _connected = false;
  bool _handshakeReady = false;
  Completer<void>? _connectReady;

  @override
  Stream<LiveMessage> get messages => _controller.stream;

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
      _connectReady = Completer<void>();
      _subscription = _channel!.stream.listen(
        _handleRawMessage,
        onError: (error) {
          if (!_handshakeReady) {
            _failConnectReady(error);
            return;
          }
          if (_connected) {
            _emit(
              LiveMessage(
                type: LiveMessageType.notice,
                content: 'Bilibili 弹幕连接异常：$error',
                timestamp: DateTime.now(),
              ),
            );
          }
        },
        onDone: () {
          if (!_handshakeReady) {
            _failConnectReady(
              _buildConnectFailure('Bilibili 弹幕连接在握手完成前已断开。'),
            );
            return;
          }
          if (_connected) {
            _emit(
              LiveMessage(
                type: LiveMessageType.notice,
                content: 'Bilibili 弹幕连接已断开',
                timestamp: DateTime.now(),
              ),
            );
          }
        },
        cancelOnError: false,
      );
      _sendJoinRoom();
      _heartbeatTimer = Timer.periodic(
        const Duration(seconds: 30),
        (_) => _sendHeartbeat(),
      );
      await _connectReady!.future;
      _emit(
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
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
    if (!_controller.isClosed) {
      await _controller.close();
    }
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
    _decodePackets(bytes);
  }

  void _decodePackets(Uint8List bytes) {
    var offset = 0;
    while (offset + 16 <= bytes.length) {
      final packetLength = _readInt(bytes, offset, 4);
      if (packetLength <= 0 || offset + packetLength > bytes.length) {
        break;
      }
      _decodePacket(bytes.sublist(offset, offset + packetLength));
      offset += packetLength;
    }
  }

  void _decodePacket(Uint8List packet) {
    final protocolVersion = _readInt(packet, 6, 2);
    final operation = _readInt(packet, 8, 4);
    var body = packet.sublist(16);

    if (operation == 8) {
      _handleJoinAck(body);
      return;
    }

    if (operation == 3 && body.length >= 4) {
      _completeConnectReady();
      _emit(
        LiveMessage(
          type: LiveMessageType.online,
          content: '当前人气 ${_readInt(body, 0, 4)}',
          timestamp: DateTime.now(),
        ),
      );
      return;
    }

    if (operation != 5) {
      return;
    }

    _completeConnectReady();
    if (protocolVersion == 2) {
      body = Uint8List.fromList(zlib.decode(body));
      _decodePackets(body);
      return;
    }

    if (protocolVersion == 3) {
      body = Uint8List.fromList(brotli.decode(body));
      _decodePackets(body);
      return;
    }

    final text = utf8.decode(body, allowMalformed: true);
    final groups = text
        .split(RegExp(r'[\x00-\x1f]+', unicode: true, multiLine: true))
        .where((item) => item.length > 2 && item.trim().startsWith('{'));
    for (final item in groups) {
      _parseJsonMessage(item);
    }
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

  void _handleJoinAck(Uint8List body) {
    final failureMessage = _parseJoinAckFailure(body);
    if (failureMessage == null) {
      _completeConnectReady();
      return;
    }
    _failConnectReady(
      _buildConnectFailure(failureMessage),
    );
  }

  String? _parseJoinAckFailure(Uint8List body) {
    if (body.isEmpty) {
      return null;
    }
    final raw = utf8.decode(body, allowMalformed: true).trim();
    if (raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          final code = _toInt(decoded['code']);
          if (code == 0) {
            return null;
          }
          return 'Bilibili 弹幕鉴权失败 code=$code';
        }
      } catch (_) {
        // Fall through to the binary status parsing below.
      }
    }
    if (body.length >= 4 && _readInt(body, 0, 4) == 0) {
      return null;
    }
    return 'Bilibili 弹幕鉴权失败';
  }

  void _parseJsonMessage(String text) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map) {
        return;
      }
      final obj = decoded.cast<String, dynamic>();
      final cmd = obj['cmd']?.toString() ?? '';
      if (cmd.contains('DANMU_MSG')) {
        final info = obj['info'];
        if (info is List && info.length > 2) {
          final content = info[1]?.toString() ?? '';
          final userName = (info[2] is List && (info[2] as List).length > 1)
              ? info[2][1]?.toString()
              : null;
          if (content.isNotEmpty) {
            _emit(
              LiveMessage(
                type: LiveMessageType.chat,
                content: content,
                userName: userName,
                timestamp: DateTime.now(),
              ),
            );
          }
        }
        return;
      }

      if (cmd == 'SUPER_CHAT_MESSAGE') {
        final data = obj['data'];
        if (data is Map) {
          _emit(
            LiveMessage(
              type: LiveMessageType.superChat,
              content: data['message']?.toString() ?? '醒目留言',
              userName: data['user_info'] is Map
                  ? (data['user_info'] as Map)['uname']?.toString()
                  : null,
              payload: data,
              timestamp: DateTime.now(),
            ),
          );
        }
        return;
      }

      if (cmd == 'SEND_GIFT') {
        final data = obj['data'];
        if (data is Map) {
          final giftName = data['giftName']?.toString() ?? '礼物';
          final userName = data['uname']?.toString();
          _emit(
            LiveMessage(
              type: LiveMessageType.gift,
              content: '送出了 $giftName',
              userName: userName,
              payload: data,
              timestamp: DateTime.now(),
            ),
          );
        }
        return;
      }

      if (cmd == 'INTERACT_WORD' || cmd == 'ENTRY_EFFECT') {
        final data = obj['data'];
        final userName = data is Map ? data['uname']?.toString() : null;
        _emit(
          LiveMessage(
            type: LiveMessageType.member,
            content: '${userName ?? '用户'} 进入了直播间',
            userName: userName,
            payload: data,
            timestamp: DateTime.now(),
          ),
        );
        return;
      }

      if (cmd == 'NOTICE_MSG') {
        final data =
            obj['msg_common']?.toString() ?? obj['msg_self']?.toString();
        if (data != null && data.isNotEmpty) {
          _emit(
            LiveMessage(
              type: LiveMessageType.notice,
              content: data,
              timestamp: DateTime.now(),
            ),
          );
        }
      }
    } catch (_) {}
  }

  void _emit(LiveMessage message) {
    if (_controller.isClosed) {
      return;
    }
    _controller.add(message);
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

  static int _readInt(Uint8List bytes, int offset, int length) {
    final data = ByteData.sublistView(bytes, offset, offset + length);
    return switch (length) {
      2 => data.getUint16(0, Endian.big),
      4 => data.getUint32(0, Endian.big),
      _ => 0,
    };
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
