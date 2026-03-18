import 'package:live_core/live_core.dart';
import 'package:live_providers/live_providers.dart';
import 'package:live_providers/src/danmaku/bilibili_danmaku_session.dart';
import 'package:live_providers/src/danmaku/chaturbate_danmaku_session.dart';
import 'package:live_providers/src/danmaku/douyin_danmaku_session.dart';
import 'package:live_providers/src/danmaku/douyu_danmaku_session.dart';
import 'package:live_providers/src/danmaku/huya_danmaku_session.dart';
import 'package:live_providers/src/danmaku/provider_ticker_danmaku_session.dart';
import 'package:live_providers/src/danmaku/provider_unavailable_danmaku_session.dart';
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
      danmakuToken: {
        'roomId': 1234,
        'uid': 0,
        'token': 'mock-token',
        'serverHost': 'broadcastlv.chat.bilibili.com',
        'buvid': 'mock-buvid',
        'cookie': '',
      },
    );

    final session = await provider.createDanmakuSession(detail);

    expect(session, isA<BilibiliDanmakuSession>());
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
      danmakuToken: {
        'broadcasterUid': 'P7746ZL',
        'csrfToken': 'mock-csrf',
        'backend': 'a',
      },
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
      danmakuToken: const <String, dynamic>{},
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
      danmakuToken: {'roomId': '3125893'},
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
      danmakuToken: {
        'ayyuid': 123456,
        'topSid': 111,
        'subSid': 222,
      },
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
      danmakuToken: {
        'roomId': '7376429659866598196',
        'cookie': 'ttwid=test-cookie',
        'userUniqueId': '123456789012',
      },
    );

    final session = await provider.createDanmakuSession(detail);

    expect(session, isA<DouyinDanmakuSession>());
  });
}
