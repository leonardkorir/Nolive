import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

void main() {
  group('DanmakuToken subclass equality and properties', () {
    test('PreviewDanmakuToken', () {
      const t1 = PreviewDanmakuToken();
      const t2 = PreviewDanmakuToken();
      expect(t1, equals(t2));
      expect(t1.hashCode, equals(t2.hashCode));
      expect(t1.props, isEmpty);
    });

    test('UnavailableDanmakuToken', () {
      const t1 = UnavailableDanmakuToken(reason: 'error', cause: 'socket');
      const t2 = UnavailableDanmakuToken(reason: 'error', cause: 'socket');
      const t3 = UnavailableDanmakuToken(reason: 'other');
      expect(t1, equals(t2));
      expect(t1.hashCode, equals(t2.hashCode));
      expect(t1, isNot(equals(t3)));
      expect(t1.reason, 'error');
      expect(t1.cause, 'socket');
    });

    test('BilibiliDanmakuToken', () {
      const t1 = BilibiliDanmakuToken(
        roomId: 1,
        uid: 2,
        token: 'token',
        serverHost: 'host',
        buvid: 'buvid',
        cookie: 'cookie',
      );
      const t2 = BilibiliDanmakuToken(
        roomId: 1,
        uid: 2,
        token: 'token',
        serverHost: 'host',
        buvid: 'buvid',
        cookie: 'cookie',
      );
      const t3 = BilibiliDanmakuToken(
        roomId: 9,
        uid: 2,
        token: 'token',
        serverHost: 'host',
        buvid: 'buvid',
        cookie: 'cookie',
      );
      expect(t1, equals(t2));
      expect(t1.hashCode, equals(t2.hashCode));
      expect(t1, isNot(equals(t3)));
      expect(t1.roomId, 1);
    });

    test('DouyinDanmakuToken', () {
      final uri = Uri.parse('wss://douyin.com');
      final t1 = DouyinDanmakuToken(
        webRid: '1',
        roomId: '2',
        cookie: '3',
        userUniqueId: '4',
        websocketUris: [uri],
      );
      final t2 = DouyinDanmakuToken(
        webRid: '1',
        roomId: '2',
        cookie: '3',
        userUniqueId: '4',
        websocketUris: [uri],
      );
      expect(t1, equals(t2));
      expect(t1.hashCode, equals(t2.hashCode));
    });

    test('DouyuDanmakuToken', () {
      const t1 = DouyuDanmakuToken(roomId: '1', socketUrls: ['url']);
      const t2 = DouyuDanmakuToken(roomId: '1', socketUrls: ['url']);
      expect(t1, equals(t2));
      expect(t1.hashCode, equals(t2.hashCode));
    });

    test('HuyaDanmakuToken', () {
      const t1 = HuyaDanmakuToken(ayyuid: 1, topSid: 2, subSid: 3);
      const t2 = HuyaDanmakuToken(ayyuid: 1, topSid: 2, subSid: 3);
      expect(t1, equals(t2));
      expect(t1.hashCode, equals(t2.hashCode));
    });

    test('TwitchDanmakuToken', () {
      const t1 = TwitchDanmakuToken(roomId: '1', oauthToken: '2');
      const t2 = TwitchDanmakuToken(roomId: '1', oauthToken: '2');
      expect(t1, equals(t2));
      expect(t1.hashCode, equals(t2.hashCode));
    });

    test('YouTubeDanmakuToken', () {
      const t1 = YouTubeDanmakuToken(
        apiKey: '1',
        clientVersion: '2',
        continuation: '3',
        liveChatPageUrl: '4',
        visitorData: '5',
      );
      const t2 = YouTubeDanmakuToken(
        apiKey: '1',
        clientVersion: '2',
        continuation: '3',
        liveChatPageUrl: '4',
        visitorData: '5',
      );
      expect(t1, equals(t2));
      expect(t1.hashCode, equals(t2.hashCode));
    });

    test('StripchatDanmakuToken', () {
      const t1 = StripchatDanmakuToken(modelId: '1', websocketUrl: '2', jwt: '3');
      const t2 = StripchatDanmakuToken(modelId: '1', websocketUrl: '2', jwt: '3');
      expect(t1, equals(t2));
      expect(t1.hashCode, equals(t2.hashCode));
    });

    test('ChaturbateDanmakuToken', () {
      const t1 = ChaturbateDanmakuToken(
        roomId: '1',
        roomUid: '2',
        broadcasterUid: '3',
        csrfToken: '4',
        backend: '5',
        host: '6',
        restHost: '7',
        fallbackHosts: ['8'],
      );
      const t2 = ChaturbateDanmakuToken(
        roomId: '1',
        roomUid: '2',
        broadcasterUid: '3',
        csrfToken: '4',
        backend: '5',
        host: '6',
        restHost: '7',
        fallbackHosts: ['8'],
      );
      expect(t1, equals(t2));
      expect(t1.hashCode, equals(t2.hashCode));
    });
  });
}
