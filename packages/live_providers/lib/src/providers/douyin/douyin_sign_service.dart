import 'package:http/http.dart' as http;

import 'douyin_request_params.dart';
import 'douyin_utils.dart';

abstract class DouyinSignService {
  Future<Map<String, String>> buildHeaders(
      {String? refererPath, bool forceRefreshCookie = false});

  String buildSignedUrl(String baseUrl, Map<String, dynamic> queryParameters);
}

class HttpDouyinSignService implements DouyinSignService {
  HttpDouyinSignService({this.cookie = '', http.Client? client})
      : _client = client ?? http.Client();

  static const String defaultCookie =
      'ttwid=1%7CB1qls3GdnZhUov9o2NxOMxxYS2ff6OSvEWbv0ytbES4%7C1680522049%7C280d802d6d478e3e78d0c807f7c487e7ffec0ae4e5fdd6a0fe74c3c6af149511';

  final String cookie;
  final http.Client _client;

  String _cookieCache = '';

  @override
  Future<Map<String, String>> buildHeaders(
      {String? refererPath, bool forceRefreshCookie = false}) async {
    final referer = refererPath == null
        ? 'https://live.douyin.com'
        : 'https://live.douyin.com/$refererPath';
    final resolvedCookie =
        await _resolveCookie(referer, forceRefreshCookie: forceRefreshCookie);
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

  Future<String> _resolveCookie(String referer,
      {bool forceRefreshCookie = false}) async {
    if (forceRefreshCookie) {
      _cookieCache = '';
    }
    if (_cookieCache.contains('ttwid=')) {
      return _cookieCache;
    }
    if (cookie.contains('ttwid=')) {
      _cookieCache = cookie;
      return _cookieCache;
    }

    try {
      final response = await _client.head(
        Uri.parse(referer),
        headers: {
          'user-agent': DouyinRequestParams.kDefaultUserAgent,
          'accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
          'accept-language': 'zh-CN,zh;q=0.9,en;q=0.8',
        },
      );
      final setCookie = response.headers['set-cookie'] ?? '';
      final cookies = <String>[];
      for (final part in setCookie.split(',')) {
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
    } catch (_) {}

    _cookieCache = defaultCookie;
    return _cookieCache;
  }
}
