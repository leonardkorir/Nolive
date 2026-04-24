import 'package:live_core/live_core.dart';

import 'chaturbate_api_client.dart';
import 'chaturbate_hls_master_playlist_parser.dart';
import 'chaturbate_room_page_parser.dart';

class ChaturbateMapper {
  const ChaturbateMapper._();

  static const int _startupMaxBandwidth = 2400000;
  static const int _startupMaxHeight = 540;

  static const String categoriesRootId = 'genders';
  static const List<LiveCategory> categories = [
    LiveCategory(
      id: categoriesRootId,
      name: 'Genders',
      children: [
        LiveSubCategory(
            id: 'female', parentId: categoriesRootId, name: 'Female'),
        LiveSubCategory(id: 'male', parentId: categoriesRootId, name: 'Male'),
        LiveSubCategory(
            id: 'couple', parentId: categoriesRootId, name: 'Couple'),
        LiveSubCategory(id: 'trans', parentId: categoriesRootId, name: 'Trans'),
      ],
    ),
  ];

  static LiveRoom mapRecommendRoom(Map<String, dynamic> payload) {
    return _mapRoom(
      payload,
      roomId: _firstNonEmpty([
        payload['room']?.toString(),
        payload['username']?.toString(),
      ]),
      viewerCount: _asInt(payload['viewers']),
    );
  }

  static LiveRoom mapSearchRoom(Map<String, dynamic> payload) {
    return _mapRoom(
      payload,
      roomId: _firstNonEmpty([
        payload['username']?.toString(),
        payload['room']?.toString(),
      ]),
      viewerCount: _asInt(payload['num_users']) ?? _asInt(payload['viewers']),
    );
  }

  static LiveRoom _mapRoom(
    Map<String, dynamic> payload, {
    required String roomId,
    required int? viewerCount,
  }) {
    final title = _firstNonEmpty([
      normalizeDisplayText(payload['room_subject']?.toString()),
      normalizeDisplayText(payload['subject']?.toString()),
      roomId,
    ]);

    return LiveRoom(
      providerId: ProviderId.chaturbate.value,
      roomId: roomId,
      title: title,
      streamerName: normalizeDisplayText(roomId),
      coverUrl: _nonEmptyString(payload['img']),
      areaName: _genderLabel(payload['gender']),
      viewerCount: viewerCount,
      isLive: true,
    );
  }

  static LiveRoomDetail mapRoomDetail(Map<String, dynamic> dossier) {
    return _mapRoomDetail(
      dossier: dossier,
      csrfToken: '',
      pushService: const {},
    );
  }

  static LiveRoomDetail mapRoomDetailFromPageContext(
    ChaturbateRoomPageContext context,
  ) {
    return _mapRoomDetail(
      dossier: context.dossier,
      csrfToken: context.csrfToken,
      pushService: context.primaryPushService,
    );
  }

  static LiveRoomDetail _mapRoomDetail({
    required Map<String, dynamic> dossier,
    required String csrfToken,
    required Map<String, dynamic> pushService,
  }) {
    final roomId = dossier['broadcaster_username']?.toString() ?? '';
    final broadcasterUid = dossier['broadcaster_uid']?.toString() ?? '';
    final roomUid = dossier['room_uid']?.toString() ?? '';
    final roomStatus = dossier['room_status']?.toString() ?? '';
    final edgeRegion = dossier['edge_region']?.toString() ?? '';
    final hlsSource = dossier['hls_source']?.toString() ?? '';
    final metadata = <String, Object?>{
      'roomStatus': roomStatus,
      'roomUid': roomUid,
      'broadcasterUid': broadcasterUid,
      'edgeRegion': edgeRegion,
      'allowPrivateShows': dossier['allow_private_shows'],
      'privateShowPrice': _asInt(dossier['private_show_price']),
      'spyPrivateShowPrice': _asInt(dossier['spy_private_show_price']),
      'hlsSource': hlsSource,
    };

    return LiveRoomDetail(
      providerId: ProviderId.chaturbate.value,
      roomId: roomId,
      title: _firstNonEmpty([
        normalizeDisplayText(dossier['room_title']?.toString()),
        roomId,
      ]),
      streamerName: normalizeDisplayText(roomId),
      areaName: _genderLabel(dossier['broadcaster_gender']),
      sourceUrl:
          roomId.isEmpty ? null : 'https://chaturbate.com/${roomId.trim()}/',
      isLive: roomStatus == 'public',
      viewerCount: _asInt(dossier['num_viewers']),
      danmakuToken: _buildDanmakuToken(
        roomId: roomId,
        broadcasterUid: broadcasterUid,
        roomUid: roomUid,
        csrfToken: csrfToken,
        pushService: pushService,
      ),
      metadata: metadata,
    );
  }

