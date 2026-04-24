import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:live_core/live_core.dart';
import 'package:web_socket_channel/io.dart';

import 'danmaku_web_socket.dart';
import '../providers/douyu/douyu_sign_service.dart';

abstract interface class DouyuSocketClient {
  Stream<dynamic> get stream;

  void add(dynamic data);

  Future<void> close();
}

typedef DouyuSocketClientConnector = Future<DouyuSocketClient> Function(
  Uri uri, {
  required Map<String, dynamic> headers,
  required Duration connectTimeout,
});

class DouyuDanmakuSession implements DanmakuSession {
  DouyuDanmakuSession({
    required this.roomId,
    DouyuSocketClientConnector? socketConnector,
  }) : _socketConnector = socketConnector ?? _defaultSocketConnector;

  static const List<String> _candidateSocketUrls = <String>[
    'wss://danmuproxy.douyu.com:8502/',
    'wss://danmuproxy.douyu.com:8506/',
  ];
  static const Duration _endpointConnectTimeout = Duration(seconds: 4);
  static const Map<String, dynamic> _socketHeaders = <String, dynamic>{
    'origin': 'https://www.douyu.com',
    'referer': 'https://www.douyu.com/',
    'user-agent': HttpDouyuSignService.defaultUserAgent,
  };

  final String roomId;
  final DouyuSocketClientConnector _socketConnector;

  final StreamController<LiveMessage> _controller =
      StreamController<LiveMessage>.broadcast();

  DouyuSocketClient? _channel;
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
    final channel = await _connectSocket();
    try {
      _channel = channel;
      _connected = true;
      _subscription = _channel!.stream.listen(
        _handleRawMessage,
        onError: (error) {
          _emit(
            LiveMessage(
              type: LiveMessageType.notice,
              content: '斗鱼弹幕连接异常：$error',
              timestamp: DateTime.now(),
            ),
          );
        },
        onDone: () {
          if (_connected) {
            _emit(
              LiveMessage(
                type: LiveMessageType.notice,
                content: '斗鱼弹幕连接已断开',
                timestamp: DateTime.now(),
              ),
            );
          }
        },
        cancelOnError: false,
      );
      _send('type@=loginreq/roomid@=$roomId/');
      _send('type@=joingroup/rid@=$roomId/gid@=-9999/');
      _heartbeatTimer = Timer.periodic(
        const Duration(seconds: 45),
        (_) => _send('type@=mrkl/'),
      );
      _emit(
        LiveMessage(
          type: LiveMessageType.notice,
          content: '斗鱼实时弹幕已连接',
          timestamp: DateTime.now(),
        ),
      );
    } catch (_) {
      _connected = false;
      await _subscription?.cancel();
      _subscription = null;
      await channel.close();
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
    await _channel?.close();
    _channel = null;
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }

  void _send(String body) {
    _channel?.add(_serialize(body));
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
    final text = _deserialize(bytes);
    if (text == null || text.isEmpty) {
      return;
    }
    final decoded = _sttToJson(text);
    if (decoded is! Map) {
      return;
    }
    final payload = decoded.cast<String, dynamic>();
    final type = payload['type']?.toString();
    LiveMessage? message;
    if (type == 'chatmsg') {
      message = LiveMessage(
        type: LiveMessageType.chat,
        userName: payload['nn']?.toString(),
        content: payload['txt']?.toString() ?? '',
        timestamp: DateTime.now(),
      );
    } else if (type == 'dgb') {
      final giftName = payload['gfn']?.toString() ?? '礼物';
      message = LiveMessage(
        type: LiveMessageType.gift,
        userName: payload['nn']?.toString(),
        content: '送出了 $giftName',
        timestamp: DateTime.now(),
      );
    } else if (type == 'uenter') {
      final userName = payload['nn']?.toString();
      message = LiveMessage(
        type: LiveMessageType.member,
        userName: userName,
        content: '${userName ?? '用户'} 进入了直播间',
        timestamp: DateTime.now(),
      );
    } else if (type == 'rss') {
      final viewerCount = payload['ss']?.toString();
      message = LiveMessage(
        type: LiveMessageType.online,
        content: viewerCount == null ? '当前在线人数更新' : '当前人气 $viewerCount',
        timestamp: DateTime.now(),
      );
    }
    if (message != null && message.content.isNotEmpty) {
      _emit(message);
    }
  }

