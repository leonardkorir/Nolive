import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:http/http.dart' as http;

import '../provider_runtime_support.dart';

abstract class DouyuTransport {
  Future<String> getText(
    String url, {
    Map<String, String> queryParameters = const {},
    Map<String, String> headers = const {},
  });

  Future<String> postText(
    String url, {
    String body = '',
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
    return _decodeJsonMap(text, requestUrl: url);
  }

  Future<Map<String, dynamic>> postJson(
    String url, {
    String body = '',
    Map<String, String> queryParameters = const {},
    Map<String, String> headers = const {},
  }) async {
    final text = await postText(
      url,
      body: body,
      queryParameters: queryParameters,
      headers: headers,
    );
    return _decodeJsonMap(text, requestUrl: url);
  }

  Map<String, dynamic> _decodeJsonMap(
    String text, {
    required String requestUrl,
  }) {
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
      providerId: ProviderId.douyu,
      message:
          'Unexpected Douyu response payload type for $requestUrl: ${decoded.runtimeType}.',
    );
  }
}

class HttpDouyuTransport extends DouyuTransport {
  HttpDouyuTransport({
    http.Client? client,
    ProviderRetryPolicy retryPolicy = const ProviderRetryPolicy(),
  }) : _client = client ?? http.Client(),
       _retryPolicy = retryPolicy;

  final http.Client _client;
  final ProviderRetryPolicy _retryPolicy;

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
    return _sendText(uri, () => _client.get(uri, headers: headers));
  }

  @override
  Future<String> postText(
    String url, {
    String body = '',
    Map<String, String> queryParameters = const {},
    Map<String, String> headers = const {},
  }) async {
    final uri = Uri.parse(url).replace(
      queryParameters: queryParameters.isEmpty ? null : queryParameters,
    );
    return _sendText(
      uri,
      () => _client.post(uri, headers: headers, body: body),
    );
  }

  Future<String> _sendText(Uri uri, Future<http.Response> Function() request) {
    return runProviderRequestWithRetry(
      providerId: ProviderId.douyu,
      operation: 'douyu transport $uri',
      policy: _retryPolicy,
      action: (_) async {
        final response = await _sendResponse(uri, request);
        return _decodeText(response.bodyBytes, uri);
      },
    );
  }

  Future<http.Response> _sendResponse(
    Uri uri,
    Future<http.Response> Function() request,
  ) async {
    late final http.Response response;
    try {
      response = await request();
    } catch (error, stackTrace) {
      throw ProviderRetryableException(
        ProviderParseException(
          providerId: ProviderId.douyu,
          message: 'Douyu request failed before response: $uri',
          cause: error,
          stackTrace: stackTrace,
        ),
        stackTrace,
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final failure = ProviderParseException(
        providerId: ProviderId.douyu,
        message:
            'Douyu request failed for $uri with status ${response.statusCode}.',
      );
      if (isRetryableHttpStatus(response.statusCode)) {
        throw ProviderRetryableException(failure);
      }
      throw failure;
    }
    return response;
  }

  String _decodeText(List<int> bodyBytes, Uri uri) {
    try {
      return utf8.decode(bodyBytes);
    } on FormatException catch (error, stackTrace) {
      throw ProviderParseException(
        providerId: ProviderId.douyu,
        message: 'Douyu response was not valid UTF-8: $uri',
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }
}
