import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';

import 'package:live_core/live_core.dart';
import 'package:web_socket_channel/io.dart';

import '../providers/chaturbate/chaturbate_api_client.dart';
import '../providers/chaturbate/chaturbate_mapper.dart';
import '../providers/provider_runtime_support.dart';
import 'danmaku_activity_watchdog.dart';
import 'danmaku_web_socket.dart';

abstract interface class ChaturbateSocketClient {
  Stream<dynamic> get stream;

  Future<void> get ready;

  void add(dynamic data);

  Future<void> close();
}

typedef ChaturbateSocketClientFactory =
    ChaturbateSocketClient Function(Uri uri);

class ChaturbateDanmakuSession extends DanmakuSession {
  ChaturbateDanmakuSession({
    required this.roomId,
    required this.broadcasterUid,
    required this.csrfToken,
    required this.backend,
    required this.apiClient,
    void Function()? disposeOwnedApiClient,
    ChaturbateSocketClientFactory? socketClientFactory,
    String? presenceId,
    List<String> realtimeHosts = const [],
    Duration inactivityTimeout = const Duration(minutes: 2),
    void Function(String message)? diagnostics,
  }) : _socketClientFactory =
           socketClientFactory ?? _defaultSocketClientFactory,
       _disposeOwnedApiClient = disposeOwnedApiClient,
       _presenceId = presenceId ?? _buildPresenceId(),
       _realtimeHosts = List.unmodifiable(
         realtimeHosts
             .map((item) => item.trim())
             .where((item) => item.isNotEmpty),
       ),
       _inactivityTimeout = inactivityTimeout,
       _diagnostics = diagnostics;

  final String roomId;
  final String broadcasterUid;
  final String csrfToken;
  final String backend;
  final ChaturbateApiClient apiClient;
  final void Function()? _disposeOwnedApiClient;

  final ChaturbateSocketClientFactory _socketClientFactory;
  final String _presenceId;
  final List<String> _realtimeHosts;
  final Duration _inactivityTimeout;
  final void Function(String message)? _diagnostics;

  final StreamController<LiveMessage> _controller =
      StreamController<LiveMessage>.broadcast();
  static const int _maxSeenMessageIds = 2048;
  static const int _maxRealtimePayloadBytes = 1024 * 1024;
  final Set<String> _seenMessageIds = <String>{};
  final Queue<String> _seenMessageOrder = Queue<String>();

  ChaturbateSocketClient? _socket;
  StreamSubscription<dynamic>? _subscription;
  DanmakuActivityWatchdog? _activityWatchdog;
  bool _connected = false;
  bool _attached = false;
  bool _ownedApiClientDisposed = false;
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

      final history = await _fetchRoomHistory();
      for (final entry in history) {
        _emitMapped(entry);
      }

      final hosts = _resolveRealtimeHosts(authResponse);
      final token = authResponse['token']?.toString() ?? '';
      if (hosts.isEmpty || token.isEmpty) {
        throw StateError('Chaturbate 实时弹幕未返回可用连接参数');
      }

