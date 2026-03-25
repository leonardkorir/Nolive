import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:live_core/live_core.dart';

abstract interface class YouTubeApiClient {
  static const String browserUserAgent =
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36';
  static const String defaultWebClientVersion = '2.20260320.01.00';
  static const String webClientNameHeader = '1';

  Future<String> fetchText(
    String url, {
    Map<String, String> headers = const {},
  });

  Future<int> probeStatus(
    String url, {
    Map<String, String> headers = const {},
  });

  Future<Map<String, dynamic>> postPlayer({
    required String apiKey,
    required String videoId,
    required String originalUrl,
    Map<String, dynamic> innertubeContext = const {},
    String rolloutToken = '',
    String poToken = '',
    YouTubePlayerClientProfile clientProfile = YouTubePlayerClientProfile.web,
  });

  Future<Map<String, dynamic>> postLiveChat({
    required String apiKey,
    required String continuation,
    required String visitorData,
    required String referer,
    String clientVersion = defaultWebClientVersion,
  });
}

enum YouTubePlayerClientProfile {
  web(
    id: 'web',
    clientName: 'WEB',
    clientNameHeader: 1,
    clientVersion: YouTubeApiClient.defaultWebClientVersion,
    apiHost: 'www.youtube.com',
    userAgent:
        '${YouTubeApiClient.browserUserAgent},gzip(gfe)',
    platform: 'DESKTOP',
    browserName: 'Chrome',
    browserVersion: '146.0.0.0',
    osName: 'X11',
    osVersion: '',
    clientFormFactor: 'UNKNOWN_FORM_FACTOR',
    lineLabel: 'WEB',
  ),
  webSafari(
    id: 'web_safari',
    clientName: 'WEB',
    clientNameHeader: 1,
    clientVersion: '2.20260114.08.00',
    apiHost: 'www.youtube.com',
    userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
        'AppleWebKit/605.1.15 (KHTML, like Gecko) '
        'Version/15.5 Safari/605.1.15,gzip(gfe)',
    platform: 'DESKTOP',
    browserName: 'Safari',
    browserVersion: '15.5',
    osName: 'Macintosh',
    osVersion: '10_15_7',
    clientFormFactor: 'UNKNOWN_FORM_FACTOR',
    lineLabel: 'Safari',
  ),
  mweb(
    id: 'mweb',
    clientName: 'MWEB',
    clientNameHeader: 2,
    clientVersion: '2.20260115.01.00',
    apiHost: 'm.youtube.com',
    userAgent: 'Mozilla/5.0 (iPad; CPU OS 16_7_10 like Mac OS X) '
        'AppleWebKit/605.1.15 (KHTML, like Gecko) '
        'Version/16.6 Mobile/15E148 Safari/604.1,gzip(gfe)',
    platform: 'MOBILE_WEB',
    browserName: 'Safari',
    browserVersion: '16.6',
    osName: 'iOS',
    osVersion: '16.7.10',
    clientFormFactor: 'SMALL_FORM_FACTOR',
    lineLabel: 'MWEB',
  ),
  ios(
    id: 'ios',
    clientName: 'IOS',
    clientNameHeader: 5,
    clientVersion: '21.02.3',
    apiHost: 'www.youtube.com',
    userAgent: 'com.google.ios.youtube/21.02.3 '
        '(iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)',
    platform: 'MOBILE',
    osName: 'iPhone',
    osVersion: '18.3.2.22D82',
    clientFormFactor: 'SMALL_FORM_FACTOR',
    deviceMake: 'Apple',
    deviceModel: 'iPhone16,2',
    lineLabel: 'iOS',
  );

  const YouTubePlayerClientProfile({
    required this.id,
    required this.clientName,
    required this.clientNameHeader,
    required this.clientVersion,
    required this.apiHost,
    required this.userAgent,
    required this.platform,
    required this.osName,
    required this.osVersion,
    required this.clientFormFactor,
    required this.lineLabel,
    this.browserName,
    this.browserVersion,
    this.deviceMake,
    this.deviceModel,
  });

  final String id;
  final String clientName;
  final int clientNameHeader;
  final String clientVersion;
  final String apiHost;
  final String userAgent;
  final String platform;
  final String? browserName;
  final String? browserVersion;
  final String osName;
  final String osVersion;
  final String clientFormFactor;
  final String? deviceMake;
  final String? deviceModel;
  final String lineLabel;

