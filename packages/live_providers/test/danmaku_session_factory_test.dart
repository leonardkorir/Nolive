import 'package:live_core/live_core.dart';
import 'package:live_providers/live_providers.dart';
import 'package:live_providers/src/danmaku/bilibili_danmaku_session.dart';
import 'package:live_providers/src/danmaku/chaturbate_danmaku_session.dart';
import 'package:live_providers/src/danmaku/douyin_danmaku_session.dart';
import 'package:live_providers/src/danmaku/douyu_danmaku_session.dart';
import 'package:live_providers/src/danmaku/huya_danmaku_session.dart';
import 'package:live_providers/src/danmaku/provider_ticker_danmaku_session.dart';
import 'package:live_providers/src/danmaku/provider_unavailable_danmaku_session.dart';
import 'package:live_providers/src/danmaku/stripchat_danmaku_session.dart';
import 'package:live_providers/src/danmaku/twitch_danmaku_session.dart';
import 'package:live_providers/src/danmaku/youtube_danmaku_session.dart';
import 'package:live_providers/src/providers/youtube/youtube_api_client.dart';
import 'package:test/test.dart';

void main() {
  test('bilibili preview detail keeps deterministic ticker danmaku', () async {
    final provider = BilibiliProvider.preview();
    final detail = await provider.fetchRoomDetail('66666');

    final session = await provider.createDanmakuSession(detail);

    expect(session, isA<ProviderTickerDanmakuSession>());
  });

  test('bilibili live-like detail uses real bilibili danmaku session',
      () async {
    final provider = BilibiliProvider.preview();
    final detail = LiveRoomDetail(
      providerId: ProviderId.bilibili.value,
      roomId: '1234',
      title: 'test',
      streamerName: 'tester',
      danmakuToken: const BilibiliDanmakuToken(
        roomId: 1234,
        uid: 0,
        token: 'mock-token',
        serverHost: 'broadcastlv.chat.bilibili.com',
        buvid: 'mock-buvid',
        cookie: '',
      ),
    );

    final session = await provider.createDanmakuSession(detail);

    expect(session, isA<BilibiliDanmakuSession>());
  });

  test(
      'bilibili live detail without danmaku auth token uses unavailable session',
      () async {
    final provider = BilibiliProvider.preview();
    final detail = LiveRoomDetail(
      providerId: ProviderId.bilibili.value,
      roomId: '1234',
      title: 'test',
      streamerName: 'tester',
      danmakuToken: const UnavailableDanmakuToken(
        reason: '暂未拿到可用弹幕连接参数',
      ),
    );

    final session = await provider.createDanmakuSession(detail);

    expect(session, isA<ProviderUnavailableDanmakuSession>());
  });

  test('bilibili danmaku session prefers cookie uid and drops bare stored uid',
      () {
    final anonymousSession = BilibiliDanmakuSession(
      danmakuToken: const BilibiliDanmakuToken(
        roomId: 1234,
        uid: 998877,
        token: 'mock-token',
        serverHost: 'broadcastlv.chat.bilibili.com',
        buvid: 'mock-buvid',
        cookie: '',
      ),
    );
    final cookieBoundSession = BilibiliDanmakuSession(
      danmakuToken: const BilibiliDanmakuToken(
        roomId: 1234,
        uid: 998877,
        token: 'mock-token',
        serverHost: 'broadcastlv.chat.bilibili.com',
        buvid: 'mock-buvid',
        cookie: 'SESSDATA=test; DedeUserID=445566;',
      ),
    );

    expect(anonymousSession.uid, 0);
    expect(cookieBoundSession.uid, 445566);
  });

  test('chaturbate preview detail keeps deterministic ticker danmaku',
      () async {
    final provider = ChaturbateProvider.preview();
    final detail = await provider.fetchRoomDetail('kittengirlxo');

    final session = await provider.createDanmakuSession(detail);

    expect(session, isA<ProviderTickerDanmakuSession>());
  });

  test('chaturbate live-like detail uses real chaturbate danmaku session',
      () async {
    final provider = ChaturbateProvider.preview();
    final detail = LiveRoomDetail(
      providerId: ProviderId.chaturbate.value,
      roomId: 'kittengirlxo',
      title: 'test',
      streamerName: 'tester',
      danmakuToken: const ChaturbateDanmakuToken(
        roomId: 'kittengirlxo',
        roomUid: '',
        broadcasterUid: 'P7746ZL',
        csrfToken: 'mock-csrf',
        backend: 'a',
      ),
    );

    final session = await provider.createDanmakuSession(detail);

    expect(session, isA<ChaturbateDanmakuSession>());
  });

  test('chaturbate live detail without token does not use deterministic ticker',
      () async {
    final provider = ChaturbateProvider.preview();
    final detail = LiveRoomDetail(
      providerId: ProviderId.chaturbate.value,
      roomId: 'consuelabrasington',
      title: 'test',
      streamerName: 'tester',
      danmakuToken: null,
    );

    final session = await provider.createDanmakuSession(detail);

    expect(session, isA<ProviderUnavailableDanmakuSession>());
  });

  test('douyu preview detail keeps deterministic ticker danmaku', () async {
    final provider = DouyuProvider.preview();
    final detail = await provider.fetchRoomDetail('3125893');

    final session = await provider.createDanmakuSession(detail);

    expect(session, isA<ProviderTickerDanmakuSession>());
  });

  test('douyu live-like detail uses real douyu danmaku session', () async {
    final provider = DouyuProvider.preview();
    final detail = LiveRoomDetail(
      providerId: ProviderId.douyu.value,
      roomId: '3125893',
      title: 'test',
      streamerName: 'tester',
      danmakuToken: const DouyuDanmakuToken(roomId: '3125893'),
    );

    final session = await provider.createDanmakuSession(detail);

    expect(session, isA<DouyuDanmakuSession>());
  });

  test('huya live-like detail uses real huya danmaku session', () async {
    final provider = HuyaProvider.preview();
    final detail = LiveRoomDetail(
      providerId: ProviderId.huya.value,
      roomId: 'yy/123456',
      title: 'test',
      streamerName: 'tester',
      danmakuToken: const HuyaDanmakuToken(
        ayyuid: 123456,
        topSid: 111,
        subSid: 222,
      ),
    );

    final session = await provider.createDanmakuSession(detail);

    expect(session, isA<HuyaDanmakuSession>());
  });

  test('douyin live-like detail uses real douyin danmaku session', () async {
    final provider = DouyinProvider(
      websocketSignatureBuilder: (roomId, userUniqueId) async =>
          'sign-$roomId-$userUniqueId',
    );
    final detail = LiveRoomDetail(
      providerId: ProviderId.douyin.value,
      roomId: '416144012050',
      title: 'test',
      streamerName: 'tester',
      danmakuToken: const DouyinDanmakuToken(
        webRid: '416144012050',
        roomId: '7376429659866598196',
        cookie: 'ttwid=test-cookie',
        userUniqueId: '123456789012',
      ),
    );

    final session = await provider.createDanmakuSession(detail);

    expect(session, isA<DouyinDanmakuSession>());
  });

  test('twitch preview detail keeps deterministic ticker danmaku', () async {
    final provider = TwitchProvider.preview();
    final detail = await provider.fetchRoomDetail('xqc');

    final session = await provider.createDanmakuSession(detail);

    expect(session, isA<ProviderTickerDanmakuSession>());
  });

  test('twitch live-like detail uses real twitch danmaku session', () async {
    final provider = TwitchProvider.preview();
    final detail = LiveRoomDetail(
      providerId: ProviderId.twitch.value,
      roomId: 'xqc',
      title: 'test',
      streamerName: 'tester',
      danmakuToken: const TwitchDanmakuToken(roomId: 'xqc'),
    );

    final session = await provider.createDanmakuSession(detail);

    expect(session, isA<TwitchDanmakuSession>());
  });

  test('youtube preview detail keeps deterministic ticker danmaku', () async {
    final provider = YouTubeProvider.preview();
    final detail = await provider.fetchRoomDetail('@ChinaStreetObserver/live');

    final session = await provider.createDanmakuSession(detail);

    expect(session, isA<ProviderTickerDanmakuSession>());
  });

  test('youtube live-like detail uses real youtube danmaku session', () async {
    final provider = YouTubeProvider.live(apiClient: _NoopYouTubeApiClient());
    final detail = LiveRoomDetail(
      providerId: ProviderId.youtube.value,
      roomId: '@demo/live',
      title: 'test',
      streamerName: 'tester',
      danmakuToken: const YouTubeDanmakuToken(
        apiKey: 'AIzaTest',
        clientVersion: YouTubeApiClient.defaultWebClientVersion,
        continuation: 'test-continuation',
        liveChatPageUrl: 'https://www.youtube.com/live_chat?continuation=1',
        visitorData: 'visitor-data',
      ),
    );

    final session = await provider.createDanmakuSession(detail);

    expect(session, isA<YouTubeDanmakuSession>());
  });

  test('stripchat preview detail uses ticker danmaku', () async {
    final provider = StripchatProvider.preview();
    final detail = await provider.fetchRoomDetail('alice_demo');

    final session = await provider.createDanmakuSession(detail);

    expect(session, isA<ProviderTickerDanmakuSession>());
  });

  test('stripchat live-like detail uses real stripchat danmaku session',
      () async {
    final provider = StripchatProvider.preview();
    final detail = LiveRoomDetail(
      providerId: ProviderId.stripchat.value,
      roomId: 'test_model',
      title: 'test',
      streamerName: 'tester',
      danmakuToken: const StripchatDanmakuToken(
        modelId: '12345',
        websocketUrl: 'wss://ws.stripchat.com/connection/websocket',
        jwt: 'mock-jwt-token',
      ),
    );

    final session = await provider.createDanmakuSession(detail);

    expect(session, isA<StripchatDanmakuSession>());
  });

  test('stripchat unavailable token uses unavailable session', () async {
    final provider = StripchatProvider.preview();
    final detail = LiveRoomDetail(
      providerId: ProviderId.stripchat.value,
      roomId: 'test',
      title: 'test',
      streamerName: 'tester',
      danmakuToken: const UnavailableDanmakuToken(
        reason: 'test reason',
      ),
    );

    final session = await provider.createDanmakuSession(detail);

    expect(session, isA<ProviderUnavailableDanmakuSession>());
  });
}

class _NoopYouTubeApiClient implements YouTubeApiClient {
  @override
  Future<String> fetchText(
    String url, {
    Map<String, String> headers = const {},
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<int> probeStatus(
    String url, {
    Map<String, String> headers = const {},
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, dynamic>> postLiveChat({
    required String apiKey,
    required String continuation,
    required String visitorData,
    required String referer,
    String clientVersion = YouTubeApiClient.defaultWebClientVersion,
    Duration timeout = YouTubeApiClient.liveChatRequestTimeout,
  }) async {
    return const {};
  }

  @override
  Future<Map<String, dynamic>> postPlayer({
    required String apiKey,
    required String videoId,
    required String originalUrl,
    Map<String, dynamic> innertubeContext = const {},
    String rolloutToken = '',
    String poToken = '',
    YouTubePlayerClientProfile clientProfile = YouTubePlayerClientProfile.web,
  }) async {
    throw UnimplementedError();
  }
}
