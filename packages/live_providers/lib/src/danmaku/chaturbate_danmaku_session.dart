import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:live_core/live_core.dart';
import 'package:web_socket_channel/io.dart';

import '../providers/chaturbate/chaturbate_api_client.dart';
import '../providers/chaturbate/chaturbate_mapper.dart';

abstract interface class ChaturbateSocketClient {
  Stream<dynamic> get stream;

  void add(dynamic data);

  Future<void> close();
}

typedef ChaturbateSocketClientFactory = ChaturbateSocketClient Function(
    Uri uri);

class ChaturbateDanmakuSession implements DanmakuSession {
  ChaturbateDanmakuSession({
    required this.roomId,
    required this.broadcasterUid,
    required this.csrfToken,
    required this.backend,
    required this.apiClient,
    ChaturbateSocketClientFactory? socketClientFactory,
    String? presenceId,
  })  : _socketClientFactory =
            socketClientFactory ?? _defaultSocketClientFactory,
        _presenceId = presenceId ?? _buildPresenceId();

  final String roomId;
  final String broadcasterUid;
  final String csrfToken;
  final String backend;
  final ChaturbateApiClient apiClient;

  final ChaturbateSocketClientFactory _socketClientFactory;
  final String _presenceId;

  final StreamController<LiveMessage> _controller =
      StreamController<LiveMessage>.broadcast();
  final Set<String> _seenMessageIds = <String>{};

  ChaturbateSocketClient? _socket;
  StreamSubscription<dynamic>? _subscription;
  bool _connected = false;
  bool _attached = false;
  List<String> _channels = const [];

  static const List<String> _authTopicNames = [
    'GlobalPushServiceBackendChangeTopic',
    'RoomAnonPresenceTopic',
    'QualityUpdateTopic',
    'LatencyUpdateTopic',
    'RoomMessageTopic',
    'RoomFanClubJoinedTopic',
    'RoomPurchaseTopic',
    'RoomNoticeTopic',
    'RoomTipAlertTopic',
    'RoomShortcodeTopic',
    'RoomPasswordProtectedTopic',
    'RoomModeratorPromotedTopic',
    'RoomModeratorRevokedTopic',
    'RoomStatusTopic',
    'RoomTitleChangeTopic',
    'RoomSilenceTopic',
    'RoomKickTopic',
    'RoomUpdateTopic',
    'RoomSettingsTopic',
    'RoomTipMenuTopic',
    'ViewerPromotionTopic',
    'RoomEnterLeaveTopic',
    'GameUpdateTopic',
  ];

  static const List<String> _historyTopicNames = [
    'RoomTipAlertTopic',
    'RoomPurchaseTopic',
    'RoomFanClubJoinedTopic',
    'RoomMessageTopic',
    'RoomShortcodeTopic',
  ];

  @override
  Stream<LiveMessage> get messages => _controller.stream;

