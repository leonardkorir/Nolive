import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:live_core/live_core.dart';
import 'package:web_socket_channel/io.dart';

class DouyuDanmakuSession implements DanmakuSession {
  DouyuDanmakuSession({required this.roomId});

  final String roomId;

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
    _connected = true;
    _channel = IOWebSocketChannel.connect(
      Uri.parse('wss://danmuproxy.douyu.com:8506'),
    );
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

  void _send(String body) {
    _channel?.sink.add(_serialize(body));
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
}
