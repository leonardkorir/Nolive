import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:live_core/live_core.dart';

import '../provider_json.dart';
import '../provider_runtime_support.dart';

abstract interface class ChaturbateApiClient {
  static const List<String> defaultRecommendCarouselIds = [
    'most_popular',
    'trending',
    'top-rated',
    'recently_started',
  ];

  static const int searchPageSize = 90;

  Future<Map<String, dynamic>> fetchDiscoverCarousel(
    String carouselId, {
    String genders = '',
  });

  Future<Map<String, dynamic>> fetchRoomList({
    required String query,
    String? genders,
    int limit = searchPageSize,
    int offset = 0,
  });

  Future<String> fetchRoomPage(String roomId);

  Future<Map<String, dynamic>> fetchRoomContext(
    String roomId, {
    String? cookie,
  });

  Future<String> fetchHlsPlaylist(
    String url, {
    String? referer,
    String? cookie,
  });

  Future<Map<String, dynamic>> authenticatePushService({
    required String roomId,
    required String csrfToken,
    required String backend,
    required String presenceId,
    required Map<String, dynamic> topics,
  });

  Future<List<Map<String, dynamic>>> fetchRoomHistory({
    required String roomId,
    required String csrfToken,
    required Map<String, dynamic> topics,
  });

  void close() {}
}

class ChaturbateRoomHistoryUnavailableException extends ProviderParseException {
  ChaturbateRoomHistoryUnavailableException({
    required this.statusCode,
    String? message,
  }) : super(
          providerId: ProviderId.chaturbate,
          message: message ??
              'Chaturbate room_history response failed with status $statusCode.',
        );

  final int statusCode;
}

class HttpChaturbateApiClient implements ChaturbateApiClient {
  HttpChaturbateApiClient({
    this.cookie = '',
    http.Client? client,
    ProviderBrowserProfile browserProfile =
        ProviderBrowserProfile.chromiumDesktop,
    ProviderRetryPolicy retryPolicy = const ProviderRetryPolicy(),
    void Function(String message)? diagnostics,
  })  : _client = client ?? http.Client(),
        _browserProfile = browserProfile,
        _retryPolicy = retryPolicy,
        _diagnostics = diagnostics;

  final http.Client _client;
  final String cookie;
  final ProviderBrowserProfile _browserProfile;
  final ProviderRetryPolicy _retryPolicy;
  final void Function(String message)? _diagnostics;

  @override
  void close() {
    _client.close();
  }

  static const String browserUserAgent = kChromiumDesktopUserAgent;
  static const String browserAcceptLanguage = kChromiumDesktopAcceptLanguage;
  static const String browserSecChUa = kChromiumDesktopSecChUa;
  static const String browserSecChUaMobile = kChromiumDesktopSecChUaMobile;
  static const String browserSecChUaPlatform = kChromiumDesktopSecChUaPlatform;

  static Map<String, String> buildPlaybackHeaders({
    required String referer,
    String cookie = '',
    ProviderBrowserProfile browserProfile =
        ProviderBrowserProfile.chromiumDesktop,
  }) {
    final normalizedReferer = _normalizePlaybackReferer(referer);
    final normalizedCookie = cookie.trim();
    return <String, String>{
      'user-agent': browserProfile.userAgent,
      'accept-language': browserProfile.acceptLanguage,
      ...browserProfile.buildClientHintHeaders(),
      'accept': '*/*',
      'origin': 'https://chaturbate.com',
      'priority': 'u=4, i',
      'referer': normalizedReferer,
      'sec-fetch-dest': 'empty',
      'sec-fetch-mode': 'cors',
      'sec-fetch-site': 'cross-site',
      if (normalizedCookie.isNotEmpty) 'cookie': normalizedCookie,
    };
  }

  static String _normalizePlaybackReferer(String referer) {
    final normalized = referer.trim();
    if (normalized.isEmpty) {
      return 'https://chaturbate.com/';
    }
    final uri = Uri.tryParse(normalized);
    if (uri == null) {
      return 'https://chaturbate.com/';
    }
    return uri.host.endsWith('chaturbate.com')
        ? 'https://chaturbate.com/'
        : normalized;
  }

  @override
  Future<Map<String, dynamic>> fetchDiscoverCarousel(
    String carouselId, {
    String genders = '',
  }) async {
    final response = await _get(
      Uri.https(
        'chaturbate.com',
        '/api/ts/discover/carousels/$carouselId/',
        {'genders': genders},
      ),
      headers: _buildApiHeaders(
        referer: _buildDiscoverReferer(genders),
      ),
      context: 'carousel $carouselId request',
    );
    _ensureSuccessfulResponse(
      response,
      context: 'carousel $carouselId request',
    );

    return _decodeJson(
      response.body,
      context: 'carousel $carouselId response',
    );
  }

