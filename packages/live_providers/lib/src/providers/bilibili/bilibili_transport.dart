import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:http/http.dart' as http;

import '../provider_runtime_support.dart';

abstract class BilibiliTransport {
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
    final decoded = jsonDecode(text);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.cast<String, dynamic>();
    }
    throw ProviderParseException(
      providerId: ProviderId.bilibili,
      message:
          'Unexpected Bilibili response payload type: ${decoded.runtimeType}.',
    );
  }
}

int bilibiliResponseCode(Map<String, dynamic> response) {
  final value = response['code'];
  if (value is int) {
    return value;
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

String bilibiliResponseMessage(Map<String, dynamic> response) {
  final message = response['message']?.toString().trim() ??
      response['msg']?.toString().trim() ??
      '';
  return message;
}

Map<String, dynamic> ensureBilibiliSuccess(
  Map<String, dynamic> response, {
  required String operation,
  Set<int> acceptedCodes = const {0},
}) {
  final code = bilibiliResponseCode(response);
  if (acceptedCodes.contains(code)) {
    return response;
  }
  final message = bilibiliResponseMessage(response);
  throw ProviderParseException(
    providerId: ProviderId.bilibili,
    message: message.isEmpty
        ? 'Bilibili $operation failed with code $code.'
        : 'Bilibili $operation failed with code $code: $message',
  );
}

class HttpBilibiliTransport implements BilibiliTransport {
  HttpBilibiliTransport({
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
    final decoded = jsonDecode(text);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.cast<String, dynamic>();
    }
    throw ProviderParseException(
      providerId: ProviderId.bilibili,
      message:
          'Unexpected Bilibili response payload type: ${decoded.runtimeType}.',
    );
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
      providerId: ProviderId.bilibili,
      operation: 'bilibili transport GET $uri',
      policy: _retryPolicy,
      diagnostics: _diagnostics,
      action: (_) async {
        late final http.Response response;
        try {
          response = await _client.get(uri, headers: headers);
        } catch (error, stackTrace) {
          throw ProviderRetryableException(
            ProviderParseException(
              providerId: ProviderId.bilibili,
              message: 'Bilibili request failed before response: $uri',
              cause: error,
              stackTrace: stackTrace,
            ),
            stackTrace,
          );
        }
        if (response.statusCode < 200 || response.statusCode >= 300) {
          final failure = ProviderParseException(
            providerId: ProviderId.bilibili,
            message:
                'Bilibili request failed for $uri with status ${response.statusCode}.',
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
