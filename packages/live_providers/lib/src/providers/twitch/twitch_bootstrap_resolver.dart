import 'dart:async';

import 'package:live_core/live_core.dart';

import '../provider_runtime_support.dart';

import 'twitch_graphql_client.dart';
import 'twitch_playback_bootstrap.dart';

class TwitchPlaybackBootstrapResolverImpl {
  TwitchPlaybackBootstrapResolverImpl({
    required TwitchGraphQlClient graphQlClient,
    required TwitchPlaybackBootstrapResolver? customResolver,
    required Duration bootstrapResolverTimeout,
    required Duration bootstrapResolverGraceTimeout,
    required String clientIntegrity,
  }) : _graphQlClient = graphQlClient,
       _customResolver = customResolver,
       _bootstrapResolverTimeout = bootstrapResolverTimeout,
       _bootstrapResolverGraceTimeout = bootstrapResolverGraceTimeout,
       _clientIntegrity = clientIntegrity;

  final TwitchGraphQlClient _graphQlClient;
  final TwitchPlaybackBootstrapResolver? _customResolver;
  final Duration _bootstrapResolverTimeout;
  final Duration _bootstrapResolverGraceTimeout;
  final String _clientIntegrity;

  Future<TwitchPlaybackBootstrap?> resolvePlaybackBootstrap(
    LiveRoomDetail detail,
  ) async {
    final metadataBootstrap = _bootstrapFromMetadata(detail);
    if (metadataBootstrap?.isUsable == true) {
      return metadataBootstrap;
    }

    final directFuture = _resolveDirectPlaybackBootstrap(detail.roomId);

    final resolver = _customResolver;
    if (resolver == null) {
      return await directFuture;
    }

    final resolverFuture = _resolvePlaybackBootstrapFromResolver(
      resolver,
      detail,
    );
    final firstResolved =
        await Future.any<({String source, TwitchPlaybackBootstrap? bootstrap})>(
          [
            directFuture.then(
              (bootstrap) => (source: 'direct', bootstrap: bootstrap),
            ),
            resolverFuture.then(
              (bootstrap) => (source: 'resolver', bootstrap: bootstrap),
            ),
          ],
        );
    if (firstResolved.source == 'resolver' &&
        firstResolved.bootstrap?.isUsable == true) {
      return firstResolved.bootstrap;
    }
    if (firstResolved.source == 'direct' &&
        firstResolved.bootstrap?.isUsable == true) {
      final resolverBootstrap = await resolverFuture.timeout(
        _bootstrapResolverGraceTimeout,
        onTimeout: () => null,
      );
      if (_shouldPreferResolverBootstrap(
        directBootstrap: firstResolved.bootstrap!,
        resolverBootstrap: resolverBootstrap,
      )) {
        return resolverBootstrap;
      }
      return firstResolved.bootstrap;
    }

    // Both sides already fail-soft; still bound the trailing wait so room
    // open never hangs on a stuck GraphQL or WebView resolver.
    if (firstResolved.source == 'direct') {
      return await resolverFuture.timeout(
        _bootstrapResolverTimeout,
        onTimeout: () => null,
      );
    }
    return await directFuture.timeout(
      _bootstrapResolverTimeout,
      onTimeout: () => null,
    );
  }

  bool _shouldPreferResolverBootstrap({
    required TwitchPlaybackBootstrap directBootstrap,
    required TwitchPlaybackBootstrap? resolverBootstrap,
  }) {
    if (resolverBootstrap?.isUsable != true) {
      return false;
    }
    return _bootstrapRichnessScore(resolverBootstrap!) >=
        _bootstrapRichnessScore(directBootstrap);
  }

  int _bootstrapRichnessScore(TwitchPlaybackBootstrap bootstrap) {
    var score = 0;
    if (bootstrap.clientIntegrity.trim().isNotEmpty) {
      score += 3;
    }
    if (bootstrap.cookie.trim().isNotEmpty) {
      score += 2;
    }
    if (bootstrap.masterPlaylistUrl.trim().isNotEmpty) {
      score += 2;
    }
    if (bootstrap.userAgent.trim().isNotEmpty) {
      score += 1;
    }
    if (bootstrap.sourceUrl.trim().isNotEmpty) {
      score += 1;
    }
    return score;
  }

  Future<TwitchPlaybackBootstrap?> _resolveDirectPlaybackBootstrap(
    String roomId,
  ) async {
    try {
      final bootstrap = await _graphQlClient.requestPlaybackBootstrap(
        roomId: roomId,
        clientIntegrity: _clientIntegrity,
      );
      return bootstrap.isUsable ? bootstrap : null;
    } catch (error, stackTrace) {
      reportProviderDiagnostic(
        providerId: ProviderId.twitch,
        scope: 'twitch direct playback bootstrap',
        message: 'failed for roomId=$roomId',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  Future<TwitchPlaybackBootstrap?> _resolvePlaybackBootstrapFromResolver(
    TwitchPlaybackBootstrapResolver resolver,
    LiveRoomDetail detail,
  ) async {
    try {
      final bootstrap = await resolver(
        detail,
      ).timeout(_bootstrapResolverTimeout);
      return bootstrap?.isUsable == true ? bootstrap : null;
    } on TimeoutException {
      return null;
    } catch (error, stackTrace) {
      reportProviderDiagnostic(
        providerId: ProviderId.twitch,
        scope: 'twitch playback bootstrap resolver',
        message: 'custom resolver failed for roomId=${detail.roomId}',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  TwitchPlaybackBootstrap? _bootstrapFromMetadata(LiveRoomDetail detail) {
    final metadata = detail.metadata;
    if (metadata == null || metadata.isEmpty) {
      return null;
    }
    final roomId =
        metadata['playbackRoomId']?.toString().trim() ?? detail.roomId.trim();
    final signature =
        metadata['playbackAccessTokenSignature']?.toString().trim() ?? '';
    final tokenValue =
        metadata['playbackAccessTokenValue']?.toString().trim() ?? '';
    if (roomId.isEmpty || signature.isEmpty || tokenValue.isEmpty) {
      return null;
    }
    return TwitchPlaybackBootstrap(
      roomId: roomId,
      signature: signature,
      tokenValue: tokenValue,
      deviceId: metadata['playbackDeviceId']?.toString().trim() ?? '',
      clientSessionId:
          metadata['playbackClientSessionId']?.toString().trim() ?? '',
      clientIntegrity:
          metadata['playbackClientIntegrity']?.toString().trim() ?? '',
      sourceUrl:
          metadata['playbackSourceUrl']?.toString().trim() ??
          detail.sourceUrl?.trim() ??
          '',
      masterPlaylistUrl:
          metadata['playbackMasterPlaylistUrl']?.toString().trim() ?? '',
      cookie: metadata['playbackCookie']?.toString().trim() ?? '',
      userAgent: metadata['playbackUserAgent']?.toString().trim() ?? '',
    );
  }
}