  static List<LivePlayQuality> mapPlayQualities(LiveRoomDetail detail) {
    final metadata = detail.metadata ?? const <String, Object?>{};
    final masterPlaylistUrl = metadata['hlsSource']?.toString().trim() ?? '';
    final masterPlaylistContent =
        metadata['hlsMasterPlaylistContent']?.toString() ?? '';
    final autoMetadata = <String, Object?>{};
    if (masterPlaylistUrl.isNotEmpty) {
      autoMetadata['masterPlaylistUrl'] = masterPlaylistUrl;
      autoMetadata['hlsBitrate'] = 'max';
    }
    if (masterPlaylistContent.trim().isNotEmpty) {
      autoMetadata['masterPlaylistContent'] = masterPlaylistContent;
    }
    return [
      LivePlayQuality(
        id: 'auto',
        label: 'Auto',
        isDefault: true,
        metadata: autoMetadata.isEmpty ? null : autoMetadata,
      ),
    ];
  }

  static List<LivePlayQuality> mapPlayQualitiesFromVariants({
    required List<ChaturbateHlsVariant> variants,
    String? fallbackPlaylistUrl,
    String? masterPlaylistContent,
  }) {
    final normalizedFallbackPlaylistUrl = fallbackPlaylistUrl?.trim() ?? '';
    final normalizedMasterPlaylistContent = masterPlaylistContent?.trim() ?? '';
    final startupVariant = _selectStartupVariant(variants);
    final autoMetadata = startupVariant == null
        ? <String, Object?>{}
        : _buildQualityMetadata(
            variant: startupVariant,
            fallbackPlaylistUrl: normalizedFallbackPlaylistUrl,
            masterPlaylistContent: normalizedMasterPlaylistContent,
          );
    if (normalizedFallbackPlaylistUrl.isNotEmpty) {
      autoMetadata['masterPlaylistUrl'] = normalizedFallbackPlaylistUrl;
      if (startupVariant == null) {
        autoMetadata['hlsBitrate'] = 'max';
      }
    }
    if (normalizedMasterPlaylistContent.isNotEmpty) {
      autoMetadata['masterPlaylistContent'] = normalizedMasterPlaylistContent;
    }
    final qualities = <LivePlayQuality>[
      LivePlayQuality(
        id: 'auto',
        label: 'Auto',
        isDefault: true,
        metadata: autoMetadata.isEmpty ? null : autoMetadata,
      ),
    ];
    for (final variant in variants) {
      final metadata = _buildQualityMetadata(
        variant: variant,
        fallbackPlaylistUrl: normalizedFallbackPlaylistUrl,
        masterPlaylistContent: normalizedMasterPlaylistContent,
      );
      qualities.add(
        LivePlayQuality(
          id: variant.bandwidth.toString(),
          label: variant.label,
          sortOrder: variant.sortOrder,
          metadata: metadata,
        ),
      );
    }
    return qualities;
  }

  static ChaturbateHlsVariant? _selectStartupVariant(
    List<ChaturbateHlsVariant> variants,
  ) {
    if (variants.isEmpty) {
      return null;
    }
    for (final variant in variants) {
      if (_isStartupSafeVariant(variant)) {
        return variant;
      }
    }
    final ascending = [...variants]..sort((left, right) {
        final compare = left.sortOrder.compareTo(right.sortOrder);
        if (compare != 0) {
          return compare;
        }
        return left.bandwidth.compareTo(right.bandwidth);
      });
    return ascending.first;
  }

