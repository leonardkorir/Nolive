import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:live_core/live_core.dart';

import '../provider_json.dart';
import '../provider_runtime_support.dart';

abstract interface class StripchatApiClient {
  String get cookie;

  Future<Map<String, dynamic>> fetchInitialDynamic();

  Future<Map<String, dynamic>> fetchRecommendModels({
    int limit = 24,
    int offset = 0,
    String? guestHash,
  });

  Future<Map<String, dynamic>> fetchCategoryModels({
    required String filterGroupTags,
    int limit = 60,
    int offset = 0,
    String? parentTag,
    String? guestHash,
  });

  Future<Map<String, dynamic>> fetchLiveTags();

  Future<Map<String, dynamic>> searchModels({
    required String query,
    int limit = 24,
    String? guestHash,
  });

  Future<Map<String, dynamic>> listModels({
    required List<int> modelIds,
    String? csrfToken,
    String? guestHash,
  });

  Future<Map<String, dynamic>> fetchCam(String username);

  Future<Map<String, dynamic>> fetchBroadcast(String username);

  Future<Map<String, dynamic>> fetchMembers(String username);

  Future<Map<String, dynamic>> fetchChatHistory(String modelId);

  Future<StripchatPlaybackProbeResult> probePlaybackPlaylist(
    String url, {
    Map<String, String> headers = const <String, String>{},
    String? preferredVariantId,
  });

  Future<List<StripchatPlaybackVariant>> fetchPlaybackVariants(
    String url, {
    Map<String, String> headers = const <String, String>{},
  });

  void close();
}

class StripchatPlaybackProbeResult {
  const StripchatPlaybackProbeResult({
    required this.isPlayable,
    required this.finalUrl,
    required this.body,
    this.reason,
  });

  final bool isPlayable;
  final Uri finalUrl;
  final String body;
  final String? reason;
}

class StripchatPlaybackVariant {
  const StripchatPlaybackVariant({
    required this.qualityId,
    required this.url,
    required this.bandwidth,
  });

  final String qualityId;
  final Uri url;
  final int bandwidth;
}

class _StripchatMasterPlaylistAuth {
  const _StripchatMasterPlaylistAuth({required this.scheme, required this.key});

  final String scheme;
  final String key;
}

class _StripchatMasterVariant {
  const _StripchatMasterVariant({
    required this.url,
    required this.bandwidth,
    required this.qualityId,
  });

  final Uri url;
  final int bandwidth;
  final String? qualityId;
}

class HttpStripchatApiClient implements StripchatApiClient {
  HttpStripchatApiClient({
    http.Client? client,
    this.cookie = '',
    ProviderBrowserProfile browserProfile =
        ProviderBrowserProfile.chromiumDesktop,
    ProviderRetryPolicy retryPolicy = const ProviderRetryPolicy(),
    bool? ownsClient,
  }) : _client = client ?? http.Client(),
       _ownsClient = ownsClient ?? client == null,
       _browserProfile = browserProfile,
       _retryPolicy = retryPolicy;

  static const String _apiHost = 'zh.stripchat.com';
  static const Duration _initialDynamicFallbackTtl = Duration(minutes: 10);
  static const Duration _initialDynamicRefreshSkew = Duration(minutes: 2);

  final http.Client _client;
  final bool _ownsClient;
  @override
  final String cookie;
  final ProviderBrowserProfile _browserProfile;
  final ProviderRetryPolicy _retryPolicy;

  Map<String, dynamic>? _cachedInitialDynamic;
  DateTime? _cachedInitialDynamicExpiresAt;
  Future<Map<String, dynamic>>? _pendingInitialDynamic;

  @override
  void close() {
    _cachedInitialDynamic = null;
    _cachedInitialDynamicExpiresAt = null;
    _pendingInitialDynamic = null;
    if (_ownsClient) {
      _client.close();
    }
  }

  @override
  Future<Map<String, dynamic>> fetchInitialDynamic() async {
    if (_cachedInitialDynamic != null && !_shouldRefreshInitialDynamic()) {
      return _cachedInitialDynamic!;
    }
    return _pendingInitialDynamic ??= _fetchInitialDynamicImpl();
  }

