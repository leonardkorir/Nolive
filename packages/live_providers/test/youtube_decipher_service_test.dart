import 'package:live_providers/src/providers/youtube/youtube_api_client.dart';
import 'package:live_providers/src/providers/youtube/youtube_decipher_service.dart';
import 'package:test/test.dart';

class MockYouTubeApiClient implements YouTubeApiClient {
  MockYouTubeApiClient({required this.mockJsContent});

  final String mockJsContent;
  int fetchTextCalls = 0;

  @override
  Future<String> fetchText(
    String url, {
    Map<String, String> headers = const {},
  }) async {
    fetchTextCalls += 1;
    return mockJsContent;
  }

  @override
  Future<int> probeStatus(
    String url, {
    Map<String, String> headers = const {},
  }) async {
    return 200;
  }

  @override
  Future<Map<String, dynamic>> postPlayer({
    required String apiKey,
    required String videoId,
    required String originalUrl,
    Map<String, dynamic> innertubeContext = const {},
    String rolloutToken = '',
    String poToken = '',
    YouTubePlayerClientProfile clientProfile =
        YouTubePlayerClientProfile.streamlinkAndroid,
  }) async {
    return {};
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
    return {};
  }
}

class ReversingNSigSolver implements YouTubeNSigSolver {
  final requests = <List<String>>[];
  final playerJsValues = <String>[];

  @override
  Future<Map<String, String>> solveNChallenges({
    required String playerJsUrl,
    required String playerJs,
    required List<String> challenges,
  }) async {
    requests.add(challenges);
    playerJsValues.add(playerJs);
    return {
      for (final challenge in challenges)
        challenge: challenge.split('').reversed.join(),
    };
  }
}

const String _mockPlayerJs = 'mock player js';

void main() {
  group('YouTubeDecipherService Tests', () {
    test('solves n-challenge in URL path (HLS manifest)', () async {
      final apiClient = MockYouTubeApiClient(mockJsContent: _mockPlayerJs);
      final solver = ReversingNSigSolver();
      final service = YouTubeDecipherService(nSigSolver: solver);

      const testUrl =
          'https://rr3.googlevideo.com/n/abcdef123/itag/140/playlist/index.m3u8';
      final result = await service.decryptUrl(
        testUrl,
        playerJsUrl: 'https://www.youtube.com/s/player/base.js',
        apiClient: apiClient,
      );

      expect(result, contains('/n/321fedcba/'));
      expect(result, isNot(contains('/n/abcdef123/')));
      expect(solver.requests, [
        ['abcdef123'],
      ]);
      expect(solver.playerJsValues, [_mockPlayerJs]);
    });

    test('solves n-challenge in query parameter (direct URL)', () async {
      final apiClient = MockYouTubeApiClient(mockJsContent: _mockPlayerJs);
      final service = YouTubeDecipherService(nSigSolver: ReversingNSigSolver());

      const testUrl =
          'https://rr3.googlevideo.com/videoplayback?n=oQw4BNQCc6BA3R2mo&itag=140';
      final result = await service.decryptUrl(
        testUrl,
        playerJsUrl: 'https://www.youtube.com/s/player/base.js',
        apiClient: apiClient,
      );

      expect(result, contains('n=om2R3AB6cCQNB4wQo'));
      expect(result, isNot(contains('n=oQw4BNQCc6BA3R2mo')));
    });

    test('returns original URL when no n-challenge present', () async {
      final apiClient = MockYouTubeApiClient(mockJsContent: _mockPlayerJs);
      final solver = ReversingNSigSolver();
      final service = YouTubeDecipherService(nSigSolver: solver);

      const testUrl = 'https://rr3.googlevideo.com/videoplayback?itag=140';
      final result = await service.decryptUrl(
        testUrl,
        playerJsUrl: 'https://www.youtube.com/s/player/base.js',
        apiClient: apiClient,
      );

      expect(result, equals(testUrl));
      expect(solver.requests, isEmpty);
      expect(apiClient.fetchTextCalls, 0);
    });

    test('returns original URL when playerJsUrl is empty', () async {
      final apiClient = MockYouTubeApiClient(mockJsContent: _mockPlayerJs);
      final service = YouTubeDecipherService(nSigSolver: ReversingNSigSolver());

      const testUrl =
          'https://rr3.googlevideo.com/n/abcdef123/playlist/index.m3u8';
      final result = await service.decryptUrl(
        testUrl,
        playerJsUrl: '',
        apiClient: apiClient,
      );

      expect(result, equals(testUrl));
    });

    test('returns original URL when no solver is injected', () async {
      final apiClient = MockYouTubeApiClient(mockJsContent: _mockPlayerJs);
      final service = YouTubeDecipherService();

      const testUrl =
          'https://rr3.googlevideo.com/n/abcdef123/playlist/index.m3u8';
      final result = await service.decryptUrl(
        testUrl,
        playerJsUrl: 'https://www.youtube.com/s/player/base.js',
        apiClient: apiClient,
      );

      expect(result, equals(testUrl));
      expect(apiClient.fetchTextCalls, 0);
    });

    test('caches solved n-challenges per player JS URL', () async {
      final apiClient = MockYouTubeApiClient(mockJsContent: _mockPlayerJs);
      final solver = ReversingNSigSolver();
      final service = YouTubeDecipherService(nSigSolver: solver);
      const playerJsUrl = 'https://www.youtube.com/s/player/base.js';

      await service.decryptUrl(
        'https://rr3.googlevideo.com/n/abcdef123/playlist/index.m3u8',
        playerJsUrl: playerJsUrl,
        apiClient: apiClient,
      );
      await service.decryptUrl(
        'https://rr3.googlevideo.com/n/abcdef123/itag/140/index.m3u8',
        playerJsUrl: playerJsUrl,
        apiClient: apiClient,
      );

      expect(apiClient.fetchTextCalls, 1);
      expect(solver.requests, [
        ['abcdef123'],
      ]);
    });
  });
}
