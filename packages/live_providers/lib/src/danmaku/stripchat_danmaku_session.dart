import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:live_core/live_core.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../providers/provider_runtime_support.dart';
import 'danmaku_web_socket.dart';

class StripchatDanmakuSession implements DanmakuSession {
  StripchatDanmakuSession({
    required StripchatDanmakuToken danmakuToken,
    Duration inactivityTimeout = const Duration(minutes: 2),
    WebSocketChannelConnector channelConnector = connectDanmakuWebSocket,
  }) : _modelId = danmakuToken.modelId,
       _websocketUrl = danmakuToken.websocketUrl,
       _jwt = danmakuToken.jwt,
       _historyUrl = danmakuToken.historyUrl,
       _requestCookie = danmakuToken.requestCookie,
       _roomUrl = danmakuToken.roomUrl,
       _inactivityTimeout = inactivityTimeout,
       _channelConnector = channelConnector;

  static const String _origin = 'https://zh.stripchat.com';
  static const ProviderBrowserProfile _browserProfile =
      ProviderBrowserProfile.chromiumDesktop;
  static const List<String> _globalChannels = <String>[
    'changeConfigFeature',
    'newModelEvent',
  ];
  static const List<String> _roomChannelTemplates = <String>[
    'newChatMessage@{modelId}',
    'broadcastChanged@{modelId}',
    'streamChanged@{modelId}',
    'modelStatusChanged@{modelId}',
    'privateStartedV3@{modelId}',
    'privateEndedV3@{modelId}',
    'topicChanged@{modelId}',
    'tipMenuUpdated@{modelId}',
    'goalChanged@{modelId}',
    'userUpdated@{modelId}',
    'interactiveToyStatusChanged@{modelId}',
    'deleteChatMessages@{modelId}',
    'tipMenuLanguageDetected@{modelId}',
    'groupShow@{modelId}',
    'modelAppUpdated@{modelId}',
    'modelDiscountActivated@{modelId}',
    'newKing@{modelId}',
    'userBanned@{modelId}',
    'fanClubUpdated@{modelId}',
    'lotteryChanged',
  ];
  static const Set<String> _noticeChannelPrefixes = <String>{
    'broadcastChanged',
    'streamChanged',
    'modelStatusChanged',
    'privateStartedV3',
    'privateEndedV3',
    'topicChanged',
    'tipMenuUpdated',
    'goalChanged',
    'userUpdated',
    'interactiveToyStatusChanged',
    'deleteChatMessages',
    'tipMenuLanguageDetected',
    'groupShow',
    'modelDiscountActivated',
    'newKing',
    'userBanned',
    'fanClubUpdated',
    'lotteryChanged',
  };
  static const int _seenMessageLimit = 256;
  static const String _connectCommandMarker = '__connect__';

  final String _modelId;
  final String _websocketUrl;
  final String _jwt;
  final String _historyUrl;
  final String _requestCookie;
  final String _roomUrl;
  final Duration _inactivityTimeout;
  final WebSocketChannelConnector _channelConnector;

  final StreamController<LiveMessage> _controller =
      StreamController<LiveMessage>.broadcast();
  final Map<int, String> _pendingChannels = <int, String>{};
  final Queue<String> _seenMessageOrder = Queue<String>();
  final Set<String> _seenMessageKeys = <String>{};

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  bool _connected = false;
  bool _roomSubscribed = false;
  bool _connectAcked = false;
  bool _roomReadyAcked = false;
  bool _receivedHistoryMessage = false;
  bool _receivedRealtimeMessage = false;
  int _nextId = 1;
  Timer? _heartbeatTimer;
  Timer? _inactivityTimer;
  Completer<void>? _connectCompleter;
  bool _disposed = false;

  @override
  Stream<LiveMessage> get messages => _controller.stream;

