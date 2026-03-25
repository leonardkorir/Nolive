import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:live_core/live_core.dart';

abstract interface class TwitchApiClient {
  static const String clientId = 'kimne78kx3ncx6brgo4mv6wki5h1ko';
  static const String browserUserAgent =
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36';

  Future<Object?> postGraphQl(
    Object payload, {
    String deviceId = '',
    String clientSessionId = '',
    String clientIntegrity = '',
  });

  Future<String> fetchText(
    String url, {
    Map<String, String> headers = const {},
  });
}

class HttpTwitchApiClient implements TwitchApiClient {
  HttpTwitchApiClient({
    http.Client? client,
    String cookie = '',
  })  : _client = client ?? http.Client(),
        _cookie = cookie.trim();

  final http.Client _client;
  final String _cookie;

  @override
  Future<Object?> postGraphQl(
    Object payload, {
    String deviceId = '',
    String clientSessionId = '',
    String clientIntegrity = '',
  }) async {
    final headers = <String, String>{
      'accept': '*/*',
      'accept-language': 'en-US,en;q=0.9',
      'client-id': TwitchApiClient.clientId,
      'content-type': 'text/plain; charset=UTF-8',
      'origin': 'https://www.twitch.tv',
      'referer': 'https://www.twitch.tv/',
      'sec-fetch-dest': 'empty',
      'sec-fetch-mode': 'cors',
      'sec-fetch-site': 'same-site',
      'user-agent': TwitchApiClient.browserUserAgent,
    };
    if (deviceId.trim().isNotEmpty) {
      headers['device-id'] = deviceId.trim();
      headers['x-device-id'] = deviceId.trim();
    }
    if (clientSessionId.trim().isNotEmpty) {
      headers['client-session-id'] = clientSessionId.trim();
    }
    if (clientIntegrity.trim().isNotEmpty) {
      headers['client-integrity'] = clientIntegrity.trim();
    }
    if (_cookie.isNotEmpty) {
      headers['cookie'] = _cookie;
    }

    final response = await _client.post(
      Uri.https('gql.twitch.tv', '/gql'),
      headers: headers,
      body: jsonEncode(payload),
    );
    _ensureSuccess(response, context: 'GraphQL request');
    return _decodeJson(
      utf8.decode(response.bodyBytes),
      context: 'GraphQL response',
    );
  }

  @override
  Future<String> fetchText(
    String url, {
    Map<String, String> headers = const {},
  }) async {
    final response = await _client.get(
      Uri.parse(url),
      headers: {
        'user-agent': TwitchApiClient.browserUserAgent,
        if (_cookie.isNotEmpty) 'cookie': _cookie,
        ...headers,
      },
    );
    _ensureSuccess(response, context: 'document request for $url');
    return utf8.decode(response.bodyBytes);
  }

  Object? _decodeJson(String text, {required String context}) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final decoded = jsonDecode(trimmed);
    if (decoded is Map<String, dynamic> || decoded is List) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.cast<String, dynamic>();
    }
    throw ProviderParseException(
      providerId: ProviderId.twitch,
      message:
          'Unexpected Twitch $context payload type: ${decoded.runtimeType}.',
    );
  }

  void _ensureSuccess(http.Response response, {required String context}) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }
    throw ProviderParseException(
      providerId: ProviderId.twitch,
      message: 'Twitch $context failed with status ${response.statusCode}.',
    );
  }
}