  @override
  Future<Map<String, dynamic>> fetchRoomList({
    required String query,
    String? genders,
    int limit = ChaturbateApiClient.searchPageSize,
    int offset = 0,
  }) async {
    final queryParameters = <String, String>{
      'keywords': query,
      'limit': '$limit',
      'offset': '$offset',
      'require_fingerprint': 'true',
    };
    final normalizedGenders = genders?.trim() ?? '';
    if (normalizedGenders.isNotEmpty) {
      queryParameters['genders'] = normalizedGenders;
    }

    final response = await _get(
      Uri.https(
        'chaturbate.com',
        '/api/ts/roomlist/room-list/',
        queryParameters,
      ),
      headers: _buildApiHeaders(
        referer: _buildSearchReferer(query: query, genders: normalizedGenders),
      ),
      context: 'room list request',
    );
    _ensureSuccessfulResponse(response, context: 'room list request');

    return _decodeJson(response.body, context: 'room list response');
  }

  @override
  Future<String> fetchRoomPage(String roomId) async {
    final response = await _get(
      Uri.https('chaturbate.com', '/$roomId/'),
      headers: _buildDocumentHeaders(
        referer: 'https://chaturbate.com/',
      ),
      context: 'room page request for $roomId',
    );
    _ensureSuccessfulResponse(
      response,
      context: 'room page request for $roomId',
    );

    return _decodeTextBody(
      response,
      context: 'room page response for $roomId',
    );
  }

  @override
  Future<Map<String, dynamic>> fetchRoomContext(
    String roomId, {
    String? cookie,
  }) async {
    final response = await _get(
      Uri.https('chaturbate.com', '/api/chatvideocontext/$roomId/'),
      headers: _buildApiHeaders(
        referer: _buildRoomReferer(roomId),
        cookieOverride: cookie,
      ),
      context: 'room context request for $roomId',
    );
    _ensureSuccessfulResponse(
      response,
      context: 'room context request for $roomId',
    );
    return _decodeJson(
      response.body,
      context: 'room context response for $roomId',
    );
  }

  @override
  Future<String> fetchHlsPlaylist(
    String url, {
    String? referer,
    String? cookie,
  }) async {
    final response = await _get(
      Uri.parse(url),
      headers: _buildMediaHeaders(
        referer: referer ?? 'https://chaturbate.com/',
        cookieOverride: cookie,
      ),
      context: 'hls playlist request',
    );
    _ensureSuccessfulResponse(response, context: 'hls playlist request');
    return response.body;
  }

  @override
  Future<Map<String, dynamic>> authenticatePushService({
    required String roomId,
    required String csrfToken,
    required String backend,
    required String presenceId,
    required Map<String, dynamic> topics,
  }) async {
    final response = await _sendMultipart(
      path: '/push_service/auth/',
      referer: _buildRoomReferer(roomId),
      fields: {
        'presence_id': presenceId,
        'topics': jsonEncode(topics),
        'backend': backend,
        'csrfmiddlewaretoken': csrfToken,
      },
    );
    return _decodeJson(response, context: 'push_service auth response');
  }

  @override
  Future<List<Map<String, dynamic>>> fetchRoomHistory({
    required String roomId,
    required String csrfToken,
    required Map<String, dynamic> topics,
  }) async {
    final response = await _sendMultipartResponse(
      path: '/push_service/room_history/',
      referer: _buildRoomReferer(roomId),
      fields: {
        'topics': jsonEncode(topics),
        'csrfmiddlewaretoken': csrfToken,
      },
    );
    if (_looksLikeCloudflareChallenge(response)) {
      _ensureSuccessfulResponse(response, context: 'room_history request');
    }
    if (response.statusCode == 403) {
      throw ChaturbateRoomHistoryUnavailableException(
        statusCode: 403,
        message:
            'Chaturbate room_history response returned status 403; realtime danmaku can continue.',
      );
    }
    _ensureSuccessfulResponse(response, context: 'room_history request');
    return _decodeJsonList(response.body, context: 'room_history response');
  }

  Future<String> _sendMultipart({
    required String path,
    required String referer,
    required Map<String, String> fields,
  }) async {
    final response = await _sendMultipartResponse(
      path: path,
      referer: referer,
      fields: fields,
    );
    _ensureSuccessfulResponse(response, context: '$path request');
    return response.body;
  }

