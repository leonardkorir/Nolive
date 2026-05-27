import 'dart:async';
import 'dart:developer' as developer;

import 'package:live_core/live_core.dart';

const String kChromiumDesktopUserAgent =
    'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36';
const String kChromiumDesktopAcceptLanguage = 'zh-CN,zh;q=0.9';
const String kChromiumDesktopBrowserName = 'Chrome';
const String kChromiumDesktopBrowserVersion = '146.0.0.0';
const String kChromiumDesktopOsName = 'Linux';
const String kChromiumDesktopOsVersion = '';
const String kChromiumDesktopSecChUa =
    '"Chromium";v="146", "Not-A.Brand";v="24", "Google Chrome";v="146"';
const String kChromiumDesktopSecChUaMobile = '?0';
const String kChromiumDesktopSecChUaPlatform = '"Linux"';

const String kChromiumMobileUserAgent =
    'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/137.0.0.0 Mobile Safari/537.36';
const String kChromiumMobileAcceptLanguage = 'zh-CN,zh;q=0.9';
const String kChromiumMobileBrowserName = 'Chrome';
const String kChromiumMobileBrowserVersion = '137.0.0.0';
const String kChromiumMobileOsName = 'Android';
const String kChromiumMobileOsVersion = '10';
const String kChromiumMobileSecChUa =
    '"Chromium";v="137", "Not/A)Brand";v="24"';
const String kChromiumMobileSecChUaMobile = '?1';
const String kChromiumMobileSecChUaPlatform = '"Android"';
const String kBilibiliLegacyDesktopUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36 Edg/126.0.0.0';

class ProviderBrowserProfile {
  const ProviderBrowserProfile({
    required this.userAgent,
    required this.acceptLanguage,
    required this.browserName,
    required this.browserVersion,
    required this.osName,
    required this.osVersion,
    this.secChUa,
    this.secChUaMobile,
    this.secChUaPlatform,
  });

  static const ProviderBrowserProfile chromiumDesktop = ProviderBrowserProfile(
    userAgent: kChromiumDesktopUserAgent,
    acceptLanguage: kChromiumDesktopAcceptLanguage,
    browserName: kChromiumDesktopBrowserName,
    browserVersion: kChromiumDesktopBrowserVersion,
    osName: kChromiumDesktopOsName,
    osVersion: kChromiumDesktopOsVersion,
    secChUa: kChromiumDesktopSecChUa,
    secChUaMobile: kChromiumDesktopSecChUaMobile,
    secChUaPlatform: kChromiumDesktopSecChUaPlatform,
  );

  
  static const ProviderBrowserProfile chromiumMobile = ProviderBrowserProfile(
    userAgent: kChromiumMobileUserAgent,
    acceptLanguage: kChromiumMobileAcceptLanguage,
    browserName: kChromiumMobileBrowserName,
    browserVersion: kChromiumMobileBrowserVersion,
    osName: kChromiumMobileOsName,
    osVersion: kChromiumMobileOsVersion,
    secChUa: kChromiumMobileSecChUa,
    secChUaMobile: kChromiumMobileSecChUaMobile,
    secChUaPlatform: kChromiumMobileSecChUaPlatform,
  );

  static const ProviderBrowserProfile bilibiliLegacyDesktop =
      ProviderBrowserProfile(
    userAgent: kBilibiliLegacyDesktopUserAgent,
    acceptLanguage: '',
    browserName: 'Edge',
    browserVersion: '126.0.0.0',
    osName: 'Windows',
    osVersion: '10.0',
  );

  final String userAgent;
  final String acceptLanguage;
  final String browserName;
  final String browserVersion;
  final String osName;
  final String osVersion;
  final String? secChUa;
  final String? secChUaMobile;
  final String? secChUaPlatform;

  Map<String, String> buildClientHintHeaders() {
    return {
      if ((secChUa?.isNotEmpty ?? false)) 'sec-ch-ua': secChUa!,
      if ((secChUaMobile?.isNotEmpty ?? false))
        'sec-ch-ua-mobile': secChUaMobile!,
      if ((secChUaPlatform?.isNotEmpty ?? false))
        'sec-ch-ua-platform': secChUaPlatform!,
    };
  }
}

class ProviderRetryPolicy {
  const ProviderRetryPolicy({
    this.maxAttempts = 2,
    this.baseBackoff = const Duration(milliseconds: 120),
  });

  final int maxAttempts;
  final Duration baseBackoff;

  Duration delayForRetry(int completedAttempts) {
    final multiplier = completedAttempts < 1 ? 1 : completedAttempts;
    return Duration(milliseconds: baseBackoff.inMilliseconds * multiplier);
  }
}

class ProviderRetryableException implements Exception {
  const ProviderRetryableException(this.error, [this.stackTrace]);

  final Object error;
  final StackTrace? stackTrace;
}

Future<T> runProviderRequestWithRetry<T>({
  required ProviderId providerId,
  required String operation,
  required Future<T> Function(int attempt) action,
  ProviderRetryPolicy policy = const ProviderRetryPolicy(),
  void Function(String message)? diagnostics,
}) async {
  Object? lastError;
  StackTrace? lastStackTrace;
  final attempts = policy.maxAttempts < 1 ? 1 : policy.maxAttempts;

  for (var attempt = 1; attempt <= attempts; attempt += 1) {
    try {
      return await action(attempt);
    } catch (error, stackTrace) {
      if (error is! ProviderRetryableException || attempt >= attempts) {
        if (error is ProviderRetryableException) {
          Error.throwWithStackTrace(
            error.error,
            error.stackTrace ?? stackTrace,
          );
        }
        rethrow;
      }
      lastError = error.error;
      lastStackTrace = error.stackTrace ?? stackTrace;
      reportProviderDiagnostic(
        providerId: providerId,
        scope: operation,
        message:
            'transient failure on attempt $attempt/$attempts, retrying after '
            '${policy.delayForRetry(attempt).inMilliseconds}ms',
        error: error.error,
        stackTrace: error.stackTrace ?? stackTrace,
        diagnostics: diagnostics,
      );
      await Future<void>.delayed(policy.delayForRetry(attempt));
    }
  }

  if (lastError != null && lastStackTrace != null) {
    Error.throwWithStackTrace(lastError, lastStackTrace);
  }
  throw StateError('Unreachable provider retry flow for $operation.');
}

bool isRetryableHttpStatus(int statusCode) {
  return statusCode == 408 ||
      statusCode == 425 ||
      statusCode == 429 ||
      statusCode == 500 ||
      statusCode == 502 ||
      statusCode == 503 ||
      statusCode == 504;
}

void reportProviderDiagnostic({
  required ProviderId providerId,
  required String scope,
  required String message,
  Object? error,
  StackTrace? stackTrace,
  void Function(String message)? diagnostics,
}) {
  final suffix = error == null ? '' : ' error=$error';
  var line = '$scope: $message$suffix';
  if (providerId == ProviderId.stripchat) {
    line = line.replaceAllMapped(
      RegExp(r'(pkeys?|psch)=([a-zA-Z0-9_-]+)'),
      (match) {
        final key = match.group(1);
        final val = match.group(2) ?? '';
        if (val.length <= 4) {
          return '$key=***';
        }
        return '$key=${val.substring(0, 4)}***';
      },
    );
  }
  diagnostics?.call(line);
  developer.log(
    line,
    name: 'live_providers.${providerId.value}',
    error: error,
    stackTrace: stackTrace,
  );
}
