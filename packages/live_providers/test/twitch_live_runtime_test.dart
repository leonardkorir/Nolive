import 'dart:async';

import 'package:live_providers/live_providers.dart';
import 'package:live_providers/src/providers/twitch/twitch_api_client.dart';
import 'package:live_providers/src/providers/twitch/twitch_live_data_source.dart';
import 'package:test/test.dart';

import 'support/twitch_fixture_loader.dart';

void main() {
  group(
    'fixture-backed twitch runtime coverage',
    skip: TwitchFixtureLoader.skipReason,
    () {
      test('live twitch runtime maps recommend/search/detail/play flow',
          () async {
        final provider = TwitchProvider(
          dataSource: TwitchLiveDataSource(
            apiClient: _FixtureTwitchApiClient(),
          ),
        );

        final recommend = await provider.fetchRecommendRooms();
        expect(recommend.items, isNotEmpty);
        expect(
          recommend.items.any((item) => item.providerId == 'twitch'),
          isTrue,
        );

        final search = await provider.searchRooms('xQc');
        expect(search.items, isNotEmpty);
        expect(search.items.first.roomId, 'xqc');
        expect(search.items.first.streamerName, isNotEmpty);

        final detail = await provider.fetchRoomDetail('xqc');
        expect(detail.roomId, 'xqc');
        expect(detail.isLive, isTrue);
        expect(detail.sourceUrl, 'https://www.twitch.tv/xqc');

        final qualities = await provider.fetchPlayQualities(detail);
        expect(qualities.length, greaterThan(1));
        expect(qualities.first.id, 'auto');
        expect(
          qualities.any((item) => item.label.contains('1080')),
          isTrue,
        );

        final urls = await provider.fetchPlayUrls(
          detail: detail,
          quality: qualities[1],
        );
        expect(urls.length, greaterThan(1));
        expect(urls.first.url, contains('.m3u8'));
        expect(
          urls.any((item) => (item.lineLabel ?? '').contains('Embed')),
          isTrue,
        );
      });

      test('live twitch runtime prefers injected playback bootstrap resolver',
          () async {
        final provider = TwitchProvider(
          dataSource: TwitchLiveDataSource(
            apiClient: _FixtureTwitchApiClient(
              forbidPopoutPlaybackTokenRequests: true,
            ),
            playbackBootstrapResolver: (detail) async =>
                TwitchPlaybackBootstrap(
              roomId: detail.roomId,
              signature: 'fixture-signature',
              tokenValue: 'fixture-token',
              deviceId: 'fixture-device-id',
              clientSessionId: 'fixture-session-id',
              sourceUrl:
                  detail.sourceUrl ?? 'https://www.twitch.tv/${detail.roomId}',
            ),
          ),
        );

        final detail = await provider.fetchRoomDetail('xqc');
        final qualities = await provider.fetchPlayQualities(detail);
        final urls = await provider.fetchPlayUrls(
          detail: detail,
          quality: qualities[1],
        );

        expect(qualities.length, greaterThan(1));
        expect(urls.length, greaterThan(1));
        expect(urls.first.url, contains('.m3u8'));
      });

      test('live twitch runtime does not hang on stalled alternate surfaces',
          () async {
        final provider = TwitchProvider(
          dataSource: TwitchLiveDataSource(
            apiClient: _FixtureTwitchApiClient(
              stalledPlayerTypes: const {'embed', 'site', 'autoplay'},
            ),
            alternateSurfaceTimeout: const Duration(milliseconds: 50),
          ),
        );

        final detail = await provider.fetchRoomDetail('xqc');
        final qualities = await provider.fetchPlayQualities(detail).timeout(
              const Duration(seconds: 2),
            );

        expect(qualities.length, greaterThan(1));
        expect(qualities.first.id, 'auto');
      });

      test(
          'live twitch runtime does not wait for slower resolver when direct bootstrap is usable',
          () async {
        final provider = TwitchProvider(
          dataSource: TwitchLiveDataSource(
            apiClient: _FixtureTwitchApiClient(
              stalledPlayerTypes: const {'embed', 'site', 'autoplay'},
            ),
            playbackBootstrapResolver: (detail) async {
              await Future<void>.delayed(const Duration(seconds: 1));
              return TwitchPlaybackBootstrap(
                roomId: detail.roomId,
                signature: 'slow-resolver-signature',
                tokenValue: 'slow-resolver-token',
                deviceId: 'slow-resolver-device-id',
                clientSessionId: 'slow-resolver-session-id',
                sourceUrl: detail.sourceUrl ??
                    'https://www.twitch.tv/${detail.roomId}',
              );
            },
            bootstrapResolverTimeout: const Duration(milliseconds: 500),
            bootstrapResolverGraceTimeout: const Duration(milliseconds: 100),
            alternateSurfaceTimeout: const Duration(milliseconds: 50),
          ),
        );

        final detail = await provider.fetchRoomDetail('xqc');
        final qualities = await provider.fetchPlayQualities(detail).timeout(
              const Duration(milliseconds: 600),
            );

        expect(qualities.length, greaterThan(1));
        expect(qualities.first.id, 'auto');
      });

      test(
          'live twitch runtime prefers richer resolver bootstrap within grace window',
          () async {
        const resolverPlaylistUrl = 'https://resolver.example/master.m3u8';
        final apiClient = _FixtureTwitchApiClient(
          resolverPlaylistUrl: resolverPlaylistUrl,
        );
        final provider = TwitchProvider(
          dataSource: TwitchLiveDataSource(
            apiClient: apiClient,
            playbackBootstrapResolver: (detail) async {
              await Future<void>.delayed(const Duration(milliseconds: 50));
              return TwitchPlaybackBootstrap(
                roomId: detail.roomId,
                signature: 'resolver-signature',
                tokenValue: 'resolver-token',
                deviceId: 'resolver-device-id',
                clientSessionId: 'resolver-session-id',
                clientIntegrity: 'resolver-integrity',
                sourceUrl:
                    detail.sourceUrl ?? 'https://www.twitch.tv/${detail.roomId}',
                masterPlaylistUrl: resolverPlaylistUrl,
                cookie: 'unique_id=resolver-cookie',
                userAgent: 'resolver-agent',
              );
            },
            bootstrapResolverGraceTimeout: const Duration(milliseconds: 200),
            alternateSurfaceTimeout: const Duration(milliseconds: 50),
          ),
        );

        final detail = await provider.fetchRoomDetail('xqc');
        final qualities = await provider.fetchPlayQualities(detail);

        expect(qualities.length, greaterThan(1));
        expect(apiClient.requestedUrls, contains(resolverPlaylistUrl));
      });
    },
  );
}