  String get origin => 'https://$apiHost';

  String rewriteOriginalUrl(String originalUrl) {
    final trimmed = originalUrl.trim();
    if (trimmed.isEmpty) {
      return origin;
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null || uri.host.isEmpty) {
      return origin;
    }
    return uri.replace(host: apiHost).toString();
  }
}

class HttpYouTubeApiClient implements YouTubeApiClient {
  HttpYouTubeApiClient({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;
  final Map<String, String> _cookies = <String, String>{};
  static const int _maxRedirects = 12;

  @override
  Future<String> fetchText(
    String url, {
    Map<String, String> headers = const {},
  }) async {
    var currentUri = Uri.parse(url);
    final visited = <String>{};
    for (var redirectCount = 0;
        redirectCount <= _maxRedirects;
        redirectCount += 1) {
      final response = await _sendRequest(
        method: 'GET',
        uri: currentUri,
        headers: {
          'accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'accept-language': 'en-US,en;q=0.9',
          'cache-control': 'no-cache',
          'pragma': 'no-cache',
          'upgrade-insecure-requests': '1',
          'user-agent': YouTubeApiClient.browserUserAgent,
          ...headers,
        },
      );
      if (_isRedirectStatus(response.statusCode)) {
        final location = response.headers['location']?.trim() ?? '';
        if (location.isEmpty) {
          throw ProviderParseException(
            providerId: ProviderId.youtube,
            message:
                'YouTube document request for $url returned redirect without location.',
          );
        }
        final nextUri = currentUri.resolve(location);
        if (!visited.add(nextUri.toString())) {
          break;
        }
        currentUri = nextUri;
        continue;
      }
      _ensureSuccess(response,
          context: 'document request for ${currentUri.toString()}');
      return utf8.decode(response.bodyBytes);
    }
    throw ProviderParseException(
      providerId: ProviderId.youtube,
      message:
          'YouTube document request redirect limit exceeded, uri=$currentUri.',
    );
  }

  @override
  Future<int> probeStatus(
    String url, {
    Map<String, String> headers = const {},
  }) async {
    var currentUri = Uri.parse(url);
    final visited = <String>{};
    for (var redirectCount = 0;
        redirectCount <= _maxRedirects;
        redirectCount += 1) {
      final response = await _sendRequest(
        method: 'HEAD',
        uri: currentUri,
        headers: {
          'accept': '*/*',
          'accept-language': 'en-US,en;q=0.9',
          'cache-control': 'no-cache',
          'pragma': 'no-cache',
          'user-agent': YouTubeApiClient.browserUserAgent,
          ...headers,
        },
      );
      if (_isRedirectStatus(response.statusCode)) {
        final location = response.headers['location']?.trim() ?? '';
        if (location.isEmpty) {
          return response.statusCode;
        }
        final nextUri = currentUri.resolve(location);
        if (!visited.add(nextUri.toString())) {
          return response.statusCode;
        }
        currentUri = nextUri;
        continue;
      }
      return response.statusCode;
    }
    throw ProviderParseException(
      providerId: ProviderId.youtube,
      message:
          'YouTube probe request redirect limit exceeded, uri=$currentUri.',
    );
  }

  @override
  Future<Map<String, dynamic>> postPlayer({
    required String apiKey,
    required String videoId,
    required String originalUrl,
    Map<String, dynamic> innertubeContext = const {},
    String rolloutToken = '',
    String poToken = '',
    YouTubePlayerClientProfile clientProfile = YouTubePlayerClientProfile.web,
  }) async {
    final clientContext = _normalizeClientContext(innertubeContext);
    final resolvedOriginalUrl = clientProfile.rewriteOriginalUrl(originalUrl);
    final resolvedVisitorData =
        clientContext['visitorData']?.toString().trim() ?? '';
    final resolvedClientVersion = clientProfile.clientVersion;
    final resolvedRolloutToken = rolloutToken.trim().isNotEmpty
        ? rolloutToken.trim()
        : clientContext['rolloutToken']?.toString().trim() ?? '';
    final client = <String, Object?>{
      'clientName': clientProfile.clientName,
      'clientVersion': resolvedClientVersion,
      'platform': clientProfile.platform,
      'hl': clientContext['hl']?.toString().trim().isNotEmpty == true
          ? clientContext['hl']!.toString().trim()
          : 'en',
      'gl': clientContext['gl']?.toString().trim().isNotEmpty == true
          ? clientContext['gl']!.toString().trim()
          : 'US',
      'originalUrl': resolvedOriginalUrl,
      'clientScreen':
          clientContext['clientScreen']?.toString().trim().isNotEmpty == true
              ? clientContext['clientScreen']!.toString().trim()
              : _inferClientScreen(resolvedOriginalUrl),
      'playerType': 'UNIPLAYER',
      'clientFormFactor': clientProfile.clientFormFactor,
      'osName': clientProfile.osName,
      'osVersion': clientProfile.osVersion,
      'userAgent': clientProfile.userAgent,
      if (resolvedVisitorData.isNotEmpty) 'visitorData': resolvedVisitorData,
      if (resolvedRolloutToken.isNotEmpty) 'rolloutToken': resolvedRolloutToken,
      if ((clientProfile.browserName?.isNotEmpty ?? false))
        'browserName': clientProfile.browserName,
      if ((clientProfile.browserVersion?.isNotEmpty ?? false))
        'browserVersion': clientProfile.browserVersion,
      if ((clientProfile.deviceMake?.isNotEmpty ?? false))
        'deviceMake': clientProfile.deviceMake,
      if ((clientProfile.deviceModel?.isNotEmpty ?? false))
        'deviceModel': clientProfile.deviceModel,
    };
    final response = await _sendRequest(
      method: 'POST',
      uri: Uri.https(clientProfile.apiHost, '/youtubei/v1/player', {
        'prettyPrint': 'false',
        'key': apiKey,
      }),
      headers: {
        'accept-language': 'en-US,en;q=0.9',
        'content-type': 'application/json',
        'origin': clientProfile.origin,
        'referer': resolvedOriginalUrl,
        'user-agent': clientProfile.userAgent,
        if (resolvedVisitorData.isNotEmpty)
          'x-goog-visitor-id': resolvedVisitorData,
        'x-youtube-client-name': clientProfile.clientNameHeader.toString(),
        'x-youtube-client-version': resolvedClientVersion,
      },
      body: jsonEncode({
        'videoId': videoId,
        'contentCheckOk': true,
        'racyCheckOk': true,
        'context': {
          'client': client,
          'user': {'lockedSafetyMode': false},
          'request': {
            'useSsl': true,
            'internalExperimentFlags': const [],
            'consistencyTokenJars': const [],
          },
        },
        'playbackContext': {
          'contentPlaybackContext': {
            'html5Preference': 'HTML5_PREF_WANTS',
            'referer': originalUrl,
            'autoplay': true,
            'autoCaptionsDefaultOn': false,
          },
          'devicePlaybackCapabilities': {
            'supportsVp9Encoding': true,
            'supportXhr': true,
          },
        },
        if (poToken.trim().isNotEmpty)
          'serviceIntegrityDimensions': {
            'poToken': poToken.trim(),
          },
        'attestationRequest': {
          'omitBotguardData': true,
        },
      }),
    );
    return _decodeJsonResponse(response, context: 'player request');
  }

  @override
  Future<Map<String, dynamic>> postLiveChat({
    required String apiKey,
    required String continuation,
    required String visitorData,
    required String referer,
    String clientVersion = YouTubeApiClient.defaultWebClientVersion,
  }) async {
    final response = await _sendRequest(
      method: 'POST',
      uri:
          Uri.https('www.youtube.com', '/youtubei/v1/live_chat/get_live_chat', {
        'prettyPrint': 'false',
        'key': apiKey,
      }),
      headers: {
        'content-type': 'application/json',
        'origin': 'https://www.youtube.com',
        'referer': referer,
        'user-agent': YouTubeApiClient.browserUserAgent,
        'x-goog-visitor-id': visitorData,
        'x-youtube-client-name': YouTubeApiClient.webClientNameHeader,
        'x-youtube-client-version': clientVersion,
      },
      body: jsonEncode({
        'context': {
          'client': {
            'clientName': 'WEB',
            'clientVersion': clientVersion,
            'platform': 'DESKTOP',
            'hl': 'en',
            'gl': 'US',
            'visitorData': visitorData,
            'userAgent': YouTubeApiClient.browserUserAgent,
            'originalUrl': referer,
          },
          'user': {
            'lockedSafetyMode': false,
          },
          'request': {
            'useSsl': true,
          },
        },
        'continuation': continuation,
        'webClientInfo': {
          'isDocumentHidden': false,
        },
      }),
    );
    return _decodeJsonResponse(response, context: 'live chat request');
  }

  Future<http.Response> _sendRequest({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    String body = '',
  }) async {
    final request = http.Request(method, uri)
      ..followRedirects = false
      ..maxRedirects = 0
      ..headers.addAll(_mergeHeadersWithCookies(headers))
      ..body = body;
    final streamed = await _client.send(request);
    _storeCookies(streamed.headers['set-cookie']);
    return http.Response.fromStream(streamed);
  }

  Map<String, String> _mergeHeadersWithCookies(Map<String, String> headers) {
    final merged = <String, String>{...headers};
    final cookieHeader = _composeCookieHeader(headers['cookie']);
    if (cookieHeader.isNotEmpty) {
      merged['cookie'] = cookieHeader;
    }
    return merged;
  }

  String _composeCookieHeader(String? requestCookie) {
    final cookies = <String, String>{..._cookies};
    final explicitCookie = requestCookie?.trim() ?? '';
    if (explicitCookie.isNotEmpty) {
      for (final part in explicitCookie.split(';')) {
        final pair = part.trim();
        final separator = pair.indexOf('=');
        if (separator <= 0) {
          continue;
        }
        cookies[pair.substring(0, separator).trim()] =
            pair.substring(separator + 1).trim();
      }
    }
    if (cookies.isEmpty) {
      return '';
    }
    return cookies.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join('; ');
  }

  void _storeCookies(String? setCookieHeader) {
    final normalized = setCookieHeader?.trim() ?? '';
    if (normalized.isEmpty) {
      return;
    }
    for (final item in _splitSetCookieHeader(normalized)) {
      final pair = item.split(';').first.trim();
      final separator = pair.indexOf('=');
      if (separator <= 0) {
        continue;
      }
      _cookies[pair.substring(0, separator).trim()] =
          pair.substring(separator + 1).trim();
    }
  }

  List<String> _splitSetCookieHeader(String header) {
    final segments = <String>[];
    var buffer = StringBuffer();
    var index = 0;
    var inExpires = false;
    while (index < header.length) {
      final char = header[index];
      if (char == ',') {
        final remainder = header.substring(index + 1);
        final startsNewCookie = RegExp(r'^\s*[^=;,]+\=').hasMatch(remainder);
        if (!inExpires && startsNewCookie) {
          segments.add(buffer.toString().trim());
          buffer = StringBuffer();
          index += 1;
          continue;
        }
      }
      buffer.write(char);
      if (buffer.toString().toLowerCase().endsWith('expires=')) {
        inExpires = true;
      } else if (inExpires && char == ';') {
        inExpires = false;
      }
      index += 1;
    }
    final tail = buffer.toString().trim();
    if (tail.isNotEmpty) {
      segments.add(tail);
    }
    return segments;
  }

  bool _isRedirectStatus(int statusCode) {
    return statusCode == 301 ||
        statusCode == 302 ||
        statusCode == 303 ||
        statusCode == 307 ||
        statusCode == 308;
  }

  void _ensureSuccess(http.Response response, {required String context}) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }
    throw ProviderParseException(
      providerId: ProviderId.youtube,
      message: 'YouTube $context failed with status ${response.statusCode}.',
    );
  }

  Map<String, dynamic> _decodeJsonResponse(
    http.Response response, {
    required String context,
  }) {
    _ensureSuccess(response, context: context);
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.cast<String, dynamic>();
    }
    throw ProviderParseException(
      providerId: ProviderId.youtube,
      message:
          'Unexpected YouTube $context payload type: ${decoded.runtimeType}.',
    );
  }

  Map<String, dynamic> _normalizeClientContext(Map<String, dynamic> raw) {
    if (raw['client'] is Map<String, dynamic>) {
      return (raw['client'] as Map<String, dynamic>);
    }
    if (raw['client'] is Map) {
      return (raw['client'] as Map).cast<String, dynamic>();
    }
    return raw;
  }

  String _inferClientScreen(String originalUrl) {
    final path = Uri.tryParse(originalUrl)?.path.toLowerCase() ?? '';
    if (path == '/watch') {
      return 'WATCH';
    }
    if (path.startsWith('/@') ||
        path.startsWith('/channel/') ||
        path.startsWith('/c/') ||
        path.startsWith('/user/')) {
      return 'CHANNEL';
    }
    return 'WATCH';
  }
}
