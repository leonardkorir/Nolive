import 'dart:convert';

import 'package:live_core/live_core.dart';

import 'youtube_api_client.dart';

class YouTubePageBootstrap {
  const YouTubePageBootstrap({
    required this.apiKey,
    this.videoId,
    this.initialData,
    this.initialPlayerResponse,
    this.innertubeContext,
    this.rolloutToken,
    this.poToken,
  });

  final String apiKey;
  final String? videoId;
  final Map<String, dynamic>? initialData;
  final Map<String, dynamic>? initialPlayerResponse;
  final Map<String, dynamic>? innertubeContext;
  final String? rolloutToken;
  final String? poToken;
}

class YouTubeSearchCandidate {
  const YouTubeSearchCandidate({
    required this.videoId,
    required this.title,
    required this.streamerName,
    this.coverUrl,
    this.streamerAvatarUrl,
    this.viewerCount,
    this.ownerProfileUrl,
  });

  final String videoId;
  final String title;
  final String streamerName;
  final String? coverUrl;
  final String? streamerAvatarUrl;
  final int? viewerCount;
  final String? ownerProfileUrl;
}

class YouTubeLiveChatBootstrap {
  const YouTubeLiveChatBootstrap({
    required this.apiKey,
    required this.continuation,
    required this.visitorData,
    required this.clientVersion,
    required this.liveChatPageUrl,
  });

  final String apiKey;
  final String continuation;
  final String visitorData;
  final String clientVersion;
  final String liveChatPageUrl;
}

class YouTubePageParser {
  const YouTubePageParser();

  static final RegExp _innertubeApiKeyPattern = RegExp(
    r'''(?:"|')INNERTUBE_API_KEY(?:"|')\s*:\s*(?:"|')([^"']+)(?:"|')''',
  );
  static final RegExp _innertubeClientVersionPattern = RegExp(
    r'''(?:"|')INNERTUBE_CLIENT_VERSION(?:"|')\s*:\s*(?:"|')([^"']+)(?:"|')''',
  );
  static final RegExp _rolloutTokenPattern = RegExp(
    r'''(?:"|')rolloutToken(?:"|')\s*:\s*(?:"|')([^"']+)(?:"|')''',
  );
  static final RegExp _poTokenPattern = RegExp(
    r'''(?:"|')poToken(?:"|')\s*:\s*(?:"|')([^"']+)(?:"|')''',
  );
  static final RegExp _canonicalBaseVideoIdPattern = RegExp(
    r'"canonicalBaseUrl":"\\/watch\?v=([A-Za-z0-9_-]{11})"',
  );
  static final RegExp _fallbackVideoIdPattern = RegExp(
    r'"videoId":"([A-Za-z0-9_-]{11})"',
  );
  static final RegExp _visitorDataPattern = RegExp(
    r'"visitorData"\s*:\s*"([^"]+)"',
  );
  static final RegExp _liveChatContinuationPattern = RegExp(
    r'"liveChatContinuation"\s*:\s*.*?"continuation"\s*:\s*"([^"]+)"',
    dotAll: true,
  );
  static final RegExp _continuationPattern = RegExp(
    r'"continuation"\s*:\s*"([^"]+)"',
  );

  YouTubePageBootstrap parsePage({
    required String requestedRoomId,
    required String html,
  }) {
    final initialData = tryExtractInitialData(html);
    final initialPlayerResponse = tryExtractInitialPlayerResponse(html);
    final innertubeContext = tryExtractInnertubeContext(html);
    final apiKey = extractInnertubeApiKey(html);
    final videoId = _firstNonEmpty([
      _isVideoId(requestedRoomId) ? requestedRoomId : null,
      _extractVideoIdFromPlayerResponse(initialPlayerResponse),
      _extractVideoIdFromCanonicalBaseUrl(html),
      _findVideoIdInInitialData(initialData),
      _extractVideoIdFromFallback(html),
    ]);
    return YouTubePageBootstrap(
      apiKey: apiKey,
      videoId: videoId,
      initialData: initialData,
      initialPlayerResponse: initialPlayerResponse,
      innertubeContext: innertubeContext,
      rolloutToken: _extractByPattern(_rolloutTokenPattern, html),
      poToken: _extractByPattern(_poTokenPattern, html),
    );
  }