  @override
  Future<void> connect() async {
    if (_connected) {
      return;
    }
    _connected = true;
    _attached = false;

    try {
      final authResponse = await apiClient.authenticatePushService(
        roomId: roomId,
        csrfToken: csrfToken,
        backend: backend,
        presenceId: _presenceId,
        topics: _buildTopics(_authTopicNames),
      );
      _channels = _extractChannelNames(authResponse);

      final history = await apiClient.fetchRoomHistory(
        roomId: roomId,
        csrfToken: csrfToken,
        topics: _buildTopics(_historyTopicNames),
      );
      for (final entry in history) {
        _emitMapped(entry);
      }

      final host = _resolveRealtimeHost(authResponse);
      final token = authResponse['token']?.toString() ?? '';
      if (host.isEmpty || token.isEmpty) {
        _emit(
          LiveMessage(
            type: LiveMessageType.notice,
            content: 'Chaturbate 实时弹幕未返回可用连接参数',
            timestamp: DateTime.now(),
          ),
        );
        return;
      }

      final uri = Uri(
        scheme: 'wss',
        host: host,
        queryParameters: {
          'access_token': token,
          'format': 'json',
          'heartbeats': 'true',
          'v': '3',
          'agent': 'ably-js/2.12.0 browser',
          'remainPresentFor': '0',
        },
      );
      _socket = _socketClientFactory(uri);
      _subscription = _socket!.stream.listen(
        _handleRawMessage,
        onError: (error) {
          _emit(
            LiveMessage(
              type: LiveMessageType.notice,
              content: 'Chaturbate 弹幕连接异常：$error',
              timestamp: DateTime.now(),
            ),
          );
        },
        onDone: () {
          if (_connected) {
            _emit(
              LiveMessage(
                type: LiveMessageType.notice,
                content: 'Chaturbate 弹幕连接已断开',
                timestamp: DateTime.now(),
              ),
            );
          }
        },
        cancelOnError: false,
      );
    } catch (error) {
      _emit(
        LiveMessage(
          type: LiveMessageType.notice,
          content: 'Chaturbate 弹幕连接失败：$error',
          timestamp: DateTime.now(),
        ),
      );
    }
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    _attached = false;
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
      List<int> value => utf8.decode(value),
      _ => '',
    };
    if (text.trim().isEmpty) {
      return;
    }
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map) {
        return;
      }
      final payload = decoded.cast<String, dynamic>();
      final action = _toInt(payload['action']);
      if (action == 4) {
        _attachChannels();
        _emit(
          LiveMessage(
            type: LiveMessageType.notice,
            content: 'Chaturbate 实时弹幕已连接',
            timestamp: DateTime.now(),
          ),
        );
        return;
      }
      if (action != 15) {
        return;
      }

      for (final message in _asList(payload['messages'])) {
        final envelope = _asMap(message);
        if (envelope.isEmpty) {
          continue;
        }
        final data = envelope['data'];
        Map<String, dynamic> event;
        if (data is String) {
          final decodedData = jsonDecode(data);
          event = _asMap(decodedData);
        } else {
          event = _asMap(data);
        }
        _emitMapped(event);
      }
    } catch (error) {
      _emit(
        LiveMessage(
          type: LiveMessageType.notice,
          content: 'Chaturbate 弹幕解析失败：$error',
          timestamp: DateTime.now(),
        ),
      );
    }
  }

  void _attachChannels() {
    if (_attached) {
      return;
    }
    _attached = true;
    for (final channel in _channels.toSet()) {
      _socket?.add(
        jsonEncode({
          'action': 10,
          'channel': channel,
          'params': <String, Object?>{},
          'flags': 327680,
        }),
      );
    }
  }

  void _emitMapped(Map<String, dynamic> payload) {
    final dedupeKey = ChaturbateMapper.dedupeKeyForDanmakuPayload(payload);
    if (dedupeKey != null && !_seenMessageIds.add(dedupeKey)) {
      return;
    }
    final message = ChaturbateMapper.mapDanmakuPayload(payload);
    if (message == null || message.content.trim().isEmpty) {
      return;
    }
    _emit(message);
  }

  Map<String, dynamic> _buildTopics(List<String> topicNames) {
    final topics = <String, dynamic>{};
    for (final topicName in topicNames) {
      final key = topicName == 'GlobalPushServiceBackendChangeTopic'
          ? '$topicName#$topicName'
          : '$topicName#$topicName:$broadcasterUid';
      topics[key] = topicName == 'GlobalPushServiceBackendChangeTopic'
          ? <String, Object?>{}
          : <String, Object?>{'broadcaster_uid': broadcasterUid};
    }
    return topics;
  }

  List<String> _extractChannelNames(Map<String, dynamic> authResponse) {
    final channels = _asMap(authResponse['channels']);
    return channels.values
        .map((value) => value?.toString().trim() ?? '')
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
  }

  String _resolveRealtimeHost(Map<String, dynamic> authResponse) {
    final settings = _asMap(authResponse['settings']);
    final host = settings['host']?.toString().trim() ?? '';
    if (host.isNotEmpty) {
      return host;
    }
    return settings['rest_host']?.toString().trim() ?? '';
  }

  int _toInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  List<dynamic> _asList(Object? value) {
    if (value is List) {
      return value;
    }
    return const [];
  }

  Map<String, dynamic> _asMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.cast<String, dynamic>();
    }
    return const {};
  }

  void _emit(LiveMessage message) {
    if (_controller.isClosed) {
      return;
    }
    _controller.add(message);
  }

  static ChaturbateSocketClient _defaultSocketClientFactory(Uri uri) {
    return _IoChaturbateSocketClient(uri);
  }

  static String _buildPresenceId() {
    final random = Random.secure();
    final now = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final suffix = random.nextInt(1 << 32).toRadixString(36);
    return '+sl$now$suffix';
  }
}

class _IoChaturbateSocketClient implements ChaturbateSocketClient {
  _IoChaturbateSocketClient(Uri uri)
      : _channel = IOWebSocketChannel.connect(uri);

  final IOWebSocketChannel _channel;

  @override
  Stream<dynamic> get stream => _channel.stream;

  @override
  void add(dynamic data) {
    _channel.sink.add(data);
  }

  @override
  Future<void> close() async {
    await _channel.sink.close();
  }
}
