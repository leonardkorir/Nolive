import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:live_core/live_core.dart';

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

  Future<String> fetchHlsPlaylist(
    String url, {
    String? referer,
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
}

class HttpChaturbateApiClient implements ChaturbateApiClient {
  HttpChaturbateApiClient({
    this.cookie = '',
    http.Client? client,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String cookie;

  static const String browserUserAgent =
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36';
  static const String browserAcceptLanguage = 'zh-CN,zh;q=0.9';
  static const String browserSecChUa =
      '"Chromium";v="146", "Not-A.Brand";v="24", "Google Chrome";v="146"';
  static const String browserSecChUaMobile = '?0';
  static const String browserSecChUaPlatform = '"Linux"';

  static const Map<String, String> _baseHeaders = {
    'user-agent': browserUserAgent,
    'accept-language': browserAcceptLanguage,
    'sec-ch-ua': browserSecChUa,
    'sec-ch-ua-mobile': browserSecChUaMobile,
    'sec-ch-ua-platform': browserSecChUaPlatform,
  };

  @override
  Future<Map<String, dynamic>> fetchDiscoverCarousel(
    String carouselId, {
    String genders = '',
  }) async {
    final response = await _client.get(
      Uri.https(
        'chaturbate.com',
        '/api/ts/discover/carousels/$carouselId/',
        {'genders': genders},
      ),
      headers: _buildApiHeaders(
        referer: _buildDiscoverReferer(genders),
      ),
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

    final response = await _client.get(
      Uri.https(
        'chaturbate.com',
        '/api/ts/roomlist/room-list/',
        queryParameters,
      ),
      headers: _buildApiHeaders(
        referer: _buildSearchReferer(query: query, genders: normalizedGenders),
      ),
    );
    _ensureSuccessfulResponse(response, context: 'room list request');

    return _decodeJson(response.body, context: 'room list response');
  }

  @override
  Future<String> fetchRoomPage(String roomId) async {
    final response = await _client.get(
      Uri.https('chaturbate.com', '/$roomId/'),
      headers: _buildDocumentHeaders(
        referer: 'https://chaturbate.com/',
      ),
    );
    _ensureSuccessfulResponse(
      response,
      context: 'room page request for $roomId',
    );

    return response.body;
  }

  @override
  Future<String> fetchHlsPlaylist(
    String url, {
    String? referer,
  }) async {
    final response = await _client.get(
      Uri.parse(url),
      headers: _buildMediaHeaders(
        referer: referer ?? 'https://chaturbate.com/',
      ),
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
    final response = await _sendMultipart(
      path: '/push_service/room_history/',
      referer: _buildRoomReferer(roomId),
      fields: {
        'topics': jsonEncode(topics),
        'csrfmiddlewaretoken': csrfToken,
      },
    );
    return _decodeJsonList(response, context: 'room_history response');
  }

  Future<String> _sendMultipart({
    required String path,
    required String referer,
    required Map<String, String> fields,
  }) async {
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

    final streamed = await _client.send(request);
    final response = await http.Response.fromStream(streamed);
    _ensureSuccessfulResponse(response, context: '$path request');
    return response.body;
  }

  Map<String, String> _buildDocumentHeaders({
    required String referer,
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
    });
  }

  Map<String, String> _buildApiHeaders({
    required String referer,
    Map<String, String> extraHeaders = const {},
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
    });
  }

  Map<String, String> _buildMediaHeaders({
    required String referer,
  }) {
    return _buildHeaders(
      {
        'accept': '*/*',
        'priority': 'u=4, i',
        'referer': referer,
        'sec-fetch-dest': 'empty',
        'sec-fetch-mode': 'cors',
        'sec-fetch-site': 'cross-site',
      },
      includeCookie: false,
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
  }) {
    final headers = <String, String>{
      ..._baseHeaders,
      ...extraHeaders,
    };
    final normalizedCookie = cookie.trim();
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
            .map((item) => _asMap(item))
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

  Map<String, dynamic> _asMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.cast<String, dynamic>();
    }
    return const {};
  }
}
