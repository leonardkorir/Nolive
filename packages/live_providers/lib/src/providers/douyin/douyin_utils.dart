import 'dart:math';

import 'abogus.dart';
import 'douyin_request_params.dart';

class DouyinUtils {
  static String getMSToken({int randomLength = 184}) {
    const baseStr =
        'ABCDEFGHIGKLMNOPQRSTUVWXYZabcdefghigklmnopqrstuvwxyz0123456789=';
    final buffer = StringBuffer();
    for (var index = 0; index < randomLength; index += 1) {
      buffer.write(baseStr[Random().nextInt(baseStr.length)]);
    }
    return buffer.toString();
  }

  static String buildRequestUrl(String baseUrl, Map<String, dynamic> params) {
    final signer = ABogus(userAgent: DouyinRequestParams.kDefaultUserAgent);
    final resolvedParams = <String, dynamic>{...params};
    resolvedParams['aid'] = DouyinRequestParams.aidValue;
    resolvedParams['compress'] = 'gzip';
    resolvedParams['device_platform'] = 'web';
    resolvedParams['browser_language'] = 'zh-CN';
    resolvedParams['browser_platform'] =
        DouyinRequestParams.browserPlatformValue;
    resolvedParams['browser_name'] = DouyinRequestParams.browserNameValue;
    resolvedParams['browser_version'] = DouyinRequestParams.browserVersionValue;
    resolvedParams.putIfAbsent('msToken', () => getMSToken());

    final query = Uri(
        queryParameters: resolvedParams.map(
      (key, value) => MapEntry(key, value.toString()),
    )).query;
    final signedQuery = signer.generateAbogus(query, body: '').first;
    return Uri.parse(baseUrl).replace(query: signedQuery).toString();
  }
}