  List<YouTubeSearchCandidate> parseSearchCandidates(String html) {
    final initialData = tryExtractInitialData(html);
    if (initialData == null || initialData.isEmpty) {
      return const [];
    }
    final candidates = <YouTubeSearchCandidate>[];
    final seen = <String>{};
    for (final renderer in _collectVideoRenderers(initialData)) {
      if (!_isLiveRenderer(renderer)) {
        continue;
      }
      final candidate = _buildSearchCandidate(renderer);
      if (candidate == null || !seen.add(candidate.videoId)) {
        continue;
      }
      candidates.add(candidate);
    }
    return candidates;
  }

  YouTubeSearchCandidate? findLiveCandidateByVideoId({
    required Map<String, dynamic>? initialData,
    required String videoId,
  }) {
    final normalizedVideoId = videoId.trim();
    if (initialData == null ||
        initialData.isEmpty ||
        normalizedVideoId.isEmpty) {
      return null;
    }
    for (final renderer in _collectVideoRenderers(initialData)) {
      final rendererVideoId = renderer['videoId']?.toString().trim() ?? '';
      if (rendererVideoId != normalizedVideoId || !_isLiveRenderer(renderer)) {
        continue;
      }
      return _buildSearchCandidate(renderer);
    }
    return _buildWatchPageCandidate(
      initialData: initialData,
      videoId: normalizedVideoId,
    );
  }

  YouTubeLiveChatBootstrap? tryParseLiveChatBootstrap({
    required String html,
    String? fallbackApiKey,
    String? fallbackClientVersion,
  }) {
    final continuation = _extractLiveChatContinuation(html);
    final visitorData = _extractByPattern(_visitorDataPattern, html);
    final apiKey = _firstNonEmpty([
      _extractByPattern(_innertubeApiKeyPattern, html),
      fallbackApiKey,
    ]);
    if (continuation == null ||
        continuation.isEmpty ||
        visitorData == null ||
        visitorData.isEmpty ||
        apiKey == null ||
        apiKey.isEmpty) {
      return null;
    }
    final clientVersion = _firstNonEmpty([
          _extractByPattern(_innertubeClientVersionPattern, html),
          fallbackClientVersion,
          YouTubeApiClient.defaultWebClientVersion,
        ]) ??
        YouTubeApiClient.defaultWebClientVersion;
    return YouTubeLiveChatBootstrap(
      apiKey: apiKey,
      continuation: continuation,
      visitorData: visitorData,
      clientVersion: clientVersion,
      liveChatPageUrl:
          'https://www.youtube.com/live_chat?continuation=$continuation&authuser=0',
    );
  }

  String extractInnertubeApiKey(String html) {
    final match = _innertubeApiKeyPattern.firstMatch(html);
    final apiKey = match?.group(1)?.trim() ?? '';
    if (apiKey.isNotEmpty) {
      return apiKey;
    }
    throw ProviderParseException(
      providerId: ProviderId.youtube,
      message: 'YouTube 页面中缺少 INNERTUBE_API_KEY。',
    );
  }

  Map<String, dynamic>? tryExtractInitialData(String html) {
    return _extractMapByMarkers(html, const [
      'var ytInitialData = ',
      'ytInitialData = ',
    ]);
  }

  Map<String, dynamic>? tryExtractInitialPlayerResponse(String html) {
    return _extractMapByMarkers(html, const [
      'var ytInitialPlayerResponse = ',
      'ytInitialPlayerResponse = ',
    ]);
  }

  Map<String, dynamic>? tryExtractInnertubeContext(String html) {
    return _extractMapByMarkers(html, const [
      '"INNERTUBE_CONTEXT":',
      '\'INNERTUBE_CONTEXT\':',
    ]);
  }