  Future<http.Response> _sendMultipartResponse({
    required String path,
    required String referer,
    required Map<String, String> fields,
  }) async {
    return runProviderRequestWithRetry(
      providerId: ProviderId.chaturbate,
      operation: 'chaturbate multipart $path',
      policy: _retryPolicy,
      diagnostics: _diagnostics,
      action: (_) async {
        final request = http.MultipartRequest(
          'POST',
          Uri.https('chaturbate.com', path),
        )
          ..headers.addAll(
            _buildApiHeaders(
              referer: referer,
              extraHeaders: {
                'origin': 'https://chaturbate.com',
              },
            ),
          )
          ..fields.addAll(fields);
        late final http.StreamedResponse streamed;
        try {
          streamed = await _client.send(request);
        } catch (error, stackTrace) {
          throw ProviderRetryableException(
            ProviderParseException(
              providerId: ProviderId.chaturbate,
              message: 'Chaturbate $path request failed before response.',
              cause: error,
              stackTrace: stackTrace,
            ),
            stackTrace,
          );
        }
        if (isRetryableHttpStatus(streamed.statusCode)) {
          throw ProviderRetryableException(
            ProviderParseException(
              providerId: ProviderId.chaturbate,
              message:
                  'Chaturbate $path request failed with status ${streamed.statusCode}.',
            ),
          );
        }
        return http.Response.fromStream(streamed);
      },
    );
  }

  Map<String, String> _buildDocumentHeaders({
    required String referer,
    String? cookieOverride,
  }) {
    return _buildHeaders({
      'accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,'
          'image/avif,image/webp,image/apng,*/*;q=0.8,'
          'application/signed-exchange;v=b3;q=0.7',
      'cache-control': 'max-age=0',
      'priority': 'u=0, i',
      'referer': referer,
      'sec-fetch-dest': 'document',
      'sec-fetch-mode': 'navigate',
      'sec-fetch-site': 'same-origin',
      'sec-fetch-user': '?1',
      'upgrade-insecure-requests': '1',
    }, cookieOverride: cookieOverride);
  }

  Map<String, String> _buildApiHeaders({
    required String referer,
    Map<String, String> extraHeaders = const {},
    String? cookieOverride,
  }) {
    return _buildHeaders({
      'accept': '*/*',
      'priority': 'u=1, i',
      'referer': referer,
      'sec-fetch-dest': 'empty',
      'sec-fetch-mode': 'cors',
      'sec-fetch-site': 'same-origin',
      'x-requested-with': 'XMLHttpRequest',
      ...extraHeaders,
    }, cookieOverride: cookieOverride);
  }

  Map<String, String> _buildMediaHeaders({
    required String referer,
    String? cookieOverride,
  }) {
    return HttpChaturbateApiClient.buildPlaybackHeaders(
      referer: referer,
      cookie: cookieOverride ?? cookie,
      browserProfile: _browserProfile,
    );
  }

  String _buildSearchReferer({
    required String query,
    required String genders,
  }) {
    if (query.trim().isEmpty) {
      return 'https://chaturbate.com/';
    }
    final path = switch (genders) {
      'f' => '/female-cams/',
      'm' => '/male-cams/',
      'c' => '/couples-cams/',
      't' => '/trans-cams/',
      _ => '/',
    };
    return Uri.https(
      'chaturbate.com',
      path,
      path == '/' ? {'keywords': query} : {'keywords': query},
    ).toString();
  }

  String _buildDiscoverReferer(String genders) {
    final path = switch (genders.trim()) {
      'f' => '/discover/female/',
      'm' => '/discover/male/',
      'c' => '/discover/couple/',
      't' => '/discover/trans/',
      _ => '/discover/',
    };
    return 'https://chaturbate.com$path';
  }

  String _buildRoomReferer(String roomId) {
    final normalizedRoomId = roomId.trim();
    if (normalizedRoomId.isEmpty) {
      return 'https://chaturbate.com/';
    }
    return 'https://chaturbate.com/$normalizedRoomId/';
  }

  Map<String, String> _buildHeaders(
    Map<String, String> extraHeaders, {
    bool includeCookie = true,
    String? cookieOverride,
  }) {
    final headers = <String, String>{
      'user-agent': _browserProfile.userAgent,
      'accept-language': _browserProfile.acceptLanguage,
      ..._browserProfile.buildClientHintHeaders(),
      ...extraHeaders,
    };
    final normalizedCookie = (cookieOverride ?? cookie).trim();
    if (includeCookie && normalizedCookie.isNotEmpty) {
      headers['cookie'] = normalizedCookie;
    }
    return headers;
  }