  Uint8List _serialize(String body) {
    final bodyBytes = utf8.encode(body);
    final totalLength = 4 + 4 + bodyBytes.length + 1;
    final bytes = ByteData(12 + bodyBytes.length + 1);
    bytes.setUint32(0, totalLength, Endian.little);
    bytes.setUint32(4, totalLength, Endian.little);
    bytes.setUint16(8, 689, Endian.little);
    bytes.setUint8(10, 0);
    bytes.setUint8(11, 0);
    final data = bytes.buffer.asUint8List();
    data.setRange(12, 12 + bodyBytes.length, bodyBytes);
    data[data.length - 1] = 0;
    return data;
  }

  String? _deserialize(Uint8List buffer) {
    if (buffer.length < 13) {
      return null;
    }
    final data = ByteData.sublistView(buffer);
    final fullLength = data.getUint32(0, Endian.little);
    final bodyLength = fullLength - 9;
    if (bodyLength <= 0 || 12 + bodyLength > buffer.length) {
      return null;
    }
    final body = buffer.sublist(12, 12 + bodyLength);
    return utf8.decode(body);
  }

  dynamic _sttToJson(String value) {
    if (value.contains('//')) {
      final result = <dynamic>[];
      for (final field in value.split('//')) {
        if (field.isEmpty) {
          continue;
        }
        result.add(_sttToJson(field));
      }
      return result;
    }
    if (value.contains('@=')) {
      final result = <String, dynamic>{};
      for (final field in value.split('/')) {
        if (field.isEmpty) {
          continue;
        }
        final tokens = field.split('@=');
        if (tokens.length != 2) {
          continue;
        }
        result[tokens[0]] = _sttToJson(_unescape(tokens[1]));
      }
      return result;
    }
    if (value.contains('@A=')) {
      return _sttToJson(_unescape(value));
    }
    return _unescape(value);
  }

  String _unescape(String value) {
    return value.replaceAll('@S', '/').replaceAll('@A', '@');
  }

  void _emit(LiveMessage message) {
    if (_controller.isClosed) {
      return;
    }
    _controller.add(message);
  }

  Future<DouyuSocketClient> _connectSocket() async {
    final completer = Completer<DouyuSocketClient>();
    var remaining = _candidateSocketUrls.length;
    Object? lastError;

    for (final rawUrl in _candidateSocketUrls) {
      unawaited(
        () async {
          try {
            final client = await _socketConnector(
              Uri.parse(rawUrl),
              headers: _socketHeaders,
              connectTimeout: _endpointConnectTimeout,
            );
            if (completer.isCompleted) {
              await client.close();
              return;
            }
            completer.complete(client);
          } catch (error, stackTrace) {
            lastError = error;
            remaining -= 1;
            if (remaining == 0 && !completer.isCompleted) {
              completer.completeError(
                error,
                stackTrace,
              );
            }
          }
        }(),
      );
    }

    try {
      return await completer.future;
    } catch (_) {
      if (lastError != null) {
        throw lastError!;
      }
      rethrow;
    }
  }
}

Future<DouyuSocketClient> _defaultSocketConnector(
  Uri uri, {
  required Map<String, dynamic> headers,
  required Duration connectTimeout,
}) async {
  final channel = await connectDanmakuWebSocket(
    uri,
    headers: headers,
    connectTimeout: connectTimeout,
  );
  return _IoDouyuSocketClient(channel);
}

class _IoDouyuSocketClient implements DouyuSocketClient {
  _IoDouyuSocketClient(this._channel);

  final IOWebSocketChannel _channel;

  @override
  Stream<dynamic> get stream => _channel.stream;

  @override
  void add(dynamic data) {
    _channel.sink.add(data);
  }

  @override
  Future<void> close() {
    return _channel.sink.close();
  }
}