  Future<Map<String, dynamic>> _fetchInitialDynamicImpl() async {
    try {
      const path = '/api/front/v3/config/initial-dynamic';
      const params = <String, String>{'requestPath': '/'};
      final response = await _get(
        Uri.https(_apiHost, path, params),
        context: 'initial-dynamic',
      );
      try {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        _cachedInitialDynamic = ProviderJson.asMap(decoded['initialDynamic']);
        _cachedInitialDynamicExpiresAt = _resolveInitialDynamicExpiry(
          _cachedInitialDynamic!,
        );
      } catch (e, s) {
        throw ProviderParseException(
          providerId: ProviderId.stripchat,
          message:
              'Stripchat initial-dynamic response is not valid JSON or missing expected structure',
          cause: e,
          stackTrace: s,
        );
      }
      return _cachedInitialDynamic!;
    } finally {
      _pendingInitialDynamic = null;
    }
  }

  bool _shouldRefreshInitialDynamic() {
    final expiresAt = _cachedInitialDynamicExpiresAt;
    if (expiresAt == null) {
      return true;
    }
    return DateTime.now().toUtc().isAfter(expiresAt.toUtc());
  }

  DateTime _resolveInitialDynamicExpiry(Map<String, dynamic> payload) {
    final websocket = ProviderJson.asMap(payload['websocket']);
    final jwt = websocket['token']?.toString().trim() ?? '';
    final jwtExpiry = _extractJwtExpiry(jwt);
    if (jwtExpiry == null) {
      return DateTime.now().add(_initialDynamicFallbackTtl);
    }
    final now = DateTime.now().toUtc();
    if (!jwtExpiry.isAfter(now)) {
      return now.subtract(const Duration(seconds: 1));
    }
    final refreshAt = jwtExpiry.subtract(_initialDynamicRefreshSkew);
    final minimumTtl = now.add(const Duration(minutes: 1));
    if (refreshAt.isBefore(minimumTtl)) {
      return minimumTtl;
    }
    return refreshAt;
  }

  DateTime? _extractJwtExpiry(String jwt) {
    if (jwt.isEmpty) {
      return null;
    }
    final segments = jwt.split('.');
    if (segments.length < 2) {
      return null;
    }
    try {
      final payloadBytes = base64Url.decode(base64.normalize(segments[1]));
      final payload = jsonDecode(utf8.decode(payloadBytes));
      if (payload is! Map<String, dynamic>) {
        return null;
      }
      final rawExp = payload['exp'];
      final expSeconds = rawExp is num
          ? rawExp.toInt()
          : int.tryParse(rawExp?.toString() ?? '');
      if (expSeconds == null || expSeconds <= 0) {
        return null;
      }
      return DateTime.fromMillisecondsSinceEpoch(
        expSeconds * 1000,
        isUtc: true,
      );
    } on Exception {
      return null;
    }
  }

  @override
  Future<Map<String, dynamic>> fetchRecommendModels({
    int limit = 24,
    int offset = 0,
    String? guestHash,
  }) async {
    final params = <String, String>{
      'primaryTag': 'girls',
      'limit': limit.toString(),
      'topLimit': '61',
      'offset': offset.toString(),
      'uniq': DateTime.now().millisecondsSinceEpoch.toString(),
      if (guestHash != null) 'guestHash': guestHash,
    };
    return _getJson(
      Uri.https(_apiHost, '/api/front/v2/models', params),
      context: 'recommend models',
    );
  }

  @override
  Future<Map<String, dynamic>> fetchCategoryModels({
    required String filterGroupTags,
    int limit = 60,
    int offset = 0,
    String? parentTag,
    String? guestHash,
  }) async {
    final params = <String, String>{
      'removeShows': 'false',
      'recInFeatured': 'false',
      'limit': limit.toString(),
      'offset': offset.toString(),
      'primaryTag': 'girls',
      'sortBy': 'stripRanking',
      'uniq': DateTime.now().millisecondsSinceEpoch.toString(),
      if (guestHash != null) 'guestHash': guestHash,
      if (parentTag != null) 'parentTag': parentTag,
      'filterGroupTags': filterGroupTags,
    };
    return _getJson(
      Uri.https(_apiHost, '/api/front/models', params),
      context: 'category models',
    );
  }

  @override
  Future<Map<String, dynamic>> fetchLiveTags() async {
    const params = <String, String>{
      'primaryTag': 'girls',
      'withMixedTags': 'true',
    };
    return _getJson(
      Uri.https(_apiHost, '/api/front/models/liveTags', params),
      context: 'live tags',
    );
  }

