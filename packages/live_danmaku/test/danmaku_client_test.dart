import 'dart:async';
import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

/// A mock/reference implementation of a DanmakuClient to test lifecycle, retry, heartbeat, and parsing.
class MockDanmakuClient {
  MockDanmakuClient({
    required this.url,
    required this.connector,
    this.heartbeatInterval = const Duration(milliseconds: 50),
    this.retryDelay = const Duration(milliseconds: 10),
  });

  final String url;
  final Future<MockWebSocketChannel> Function(String url) connector;
  final Duration heartbeatInterval;
  final Duration retryDelay;

  final StreamController<LiveMessage> _controller = StreamController<LiveMessage>.broadcast();
  Stream<LiveMessage> get messages => _controller.stream;

  MockWebSocketChannel? _channel;
  Timer? _heartbeatTimer;
  bool _isDisposed = false;
  bool _isConnected = false;
  int connectCount = 0;
  int heartbeatCount = 0;

  bool get isConnected => _isConnected;

  Future<void> connect() async {
    if (_isDisposed) return;
    connectCount++;
    try {
      _channel = await connector(url);
      _isConnected = true;

      // Start heartbeat
      _heartbeatTimer?.cancel();
      _heartbeatTimer = Timer.periodic(heartbeatInterval, (_) {
        if (_isConnected && _channel != null) {
          _channel!.send('heartbeat');
          heartbeatCount++;
        }
      });

      // Listen to incoming messages
      _channel!.stream.listen(
        (data) {
          if (data is String) {
            if (data == 'heartbeat_ack') return;
            // Simple text format parsing: "user:text"
            final parts = data.split(':');
            if (parts.length >= 2) {
              _controller.add(LiveMessage(
                type: LiveMessageType.chat,
                userName: parts[0],
                content: parts.sublist(1).join(':'),
              ));
            }
          }
        },
        onError: (err) {
          _handleDisconnect();
        },
        onDone: () {
          _handleDisconnect();
        },
        cancelOnError: true,
      );
    } catch (e) {
      _handleDisconnect();
    }
  }

  void _handleDisconnect() {
    _isConnected = false;
    _heartbeatTimer?.cancel();
    _channel = null;

    if (!_isDisposed) {
      Timer(retryDelay, () {
        if (!_isDisposed && !_isConnected) {
          connect();
        }
      });
    }
  }

  void disconnect() {
    _isDisposed = true;
    _isConnected = false;
    _heartbeatTimer?.cancel();
    _channel?.close();
    _controller.close();
  }
}

class MockWebSocketChannel {
  final StreamController<dynamic> _incoming = StreamController<dynamic>();
  final List<dynamic> sentMessages = [];
  bool isClosed = false;

  Stream<dynamic> get stream => _incoming.stream;

  void send(dynamic data) {
    if (isClosed) return;
    sentMessages.add(data);
  }

  void receiveFromServer(dynamic data) {
    if (isClosed) return;
    _incoming.add(data);
  }

  void close() {
    isClosed = true;
    _incoming.close();
  }
}

void main() {
  group('MockDanmakuClient Tests', () {
    late List<MockWebSocketChannel> channels;

    setUp(() {
      channels = [];
    });

    Future<MockWebSocketChannel> mockConnector(String url) async {
      final channel = MockWebSocketChannel();
      channels.add(channel);
      return channel;
    }

    test('successful connection parses chat messages and runs heartbeats', () async {
      final client = MockDanmakuClient(
        url: 'ws://mock-danmaku',
        connector: mockConnector,
        heartbeatInterval: const Duration(milliseconds: 20),
      );

      final received = <LiveMessage>[];
      final sub = client.messages.listen(received.add);

      await client.connect();
      expect(client.isConnected, isTrue);
      expect(channels, hasLength(1));

      // Simulate server sending chat message
      channels[0].receiveFromServer('Alice:Hello Danmaku!');
      await Future.delayed(const Duration(milliseconds: 5));

      expect(received, hasLength(1));
      expect(received[0].userName, 'Alice');
      expect(received[0].content, 'Hello Danmaku!');

      // Wait for heartbeats
      await Future.delayed(const Duration(milliseconds: 50));
      expect(client.heartbeatCount, greaterThanOrEqualTo(2));
      expect(channels[0].sentMessages, contains('heartbeat'));

      client.disconnect();
      await sub.cancel();
    });

    test('connection drop triggers auto-reconnect and retry logic', () async {
      final client = MockDanmakuClient(
        url: 'ws://mock-danmaku',
        connector: mockConnector,
        heartbeatInterval: const Duration(milliseconds: 100),
        retryDelay: const Duration(milliseconds: 10),
      );

      await client.connect();
      expect(client.connectCount, 1);
      expect(client.isConnected, isTrue);

      // Drop connection by closing the channel
      channels[0].close();
      await Future.delayed(const Duration(milliseconds: 5));
      expect(client.isConnected, isFalse);

      // Wait for retryDelay to kick in
      await Future.delayed(const Duration(milliseconds: 20));
      expect(client.connectCount, 2);
      expect(client.isConnected, isTrue);

      client.disconnect();
    });

    test('disconnect prevents further retries and disposes resources', () async {
      final client = MockDanmakuClient(
        url: 'ws://mock-danmaku',
        connector: mockConnector,
        retryDelay: const Duration(milliseconds: 10),
      );

      await client.connect();
      client.disconnect();
      expect(client.isConnected, isFalse);

      // Trigger a retry event via an async task if it weren't disposed
      await Future.delayed(const Duration(milliseconds: 25));
      expect(client.connectCount, 1); // No increase, retry didn't run
    });
  });
}
