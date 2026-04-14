import 'dart:async';
import 'dart:math';

import 'package:live_core/live_core.dart';
import 'package:web_socket_channel/io.dart';

import 'danmaku_web_socket.dart';

abstract interface class TwitchSocketClient {
  Stream<dynamic> get stream;

  Future<void> get ready;

  void add(dynamic data);

  Future<void> close();
}

typedef TwitchSocketClientFactory = TwitchSocketClient Function(Uri uri);

class TwitchDanmakuSession implements DanmakuSession {
  TwitchDanmakuSession({
    required this.roomId,
    TwitchSocketClientFactory? socketClientFactory,
    String? nick,
  })  : _socketClientFactory =
            socketClientFactory ?? _defaultSocketClientFactory,
        _nick = nick ?? _buildAnonymousNick();

  final String roomId;

  final TwitchSocketClientFactory _socketClientFactory;
  final String _nick;
  final StreamController<LiveMessage> _controller =
      StreamController<LiveMessage>.broadcast();

  TwitchSocketClient? _socket;
  StreamSubscription<dynamic>? _subscription;
  bool _connected = false;
  bool _announcedReady = false;

  @override
  Stream<LiveMessage> get messages => _controller.stream;

  @override
  Future<void> connect() async {
    if (_connected) {
      return;
    }
    final uri = Uri.parse('wss://irc-ws.chat.twitch.tv/');
    final socket = _socketClientFactory(uri);
    try {
      await waitForDanmakuSocketReady(socket.ready);
      _socket = socket;
      _connected = true;
      _subscription = _socket!.stream.listen(
        _handleRawMessage,
        onError: (error) {
          _emit(
            LiveMessage(
              type: LiveMessageType.notice,
              content: 'Twitch 弹幕连接异常：$error',
              timestamp: DateTime.now(),
            ),
          );
        },
        onDone: () {
          if (_connected) {
            _emit(
              LiveMessage(
                type: LiveMessageType.notice,
                content: 'Twitch 弹幕连接已断开',
                timestamp: DateTime.now(),
              ),
            );
          }
        },
        cancelOnError: false,
      );

      _send('CAP REQ :twitch.tv/tags twitch.tv/commands twitch.tv/membership');
      _send('PASS SCHMOOPIIE');
      _send('NICK $_nick');
      _send('USER $_nick 8 * :$_nick');
      _send('JOIN #${roomId.trim().toLowerCase()}');
    } catch (_) {
      _connected = false;
      await _subscription?.cancel();
      _subscription = null;
      await socket.close();
      if (identical(_socket, socket)) {
        _socket = null;
      }
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    _announcedReady = false;
    await _subscription?.cancel();
    _subscription = null;
    await _socket?.close();
    _socket = null;
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }

  void _handleRawMessage(dynamic raw) {
    final text = switch (raw) {
      String value => value,
      List<int> value => String.fromCharCodes(value),
      _ => '',
    };
    if (text.trim().isEmpty) {
      return;
    }
    final lines = text
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty);
    for (final line in lines) {
      _handleLine(line);
    }
  }

  void _handleLine(String line) {
    if (line.startsWith('PING')) {
      _send(line.replaceFirst('PING', 'PONG'));
      return;
    }

    if (!_announcedReady &&
        (line.contains(' JOIN #${roomId.trim().toLowerCase()}') ||
            line.contains(' ROOMSTATE #${roomId.trim().toLowerCase()}'))) {
      _announcedReady = true;
      _emit(
        LiveMessage(
          type: LiveMessageType.notice,
          content: 'Twitch 实时弹幕已连接',
          timestamp: DateTime.now(),
        ),
      );
    }

    final tags = _parseTags(line);
    final taglessLine =
        line.startsWith('@') ? line.substring(line.indexOf(' ') + 1) : line;
    if (taglessLine.contains(' PRIVMSG #')) {
      final content = _extractTrailingContent(taglessLine);
      if (content.isEmpty) {
        return;
      }
      _emit(
        LiveMessage(
          type: LiveMessageType.chat,
          userName: _firstNonEmpty([
            _decodeTagValue(tags['display-name']),
            _extractPrefixNick(taglessLine),
          ]),
          content: content,
          timestamp: _readTimestamp(tags['tmi-sent-ts']),
          payload: {
            'line': line,
            'tags': tags,
          },
        ),
      );
      return;
    }

    if (taglessLine.contains(' USERNOTICE #')) {
      final content = _buildUserNoticeContent(
        tags: tags,
        trailingContent: _extractTrailingContent(taglessLine),
      );
      if (content.isEmpty) {
        return;
      }
      final msgId = tags['msg-id']?.toString() ?? '';
      final type = switch (msgId) {
        'sub' || 'resub' || 'raid' => LiveMessageType.member,
        'subgift' || 'anonsubgift' => LiveMessageType.gift,
        _ => LiveMessageType.notice,
      };
      _emit(
        LiveMessage(
          type: type,
          userName: _firstNonEmpty([
            _decodeTagValue(tags['display-name']),
            _extractPrefixNick(taglessLine),
          ]),
          content: content,
          timestamp: _readTimestamp(tags['tmi-sent-ts']),
          payload: {
            'line': line,
            'tags': tags,
          },
        ),
      );
      return;
    }

    if (taglessLine.contains(' NOTICE #')) {
      final content = _extractTrailingContent(taglessLine);
      if (content.isEmpty) {
        return;
      }
      _emit(
        LiveMessage(
          type: LiveMessageType.notice,
          content: content,
          timestamp: DateTime.now(),
          payload: {
            'line': line,
            'tags': tags,
          },
        ),
      );
    }
  }