  static bool _isStartupSafeVariant(ChaturbateHlsVariant variant) {
    final height = variant.height ?? 0;
    if (height > 0 && height <= _startupMaxHeight) {
      return true;
    }
    final bandwidth = variant.bandwidth;
    return bandwidth > 0 && bandwidth <= _startupMaxBandwidth;
  }

  static List<LivePlayUrl> mapPlayUrls(
    LiveRoomDetail detail,
    LivePlayQuality quality,
  ) {
    final metadata = detail.metadata ?? const <String, Object?>{};
    final initialVariantPlaylistUrl = _firstNonEmpty([
      quality.metadata?['playlistUrl']?.toString(),
    ]);
    final masterPlaylistUrl = _firstNonEmpty([
      quality.metadata?['masterPlaylistUrl']?.toString(),
      metadata['hlsSource']?.toString(),
    ]);
    final masterPlaylistContent = _firstNonEmpty([
      quality.metadata?['masterPlaylistContent']?.toString(),
      metadata['hlsMasterPlaylistContent']?.toString(),
    ]);
    final derivedVariant = initialVariantPlaylistUrl.isNotEmpty
        ? null
        : _resolveVariantFromMasterPlaylist(
            quality: quality,
            masterPlaylistUrl: masterPlaylistUrl,
            masterPlaylistContent: masterPlaylistContent,
          );
    final variantPlaylistUrl = _firstNonEmpty([
      initialVariantPlaylistUrl,
      derivedVariant?.url,
    ]);
    final preferMasterPlaylist = _shouldPreferMasterPlaylistForPlayback(
      variantPlaylistUrl: variantPlaylistUrl,
      masterPlaylistUrl: masterPlaylistUrl,
      qualityMetadata: quality.metadata,
    );
    final useMasterPlaylist = masterPlaylistUrl.isNotEmpty &&
        (variantPlaylistUrl.isEmpty || preferMasterPlaylist);
    final selectedUrl =
        useMasterPlaylist ? masterPlaylistUrl : variantPlaylistUrl;
    if (selectedUrl.isEmpty) {
      return const [];
    }

    final edgeRegion = metadata['edgeRegion']?.toString() ?? '';
    final playbackHeaders = _buildPlaybackHeaders(detail);
    final derivedAudioUrl = derivedVariant?.audioUrl?.trim() ?? '';
    final derivedBandwidth = derivedVariant?.bandwidth ?? 0;
    final playMetadata = <String, Object?>{
      ...?quality.metadata,
      if (derivedVariant != null) 'playlistUrl': derivedVariant.url,
      if (masterPlaylistUrl.isNotEmpty) 'masterPlaylistUrl': masterPlaylistUrl,
      if (masterPlaylistContent.isNotEmpty)
        'masterPlaylistContent': masterPlaylistContent,
      if (derivedVariant != null && derivedBandwidth > 0)
        'bandwidth': derivedBandwidth,
      if (derivedVariant?.width != null) 'width': derivedVariant!.width,
      if (derivedVariant?.height != null) 'height': derivedVariant!.height,
      if (useMasterPlaylist &&
          (quality.metadata?['hlsBitrate']?.toString().trim().isEmpty ?? true))
        'hlsBitrate': quality.id == 'auto'
            ? 'max'
            : quality.metadata?['bandwidth']?.toString(),
      if (!useMasterPlaylist &&
          derivedVariant != null &&
          (quality.metadata?['hlsBitrate']?.toString().trim().isEmpty ??
              true) &&
          derivedBandwidth > 0)
        'hlsBitrate': derivedBandwidth.toString(),
      if (useMasterPlaylist && variantPlaylistUrl.isNotEmpty)
        'resolvedVariantUrl': variantPlaylistUrl,
      if (!useMasterPlaylist &&
          ((quality.metadata?['audioUrl']?.toString().trim().isNotEmpty ??
                  false) ||
              derivedAudioUrl.isNotEmpty))
        'audioHeaders': playbackHeaders,
      if (!useMasterPlaylist && derivedAudioUrl.isNotEmpty)
        'audioUrl': derivedAudioUrl,
      if (!useMasterPlaylist && derivedAudioUrl.isNotEmpty)
        'audioMimeType': 'application/x-mpegURL',
      if (!useMasterPlaylist && derivedVariant?.audioGroupId != null)
        'audioGroupId': derivedVariant!.audioGroupId,
    };
    if (useMasterPlaylist) {
      playMetadata
        ..remove('audioUrl')
        ..remove('audioHeaders')
        ..remove('audioMimeType')
        ..remove('audioGroupId');
    }
    return [
      LivePlayUrl(
        url: selectedUrl,
        headers: playbackHeaders,
        lineLabel: edgeRegion.isEmpty ? null : edgeRegion,
        metadata: playMetadata,
      ),
    ];
  }

