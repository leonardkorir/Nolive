import 'dart:async';
import 'dart:math';

import 'package:live_core/live_core.dart';

import '../provider_json.dart';
import 'twitch_api_client.dart';
import 'twitch_graphql_hashes.dart';
import 'twitch_playback_bootstrap.dart';

class TwitchGraphQlClient {
  TwitchGraphQlClient({
    required TwitchApiClient apiClient,
    Duration requestTimeout = const Duration(seconds: 12),
  }) : _apiClient = apiClient,
       _requestTimeout = requestTimeout;

  final TwitchApiClient _apiClient;
  final Duration _requestTimeout;

  static const String _playbackAccessTokenQuery =
      'query PlaybackAccessToken_Template('
      r'$login: String!, $isLive: Boolean!, $vodID: ID!, $isVod: Boolean!, '
      r'$playerType: String!, $platform: String!) {'
      '  streamPlaybackAccessToken('
      'channelName: \$login, '
      'params: {platform: \$platform, playerBackend: "mediaplayer", '
      'playerType: \$playerType}'
      '  ) @include(if: \$isLive) {'
      '    value'
      '    signature'
      '    authorization { isForbidden forbiddenReasonCode }'
      '    __typename'
      '  }'
      '  videoPlaybackAccessToken('
      'id: \$vodID, '
      'params: {platform: \$platform, playerBackend: "mediaplayer", '
      'playerType: \$playerType}'
      '  ) @include(if: \$isVod) {'
      '    value'
      '    signature'
      '    __typename'
      '  }'
      '}';

  Future<Map<String, dynamic>> fetchSideNav() async {
    final query = _buildPersistedQuery(
      operationName: 'SideNav',
      sha256Hash: TwitchGraphQlHashes.sideNav,
      variables: {
        'input': {
          'recommendationContext': {
            'platform': 'web',
            'clientApp': 'twilight',
            'location': 'search_results',
            'referrerDomain': 'www.twitch.tv',
            'viewportHeight': 1609,
            'viewportWidth': 2291,
            'channelName': null,
            'categorySlug': null,
            'lastChannelName': null,
            'lastCategorySlug': null,
            'pageviewContent': null,
            'pageviewContentType': null,
            'pageviewLocation': 'search_results',
            'pageviewMedium': 'search',
            'previousPageviewContent': null,
            'previousPageviewContentType': null,
            'previousPageviewLocation': null,
            'previousPageviewMedium': null,
          },
        },
        'creatorAnniversariesFeature': false,
        'withFreeformTags': false,
      },
    );
    return _requireMap(
      _withRequestTimeout(
        _apiClient.postGraphQl(query),
        context: 'side nav response',
      ),
      context: 'side nav response',
    );
  }

  Future<Map<String, dynamic>> search(String query) async {
    final q = _buildPersistedQuery(
      operationName: 'SearchResultsPage_SearchResults',
      sha256Hash: TwitchGraphQlHashes.search,
      variables: {
        'platform': 'web',
        'query': query,
        'options': {'targets': null, 'shouldSkipDiscoveryControl': false},
        'requestID': _randomHex(32),
      },
    );
    return _requireMap(
      _withRequestTimeout(
        _apiClient.postGraphQl(q),
        context: 'search response',
      ),
      context: 'search response',
    );
  }

  Future<Map<String, dynamic>> fetchBrowsePopular({
    String? cursor,
    required int limit,
  }) async {
    final query = _buildPersistedQuery(
      operationName: 'BrowsePage_Popular',
      sha256Hash: TwitchGraphQlHashes.browsePopular,
      variables: {
        'imageWidth': 50,
        'limit': limit,
        'platformType': 'all',
        if (cursor != null && cursor.trim().isNotEmpty) 'cursor': cursor.trim(),
        'options': {
          'sort': 'VIEWER_COUNT',
          'freeformTags': null,
          'tags': [],
          'recommendationsContext': {'platform': 'web'},
          'requestID': 'JIRA-VXP-2397',
          'broadcasterLanguages': [],
        },
        'sortTypeIsRecency': false,
        'includeCostreaming': true,
      },
    );
    return _requireMap(
      _withRequestTimeout(
        _apiClient.postGraphQl(query),
        context: 'browse popular response',
      ),
      context: 'browse popular response',
    );
  }