  Map<String, String> _parseTags(String line) {
    if (!line.startsWith('@')) {
      return const {};
    }
    final firstSpace = line.indexOf(' ');
    if (firstSpace <= 1) {
      return const {};
    }
    final rawTags = line.substring(1, firstSpace).split(';');
    final result = <String, String>{};
    for (final rawTag in rawTags) {
      final separator = rawTag.indexOf('=');
      if (separator <= 0) {
        continue;
      }
      final key = rawTag.substring(0, separator).trim();
      final value = rawTag.substring(separator + 1);
      if (key.isEmpty) {
        continue;
      }
      result[key] = value;
    }
    return result;
  }

  String _buildUserNoticeContent({
    required Map<String, String> tags,
    required String trailingContent,
  }) {
    final systemMessage = _decodeTagValue(tags['system-msg']);
    if (systemMessage.isNotEmpty && trailingContent.isNotEmpty) {
      return '$systemMessage · $trailingContent';
    }
    if (systemMessage.isNotEmpty) {
      return systemMessage;
    }
    return trailingContent;
  }

  String _extractPrefixNick(String line) {
    if (!line.startsWith(':')) {
      return '';
    }
    final bangIndex = line.indexOf('!');
    if (bangIndex <= 1) {
      return '';
    }
    return line.substring(1, bangIndex).trim();
  }

  String _extractTrailingContent(String line) {
    final marker = ' :';
    final index = line.indexOf(marker);
    if (index == -1 || index + marker.length >= line.length) {
      return '';
    }
    return line.substring(index + marker.length).trim();
  }

  DateTime? _readTimestamp(String? raw) {
    final millis = int.tryParse(raw?.trim() ?? '');
    if (millis == null) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }

  String _decodeTagValue(String? value) {
    final raw = value ?? '';
    if (raw.isEmpty) {
      return '';
    }
    return raw
        .replaceAll(r'\s', ' ')
        .replaceAll(r'\:', ';')
        .replaceAll(r'\r', '\r')
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\\', '\\');
  }

  String _firstNonEmpty(List<String> values) {
    for (final value in values) {
      final normalized = value.trim();
      if (normalized.isNotEmpty) {
        return normalized;
      }
    }
    return '';
  }

  void _send(String line) {
    _socket?.add(line);
  }

  void _emit(LiveMessage message) {
    if (_controller.isClosed) {
      return;
    }
    _controller.add(message);
  }

  static String _buildAnonymousNick() {
    final value = 1000 + Random().nextInt(90000);
    return 'justinfan$value';
  }

  static TwitchSocketClient _defaultSocketClientFactory(Uri uri) {
    final channel = IOWebSocketChannel.connect(
      uri,
      connectTimeout: defaultDanmakuWebSocketConnectTimeout,
    );
    return _ChannelBackedTwitchSocketClient(channel);
  }
}

class _ChannelBackedTwitchSocketClient implements TwitchSocketClient {
  _ChannelBackedTwitchSocketClient(this._channel);

  final IOWebSocketChannel _channel;

  @override
  Stream<dynamic> get stream => _channel.stream;

  @override
  Future<void> get ready => _channel.ready;

  @override
  void add(dynamic data) {
    _channel.sink.add(data);
  }

  @override
  Future<void> close() async {
    await _channel.sink.close();
  }
}
