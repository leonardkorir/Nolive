import 'dart:async';

import 'package:live_core/live_core.dart';
import 'package:live_providers/src/danmaku/twitch_danmaku_session.dart';
import 'package:test/test.dart';

void main() {
  test('twitch danmaku session performs IRC handshake and maps chat messages',
      () async {
    final inbound = StreamController<dynamic>();
    final socket = _FakeTwitchSocketClient(inbound.stream);
    final session = TwitchDanmakuSession(
      roomId: 'xqc',
      nick: 'justinfan4242',
      socketClientFactory: (_) => socket,
    );
    final messages = <LiveMessage>[];
    final subscription = session.messages.listen(messages.add);

    await session.connect();
    expect(
      socket.sent,
      containsAll([
        'CAP REQ :twitch.tv/tags twitch.tv/commands twitch.tv/membership',
        'PASS SCHMOOPIIE',
        'NICK justinfan4242',
        'USER justinfan4242 8 * :justinfan4242',
        'JOIN #xqc',
      ]),
    );

    inbound.add(':tmi.twitch.tv ROOMSTATE #xqc');
    inbound.add(
      '@display-name=Alice;tmi-sent-ts=1711111111111 '
      ':alice!alice@alice.tmi.twitch.tv PRIVMSG #xqc :hello world',
    );
    inbound.add('PING :tmi.twitch.tv');
    await Future<void>.delayed(Duration.zero);

    expect(socket.sent, contains('PONG :tmi.twitch.tv'));
    expect(messages, hasLength(2));
    expect(messages.first.type, LiveMessageType.notice);
    expect(messages.last.type, LiveMessageType.chat);
    expect(messages.last.userName, 'Alice');
    expect(messages.last.content, 'hello world');

    await session.disconnect();
    await subscription.cancel();
    await inbound.close();
  });
}

class _FakeTwitchSocketClient implements TwitchSocketClient {
  _FakeTwitchSocketClient(this._stream);

  final Stream<dynamic> _stream;
  final List<dynamic> sent = [];

  @override
  void add(dynamic data) {
    sent.add(data);
  }

  @override
  Future<void> close() async {}

  @override
  Stream<dynamic> get stream => _stream;
}
