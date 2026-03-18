import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:live_core/live_core.dart';

import 'douyin_request_params.dart';

class DouyinAccountProfile {
  const DouyinAccountProfile({
    required this.displayName,
    required this.secUid,
    required this.avatarUrl,
  });

  final String displayName;
  final String secUid;
  final String avatarUrl;
}

abstract class DouyinAccountClient {
  Future<DouyinAccountProfile> loadProfile({required String cookie});
}

class HttpDouyinAccountClient implements DouyinAccountClient {
  HttpDouyinAccountClient({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  @override
  Future<DouyinAccountProfile> loadProfile({required String cookie}) async {
    final response = await _client.get(
      Uri.parse('https://live.douyin.com/webcast/user/me/').replace(
        queryParameters: {'aid': DouyinRequestParams.aidValue},
      ),
      headers: {
        'user-agent': DouyinRequestParams.kDefaultUserAgent,
        'referer': 'https://live.douyin.com/',
        'cookie': cookie,
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ProviderException(
        code: 'provider.account_request_failed',
        message: '抖音账号请求失败：HTTP ${response.statusCode}',
        providerId: ProviderId.douyin,
      );
    }

    final decoded = json.decode(response.body);
    if (decoded is! Map) {
      throw ProviderParseException(
        providerId: ProviderId.douyin,
        message: '无法解析抖音账号响应。',
        cause: decoded,
      );
    }

    final payload = decoded.cast<String, dynamic>();
    if (payload['status_code'] != 0) {
      throw ProviderException(
        code: 'provider.account_invalid',
        message: payload['status_msg']?.toString() ?? '抖音账号凭据已失效。',
        providerId: ProviderId.douyin,
      );
    }
    final data = payload['data'];
    final map = data is Map<String, dynamic>
        ? data
        : data is Map
            ? data.cast<String, dynamic>()
            : const <String, dynamic>{};
    return DouyinAccountProfile(
      displayName: map['nickname']?.toString() ?? '未登录',
      secUid: map['sec_uid']?.toString() ?? '',
      avatarUrl: map['avatar_thumb']?['url_list'] is List
          ? (map['avatar_thumb']['url_list'] as List)
                  .whereType<String>()
                  .firstOrNull ??
              ''
          : '',
    );
  }
}
