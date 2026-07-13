import 'package:live_core/live_core.dart';

import '../provider_runtime_support.dart';
import 'youtube_api_client.dart';

abstract interface class YouTubeNSigSolver {
  Future<Map<String, String>> solveNChallenges({
    required String playerJsUrl,
    required String playerJs,
    required List<String> challenges,
  });
}

class YouTubeDecipherService {
  YouTubeDecipherService({YouTubeNSigSolver? nSigSolver})
    : _nSigSolver = nSigSolver;

  static final YouTubeDecipherService instance = YouTubeDecipherService();

  final YouTubeNSigSolver? _nSigSolver;
  String? _cachedPlayerJsUrl;
  String? _cachedPlayerJsContent;
  final Map<String, Map<String, String>> _solutionCache =
      <String, Map<String, String>>{};
  bool _disposed = false;

  Future<String> decryptUrl(
    String url, {
    required String? playerJsUrl,
    required YouTubeApiClient apiClient,
  }) async {
    if (playerJsUrl == null || playerJsUrl.isEmpty || _nSigSolver == null) {
      return url;
    }
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return url;
    }

    final pathChallenges = _extractPathChallenges(uri);
    final queryChallenge = uri.queryParameters['n']?.trim() ?? '';
    final challenges = <String>{
      ...pathChallenges,
      if (queryChallenge.isNotEmpty) queryChallenge,
    }.toList(growable: false);
    if (challenges.isEmpty) {
      return url;
    }

    try {
      final solved = await _solveNChallenges(
        playerJsUrl: playerJsUrl,
        apiClient: apiClient,
        challenges: challenges,
      );
      if (solved.isEmpty) {
        return url;
      }
      var rewritten = uri;
      if (pathChallenges.isNotEmpty) {
        final segments = rewritten.pathSegments;
        rewritten = rewritten.replace(
          pathSegments: [
            for (var index = 0; index < segments.length; index += 1)
              index > 0 &&
                      segments[index - 1] == 'n' &&
                      solved[segments[index]]?.isNotEmpty == true
                  ? solved[segments[index]]!
                  : segments[index],
          ],
        );
      }
      if (queryChallenge.isNotEmpty &&
          solved[queryChallenge]?.isNotEmpty == true) {
        final queryParameters = Map<String, String>.from(
          rewritten.queryParameters,
        );
        queryParameters['n'] = solved[queryChallenge]!;
        rewritten = rewritten.replace(queryParameters: queryParameters);
      }
      return rewritten.toString();
    } catch (error, stackTrace) {
      reportProviderDiagnostic(
        providerId: ProviderId.youtube,
        scope: 'youtube n challenge',
        message: 'failed to solve n challenge for url=$url',
        error: error,
        stackTrace: stackTrace,
      );
      return url;
    }
  }

  Future<Map<String, String>> _solveNChallenges({
    required String playerJsUrl,
    required YouTubeApiClient apiClient,
    required List<String> challenges,
  }) async {
    if (_disposed) {
      throw StateError('YouTubeDecipherService has been disposed.');
    }

    final cachedSolutions = _solutionCache.putIfAbsent(
      playerJsUrl,
      () => <String, String>{},
    );
    final missing = challenges
        .where((challenge) => !cachedSolutions.containsKey(challenge))
        .toList(growable: false);
    if (missing.isNotEmpty) {
      final playerJs = await _loadPlayerJs(
        playerJsUrl: playerJsUrl,
        apiClient: apiClient,
      );
      final solved = await _nSigSolver!.solveNChallenges(
        playerJsUrl: playerJsUrl,
        playerJs: playerJs,
        challenges: missing,
      );
      for (final entry in solved.entries) {
        final challenge = entry.key.trim();
        final result = entry.value.trim();
        if (challenge.isEmpty || result.isEmpty || result == challenge) {
          continue;
        }
        cachedSolutions[challenge] = result;
      }
    }
    return {
      for (final challenge in challenges)
        if (cachedSolutions[challenge]?.isNotEmpty == true)
          challenge: cachedSolutions[challenge]!,
    };
  }

  Future<String> _loadPlayerJs({
    required String playerJsUrl,
    required YouTubeApiClient apiClient,
  }) async {
    if (_cachedPlayerJsUrl == playerJsUrl && _cachedPlayerJsContent != null) {
      return _cachedPlayerJsContent!;
    }
    final content = await apiClient.fetchText(playerJsUrl);
    _cachedPlayerJsUrl = playerJsUrl;
    _cachedPlayerJsContent = content;
    return content;
  }

  List<String> _extractPathChallenges(Uri uri) {
    final segments = uri.pathSegments;
    if (segments.length < 2) {
      return const [];
    }
    final values = <String>[];
    for (var index = 0; index < segments.length - 1; index += 1) {
      if (segments[index] != 'n') {
        continue;
      }
      final value = segments[index + 1].trim();
      if (value.isNotEmpty) {
        values.add(value);
      }
    }
    return values;
  }

  void disposeIsolate() {}

  void dispose() {
    _disposed = true;
    _solutionCache.clear();
  }
}
