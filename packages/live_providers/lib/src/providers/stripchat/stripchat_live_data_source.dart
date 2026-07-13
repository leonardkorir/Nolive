import 'dart:async';

import 'package:live_core/live_core.dart';

import '../provider_runtime_support.dart';
import '../provider_json.dart';
import 'stripchat_api_client.dart';
import 'stripchat_data_source.dart';
import 'stripchat_mapper.dart';

class StripchatLiveDataSource implements StripchatDataSource {
  StripchatLiveDataSource({
    required this.apiClient,
    Duration broadcastFetchTimeout = const Duration(seconds: 2),
  }) : _broadcastFetchTimeout = broadcastFetchTimeout;

  static const int _defaultLimit = 24;
  static const int _categoryLimit = 60;

  final StripchatApiClient apiClient;
  final Duration _broadcastFetchTimeout;
  Map<String, dynamic>? _cachedInitialDynamic;
  String? _cachedGuestHash;
  String? _cachedCsrfToken;
  int? _cachedGuestId;
  Future<Map<String, dynamic>>? _initialDynamicFuture;
  DateTime? _initialDynamicFetchedTime;

  Future<Map<String, dynamic>> get _initialDynamic {
    final now = DateTime.now();
    if (_initialDynamicFuture != null &&
        _initialDynamicFetchedTime != null &&
        now.difference(_initialDynamicFetchedTime!) >
            const Duration(minutes: 15)) {
      _initialDynamicFuture = null;
    }
    return _initialDynamicFuture ??= apiClient
        .fetchInitialDynamic()
        .then((result) {
          _initialDynamicFetchedTime = DateTime.now();
          _cachedInitialDynamic = result;
          _cachedGuestHash = result['userHash']?.toString();
          _cachedCsrfToken = result['csrfToken']?.toString();
          _cachedGuestId = ProviderJson.asInt(result['guestId']);
          return result;
        })
        .catchError((Object error, StackTrace stackTrace) {
          _initialDynamicFuture = null;
          _initialDynamicFetchedTime = null;
          throw error;
        });
  }

  Future<String?> get _guestHash async {
    if (_cachedGuestHash != null) return _cachedGuestHash;
    await _initialDynamic;
    return _cachedGuestHash;
  }

  @override
  Future<List<LiveCategory>> fetchCategories() async {
    final response = await apiClient.fetchLiveTags();
    return StripchatMapper.mapCategories(response);
  }

  @override
  Future<PagedResponse<LiveRoom>> fetchCategoryRooms(
    LiveSubCategory category, {
    int page = 1,
  }) async {
    final offset = (page - 1) * _categoryLimit;
    final filterGroupTags = '[["${category.id}"]]';
    final guestHash = await _guestHash;
    final response = await apiClient.fetchCategoryModels(
      filterGroupTags: filterGroupTags,
      parentTag: category.id,
      limit: _categoryLimit,
      offset: offset,
      guestHash: guestHash,
    );
    return StripchatMapper.mapCategoryRoomsResponse(
      response,
      page: page,
      limit: _categoryLimit,
    );
  }

  @override
  Future<PagedResponse<LiveRoom>> fetchRecommendRooms({int page = 1}) async {
    final offset = (page - 1) * _defaultLimit;
    final guestHash = await _guestHash;
    final response = await apiClient.fetchRecommendModels(
      limit: _defaultLimit,
      offset: offset,
      guestHash: guestHash,
    );
    return StripchatMapper.mapRecommendResponse(
      response,
      page: page,
      limit: _defaultLimit,
    );
  }

  @override
  Future<PagedResponse<LiveRoom>> searchRooms(
    String query, {
    int page = 1,
  }) async {
    final guestHash = await _guestHash;
    final response = await apiClient.searchModels(
      query: query,
      limit: _defaultLimit,
      guestHash: guestHash,
    );
    return StripchatMapper.mapSearchResponse(
      response,
      page: page,
      limit: _defaultLimit,
    );
  }

