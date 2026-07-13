import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:live_core/live_core.dart';

import '../provider_runtime_support.dart';

abstract interface class TwitchApiClient {
  static const String defaultClientId = 'kimne78kx3ncx6brgo4mv6wki5h1ko';
  static const String browserUserAgent = kChromiumDesktopUserAgent;

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
    String clientId = TwitchApiClient.defaultClientId,
    ProviderBrowserProfile browserProfile =
        ProviderBrowserProfile.chromiumDesktop,
    ProviderRetryPolicy retryPolicy = const ProviderRetryPolicy(),
    void Function(String message)? diagnostics,
  }) : _client = client ?? http.Client(),
       _cookie = cookie.trim(),
       _browserProfile = browserProfile,
       _retryPolicy = retryPolicy,
       _diagnostics = diagnostics,
       _clientId = clientId.trim().isEmpty
           ? TwitchApiClient.defaultClientId
           : clientId.trim();

  final http.Client _client;
  final String _cookie;
  final ProviderBrowserProfile _browserProfile;
  final ProviderRetryPolicy _retryPolicy;
  final void Function(String message)? _diagnostics;
  final String _clientId;

  void close() {
    _client.close();
  }

  @override
  Future<Object?> postGraphQl(
    Object payload, {
    String deviceId = '',
    String clientSessionId = '',
    String clientIntegrity = '',
  }) async {
    final headers = <String, String>{
      'accept': '*/*',
      'accept-language': _browserProfile.acceptLanguage,
      'client-id': _clientId,
      'content-type': 'text/plain; charset=UTF-8',
      'origin': 'https://www.twitch.tv',
      'referer': 'https://www.twitch.tv/',
      'sec-fetch-dest': 'empty',
      'sec-fetch-mode': 'cors',
      'sec-fetch-site': 'same-site',
      'user-agent': _browserProfile.userAgent,
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

    final response = await runProviderRequestWithRetry(
      providerId: ProviderId.twitch,
      operation: 'twitch GraphQL request',
      policy: _retryPolicy,
      diagnostics: _diagnostics,
      action: (_) async {
        late final http.Response response;
        try {
          response = await _client.post(
            Uri.https('gql.twitch.tv', '/gql'),
            headers: headers,
            body: jsonEncode(payload),
          );
        } catch (error, stackTrace) {
          throw ProviderRetryableException(
            ProviderParseException(
              providerId: ProviderId.twitch,
              message: 'Twitch GraphQL request failed before response.',
              cause: error,
              stackTrace: stackTrace,
            ),
            stackTrace,
          );
        }
        if (isRetryableHttpStatus(response.statusCode)) {
          throw ProviderRetryableException(
            ProviderParseException(
              providerId: ProviderId.twitch,
              message:
                  'Twitch GraphQL request failed with status ${response.statusCode}.',
            ),
          );
        }
        return response;
      },
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
    final response = await runProviderRequestWithRetry(
      providerId: ProviderId.twitch,
      operation: 'twitch document request',
      policy: _retryPolicy,
      diagnostics: _diagnostics,
      action: (_) async {
        late final http.Response response;
        try {
          response = await _client.get(
            Uri.parse(url),
            headers: {
              'user-agent': _browserProfile.userAgent,
              'accept-language': _browserProfile.acceptLanguage,
              if (_cookie.isNotEmpty) 'cookie': _cookie,
              ...headers,
            },
          );
        } catch (error, stackTrace) {
          throw ProviderRetryableException(
            ProviderParseException(
              providerId: ProviderId.twitch,
              message: 'Twitch document request failed before response: $url',
              cause: error,
              stackTrace: stackTrace,
            ),
            stackTrace,
          );
        }
        if (isRetryableHttpStatus(response.statusCode)) {
          throw ProviderRetryableException(
            ProviderParseException(
              providerId: ProviderId.twitch,
              message:
                  'Twitch document request failed with status ${response.statusCode}: $url',
            ),
          );
        }
        return response;
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
