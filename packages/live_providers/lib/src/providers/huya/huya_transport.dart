import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:http/http.dart' as http;

import '../provider_runtime_support.dart';

abstract class HuyaTransport {
  Future<String> getText(
    String url, {
    Map<String, String> queryParameters = const {},
    Map<String, String> headers = const {},
  });

  Future<Map<String, dynamic>> getJson(
    String url, {
    Map<String, String> queryParameters = const {},
    Map<String, String> headers = const {},
  }) async {
    final text = await getText(
      url,
      queryParameters: queryParameters,
      headers: headers,
    );
    Object? decoded = jsonDecode(text);
    if (decoded is String) {
      decoded = jsonDecode(decoded);
    }
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.cast<String, dynamic>();
    }
    throw ProviderParseException(
      providerId: ProviderId.huya,
      message:
          'Unexpected Huya response payload type for $url: ${decoded.runtimeType}.',
    );
  }
}

class HttpHuyaTransport extends HuyaTransport {
  HttpHuyaTransport({
    http.Client? client,
    ProviderRetryPolicy retryPolicy = const ProviderRetryPolicy(),
    void Function(String message)? diagnostics,
  })  : _client = client ?? http.Client(),
        _retryPolicy = retryPolicy,
        _diagnostics = diagnostics;

  final http.Client _client;
  final ProviderRetryPolicy _retryPolicy;
  final void Function(String message)? _diagnostics;

  void close() {
    _client.close();
  }

  @override
  Future<String> getText(
    String url, {
    Map<String, String> queryParameters = const {},
    Map<String, String> headers = const {},
  }) async {
    final uri = Uri.parse(url).replace(
      queryParameters: queryParameters.isEmpty ? null : queryParameters,
    );
    return runProviderRequestWithRetry(
      providerId: ProviderId.huya,
      operation: 'huya transport GET $uri',
      policy: _retryPolicy,
      diagnostics: _diagnostics,
      action: (_) async {
        late final http.Response response;
        try {
          response = await _client.get(uri, headers: headers);
        } catch (error, stackTrace) {
          throw ProviderRetryableException(
            ProviderParseException(
              providerId: ProviderId.huya,
              message: 'Huya request failed before response: $uri',
              cause: error,
              stackTrace: stackTrace,
            ),
            stackTrace,
          );
        }
        if (response.statusCode < 200 || response.statusCode >= 300) {
          final failure = ProviderParseException(
            providerId: ProviderId.huya,
            message:
                'Huya request failed for $uri with status ${response.statusCode}.',
          );
          if (isRetryableHttpStatus(response.statusCode)) {
            throw ProviderRetryableException(failure);
          }
          throw failure;
        }
        return utf8.decode(response.bodyBytes);
      },
    );
  }
}