  @override
  Future<LiveRoomDetail> fetchRoomDetail(String roomId) async {
    final isNumeric = RegExp(r'^\d+$').hasMatch(roomId);
    String username;

    if (isNumeric) {
      final modelId = int.parse(roomId);
      final guestHash = await _guestHash;
      final listResponse = await apiClient.listModels(
        modelIds: [modelId],
        guestHash: guestHash,
      );
      final models = listResponse['models'] as List? ?? [];
      if (models.isEmpty) {
        throw ProviderParseException(
          providerId: ProviderId.stripchat,
          message: 'Stripchat model not found for numeric modelId $roomId.',
        );
      }
      final modelMap = ProviderJson.asMap(models.first);
      username = modelMap['username']?.toString() ?? roomId;
    } else {
      username = roomId;
    }

    final initialDynamicFuture = _initialDynamic;
    final camPayloadFuture = apiClient.fetchCam(username);
    final broadcastPayloadFuture = apiClient
        .fetchBroadcast(username)
        .timeout(_broadcastFetchTimeout);
    final membersPayloadFuture = apiClient
        .fetchMembers(username)
        .timeout(_broadcastFetchTimeout);

    await initialDynamicFuture;
    Map<String, dynamic> camPayload;
    try {
      camPayload = await camPayloadFuture;
    } catch (error, stackTrace) {
      reportProviderDiagnostic(
        providerId: ProviderId.stripchat,
        scope: 'stripchat room detail',
        message: 'fetchCam failed for $username',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }

    Map<String, dynamic>? broadcastPayload;
    try {
      broadcastPayload = await broadcastPayloadFuture;
    } catch (error, stackTrace) {
      reportProviderDiagnostic(
        providerId: ProviderId.stripchat,
        scope: 'stripchat room detail',
        message:
            'fetchBroadcast failed for $username, detail will proceed without broadcast settings',
        error: error,
        stackTrace: stackTrace,
      );
    }

    Map<String, dynamic>? membersPayload;
    try {
      membersPayload = await membersPayloadFuture;
    } catch (error, stackTrace) {
      reportProviderDiagnostic(
        providerId: ProviderId.stripchat,
        scope: 'stripchat room detail',
        message:
            'fetchMembers failed for $username, detail will proceed without members data',
        error: error,
        stackTrace: stackTrace,
      );
    }

    return StripchatMapper.mapRoomDetail(
      roomId: roomId,
      camPayload: camPayload,
      broadcastPayload: broadcastPayload,
      membersPayload: membersPayload,
      userHash: _cachedGuestHash,
      csrfToken: _cachedCsrfToken,
      guestId: _cachedGuestId,
      initialDynamicPayload: _cachedInitialDynamic,
      requestCookie: apiClient.cookie,
    );
  }

  @override
  Future<List<LivePlayQuality>> fetchPlayQualities(
    LiveRoomDetail detail,
  ) async {
    final mapped = StripchatMapper.mapPlayQualities(detail);
    if (_isPlaybackBlocked(detail) ||
        mapped.any((quality) => quality.id.trim().toLowerCase() == 'source')) {
      return mapped;
    }
    final playbackUrls = await StripchatMapper.mapPlayUrls(
      detail: detail,
      quality: LivePlayQuality(id: 'auto', label: 'Auto', isDefault: true),
    );
    if (playbackUrls.isEmpty) {
      return mapped;
    }
    try {
      final variants = await apiClient.fetchPlaybackVariants(
        playbackUrls.first.url,
        headers: playbackUrls.first.headers,
      );
      if (variants.isEmpty) {
        return mapped;
      }
      return StripchatMapper.mapPlayQualities(
        detail,
        discoveredQualityIds: variants
            .map((variant) => variant.qualityId)
            .toList(growable: false),
      );
    } catch (error, stackTrace) {
      reportProviderDiagnostic(
        providerId: ProviderId.stripchat,
        scope: 'stripchat play qualities',
        message:
            'fetchPlaybackVariants failed room=${detail.roomId} stream=${detail.metadata?['streamName'] ?? '-'}',
        error: error,
        stackTrace: stackTrace,
      );
      return mapped;
    }
  }

  @override
  Future<List<LivePlayUrl>> fetchPlayUrls({
    required LiveRoomDetail detail,
    required LivePlayQuality quality,
  }) async {
    if (_isPlaybackBlocked(detail)) {
      return const <LivePlayUrl>[];
    }
    final urls = await StripchatMapper.mapPlayUrls(
      detail: detail,
      quality: quality,
    );
    if (urls.isEmpty) {
      return urls;
    }
    for (final candidate in urls) {
      final probe = await apiClient.probePlaybackPlaylist(
        candidate.url,
        headers: candidate.headers,
        preferredVariantId: candidate.metadata?['preferredVariantId']
            ?.toString(),
      );
      if (!probe.isPlayable) {
        reportProviderDiagnostic(
          providerId: ProviderId.stripchat,
          scope: 'stripchat playback probe',
          message:
              'rejecting non-playable playlist room=${detail.roomId} '
              'quality=${quality.id} finalUrl=${probe.finalUrl} reason=${probe.reason ?? '-'}',
        );
        continue;
      }
      return [
        _resolvedPlayUrl(candidate: candidate, quality: quality, probe: probe),
      ];
    }
    return const <LivePlayUrl>[];
  }

  LivePlayUrl _resolvedPlayUrl({
    required LivePlayUrl candidate,
    required LivePlayQuality quality,
    required StripchatPlaybackProbeResult probe,
  }) {
    final resolvedUrl = probe.finalUrl.toString();
    final metadata = <String, Object?>{
      ...?candidate.metadata,
      'masterPlaylistUrl': candidate.url,
      if (resolvedUrl.isNotEmpty && resolvedUrl != candidate.url)
        'resolvedPlaylistUrl': resolvedUrl,
      if (probe.body.trim().isNotEmpty) 'masterPlaylistContent': probe.body,
    };
    return LivePlayUrl(
      url: candidate.url,
      headers: candidate.headers,
      lineLabel: candidate.lineLabel,
      metadata: metadata,
    );
  }

  bool _isPlaybackBlocked(LiveRoomDetail detail) {
    final metadata = detail.metadata;
    if (metadata == null) {
      return false;
    }
    final reason =
        metadata['playbackUnavailableReason']?.toString().trim() ?? '';
    if (reason.isNotEmpty) {
      return true;
    }
    return false;
  }

  @override
  void close() {
    _initialDynamicFuture = null;
    _initialDynamicFetchedTime = null;
    _cachedInitialDynamic = null;
    _cachedGuestHash = null;
    _cachedCsrfToken = null;
    _cachedGuestId = null;
    apiClient.close();
  }
}