class _FixtureTwitchApiClient implements TwitchApiClient {
  _FixtureTwitchApiClient({
    this.forbidPopoutPlaybackTokenRequests = false,
    this.stalledPlayerTypes = const <String>{},
    this.resolverPlaylistUrl,
  })  : _sideNav = TwitchFixtureLoader.loadGraphQlOperation('SideNav'),
        _browsePopular = TwitchFixtureLoader.loadGraphQlOperation(
          'BrowsePage_Popular',
        ),
        _search = TwitchFixtureLoader.loadGraphQlOperation(
          'SearchResultsPage_SearchResults',
          requestContains: '"query":"xQc"',
        ),
        _channelShell = TwitchFixtureLoader.loadGraphQlOperation(
          'ChannelShell',
          requestContains: '"login":"xqc"',
        ),
        _streamMetadata = TwitchFixtureLoader.loadGraphQlOperation(
          'StreamMetadata',
          requestContains: '"channelLogin":"xqc"',
        ),
        _viewCount = TwitchFixtureLoader.loadGraphQlOperation(
          'UseViewCount',
          requestContains: '"channelLogin":"xqc"',
        ),
        _liveBroadcast = TwitchFixtureLoader.loadGraphQlOperation(
          'UseLiveBroadcast',
          requestContains: '"channelLogin":"xqc"',
        ),
        _playbackToken = TwitchFixtureLoader.loadPlaybackAccessToken('xqc'),
        _playlist = TwitchFixtureLoader.loadHlsMasterPlaylist('xqc');

  final bool forbidPopoutPlaybackTokenRequests;
  final Set<String> stalledPlayerTypes;
  final String? resolverPlaylistUrl;
  final List<String> requestedUrls = <String>[];

  final Map<String, dynamic> _sideNav;
  final Map<String, dynamic> _browsePopular;
  final Map<String, dynamic> _search;
  final Map<String, dynamic> _channelShell;
  final Map<String, dynamic> _streamMetadata;
  final Map<String, dynamic> _viewCount;
  final Map<String, dynamic> _liveBroadcast;
  final Map<String, dynamic> _playbackToken;
  final String _playlist;

  @override
  Future<String> fetchText(
    String url, {
    Map<String, String> headers = const {},
  }) async {
    requestedUrls.add(url);
    if (resolverPlaylistUrl != null && url == resolverPlaylistUrl) {
      return _playlist;
    }
    if (url.contains('/channel/hls/xqc.m3u8')) {
      for (final playerType in stalledPlayerTypes) {
        if (url.contains('-$playerType')) {
          return Completer<String>().future;
        }
      }
      return _playlist;
    }
    throw StateError('Unexpected Twitch fetchText url: $url');
  }

  @override
  Future<Object?> postGraphQl(
    Object payload, {
    String deviceId = '',
    String clientSessionId = '',
    String clientIntegrity = '',
  }) async {
    if (payload is Map) {
      final operationName = payload['operationName']?.toString() ?? '';
      if (operationName == 'SideNav') {
        return _sideNav;
      }
      if (operationName == 'BrowsePage_Popular') {
        return _browsePopular;
      }
      if (operationName == 'SearchResultsPage_SearchResults') {
        return _search;
      }
      if (operationName.startsWith('PlaybackAccessToken')) {
        final variables = payload['variables'];
        final playerType = variables is Map
            ? variables['playerType']?.toString().trim() ?? ''
            : '';
        if (forbidPopoutPlaybackTokenRequests && playerType == 'popout') {
          throw StateError(
            'Popout PlaybackAccessToken request should have been resolved by bootstrap resolver.',
          );
        }
        return _tokenForPlayerType(playerType);
      }
    }
    if (payload is List) {
      return [
        _channelShell,
        _streamMetadata,
        _viewCount,
        _liveBroadcast,
      ];
    }
    throw StateError('Unexpected Twitch GraphQL payload: $payload');
  }

  Map<String, dynamic> _tokenForPlayerType(String playerType) {
    final playerTypeSuffix = playerType.isEmpty ? 'popout' : playerType;
    final cloned = Map<String, dynamic>.from(_playbackToken);
    final data = Map<String, dynamic>.from(
      (cloned['data'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
    final token = Map<String, dynamic>.from(
      (data['streamPlaybackAccessToken'] as Map?)?.cast<String, dynamic>() ??
          const {},
    );
    token['signature'] =
        '${token['signature'] ?? 'fixture-signature'}-$playerTypeSuffix';
    token['value'] = '${token['value'] ?? 'fixture-token'}-$playerTypeSuffix';
    data['streamPlaybackAccessToken'] = token;
    cloned['data'] = data;
    return cloned;
  }
}