  Future<Map<String, dynamic>> fetchBrowseAllDirectories({
    String? cursor,
    required int limit,
  }) async {
    final query = _buildPersistedQuery(
      operationName: 'BrowsePage_AllDirectories',
      sha256Hash: TwitchGraphQlHashes.browseAllDirectories,
      variables: {
        'limit': limit,
        'options': {
          'sort': 'VIEWER_COUNT',
          'recommendationsContext': {'platform': 'web'},
          'requestID': 'JIRA-VXP-2397',
          'tags': [],
        },
        if (cursor != null && cursor.trim().isNotEmpty) 'cursor': cursor.trim(),
      },
    );
    return _requireMap(
      _withRequestTimeout(
        _apiClient.postGraphQl(query),
        context: 'browse directories response',
      ),
      context: 'browse directories response',
    );
  }

  Future<Map<String, dynamic>> fetchDirectoryPageGame({
    required String slug,
    required int limit,
  }) async {
    final query = _buildPersistedQuery(
      operationName: 'DirectoryPage_Game',
      sha256Hash: TwitchGraphQlHashes.directoryPageGame,
      variables: {
        'imageWidth': 50,
        'slug': slug,
        'options': {
          'sort': 'VIEWER_COUNT',
          'requestID': 'JIRA-VXP-2397',
          'freeformTags': null,
          'tags': [],
          'recommendationsContext': {'platform': 'web'},
          'broadcasterLanguages': [],
          'systemFilters': [],
        },
        'sortTypeIsRecency': false,
        'limit': limit,
        'includeCostreaming': true,
      },
    );
    return _requireMap(
      _withRequestTimeout(
        _apiClient.postGraphQl(query),
        context: 'directory page game response',
      ),
      context: 'directory page game response',
    );
  }

  Future<List<Map<String, dynamic>>> fetchRoomDetailBatch({
    required String login,
  }) async {
    final queries = [
      _buildPersistedQuery(
        operationName: 'ChannelShell',
        sha256Hash: TwitchGraphQlHashes.channelShell,
        variables: {'login': login},
      ),
      _buildPersistedQuery(
        operationName: 'StreamMetadata',
        sha256Hash: TwitchGraphQlHashes.streamMetadata,
        variables: {'channelLogin': login},
      ),
      _buildPersistedQuery(
        operationName: 'UseViewCount',
        sha256Hash: TwitchGraphQlHashes.useViewCount,
        variables: {'channelLogin': login},
      ),
      _buildPersistedQuery(
        operationName: 'UseLiveBroadcast',
        sha256Hash: TwitchGraphQlHashes.useLiveBroadcast,
        variables: {'channelLogin': login},
      ),
    ];
    return _requireList(
      _withRequestTimeout(
        _apiClient.postGraphQl(queries),
        context: 'detail batch response',
      ),
      context: 'detail batch response',
    );
  }

