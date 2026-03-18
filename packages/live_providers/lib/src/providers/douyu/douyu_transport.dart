import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:http/http.dart' as http;

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
  HttpDouyuTransport({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  @override
  Future<String> getText(
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
        providerId: ProviderId.douyu,
        message:
            'Douyu request failed for $uri with status ${response.statusCode}.',
      );
    }
    return utf8.decode(response.bodyBytes);
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
    final response = await _client.post(
      uri,
      headers: headers,
      body: body,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ProviderParseException(
        providerId: ProviderId.douyu,
        message:
            'Douyu request failed for $uri with status ${response.statusCode}.',
      );
    }
    return utf8.decode(response.bodyBytes);
  }
}
