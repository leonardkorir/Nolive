import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:http/http.dart' as http;

class DouyinHttpResponse {
  const DouyinHttpResponse({required this.body, required this.headers});

  final String body;
  final Map<String, String> headers;
}

abstract class DouyinTransport {
  Future<DouyinHttpResponse> getResponse(
    String url, {
    Map<String, String> queryParameters = const {},
    Map<String, String> headers = const {},
  });

  Future<String> getText(
    String url, {
    Map<String, String> queryParameters = const {},
    Map<String, String> headers = const {},
  }) async {
    final response = await getResponse(
      url,
      queryParameters: queryParameters,
      headers: headers,
    );
    return response.body;
  }

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
      providerId: ProviderId.douyin,
      message:
          'Unexpected Douyin response payload type for $url: ${decoded.runtimeType}.',
    );
  }
}

class HttpDouyinTransport extends DouyinTransport {
  HttpDouyinTransport({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  @override
  Future<DouyinHttpResponse> getResponse(
    String url, {
    Map<String, String> queryParameters = const {},
    Map<String, String> headers = const {},
  }) async {
    final uri = Uri.parse(url).replace(
      queryParameters: queryParameters.isEmpty ? null : queryParameters,
    );
    final response = await _client.get(uri, headers: headers);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ProviderParseException(
        providerId: ProviderId.douyin,
        message:
            'Douyin request failed for $uri with status ${response.statusCode}.',
      );
    }
    return DouyinHttpResponse(
      body: utf8.decode(response.bodyBytes),
      headers: response.headers,
    );
  }
}