  static bool _shouldPreferMasterPlaylistForPlayback({
    required String variantPlaylistUrl,
    required String masterPlaylistUrl,
    required Map<String, Object?>? qualityMetadata,
  }) {
    if (variantPlaylistUrl.isEmpty || masterPlaylistUrl.isEmpty) {
      return false;
    }
    final audioUrl = qualityMetadata?['audioUrl']?.toString().trim() ?? '';
    if (audioUrl.isEmpty) {
      return _looksLikeMmcdnLegacyChunklistPlaybackUrl(variantPlaylistUrl) &&
          _looksLikeMmcdnLegacyMasterPlaylistUrl(masterPlaylistUrl);
    }
    final uri = Uri.tryParse(masterPlaylistUrl);
    if (uri == null) {
      return masterPlaylistUrl.contains('/v1/edge/streams/') &&
          masterPlaylistUrl.contains('llhls.m3u8');
    }
    // Browsers currently resolve the v1/edge LL-HLS master into split
    // video/audio chunklists. Treat the master as metadata for later refresh
    // or diagnostics, but keep playback pinned to the resolved split variant.
    return false;
  }

  static bool _looksLikeMmcdnLegacyChunklistPlaybackUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return false;
    }
    final host = uri.host.trim().toLowerCase();
    final path = uri.path.trim().toLowerCase();
    return host.endsWith('live.mmcdn.com') &&
        path.contains('/live-hls/amlst:') &&
        path.contains('chunklist_') &&
        path.endsWith('.m3u8');
  }

  static bool _looksLikeMmcdnLegacyMasterPlaylistUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return false;
    }
    final host = uri.host.trim().toLowerCase();
    final path = uri.path.trim().toLowerCase();
    return host.endsWith('live.mmcdn.com') &&
        path.contains('/live-hls/amlst:') &&
        path.endsWith('playlist.m3u8');
  }

  static ChaturbateHlsVariant? _resolveVariantFromMasterPlaylist({
    required LivePlayQuality quality,
    required String masterPlaylistUrl,
    required String masterPlaylistContent,
  }) {
    if (masterPlaylistUrl.isEmpty || masterPlaylistContent.trim().isEmpty) {
      return null;
    }
    final variants = const ChaturbateHlsMasterPlaylistParser().parse(
      playlistUrl: masterPlaylistUrl,
      source: masterPlaylistContent,
    );
    if (variants.isEmpty) {
      return null;
    }
    return _selectVariantForQuality(
      quality: quality,
      variants: variants,
    );
  }

  static ChaturbateHlsVariant? _selectVariantForQuality({
    required LivePlayQuality quality,
    required List<ChaturbateHlsVariant> variants,
  }) {
    if (variants.isEmpty) {
      return null;
    }
    if (quality.id.trim().toLowerCase() == 'auto') {
      return _selectStartupVariant(variants);
    }
    final requestedBandwidth = int.tryParse(quality.id.trim());
    if (requestedBandwidth != null) {
      for (final variant in variants) {
        if (variant.bandwidth == requestedBandwidth) {
          return variant;
        }
      }
      variants.sort((left, right) {
        final leftDelta = (left.bandwidth - requestedBandwidth).abs();
        final rightDelta = (right.bandwidth - requestedBandwidth).abs();
        final compare = leftDelta.compareTo(rightDelta);
        if (compare != 0) {
          return compare;
        }
        return left.bandwidth.compareTo(right.bandwidth);
      });
      return variants.first;
    }
    final requestedLabel = quality.label.trim().toLowerCase();
    if (requestedLabel.isNotEmpty) {
      for (final variant in variants) {
        if (variant.label.trim().toLowerCase() == requestedLabel) {
          return variant;
        }
      }
    }
    return variants.first;
  }

  static Map<String, String> _buildPlaybackHeaders(LiveRoomDetail detail) {
    return HttpChaturbateApiClient.buildPlaybackHeaders(
      referer: detail.sourceUrl ?? 'https://chaturbate.com/',
    );
  }

  static Map<String, Object?> _buildQualityMetadata({
    required ChaturbateHlsVariant variant,
    required String fallbackPlaylistUrl,
    required String masterPlaylistContent,
  }) {
    final metadata = <String, Object?>{
      'playlistUrl': variant.url,
      'bandwidth': variant.bandwidth,
      'width': variant.width,
      'height': variant.height,
    };
    if (fallbackPlaylistUrl.isNotEmpty) {
      metadata['masterPlaylistUrl'] = fallbackPlaylistUrl;
    }
    if (masterPlaylistContent.isNotEmpty) {
      metadata['masterPlaylistContent'] = masterPlaylistContent;
    }
    if (variant.bandwidth > 0) {
      metadata['hlsBitrate'] = variant.bandwidth.toString();
    }
    final audioUrl = variant.audioUrl?.trim() ?? '';
    if (audioUrl.isNotEmpty) {
      metadata['audioGroupId'] = variant.audioGroupId;
      metadata['audioUrl'] = audioUrl;
      metadata['audioMimeType'] = 'application/x-mpegURL';
    }
    return metadata;
  }

  static String? genderQueryForCategory(LiveSubCategory category) {
    return switch (category.id.trim().toLowerCase()) {
      'female' => 'f',
      'male' => 'm',
      'couple' => 'c',
      'trans' => 't',
      _ => null,
    };
  }

  static LiveMessage? mapDanmakuPayload(Map<String, dynamic> payload) {
    final topic = _resolveTopic(payload);
    final event = _unwrapEvent(payload);
    final timestamp = _asDateTime(event['pub_ts'] ?? event['ts']);
    switch (topic) {
      case 'RoomMessageTopic':
        final content = normalizeDisplayText(event['message']?.toString());
        if (content.isEmpty) {
          return null;
        }
        final fromUser = _asMap(event['from_user']);
        final userName = _nonEmptyString(
          _firstNonEmpty([
            fromUser['username']?.toString(),
            event['from_username']?.toString(),
          ]),
        );
        return LiveMessage(
          type: LiveMessageType.chat,
          userName: userName,
          content: content,
          timestamp: timestamp,
          payload: event,
        );
      case 'RoomTipAlertTopic':
        final amount = _asInt(event['amount']);
        final note = normalizeDisplayText(event['message']?.toString());
        final content = note.isEmpty
            ? amount == null
                ? '送出打赏'
                : '送出 $amount tokens'
            : amount == null
                ? '送出打赏 · $note'
                : '送出 $amount tokens · $note';
        return LiveMessage(
          type: LiveMessageType.gift,
          userName: _nonEmptyString(event['from_username']),
          content: content,
          timestamp: timestamp,
          payload: event,
        );
      case 'RoomNoticeTopic':
        final messages = _asList(event['messages'])
            .map((item) => normalizeDisplayText(item?.toString()))
            .where((item) => item.isNotEmpty)
            .toList(growable: false);
        final content = messages.isNotEmpty
            ? messages.join(' ')
            : normalizeDisplayText(event['message']?.toString());
        if (content.isEmpty) {
          return null;
        }
        return LiveMessage(
          type: LiveMessageType.notice,
          content: content,
          timestamp: timestamp,
          payload: event,
        );
      case 'RoomFanClubJoinedTopic':
        final userName = _nonEmptyString(event['from_username']);
        return LiveMessage(
          type: LiveMessageType.member,
          userName: userName,
          content: userName == null ? '有用户加入粉丝团' : '$userName 加入了粉丝团',
          timestamp: timestamp,
          payload: event,
        );
      case 'RoomPurchaseTopic':
        final userName = _nonEmptyString(event['from_username']);
        final content = _firstNonEmpty([
          normalizeDisplayText(event['message']?.toString()),
          '购买了房间内容',
        ]);
        return LiveMessage(
          type: LiveMessageType.notice,
          userName: userName,
          content: content,
          timestamp: timestamp,
          payload: event,
        );
      default:
        final content = _firstNonEmpty([
          normalizeDisplayText(event['message']?.toString()),
          normalizeDisplayText(_asList(event['messages']).join(' ')),
        ]);
        if (content.isEmpty) {
          return null;
        }
        return LiveMessage(
          type: LiveMessageType.notice,
          content: content,
          timestamp: timestamp,
          payload: event,
        );
    }
  }

  static String? dedupeKeyForDanmakuPayload(Map<String, dynamic> payload) {
    final event = _unwrapEvent(payload);
    return _nonEmptyString(
      _firstNonEmpty([
        event['tid']?.toString(),
        event['id']?.toString(),
      ]),
    );
  }

  static Map<String, Object?>? _buildDanmakuToken({
    required String roomId,
    required String broadcasterUid,
    required String roomUid,
    required String csrfToken,
    required Map<String, dynamic> pushService,
  }) {
    if (roomId.isEmpty || broadcasterUid.isEmpty || csrfToken.isEmpty) {
      return null;
    }
    return {
      'roomId': roomId,
      'roomUid': roomUid,
      'broadcasterUid': broadcasterUid,
      'csrfToken': csrfToken,
      'backend': _firstNonEmpty([
        pushService['backend']?.toString(),
        'a',
      ]),
      'host': _nonEmptyString(pushService['host']),
      'restHost': _nonEmptyString(pushService['rest_host']),
      'fallbackHosts': _asList(pushService['fallback_hosts'])
          .map((item) => item?.toString() ?? '')
          .where((item) => item.isNotEmpty)
          .toList(growable: false),
    };
  }

  static String _resolveTopic(Map<String, dynamic> payload) {
    final event = _unwrapEvent(payload);
    final topic = event['_topic']?.toString().trim() ?? '';
    if (topic.isNotEmpty) {
      return topic;
    }
    if (payload.length == 1) {
      final key = payload.keys.single;
      return key.split('#').first;
    }
    return '';
  }

  static Map<String, dynamic> _unwrapEvent(Map<String, dynamic> payload) {
    if (payload.length == 1) {
      final entry = payload.entries.single;
      final value = _asMap(entry.value);
      if (value.isNotEmpty) {
        return value;
      }
    }
    return payload;
  }

  static String _firstNonEmpty(List<String?> values) {
    for (final value in values) {
      final trimmed = value?.trim() ?? '';
      if (trimmed.isNotEmpty) {
        return trimmed;
      }
    }
    return '';
  }

  static String? _genderLabel(Object? rawGender) {
    final value = rawGender?.toString().trim().toLowerCase() ?? '';
    return switch (value) {
      'f' || 'female' => 'Female',
      'm' || 'male' => 'Male',
      'c' || 'couple' => 'Couple',
      's' || 'trans' => 'Trans',
      _ => null,
    };
  }

  static String? _nonEmptyString(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  static List<dynamic> _asList(Object? value) {
    if (value is List) {
      return value;
    }
    return const [];
  }

  static Map<String, dynamic> _asMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.cast<String, dynamic>();
    }
    return const {};
  }

  static int? _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '');
  }

  static DateTime? _asDateTime(Object? value) {
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch((value * 1000).round());
    }
    final parsed = num.tryParse(value?.toString() ?? '');
    if (parsed == null) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch((parsed * 1000).round());
  }
}