  @override
  Future<Map<String, dynamic>> searchModels({
    required String query,
    int limit = 24,
    String? guestHash,
  }) async {
    final params = <String, String>{
      'query': query,
      'limit': limit.toString(),
      'primaryTag': 'girls',
      'includeCvSearchResults': 'false',
      'rcmGrp': 'A',
      'oRcmGrp': 'A',
      'uniq': DateTime.now().millisecondsSinceEpoch.toString(),
      if (guestHash != null) 'guestHash': guestHash,
    };
    final response = await _get(
      Uri.https(_apiHost, '/api/front/v5/models/search/group/all', params),
      context: 'search models',
    );
    final body = response.body;
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } on FormatException {
      try {
        final decoded = base64Decode(body);
        return jsonDecode(utf8.decode(decoded)) as Map<String, dynamic>;
      } on Exception {
        throw ProviderParseException(
          providerId: ProviderId.stripchat,
          message:
              'Stripchat search models response is not valid JSON (plain or base64)',
        );
      }
    } on TypeError {
      throw ProviderParseException(
        providerId: ProviderId.stripchat,
        message:
            'Stripchat search models response is valid JSON but has unexpected structure',
      );
    }
  }

  @override
  Future<Map<String, dynamic>> listModels({
    required List<int> modelIds,
    String? csrfToken,
    String? guestHash,
  }) async {
    final params = {
      'uniq': DateTime.now().millisecondsSinceEpoch.toString(),
      if (guestHash != null) 'guestHash': guestHash,
      'modelIds[]': modelIds.map((id) => id.toString()).toList(),
    };
    return _getJson(
      Uri.https(_apiHost, '/api/front/models/list', params),
      context: 'list models',
    );
  }

  @override
  Future<Map<String, dynamic>> fetchCam(String username) async {
    const params = <String, String>{
      'timezoneOffset': '-480',
      'triggerRequest': 'loadCam',
      'primaryTag': 'girls',
      'withRecentShow': '1',
    };
    return _getJson(
      Uri.https(
        _apiHost,
        '/api/front/v2/models/username/$username/cam',
        params,
      ),
      context: 'cam $username',
    );
  }

  @override
  Future<Map<String, dynamic>> fetchBroadcast(String username) async {
    return _getJson(
      Uri.https(_apiHost, '/api/front/v1/broadcasts/$username'),
      context: 'broadcast $username',
    );
  }

  @override
  Future<Map<String, dynamic>> fetchMembers(String username) async {
    final params = <String, String>{
      'uniq': DateTime.now().millisecondsSinceEpoch.toString(),
    };
    return _getJson(
      Uri.https(
        _apiHost,
        '/api/front/models/username/$username/members',
        params,
      ),
      context: 'members $username',
    );
  }

  @override
  Future<Map<String, dynamic>> fetchChatHistory(String modelId) async {
    const params = <String, String>{'source': 'regular'};
    return _getJson(
      Uri.https(_apiHost, '/api/front/v2/models/$modelId/chat', params),
      context: 'chat history $modelId',
    );
  }

  @override
  Future<StripchatPlaybackProbeResult> probePlaybackPlaylist(
    String url, {
    Map<String, String> headers = const <String, String>{},
    String? preferredVariantId,
  }) async {
    final response = await _get(
      Uri.parse(url),
      context: 'playback playlist',
      headers: headers,
    );
    final finalUrl = response.request?.url ?? Uri.parse(url);
    final body = response.body;
    final directProbe = _inspectPlaylistResponse(uri: finalUrl, body: body);
    if (!directProbe.isPlayable || !_looksLikeMasterPlaylist(body)) {
      return directProbe;
    }
    final masterAuth = _parseMasterPlaylistAuth(body);

    final variants = _parseMasterVariants(
      finalUrl,
      body,
      masterAuth: masterAuth,
    );
    if (variants.isEmpty) {
      return directProbe;
    }
    // Preferred first, then remaining by bandwidth (source child 404 must not
    // leave playback stuck on empty master — same recovery as llhls proxy).
    final ordered = <_StripchatMasterVariant>[];
    final preferred = variants
        .where(
          (variant) =>
              _matchesPreferredVariant(variant.url, preferredVariantId),
        )
        .toList(growable: false)
      ..sort((a, b) => b.bandwidth.compareTo(a.bandwidth));
    ordered.addAll(preferred);
    final rest = List<_StripchatMasterVariant>.of(variants)
      ..sort((a, b) => b.bandwidth.compareTo(a.bandwidth));
    for (final variant in rest) {
      if (ordered.any((v) => v.url.toString() == variant.url.toString())) {
        continue;
      }
      ordered.add(variant);
    }
    StripchatPlaybackProbeResult? lastChildReject;
    for (final variant in ordered) {
      try {
        final childResponse = await _get(
          variant.url,
          context: 'playback variant playlist',
          headers: headers,
        );
        final childProbe = _inspectPlaylistResponse(
          uri: childResponse.request?.url ?? variant.url,
          body: childResponse.body,
        );
        if (childProbe.isPlayable &&
            !_looksLikeMasterPlaylist(childResponse.body)) {
          return childProbe;
        }
        // Keep ad/VOD reject so we do not fall through to "master is #EXTM3U".
        if (!childProbe.isPlayable) {
          lastChildReject = childProbe;
        }
      } catch (_) {
        continue;
      }
    }
    return lastChildReject ?? directProbe;
  }

  @override
  Future<List<StripchatPlaybackVariant>> fetchPlaybackVariants(
    String url, {
    Map<String, String> headers = const <String, String>{},
  }) async {
    final response = await _get(
      Uri.parse(url),
      context: 'playback variants',
      headers: headers,
    );
    final finalUrl = response.request?.url ?? Uri.parse(url);
    final body = response.body;
    if (!_looksLikeMasterPlaylist(body)) {
      return const <StripchatPlaybackVariant>[];
    }
    final masterAuth = _parseMasterPlaylistAuth(body);
    return _parsePlaybackVariants(finalUrl, body, masterAuth: masterAuth);
  }

  Future<Map<String, dynamic>> _getJson(
    Uri uri, {
    required String context,
    Map<String, String> headers = const <String, String>{},
  }) async {
    final response = await _get(uri, context: context, headers: headers);
    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e, s) {
      throw ProviderParseException(
        providerId: ProviderId.stripchat,
        message: 'Stripchat $context response is not valid JSON',
        cause: e,
        stackTrace: s,
      );
    }
  }

  Future<http.Response> _get(
    Uri uri, {
    required String context,
    Map<String, String> headers = const <String, String>{},
  }) async {
    return runProviderRequestWithRetry(
      providerId: ProviderId.stripchat,
      operation: 'GET $context',
      policy: _retryPolicy,
      action: (_) async {
        final mergedHeaders = _buildApiHeaders(referer: 'https://$_apiHost/');
        mergedHeaders.addAll(headers);
        try {
          final response = await _client.get(uri, headers: mergedHeaders);
          _ensureSuccess(response, context: context);
          return response;
        } catch (e, s) {
          if (e is ProviderException) {
            rethrow;
          }
          if (e is ProviderRetryableException) {
            rethrow;
          }
          throw ProviderRetryableException(e, s);
        }
      },
    );
  }

  Map<String, String> _buildApiHeaders({required String referer}) {
    return {
      'user-agent': _browserProfile.userAgent,
      'accept-language': _browserProfile.acceptLanguage,
      ..._browserProfile.buildClientHintHeaders(),
      'accept': 'application/json',
      'origin': 'https://$_apiHost',
      'referer': referer,
      'sec-fetch-dest': 'empty',
      'sec-fetch-mode': 'cors',
      'sec-fetch-site': 'same-origin',
      if (cookie.trim().isNotEmpty) 'cookie': cookie.trim(),
    };
  }

  StripchatPlaybackProbeResult _inspectPlaylistResponse({
    required Uri uri,
    required String body,
  }) {
    final normalizedBody = body.toLowerCase();
    if (uri.path.contains('/cpa/') ||
        normalizedBody.contains('#ext-x-mouflon-advert') ||
        normalizedBody.contains('#ext-x-playlist-type:vod')) {
      return StripchatPlaybackProbeResult(
        isPlayable: false,
        finalUrl: uri,
        body: body,
        reason: 'stripchat_advertisement_playlist',
      );
    }
    return StripchatPlaybackProbeResult(
      isPlayable: body.contains('#EXTM3U'),
      finalUrl: uri,
      body: body,
      reason: body.contains('#EXTM3U')
          ? null
          : 'stripchat_invalid_playlist_response',
    );
  }

  bool _looksLikeMasterPlaylist(String body) {
    return body.contains('#EXT-X-STREAM-INF');
  }

  List<StripchatPlaybackVariant> _parsePlaybackVariants(
    Uri playlistUri,
    String body, {
    _StripchatMasterPlaylistAuth? masterAuth,
  }) {
    final masterVariants = _parseMasterVariants(
      playlistUri,
      body,
      masterAuth: masterAuth,
    );
    final variants = <StripchatPlaybackVariant>[];
    final seenQualityIds = <String>{};
    for (final masterVariant in masterVariants) {
      final qualityId = masterVariant.qualityId;
      if (qualityId == null || !seenQualityIds.add(qualityId)) {
        continue;
      }
      variants.add(
        StripchatPlaybackVariant(
          qualityId: qualityId,
          url: masterVariant.url,
          bandwidth: masterVariant.bandwidth,
        ),
      );
    }
    return variants;
  }

  List<_StripchatMasterVariant> _parseMasterVariants(
    Uri playlistUri,
    String body, {
    _StripchatMasterPlaylistAuth? masterAuth,
  }) {
    String? currentInfoLine;
    final variants = <_StripchatMasterVariant>[];
    for (final rawLine in const LineSplitter().convert(body)) {
      final line = rawLine.trim();
      if (line.isEmpty) {
        continue;
      }
      if (line.startsWith('#EXT-X-STREAM-INF')) {
        currentInfoLine = line;
        continue;
      }
      if (line.startsWith('#')) {
        continue;
      }
      if (!line.contains('.m3u8')) {
        currentInfoLine = null;
        continue;
      }
      final bandwidth = _parseBandwidth(currentInfoLine);
      if (bandwidth <= 0) {
        currentInfoLine = null;
        continue;
      }
      final resolved = _appendMasterPlaylistAuth(
        playlistUri.resolve(line),
        masterAuth,
      );
      variants.add(
        _StripchatMasterVariant(
          qualityId: _extractVariantQualityId(resolved),
          url: resolved,
          bandwidth: bandwidth,
        ),
      );
      currentInfoLine = null;
    }
    return variants;
  }

  String? _extractVariantQualityId(Uri uri) {
    final filename = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    final match = RegExp(
      r'_(\d+p(?:60)?)\.m3u8$',
      caseSensitive: false,
    ).firstMatch(filename);
    if (match != null) {
      return match.group(1)?.toLowerCase();
    }
    return _isSourceVariantUri(uri) ? 'source' : null;
  }

  _StripchatMasterPlaylistAuth? _parseMasterPlaylistAuth(String body) {
    for (final rawLine in const LineSplitter().convert(body)) {
      final line = rawLine.trim();
      final match = RegExp(
        r'^#EXT-X-MOUFLON:PSCH:([^:]+):(.+)$',
      ).firstMatch(line);
      if (match == null) {
        continue;
      }
      final scheme = match.group(1)?.trim() ?? '';
      final key = match.group(2)?.trim() ?? '';
      if (scheme.isEmpty || key.isEmpty) {
        continue;
      }
      return _StripchatMasterPlaylistAuth(scheme: scheme, key: key);
    }
    return null;
  }

  Uri _appendMasterPlaylistAuth(
    Uri uri,
    _StripchatMasterPlaylistAuth? masterAuth,
  ) {
    if (masterAuth == null) {
      return uri;
    }
    final queryParameters = Map<String, String>.from(uri.queryParameters);
    queryParameters.putIfAbsent('psch', () => masterAuth.scheme);
    queryParameters.putIfAbsent('pkey', () => masterAuth.key);
    return uri.replace(queryParameters: queryParameters);
  }

  bool _matchesPreferredVariant(Uri uri, String? preferredVariantId) {
    final normalized = preferredVariantId?.trim().toLowerCase() ?? '';
    if (normalized.isEmpty || normalized == 'auto') {
      return false;
    }
    if (normalized == 'source') {
      return _isSourceVariantUri(uri);
    }
    final path = uri.path.toLowerCase();
    return path.contains('_$normalized.m3u8') || path.endsWith('/$normalized');
  }

  bool _isSourceVariantUri(Uri uri) {
    final filename = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    if (!filename.toLowerCase().endsWith('.m3u8')) {
      return false;
    }
    if (RegExp(
      r'_\d+p(?:60)?\.m3u8$',
      caseSensitive: false,
    ).hasMatch(filename)) {
      return false;
    }
    final stem = filename.substring(0, filename.length - '.m3u8'.length);
    if (uri.pathSegments.length < 2) {
      return false;
    }
    final parentSegment = uri.pathSegments[uri.pathSegments.length - 2];
    return stem == parentSegment;
  }

  int _parseBandwidth(String? infoLine) {
    if (infoLine == null) {
      return -1;
    }
    final match = RegExp(r'BANDWIDTH=(\d+)').firstMatch(infoLine);
    return int.tryParse(match?.group(1) ?? '') ?? -1;
  }

  void _ensureSuccess(http.Response response, {required String context}) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }
    if (isRetryableHttpStatus(response.statusCode) ||
        response.statusCode == 403) {
      throw ProviderRetryableException(
        ProviderParseException(
          providerId: ProviderId.stripchat,
          message:
              'Stripchat $context received retryable status ${response.statusCode}.',
        ),
        null,
      );
    }
    throw ProviderParseException(
      providerId: ProviderId.stripchat,
      message: 'Stripchat $context failed with status ${response.statusCode}.',
    );
  }
}
