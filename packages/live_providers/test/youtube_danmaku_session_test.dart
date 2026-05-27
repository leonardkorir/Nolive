import 'package:live_core/live_core.dart';
import 'package:live_providers/src/danmaku/youtube_danmaku_session.dart';
import 'package:live_providers/src/providers/youtube/youtube_api_client.dart';
import 'package:live_providers/src/providers/youtube/youtube_page_parser.dart';
import 'package:test/test.dart';

import 'support/youtube_fixture_loader.dart';

void main() {
  group(
    'youtube danmaku session',
    skip: YouTubeFixtureLoader.skipReason,
    () {
      test('polls live chat and maps text messages from fixtures', () async {
        final bootstrap = YouTubePageParser().tryParseLiveChatBootstrap(
          html: YouTubeFixtureLoader.loadLiveChatPageHtml(),
          fallbackApiKey: 'AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8',
        );
        expect(bootstrap, isNotNull);

        final apiClient = _FixtureDanmakuApiClient(
          YouTubeFixtureLoader.loadLiveChatResponses(),
        );
        final session = YouTubeDanmakuSession(
          apiClient: apiClient,
          apiKey: bootstrap!.apiKey,
          continuation: bootstrap.continuation,
          visitorData: bootstrap.visitorData,
          referer: bootstrap.liveChatPageUrl,
          clientVersion: bootstrap.clientVersion,
        );

        final messages = <LiveMessage>[];
        final subscription = session.messages.listen(messages.add);

        await session.connect();
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(apiClient.calls, isNotEmpty);
        expect(messages, isNotEmpty);
        expect(messages.first.type, LiveMessageType.notice);
        expect(
          messages.any(
            (item) =>
                item.type == LiveMessageType.chat &&
                item.userName == '@The-Ishita-Diaries' &&
                item.content.contains('said hi'),
          ),
          isTrue,
        );

        await session.disconnect();
        await subscription.cancel();
      });
    },
  );

  test('youtube danmaku session emits inactivity timeout notice', () async {
    final apiClient = _SinglePollDanmakuApiClient(
      {
        'continuationContents': {
          'liveChatContinuation': {
            'actions': const [],
            'continuations': [
              {
                'timedContinuationData': {
                  'continuation': 'next-continuation',
                  'timeoutMs': 60000,
                },
              },
            ],
          },
        },
      },
    );
    final session = YouTubeDanmakuSession(
      apiClient: apiClient,
      apiKey: 'key',
      continuation: 'first-continuation',
      visitorData: 'visitor',
      referer: 'https://www.youtube.com/live_chat?v=test',
      inactivityTimeout: const Duration(milliseconds: 20),
    );
    final messages = <LiveMessage>[];
    final subscription = session.messages.listen(messages.add);

    await session.connect();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(
      messages.any((item) => item.content.contains('连接活动超时')),
      isTrue,
    );

    await session.disconnect();
    await subscription.cancel();
  });
}

class _FixtureDanmakuApiClient implements YouTubeApiClient {
  _FixtureDanmakuApiClient(this._responses);

  final List<Map<String, dynamic>> _responses;
  final List<Map<String, String>> calls = [];
  int _index = 0;

  @override
  Future<String> fetchText(
    String url, {
    Map<String, String> headers = const {},
  }) {
    throw UnimplementedError();
  }

  @override
  Future<int> probeStatus(
    String url, {
    Map<String, String> headers = const {},
  }) {
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
    calls.add({
      'apiKey': apiKey,
      'continuation': continuation,
      'visitorData': visitorData,
      'referer': referer,
      'clientVersion': clientVersion,
      'timeoutMs': timeout.inMilliseconds.toString(),
    });
    final index = _index < _responses.length ? _index : _responses.length - 1;
    _index += 1;
    return _responses[index];
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
  }) {
    throw UnimplementedError();
  }
}

class _SinglePollDanmakuApiClient implements YouTubeApiClient {
  _SinglePollDanmakuApiClient(this._response);

  final Map<String, dynamic> _response;

  @override
  Future<String> fetchText(
    String url, {
    Map<String, String> headers = const {},
  }) {
    throw UnimplementedError();
  }

  @override
  Future<int> probeStatus(
    String url, {
    Map<String, String> headers = const {},
  }) {
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
    return _response;
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
  }) {
    throw UnimplementedError();
  }
}