  Map<String, dynamic>? _extractMapByMarkers(
    String html,
    List<String> markers,
  ) {
    for (final marker in markers) {
      final jsonText = _extractJsonAfterMarker(html, marker);
      if (jsonText == null) {
        continue;
      }
      final decoded = jsonDecode(jsonText);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.cast<String, dynamic>();
      }
    }
    return null;
  }

  String? _extractJsonAfterMarker(String source, String marker) {
    final markerIndex = source.indexOf(marker);
    if (markerIndex == -1) {
      return null;
    }
    var index = markerIndex + marker.length;
    while (index < source.length && _isWhitespace(source.codeUnitAt(index))) {
      index += 1;
    }
    if (index >= source.length) {
      return null;
    }
    final start = source[index];
    if (start != '{' && start != '[') {
      return null;
    }
    return _scanJsonValue(source, index);
  }

  String? _scanJsonValue(String source, int startIndex) {
    final start = source[startIndex];
    final end = start == '{' ? '}' : ']';
    var depth = 0;
    var inString = false;
    var escape = false;
    var quote = '';
    for (var index = startIndex; index < source.length; index += 1) {
      final char = source[index];
      if (inString) {
        if (escape) {
          escape = false;
        } else if (char == '\\') {
          escape = true;
        } else if (char == quote) {
          inString = false;
        }
        continue;
      }
      if (char == '"' || char == "'") {
        inString = true;
        quote = char;
        continue;
      }
      if (char == start) {
        depth += 1;
        continue;
      }
      if (char == end) {
        depth -= 1;
        if (depth == 0) {
          return source.substring(startIndex, index + 1);
        }
      }
    }
    return null;
  }

  List<Map<String, dynamic>> _collectVideoRenderers(Object? node) {
    final results = <Map<String, dynamic>>[];
    void visit(Object? current) {
      if (current is Map) {
        final map = current.cast<String, dynamic>();
        for (final key in const [
          'videoRenderer',
          'gridVideoRenderer',
          'videoWithContextRenderer',
        ]) {
          final renderer = _asMap(map[key]);
          if (renderer.isNotEmpty) {
            results.add(renderer);
          }
        }
        for (final value in map.values) {
          visit(value);
        }
        return;
      }
      if (current is List) {
        for (final item in current) {
          visit(item);
        }
      }
    }

    visit(node);
    return results;
  }

  YouTubeSearchCandidate? _buildSearchCandidate(Map<String, dynamic> renderer) {
    final videoId = renderer['videoId']?.toString().trim() ?? '';
    if (videoId.isEmpty) {
      return null;
    }
    final title = _readText(renderer['title']);
    final streamerName = _firstNonEmpty([
      _readText(renderer['ownerText']),
      _readText(renderer['shortBylineText']),
      _readText(renderer['longBylineText']),
    ]);
    final thumbnails = _asList(_asMap(renderer['thumbnail'])['thumbnails']);
    final channelThumbnail = _asList(
      _asMap(
        _asMap(
          _asMap(
            _asMap(renderer['channelThumbnailSupportedRenderers'])[
                'channelThumbnailWithLinkRenderer'],
          )['thumbnail'],
        ),
      )['thumbnails'],
    );
    final displayStreamerName =
        streamerName?.isNotEmpty == true ? streamerName! : 'YouTube Live';
    return YouTubeSearchCandidate(
      videoId: videoId,
      title: title.isEmpty ? videoId : title,
      streamerName: displayStreamerName,
      coverUrl: _pickLastThumbnailUrl(thumbnails),
      streamerAvatarUrl: _pickLastThumbnailUrl(channelThumbnail),
      viewerCount: _parseViewerCount(_readText(renderer['viewCountText'])),
      ownerProfileUrl: _extractOwnerProfileUrl(renderer),
    );
  }

  bool _isLiveRenderer(Map<String, dynamic> renderer) {
    if (renderer['isLive'] == true) {
      return true;
    }
    if (_containsLiveStyle(_asList(renderer['thumbnailOverlays']))) {
      return true;
    }
    if (_containsLiveBadge(_asList(renderer['badges']))) {
      return true;
    }
    final viewCount = _readText(renderer['viewCountText']).toLowerCase();
    return viewCount.contains('watching') || viewCount.contains('直播');
  }

  bool _containsLiveStyle(List<dynamic> overlays) {
    for (final item in overlays) {
      final style =
          _asMap(_asMap(item)['thumbnailOverlayTimeStatusRenderer'])['style']
              ?.toString()
              .trim()
              .toUpperCase();
      if (style == 'LIVE') {
        return true;
      }
    }
    return false;
  }

  bool _containsLiveBadge(List<dynamic> badges) {
    for (final item in badges) {
      final badge = _asMap(_asMap(item)['metadataBadgeRenderer']);
      final label = badge['label']?.toString().trim().toLowerCase() ?? '';
      final style = badge['style']?.toString().trim().toUpperCase() ?? '';
      if (label.contains('live') ||
          label.contains('直播') ||
          style.contains('LIVE')) {
        return true;
      }
    }
    return false;
  }

  String? _extractOwnerProfileUrl(Map<String, dynamic> renderer) {
    for (final candidate in [
      _asMap(_firstRun(_asMap(renderer['ownerText']))?['navigationEndpoint']),
      _asMap(_firstRun(
          _asMap(renderer['shortBylineText']))?['navigationEndpoint']),
      _asMap(
          _firstRun(_asMap(renderer['longBylineText']))?['navigationEndpoint']),
    ]) {
      final url = _extractOwnerProfileUrlFromNavigationEndpoint(candidate);
      if (url != null && url.isNotEmpty) {
        return url;
      }
    }
    return null;
  }

  String? _extractOwnerProfileUrlFromNavigationEndpoint(
    Map<String, dynamic> navigationEndpoint,
  ) {
    final url = _asMap(_asMap(
            navigationEndpoint['commandMetadata'])['webCommandMetadata'])['url']
        ?.toString()
        .trim();
    if (url == null || url.isEmpty) {
      return null;
    }
    return url;
  }

  Map<String, dynamic>? _firstRun(Map<String, dynamic> textNode) {
    final runs = _asList(textNode['runs']);
    if (runs.isEmpty) {
      return null;
    }
    return _asMap(runs.first);
  }

  String _readText(Object? value) {
    if (value is String) {
      return value.trim();
    }
    final map = _asMap(value);
    final simpleText = map['simpleText']?.toString().trim() ?? '';
    if (simpleText.isNotEmpty) {
      return simpleText;
    }
    final runs = _asList(map['runs']);
    if (runs.isEmpty) {
      return '';
    }
    return runs
        .map((item) => _asMap(item)['text']?.toString() ?? '')
        .join()
        .trim();
  }

  int? _parseViewerCount(String text) {
    final compact = text.trim().toUpperCase();
    final compactMatch =
        RegExp(r'([0-9]+(?:\.[0-9]+)?)\s*([KMB])').firstMatch(compact);
    if (compactMatch != null) {
      final value = double.tryParse(compactMatch.group(1) ?? '');
      final suffix = compactMatch.group(2) ?? '';
      if (value == null) {
        return null;
      }
      final multiplier = switch (suffix) {
        'K' => 1000,
        'M' => 1000000,
        'B' => 1000000000,
        _ => 1,
      };
      return (value * multiplier).round();
    }
    final normalized = compact.replaceAll(RegExp(r'[^0-9]'), '');
    if (normalized.isEmpty) {
      return null;
    }
    return int.tryParse(normalized);
  }

  String? _pickLastThumbnailUrl(List<dynamic> thumbnails) {
    for (var index = thumbnails.length - 1; index >= 0; index -= 1) {
      final url = _asMap(thumbnails[index])['url']?.toString().trim() ?? '';
      if (url.isNotEmpty) {
        return url;
      }
    }
    return null;
  }

  String? _extractVideoIdFromPlayerResponse(Map<String, dynamic>? response) {
    final videoId =
        _asMap(response?['videoDetails'])['videoId']?.toString().trim() ?? '';
    return videoId.isEmpty ? null : videoId;
  }

  String? _extractVideoIdFromCanonicalBaseUrl(String html) {
    final match = _canonicalBaseVideoIdPattern.firstMatch(html);
    return match?.group(1)?.trim();
  }

  String? _extractVideoIdFromFallback(String html) {
    final match = _fallbackVideoIdPattern.firstMatch(html);
    return match?.group(1)?.trim();
  }

  String? _extractLiveChatContinuation(String html) {
    final scopedMatch = _liveChatContinuationPattern.firstMatch(html);
    final scopedValue = scopedMatch?.group(1)?.trim() ?? '';
    if (scopedValue.isNotEmpty) {
      return scopedValue;
    }
    final fallbackMatch = _continuationPattern.firstMatch(html);
    final fallbackValue = fallbackMatch?.group(1)?.trim() ?? '';
    return fallbackValue.isEmpty ? null : fallbackValue;
  }

  String? _findVideoIdInInitialData(Map<String, dynamic>? initialData) {
    if (initialData == null || initialData.isEmpty) {
      return null;
    }
    for (final renderer in _collectVideoRenderers(initialData)) {
      final videoId = renderer['videoId']?.toString().trim() ?? '';
      if (videoId.isNotEmpty) {
        return videoId;
      }
    }
    return null;
  }

  YouTubeSearchCandidate? _buildWatchPageCandidate({
    required Map<String, dynamic> initialData,
    required String videoId,
  }) {
    final contents = _asList(
      _asMap(
        _asMap(
          _asMap(
            _asMap(initialData['contents'])['twoColumnWatchNextResults'],
          )['results'],
        )['results'],
      )['contents'],
    );
    if (contents.length < 2) {
      return null;
    }
    final primaryInfo = _asMap(contents[0])['videoPrimaryInfoRenderer'];
    final secondaryInfo = _asMap(contents[1])['videoSecondaryInfoRenderer'];
    final primaryRenderer = _asMap(primaryInfo);
    final secondaryRenderer = _asMap(secondaryInfo);
    if (primaryRenderer.isEmpty || secondaryRenderer.isEmpty) {
      return null;
    }

    final ownerRenderer =
        _asMap(_asMap(secondaryRenderer['owner'])['videoOwnerRenderer']);
    final title = _readText(primaryRenderer['title']);
    final streamerName = _readText(ownerRenderer['title']);
    final viewerRenderer =
        _asMap(_asMap(primaryRenderer['viewCount'])['videoViewCountRenderer']);
    final viewerCount = _asInt(viewerRenderer['originalViewCount']) ??
        _parseViewerCount(_readText(viewerRenderer['viewCount']));
    final ownerProfileUrl = _extractOwnerProfileUrlFromNavigationEndpoint(
      _asMap(ownerRenderer['navigationEndpoint']),
    );
    final thumbnails =
        _asList(_asMap(ownerRenderer['thumbnail'])['thumbnails']);
    final displayStreamerName =
        streamerName.isNotEmpty ? streamerName : 'YouTube Live';
    if (title.isEmpty && displayStreamerName == 'YouTube Live') {
      return null;
    }
    return YouTubeSearchCandidate(
      videoId: videoId,
      title: title.isEmpty ? videoId : title,
      streamerName: displayStreamerName,
      streamerAvatarUrl: _pickLastThumbnailUrl(thumbnails),
      viewerCount: viewerCount,
      ownerProfileUrl: ownerProfileUrl,
    );
  }

  bool _isVideoId(String value) {
    return RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(value.trim());
  }

  int? _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString().trim() ?? '');
  }

  bool _isWhitespace(int codeUnit) {
    return codeUnit == 9 || codeUnit == 10 || codeUnit == 13 || codeUnit == 32;
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

  List<dynamic> _asList(Object? value) {
    if (value is List) {
      return value;
    }
    return const [];
  }

  String? _firstNonEmpty(List<String?> values) {
    for (final value in values) {
      final normalized = value?.trim() ?? '';
      if (normalized.isNotEmpty) {
        return normalized;
      }
    }
    return null;
  }

  String? _extractByPattern(RegExp pattern, String source) {
    final match = pattern.firstMatch(source);
    final value = match?.group(1)?.trim() ?? '';
    return value.isEmpty ? null : value;
  }
}