  Future<TwitchPlaybackBootstrap> requestPlaybackBootstrap({
    required String roomId,
    String playerType = 'popout',
    String platform = 'web',
    TwitchPlaybackBootstrap? contextBootstrap,
    required String clientIntegrity,
  }) async {
    final normalizedRoomId = roomId.trim().toLowerCase();
    final deviceId = contextBootstrap?.deviceId.trim().isNotEmpty == true
        ? contextBootstrap!.deviceId.trim()
        : _randomHex(32);
    final sessionId =
        contextBootstrap?.clientSessionId.trim().isNotEmpty == true
        ? contextBootstrap!.clientSessionId.trim()
        : _randomHex(32);
    final sourceUrl = contextBootstrap?.sourceUrl.trim().isNotEmpty == true
        ? contextBootstrap!.sourceUrl.trim()
        : 'https://www.twitch.tv/$normalizedRoomId';
    final payload = await _requireMap(
      _withRequestTimeout(
        _apiClient.postGraphQl(
          {
            'operationName': 'PlaybackAccessToken_Template',
            'query': _playbackAccessTokenQuery,
            'variables': {
              'isLive': true,
              'login': normalizedRoomId,
              'isVod': false,
              'vodID': '',
              'playerType': playerType,
              'platform': platform,
            },
          },
          deviceId: deviceId,
          clientSessionId: sessionId,
          clientIntegrity:
              contextBootstrap?.clientIntegrity.trim().isNotEmpty == true
              ? contextBootstrap!.clientIntegrity.trim()
              : clientIntegrity,
        ),
        context: 'playback access token response',
      ),
      context: 'playback access token response',
    );
    final token = _asMap(_asMap(payload['data'])['streamPlaybackAccessToken']);
    final authorization = _asMap(token['authorization']);
    if (authorization['isForbidden'] == true) {
      final reason = authorization['forbiddenReasonCode']?.toString().trim();
      throw ProviderParseException(
        providerId: ProviderId.twitch,
        message: reason?.isNotEmpty == true
            ? 'Twitch 拒绝返回播放 token：$reason'
            : 'Twitch 拒绝返回播放 token。',
      );
    }
    final signature = token['signature']?.toString().trim() ?? '';
    final tokenValue = token['value']?.toString().trim() ?? '';
    if (signature.isEmpty || tokenValue.isEmpty) {
      throw ProviderParseException(
        providerId: ProviderId.twitch,
        message: 'Twitch 当前未返回可用播放 token。',
      );
    }
    return TwitchPlaybackBootstrap(
      roomId: normalizedRoomId,
      signature: signature,
      tokenValue: tokenValue,
      deviceId: deviceId,
      clientSessionId: sessionId,
      clientIntegrity:
          contextBootstrap?.clientIntegrity.trim().isNotEmpty == true
          ? contextBootstrap!.clientIntegrity.trim()
          : clientIntegrity,
      sourceUrl: sourceUrl,
      cookie: contextBootstrap?.cookie ?? '',
      userAgent: contextBootstrap?.userAgent ?? '',
    );
  }

  Map<String, dynamic> _buildPersistedQuery({
    required String operationName,
    required String sha256Hash,
    required Map<String, Object?> variables,
  }) {
    return {
      'operationName': operationName,
      'variables': variables,
      'extensions': {
        'persistedQuery': {'version': 1, 'sha256Hash': sha256Hash},
      },
    };
  }

  Future<Map<String, dynamic>> _requireMap(
    Future<Object?> future, {
    required String context,
  }) async {
    final resolved = await future;
    if (resolved is Map<String, dynamic>) {
      return resolved;
    }
    if (resolved is Map) {
      return resolved.cast<String, dynamic>();
    }
    throw ProviderParseException(
      providerId: ProviderId.twitch,
      message:
          'Unexpected Twitch $context payload type: ${resolved.runtimeType}.',
    );
  }

  Future<List<Map<String, dynamic>>> _requireList(
    Future<Object?> future, {
    required String context,
  }) async {
    final resolved = await future;
    if (resolved is! List) {
      throw ProviderParseException(
        providerId: ProviderId.twitch,
        message:
            'Unexpected Twitch $context payload type: ${resolved.runtimeType}.',
      );
    }
    return resolved
        .map((item) => _asMap(item))
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  Map<String, dynamic> findOperationResponse(
    List<Map<String, dynamic>> payload,
    String operationName,
  ) {
    for (final item in payload) {
      final extensions = _asMap(item['extensions']);
      if (extensions['operationName']?.toString() == operationName) {
        return item;
      }
    }
    throw ProviderParseException(
      providerId: ProviderId.twitch,
      message: 'Twitch 当前缺少 $operationName 响应。',
    );
  }

  Map<String, dynamic> _asMap(Object? value) {
    return ProviderJson.asMap(value);
  }

  String _randomHex(int length) {
    final buffer = StringBuffer();
    final random = Random();
    while (buffer.length < length) {
      buffer.write(random.nextInt(16).toRadixString(16));
    }
    return buffer.toString().substring(0, length);
  }

  Future<T> _withRequestTimeout<T>(
    Future<T> future, {
    required String context,
  }) async {
    try {
      return await future.timeout(_requestTimeout);
    } on TimeoutException {
      throw ProviderParseException(
        providerId: ProviderId.twitch,
        message: 'Twitch $context 请求超时。',
      );
    }
  }
}