  @override
  Future<void> connect() async {
    if (_connected) {
      return;
    }
    if (_connectCompleter != null) {
      return _connectCompleter!.future;
    }

    final uri = Uri.parse(_websocketUrl);
    final channel = await _channelConnector(
      uri,
      headers: const {'origin': _origin},
    );

    _channel = channel;
    _resetInactivityTimer();

    final completer = Completer<void>();
    _connectCompleter = completer;

    _subscription = channel.stream.listen(
      (data) {
        _resetInactivityTimer();
        _handleMessage(data as String, completer);
      },
      onError: (Object error, StackTrace stackTrace) {
        _connected = false;
        reportProviderDiagnostic(
          providerId: ProviderId.stripchat,
          scope: 'stripchat danmaku session',
          message: 'WebSocket error for modelId=$_modelId',
          error: error,
          stackTrace: stackTrace,
        );
        _completeConnectFailure(error, stackTrace);
        unawaited(disconnect());
      },
      onDone: () {
        _connected = false;
        if (!_roomReadyAcked && !_receivedRealtimeMessage) {
          _completeConnectFailure(
            StateError('WebSocket closed before danmaku handshake completed.'),
          );
        }
        unawaited(disconnect());
      },
      cancelOnError: false,
    );

    _sendConnectCommand(completer);
    _startHeartbeat();
    _connected = true;
    try {
      await completer.future;
    } finally {
      _connectCompleter = null;
    }
  }

  @override
  Future<void> disconnect() async {
    await _cleanup();
  }

