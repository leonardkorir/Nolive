import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:live_core/live_core.dart';

import 'bilibili_sign_service.dart';

class BilibiliAccountProfile {
  const BilibiliAccountProfile({
    required this.userId,
    required this.displayName,
    required this.avatarUrl,
  });

  final int userId;
  final String displayName;
  final String avatarUrl;
}

class BilibiliQrLoginSession {
  const BilibiliQrLoginSession({
    required this.qrcodeKey,
    required this.qrcodeUrl,
  });

  final String qrcodeKey;
  final String qrcodeUrl;
}

enum BilibiliQrLoginStatus { pending, scanned, expired, success }

class BilibiliQrLoginPollResult {
  const BilibiliQrLoginPollResult({
    required this.status,
    this.cookie = '',
  });

  final BilibiliQrLoginStatus status;
  final String cookie;
}

abstract class BilibiliAccountClient {
  Future<BilibiliAccountProfile> loadProfile({required String cookie});

  Future<BilibiliQrLoginSession> createQrLoginSession();

  Future<BilibiliQrLoginPollResult> pollQrLogin({required String qrcodeKey});
}

class HttpBilibiliAccountClient implements BilibiliAccountClient {
  HttpBilibiliAccountClient({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  @override
  Future<BilibiliQrLoginSession> createQrLoginSession() async {
    final response = await _getJson(
      'https://passport.bilibili.com/x/passport-login/web/qrcode/generate',
    );
    if (response['code'] != 0) {
      throw ProviderException(
        code: 'provider.account_qr_generate_failed',
        message: response['message']?.toString() ?? '无法获取哔哩哔哩登录二维码。',
        providerId: ProviderId.bilibili,
      );
    }
    final data = _mapFromDynamic(response['data']);
    return BilibiliQrLoginSession(
      qrcodeKey: data['qrcode_key']?.toString() ?? '',
      qrcodeUrl: data['url']?.toString() ?? '',
    );
  }

  @override
  Future<BilibiliAccountProfile> loadProfile({required String cookie}) async {
    final response = await _getJson(
      'https://api.bilibili.com/x/member/web/account',
      headers: {'cookie': cookie},
    );
    if (response['code'] != 0) {
      throw ProviderException(
        code: 'provider.account_invalid',
        message: response['message']?.toString() ?? '哔哩哔哩账号凭据已失效。',
        providerId: ProviderId.bilibili,
      );
    }
    final data = _mapFromDynamic(response['data']);
    return BilibiliAccountProfile(
      userId: int.tryParse(data['mid']?.toString() ?? '') ?? 0,
      displayName: data['uname']?.toString() ?? '未登录',
      avatarUrl: data['face']?.toString() ?? '',
    );
  }

  @override
  Future<BilibiliQrLoginPollResult> pollQrLogin({
    required String qrcodeKey,
  }) async {
    final response = await _client.get(
      Uri.parse(
        'https://passport.bilibili.com/x/passport-login/web/qrcode/poll',
      ).replace(queryParameters: {'qrcode_key': qrcodeKey}),
      headers: _defaultHeaders(),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ProviderException(
        code: 'provider.account_qr_poll_failed',
        message: '哔哩哔哩二维码登录轮询失败：HTTP ${response.statusCode}',
        providerId: ProviderId.bilibili,
      );
    }

    final decoded = json.decode(response.body);
    if (decoded is! Map) {
      throw ProviderParseException(
        providerId: ProviderId.bilibili,
        message: '无法解析哔哩哔哩二维码轮询结果。',
        cause: decoded,
      );
    }

    final payload = decoded.cast<String, dynamic>();
    if (payload['code'] != 0) {
      throw ProviderException(
        code: 'provider.account_qr_poll_failed',
        message: payload['message']?.toString() ?? '哔哩哔哩二维码登录轮询失败。',
        providerId: ProviderId.bilibili,
      );
    }

    final data = _mapFromDynamic(payload['data']);
    final code = int.tryParse(data['code']?.toString() ?? '') ?? -1;
    if (code == 0) {
      final cookie = _extractCookieHeader(response.headers['set-cookie'] ?? '');
      if (cookie.isEmpty) {
        throw ProviderException(
          code: 'provider.account_cookie_missing',
          message: '哔哩哔哩登录成功，但未拿到可用 Cookie。',
          providerId: ProviderId.bilibili,
        );
      }
      return BilibiliQrLoginPollResult(
        status: BilibiliQrLoginStatus.success,
        cookie: cookie,
      );
    }
    if (code == 86090) {
      return const BilibiliQrLoginPollResult(
        status: BilibiliQrLoginStatus.scanned,
      );
    }
    if (code == 86038) {
      return const BilibiliQrLoginPollResult(
        status: BilibiliQrLoginStatus.expired,
      );
    }
    return const BilibiliQrLoginPollResult(
      status: BilibiliQrLoginStatus.pending,
    );
  }

  Map<String, String> _defaultHeaders({Map<String, String>? headers}) {
    return {
      'user-agent': BilibiliSignService.defaultUserAgent,
      'referer': BilibiliSignService.defaultReferer,
      if (headers != null) ...headers,
    };
  }

  Future<Map<String, dynamic>> _getJson(
    String url, {
    Map<String, String>? headers,
  }) async {
    final response = await _client.get(
      Uri.parse(url),
      headers: _defaultHeaders(headers: headers),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ProviderException(
        code: 'provider.account_request_failed',
        message: '哔哩哔哩账号请求失败：HTTP ${response.statusCode}',
        providerId: ProviderId.bilibili,
      );
    }
    final decoded = json.decode(response.body);
    if (decoded is! Map) {
      throw ProviderParseException(
        providerId: ProviderId.bilibili,
        message: '无法解析哔哩哔哩账号响应。',
        cause: decoded,
      );
    }
    return decoded.cast<String, dynamic>();
  }

  Map<String, dynamic> _mapFromDynamic(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.cast<String, dynamic>();
    }
    return const <String, dynamic>{};
  }

  String _extractCookieHeader(String setCookie) {
    final matches = RegExp(
      r'(?:^|,\s*)([A-Za-z0-9_\-]+=[^;,\r\n]+)',
    ).allMatches(setCookie);
    final cookies = <String>[];
    for (final match in matches) {
      final pair = match.group(1);
      if (pair == null) {
        continue;
      }
      if (pair.startsWith('SESSDATA=') ||
          pair.startsWith('bili_jct=') ||
          pair.startsWith('DedeUserID=') ||
          pair.startsWith('DedeUserID__ckMd5=') ||
          pair.startsWith('sid=')) {
        cookies.add(pair);
      }
    }
    return cookies.join('; ');
  }
}
