import 'dart:async';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import 'douyin_request_params.dart';
import 'douyin_utils.dart';

abstract class DouyinSignService {
  Future<Map<String, String>> buildHeaders({
    String? refererPath,
    bool forceRefreshCookie = false,
  });

  String buildSignedUrl(String baseUrl, Map<String, dynamic> queryParameters);
}

class HttpDouyinSignService implements DouyinSignService {
  HttpDouyinSignService({
    this.cookie = '',
    http.Client? client,
    Duration cookieRequestTimeout = const Duration(seconds: 2),
  }) : _client = client ?? http.Client(),
       _cookieRequestTimeout = cookieRequestTimeout;

  static String get defaultCookie {
    final seconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return 'ttwid=local-fallback-$seconds';
  }

  final String cookie;
  final http.Client _client;
  final Duration _cookieRequestTimeout;

  String _cookieCache = '';

  @override
  Future<Map<String, String>> buildHeaders({
    String? refererPath,
    bool forceRefreshCookie = false,
  }) async {
    final referer = refererPath == null
        ? 'https://live.douyin.com'
        : 'https://live.douyin.com/$refererPath';
    final resolvedCookie = await _resolveCookie(
      referer,
      forceRefreshCookie: forceRefreshCookie,
    );
    return {
      'referer': referer,
      'user-agent': DouyinRequestParams.kDefaultUserAgent,
      'cookie': resolvedCookie,
      'accept': '*/*',
      'accept-language': 'zh-CN,zh;q=0.9,en;q=0.8',
    };
  }

  @override
  String buildSignedUrl(String baseUrl, Map<String, dynamic> queryParameters) {
    return DouyinUtils.buildRequestUrl(baseUrl, queryParameters);
  }

  Future<String> _resolveCookie(
    String referer, {
    bool forceRefreshCookie = false,
  }) async {
    if (forceRefreshCookie) {
      _cookieCache = '';
    } else if (_cookieCache.contains('ttwid=')) {
      return _cookieCache;
    }
    if (!forceRefreshCookie && cookie.contains('ttwid=')) {
      _cookieCache = cookie;
      return _cookieCache;
    }

    try {
      final response = await _client
          .head(
            Uri.parse(referer),
            headers: {
              'user-agent': DouyinRequestParams.kDefaultUserAgent,
              'accept':
                  'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
              'accept-language': 'zh-CN,zh;q=0.9,en;q=0.8',
            },
          )
          .timeout(_cookieRequestTimeout);
      final setCookie = response.headers['set-cookie'] ?? '';
      final cookies = <String>[];
      for (final part in _splitSetCookieHeader(setCookie)) {
        final cookiePair = part.split(';').first.trim();
        if (cookiePair.startsWith('ttwid=') ||
            cookiePair.startsWith('__ac_nonce=') ||
            cookiePair.startsWith('msToken=')) {
          cookies.add(cookiePair);
        }
      }
      if (cookies.isNotEmpty) {
        _cookieCache = cookies.join(';');
        return _cookieCache;
      }
    } catch (error, stackTrace) {
      developer.log(
        'Failed to refresh Douyin cookies, falling back to generated cookie.',
        name: 'live_providers.douyin_sign_service',
        error: error,
        stackTrace: stackTrace,
      );
    }

    _cookieCache = defaultCookie;
    return _cookieCache;
  }

  List<String> _splitSetCookieHeader(String headerValue) {
    if (headerValue.trim().isEmpty) {
      return const <String>[];
    }

    final parts = <String>[];
    final buffer = StringBuffer();
    var inExpiresValue = false;
    for (var index = 0; index < headerValue.length; index += 1) {
      final current = headerValue[index];
      if (!inExpiresValue &&
          _startsWithIgnoreCase(headerValue, 'expires=', index)) {
        inExpiresValue = true;
      }
      if (current == ',' && !inExpiresValue) {
        final candidate = buffer.toString().trim();
        if (candidate.isNotEmpty) {
          parts.add(candidate);
        }
        buffer.clear();
        continue;
      }
      if (inExpiresValue && current == ';') {
        inExpiresValue = false;
      }
      buffer.write(current);
    }

    final candidate = buffer.toString().trim();
    if (candidate.isNotEmpty) {
      parts.add(candidate);
    }
    return parts;
  }

  bool _startsWithIgnoreCase(String value, String pattern, int index) {
    if (index + pattern.length > value.length) {
      return false;
    }
    return value.substring(index, index + pattern.length).toLowerCase() ==
        pattern;
  }

  void close() {
    _client.close();
  }
}