  Future<void> _cleanup() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _connected = false;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _inactivityTimer?.cancel();
    _inactivityTimer = null;
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }

  void _completeConnectFailure(Object error, [StackTrace? stackTrace]) {
    final completer = _connectCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(error, stackTrace);
    }
  }

  void _resetInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(_inactivityTimeout, () {
      final message = switch ((
        _connectAcked,
        _roomReadyAcked,
        _receivedHistoryMessage,
        _receivedRealtimeMessage,
      )) {
        (false, _, _, _) =>
          'WebSocket idle timeout before connect ack for modelId=$_modelId.',
        (true, false, _, _) =>
          'WebSocket idle timeout before room subscribe ack for modelId=$_modelId.',
        (true, true, true, false) =>
          'History replay succeeded but realtime push absent for modelId=$_modelId.',
        _ => 'WebSocket idle timeout for modelId=$_modelId.',
      };
      reportProviderDiagnostic(
        providerId: ProviderId.stripchat,
        scope: 'stripchat danmaku session',
        message: message,
      );
      _completeConnectFailure(TimeoutException(message, _inactivityTimeout));
      unawaited(disconnect());
    });
  }

  void _startHeartbeat() {
    if (_disposed) {
      return;
    }
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _sendLine('{}');
    });
  }

  void _sendConnectCommand(Completer<void> handshake) {
    _roomSubscribed = false;
    _connectAcked = false;
    _roomReadyAcked = false;
    _receivedHistoryMessage = false;
    _receivedRealtimeMessage = false;
    _pendingChannels.clear();

    final connectId = _nextId++;
    _pendingChannels[connectId] = handshake.isCompleted
        ? _connectCommandMarker
        : '$_connectCommandMarker:handshake';
    _sendLine(
      jsonEncode({
        'connect': {'token': _jwt, 'name': 'js'},
        'id': connectId,
      }),
    );
  }

  void _subscribeToPrimaryRoomChannel() {
    _subscribeToChannel(_resolveRoomChannel(_roomChannelTemplates.first));
  }

  void _subscribeToAncillaryChannels() {
    for (final channelName in _globalChannels) {
      _subscribeToChannel(channelName);
    }
    for (final channelName
        in _roomChannelTemplates.skip(1).map(_resolveRoomChannel)) {
      _subscribeToChannel(channelName);
    }
  }

  String _resolveRoomChannel(String template) {
    return template.replaceAll('{modelId}', _modelId);
  }

  void _subscribeToChannel(String channelName) {
    final id = _nextId++;
    _pendingChannels[id] = channelName;
    _sendLine(
      jsonEncode({
        'subscribe': {'channel': channelName},
        'id': id,
      }),
    );
  }

  void _sendLine(String line) {
    try {
      _channel?.sink.add('$line\n');
      _resetInactivityTimer();
    } catch (error, stackTrace) {
      reportProviderDiagnostic(
        providerId: ProviderId.stripchat,
        scope: 'stripchat danmaku session',
        message: 'Failed to send WebSocket frame for modelId=$_modelId',
        error: error,
        stackTrace: stackTrace,
      );
      _completeConnectFailure(error, stackTrace);
      unawaited(disconnect());
    }
  }

  void _handleMessage(String raw, Completer<void> handshake) {
    final lines = raw
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .toList();
    for (final line in lines) {
      _handleLine(line, handshake);
    }
  }

  void _handleLine(String line, Completer<void> handshake) {
    Map<String, dynamic>? parsed;
    try {
      parsed = jsonDecode(line) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    if (parsed.isEmpty) {
      _sendLine('{}');
      return;
    }

    if (parsed.containsKey('result') || parsed.containsKey('connect')) {
      final id = parsed['id'];
      if (id is int) {
        final ackedChannel = _pendingChannels.remove(id);
        if (ackedChannel == _connectCommandMarker ||
            ackedChannel == '$_connectCommandMarker:handshake') {
          _connectAcked = true;
          if (!_roomSubscribed) {
            _roomSubscribed = true;
            _subscribeToPrimaryRoomChannel();
          }
          if (!handshake.isCompleted) {
            handshake.complete();
          }
          unawaited(_replayHistory());
          return;
        }
        if (ackedChannel == 'newChatMessage@$_modelId') {
          _roomReadyAcked = true;
          _subscribeToAncillaryChannels();
        }
      }
      return;
    }

    if (parsed.containsKey('push')) {
      _handlePush(parsed, handshake);
    }
  }

  void _handlePush(Map<String, dynamic> push, Completer<void> handshake) {
    if (!_connectAcked) {
      _connectAcked = true;
      if (!_roomSubscribed) {
        _roomSubscribed = true;
        _subscribeToPrimaryRoomChannel();
      }
      if (!handshake.isCompleted) {
        handshake.complete();
      }
    }
    if (!_roomReadyAcked) {
      _roomReadyAcked = true;
      _subscribeToAncillaryChannels();
    }
    final dedupKey = extractPushDedupKey(push);
    if (!_rememberMessageKey(dedupKey)) {
      return;
    }
    final message = parsePushMessage(push, modelId: _modelId);
    if (message != null && !_controller.isClosed) {
      _receivedRealtimeMessage = true;
      _controller.add(message);
    }
  }

  Future<void> _replayHistory() async {
    final historyUrl = _historyUrl.trim();
    if (historyUrl.isEmpty) {
      return;
    }
    final client = HttpClient();
    try {
      client.connectionTimeout = const Duration(seconds: 10);
      client.idleTimeout = const Duration(seconds: 10);
      final request = await client.getUrl(Uri.parse(historyUrl));
      final headers = _buildHistoryHeaders();
      headers.forEach(request.headers.set);
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        reportProviderDiagnostic(
          providerId: ProviderId.stripchat,
          scope: 'stripchat danmaku history',
          message:
              'history request status=${response.statusCode} modelId=$_modelId',
        );
        return;
      }
      final body = await response.transform(utf8.decoder).join();
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        return;
      }
      final rawMessages = decoded['messages'];
      if (rawMessages is! List) {
        return;
      }
      for (final entry in rawMessages) {
        if (_controller.isClosed || entry is! Map<String, dynamic>) {
          continue;
        }
        if (!_rememberMessageKey(extractMessageDedupKey(entry))) {
          continue;
        }
        _receivedHistoryMessage = true;
        _controller.add(parseChatMessage(entry));
      }
    } catch (error, stackTrace) {
      reportProviderDiagnostic(
        providerId: ProviderId.stripchat,
        scope: 'stripchat danmaku history',
        message: 'Failed to fetch room history for modelId=$_modelId',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      client.close(force: true);
    }
  }

  Map<String, String> _buildHistoryHeaders() {
    final referer = _roomUrl.trim().isNotEmpty ? _roomUrl.trim() : '$_origin/';
    return {
      'user-agent': _browserProfile.userAgent,
      'accept-language': _browserProfile.acceptLanguage,
      ..._browserProfile.buildClientHintHeaders(),
      'accept': 'application/json',
      'origin': _origin,
      'referer': referer,
      'sec-fetch-dest': 'empty',
      'sec-fetch-mode': 'cors',
      'sec-fetch-site': 'same-origin',
      if (_requestCookie.trim().isNotEmpty) 'cookie': _requestCookie.trim(),
    };
  }

  bool _rememberMessageKey(String? rawKey) {
    final key = rawKey?.trim() ?? '';
    if (key.isEmpty) {
      return true;
    }
    if (!_seenMessageKeys.add(key)) {
      return false;
    }
    _seenMessageOrder.addLast(key);
    while (_seenMessageOrder.length > _seenMessageLimit) {
      final expired = _seenMessageOrder.removeFirst();
      _seenMessageKeys.remove(expired);
    }
    return true;
  }

  static LiveMessage? parsePushMessage(
    Map<String, dynamic> push, {
    required String modelId,
  }) {
    final pushRaw = push['push'];
    if (pushRaw is! Map<String, dynamic>) {
      return null;
    }
    final pubRaw = pushRaw['pub'];
    if (pubRaw is! Map<String, dynamic>) {
      return null;
    }
    final dataRaw = pubRaw['data'];
    if (dataRaw is! Map<String, dynamic>) {
      return null;
    }

    final channel = pushRaw['channel']?.toString() ?? '';
    if (channel.startsWith('newChatMessage@')) {
      final message = dataRaw['message'];
      if (message is Map<String, dynamic>) {
        return parseChatMessage(message);
      }
      return null;
    }
    if (_isNoticeChannel(channel)) {
      return parseNoticeChannel(channel, dataRaw);
    }
    return null;
  }

  static String? extractPushDedupKey(Map<String, dynamic> push) {
    final pushRaw = push['push'];
    if (pushRaw is! Map<String, dynamic>) {
      return null;
    }
    final channel = pushRaw['channel']?.toString() ?? '';
    if (!channel.startsWith('newChatMessage@')) {
      return null;
    }
    final pubRaw = pushRaw['pub'];
    if (pubRaw is! Map<String, dynamic>) {
      return null;
    }
    final dataRaw = pubRaw['data'];
    if (dataRaw is! Map<String, dynamic>) {
      return null;
    }
    final message = dataRaw['message'];
    if (message is! Map<String, dynamic>) {
      return null;
    }
    return extractMessageDedupKey(message);
  }

  static String? extractMessageDedupKey(Map<String, dynamic> message) {
    final id = message['id']?.toString().trim() ?? '';
    if (id.isNotEmpty) {
      return 'id:$id';
    }
    final cacheId = message['cacheId']?.toString().trim() ?? '';
    if (cacheId.isNotEmpty) {
      return 'cache:$cacheId';
    }
    return null;
  }

  static LiveMessage parseChatMessage(Map<String, dynamic> message) {
    final type = message['type']?.toString() ?? 'text';
    final details = message['details'] as Map<String, dynamic>? ?? {};
    final userData = message['userData'] as Map<String, dynamic>? ?? {};
    final createdAt = message['createdAt']?.toString() ?? '';

    final body = details['body']?.toString() ?? '';
    final username = userData['username']?.toString() ?? '';

    final messageType = switch (type) {
      'text' => LiveMessageType.chat,
      'tip' => LiveMessageType.gift,
      'lovense' => LiveMessageType.gift,
      _ => LiveMessageType.notice,
    };

    return LiveMessage(
      type: messageType,
      content: body,
      userName: username,
      timestamp: parseTimestamp(createdAt),
    );
  }

  static LiveMessage parseNoticeChannel(
    String channel,
    Map<String, dynamic> data,
  ) {
    final noticeBody = channel.replaceFirst(RegExp(r'@\d+$'), '');
    return LiveMessage(
      type: LiveMessageType.notice,
      content: '[$noticeBody] ${data.toString()}',
    );
  }

  static DateTime parseTimestamp(String raw) {
    try {
      return DateTime.parse(raw);
    } catch (_) {
      return DateTime.now();
    }
  }

  static List<LiveMessage> parseHistoryMessages(Map<String, dynamic> payload) {
    final rawMessages = payload['messages'];
    if (rawMessages is! List) {
      return const <LiveMessage>[];
    }
    final parsed = <LiveMessage>[];
    for (final entry in rawMessages) {
      if (entry is! Map<String, dynamic>) {
        continue;
      }
      parsed.add(parseChatMessage(entry));
    }
    return parsed;
  }

  static bool _isNoticeChannel(String channel) {
    final prefix = channel.split('@').first.trim();
    return _noticeChannelPrefixes.contains(prefix);
  }

  static List<String> simulateSubscribeTriggers(
    List<String> serverResultLines,
  ) {
    var roomSubscribed = false;
    var primaryAcked = false;
    final triggers = <String>[];

    for (final line in serverResultLines) {
      Map<String, dynamic>? parsed;
      try {
        parsed = jsonDecode(line) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }
      if (!parsed.containsKey('result') && !parsed.containsKey('connect')) {
        continue;
      }
      final id = parsed['id'];
      if (id is int && id == 1 && !roomSubscribed) {
        roomSubscribed = true;
        triggers.add(
          _roomChannelTemplates.first.replaceAll('{modelId}', '(modelId)'),
        );
        continue;
      }
      if (id is int && id == 2 && roomSubscribed && !primaryAcked) {
        primaryAcked = true;
        triggers.addAll(_globalChannels);
        triggers.addAll(
          _roomChannelTemplates
              .skip(1)
              .map((template) => template.replaceAll('{modelId}', '(modelId)')),
        );
      }
    }
    return triggers;
  }
}