  void _ensureSuccessfulResponse(
    http.Response response, {
    required String context,
  }) {
    if (_looksLikeCloudflareChallenge(response)) {
      throw ProviderParseException(
        providerId: ProviderId.chaturbate,
        message: _buildCloudflareChallengeMessage(context),
      );
    }
    if (response.statusCode == 200) {
      return;
    }
    throw ProviderParseException(
      providerId: ProviderId.chaturbate,
      message: 'Chaturbate $context failed with status ${response.statusCode}.',
    );
  }

  bool _looksLikeCloudflareChallenge(http.Response response) {
    if (response.headers['cf-mitigated']?.toLowerCase() == 'challenge') {
      return true;
    }
    final body = response.body.toLowerCase();
    return body.contains('<title>just a moment...</title>') ||
        body.contains('window._cf_chl_opt') ||
        body.contains('/cdn-cgi/challenge-platform/');
  }

  String _buildCloudflareChallengeMessage(String context) {
    final hasClearance = cookie.contains('cf_clearance=');
    final guidance = hasClearance
        ? '当前配置的 Chaturbate Cookie 已过期或不再通过 Cloudflare 校验，请在账号管理中更新最新浏览器 Cookie。'
        : '当前请求被 Chaturbate / Cloudflare 拦截。请在账号管理中粘贴可正常打开该房间的浏览器完整 Cookie；如果浏览器 Cookie 中本来包含 cf_clearance，也请一并带上。';
    return 'Chaturbate $context was blocked by Cloudflare challenge. $guidance';
  }

  String _decodeTextBody(
    http.Response response, {
    required String context,
  }) {
    final bytes = response.bodyBytes;
    try {
      return utf8.decode(bytes);
    } on FormatException {
      final encoding = _resolveResponseEncoding(response);
      if (encoding != null) {
        try {
          return encoding.decode(bytes);
        } on FormatException {
          // Fall through to the package http body decoder below.
        }
      }
      return response.body;
    }
  }

  Encoding? _resolveResponseEncoding(http.Response response) {
    final contentType = response.headers['content-type'];
    if (contentType == null) {
      return null;
    }
    final match = RegExp(r'charset=([^;]+)', caseSensitive: false)
        .firstMatch(contentType);
    if (match == null) {
      return null;
    }
    return Encoding.getByName(match.group(1)?.trim());
  }

  Map<String, dynamic> _decodeJson(
    String body, {
    required String context,
  }) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.cast<String, dynamic>();
      }
    } catch (error, stackTrace) {
      throw ProviderParseException(
        providerId: ProviderId.chaturbate,
        message: 'Failed to decode Chaturbate $context.',
        cause: error,
        stackTrace: stackTrace,
      );
    }

    throw ProviderParseException(
      providerId: ProviderId.chaturbate,
      message: 'Chaturbate $context was not a JSON object.',
    );
  }

  List<Map<String, dynamic>> _decodeJsonList(
    String body, {
    required String context,
  }) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is List) {
        return decoded
            .map((item) => ProviderJson.asMap(item))
            .where((item) => item.isNotEmpty)
            .toList(growable: false);
      }
    } catch (error, stackTrace) {
      throw ProviderParseException(
        providerId: ProviderId.chaturbate,
        message: 'Failed to decode Chaturbate $context.',
        cause: error,
        stackTrace: stackTrace,
      );
    }

    throw ProviderParseException(
      providerId: ProviderId.chaturbate,
      message: 'Chaturbate $context was not a JSON list.',
    );
  }

  Future<http.Response> _get(
    Uri uri, {
    required Map<String, String> headers,
    required String context,
  }) {
    return runProviderRequestWithRetry(
      providerId: ProviderId.chaturbate,
      operation: 'chaturbate GET ${uri.toString()}',
      policy: _retryPolicy,
      diagnostics: _diagnostics,
      action: (_) async {
        late final http.Response response;
        try {
          response = await _client.get(uri, headers: headers);
        } catch (error, stackTrace) {
          throw ProviderRetryableException(
            ProviderParseException(
              providerId: ProviderId.chaturbate,
              message: 'Chaturbate $context failed before response.',
              cause: error,
              stackTrace: stackTrace,
            ),
            stackTrace,
          );
        }
        if (isRetryableHttpStatus(response.statusCode)) {
          throw ProviderRetryableException(
            ProviderParseException(
              providerId: ProviderId.chaturbate,
              message:
                  'Chaturbate $context failed with status ${response.statusCode}.',
            ),
          );
        }
        return response;
      },
    );
  }
}