      final socket = await _connectRealtimeSocket(hosts: hosts, token: token);
      try {
        _socket = socket;
        _connected = true;
        _activityWatchdog = DanmakuActivityWatchdog(
          timeout: _inactivityTimeout,
          onTimeout: _handleActivityTimeout,
        )..start();
        StreamSubscription<dynamic>? subscription;
        subscription = socket.stream.listen(
          _handleRawMessage,
          onError: (error) {
            unawaited(
              _teardownRemoteDisconnect(
                socket: socket,
                subscription: subscription,
                notice: 'Chaturbate 弹幕连接异常：$error',
              ),
            );
          },
          onDone: () {
            unawaited(
              _teardownRemoteDisconnect(
                socket: socket,
                subscription: subscription,
                notice: 'Chaturbate 弹幕连接已断开',
              ),
            );
          },
          cancelOnError: false,
        );
        _subscription = subscription;
      } catch (_) {
        _connected = false;
        _activityWatchdog?.stop();
        _activityWatchdog = null;
        await _subscription?.cancel();
        _subscription = null;
        await socket.close();
        if (identical(_socket, socket)) {
          _socket = null;
        }
        rethrow;
      }
    } catch (_) {
      _connected = false;
      _activityWatchdog?.stop();
      _activityWatchdog = null;
      await _subscription?.cancel();
      _subscription = null;
      await _socket?.close();
      _socket = null;
      _disposeOwnedApiClientIfNeeded();
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> _fetchRoomHistory() async {
    try {
      return await apiClient.fetchRoomHistory(
        roomId: roomId,
        csrfToken: csrfToken,
        topics: _buildTopics(_historyTopicNames),
      );
    } catch (error, stackTrace) {
      if (!_shouldIgnoreRoomHistoryFailure(error)) {
        rethrow;
      }
      reportProviderDiagnostic(
        providerId: ProviderId.chaturbate,
        scope: 'chaturbate room history',
        message:
            'non-fatal room_history status=${_roomHistoryStatusCode(error)}; continuing with realtime danmaku only',
        error: error,
        stackTrace: stackTrace,
        diagnostics: _diagnostics,
      );
      _emit(
        LiveMessage(
          type: LiveMessageType.notice,
          content: 'Chaturbate 历史弹幕不可用，已切换为仅实时弹幕。',
          timestamp: DateTime.now(),
        ),
      );
      return const <Map<String, dynamic>>[];
    }
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    _attached = false;
    _activityWatchdog?.stop();
    _activityWatchdog = null;
    await _subscription?.cancel();
    _subscription = null;
    await _socket?.close();
    _socket = null;
    _disposeOwnedApiClientIfNeeded();
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }

  Future<void> _teardownRemoteDisconnect({
    required ChaturbateSocketClient socket,
    required StreamSubscription<dynamic>? subscription,
    required String notice,
  }) async {
    if (!identical(_socket, socket) ||
        !identical(_subscription, subscription)) {
      return;
    }
    _connected = false;
    _attached = false;
    _activityWatchdog?.stop();
    _activityWatchdog = null;
    _subscription = null;
    _socket = null;
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
      await socket.close();
    } catch (_) {}
  }

  void _disposeOwnedApiClientIfNeeded() {
    if (_ownedApiClientDisposed) {
      return;
    }
    _ownedApiClientDisposed = true;
    _disposeOwnedApiClient?.call();
  }

  Future<ChaturbateSocketClient> _connectRealtimeSocket({
    required List<String> hosts,
    required String token,
  }) async {
    Object? lastError;
    for (final host in hosts) {
      final socket = _socketClientFactory(
        Uri(
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
        ),
      );
      try {
        await waitForDanmakuSocketReady(socket.ready);
        return socket;
      } catch (error) {
        lastError = error;
        await socket.close();
      }
    }
    throw lastError ?? StateError('Chaturbate 实时弹幕未返回可用连接参数');
  }

  void _handleRawMessage(dynamic raw) {
    if (raw is List<int> && raw.length > _maxRealtimePayloadBytes) {
      _emit(
        LiveMessage(
          type: LiveMessageType.notice,
          content: 'Chaturbate 弹幕消息过大，已忽略。',
          timestamp: DateTime.now(),
        ),
      );
      return;
    }
    final text = switch (raw) {
      String value => value,
      List<int> value => utf8.decode(value),
      _ => '',
    };
    if (text.trim().isEmpty) {
      return;
    }
    if (utf8.encode(text).length > _maxRealtimePayloadBytes) {
      _emit(
        LiveMessage(
          type: LiveMessageType.notice,
          content: 'Chaturbate 弹幕消息过大，已忽略。',
          timestamp: DateTime.now(),
        ),
      );
      return;
    }
    _activityWatchdog?.ping();
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
    if (dedupeKey != null) {
      if (_seenMessageIds.contains(dedupeKey)) {
        return;
      }
      _seenMessageIds.add(dedupeKey);
      _seenMessageOrder.addLast(dedupeKey);
      while (_seenMessageOrder.length > _maxSeenMessageIds) {
        final expired = _seenMessageOrder.removeFirst();
        _seenMessageIds.remove(expired);
      }
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

  static const List<String> _defaultRealtimeHosts = [
    'realtime.pa.highwebmedia.com',
    'realtime.highwebmedia.com',
  ];

  List<String> _resolveRealtimeHosts(Map<String, dynamic> authResponse) {
    final settings = _asMap(authResponse['settings']);
    final orderedHosts = <String>[
      settings['host']?.toString().trim() ?? '',
      settings['rest_host']?.toString().trim() ?? '',
      ..._realtimeHosts,
      ..._defaultRealtimeHosts,
    ];
    final resolved = <String>[];
    for (final host in orderedHosts) {
      if (host.isEmpty || resolved.contains(host)) {
        continue;
      }
      resolved.add(host);
    }
    return resolved;
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

  Future<void> _handleActivityTimeout() async {
    if (!_connected) {
      return;
    }
    _connected = false;
    _attached = false;
    _activityWatchdog?.stop();
    _activityWatchdog = null;
    await _subscription?.cancel();
    _subscription = null;
    await _socket?.close();
    _socket = null;
    _emit(
      LiveMessage(
        type: LiveMessageType.notice,
        content: 'Chaturbate 弹幕连接活动超时',
        timestamp: DateTime.now(),
      ),
    );
  }

  int get debugSeenMessageCount => _seenMessageIds.length;

  void debugIngestPayload(Map<String, dynamic> payload) {
    _emitMapped(payload);
  }

  bool _shouldIgnoreRoomHistoryFailure(Object error) {
    return error is ChaturbateRoomHistoryUnavailableException &&
        error.statusCode == 403;
  }

  String _roomHistoryStatusCode(Object error) {
    if (error is ChaturbateRoomHistoryUnavailableException) {
      return '${error.statusCode}';
    }
    return '-';
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
    : _channel = IOWebSocketChannel.connect(
        uri,
        connectTimeout: defaultDanmakuWebSocketConnectTimeout,
      );

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
