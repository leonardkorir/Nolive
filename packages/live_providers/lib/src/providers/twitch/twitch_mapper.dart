import 'package:live_core/live_core.dart';

import 'twitch_hls_master_playlist_parser.dart';
import 'twitch_playback_manifest.dart';

class TwitchMapper {
  const TwitchMapper._();

  static LiveRoom mapRecommendRoom(Map<String, dynamic> payload) {
    final broadcaster = _asMap(payload['broadcaster']);
    final settings = _asMap(broadcaster['broadcastSettings']);
    final game = _asMap(payload['game']);
    final roomId = _firstNonEmpty([
      broadcaster['login']?.toString(),
      broadcaster['displayName']?.toString(),
    ]);
    return LiveRoom(
      providerId: ProviderId.twitch.value,
      roomId: roomId,
      title: _firstNonEmpty([
        normalizeDisplayText(settings['title']?.toString()),
        normalizeDisplayText(broadcaster['displayName']?.toString()),
        roomId,
      ]),
      streamerName: _firstNonEmpty([
        normalizeDisplayText(broadcaster['displayName']?.toString()),
        roomId,
      ]),
      coverUrl: _nonEmptyString(broadcaster['profileImageURL']),
      streamerAvatarUrl: _nonEmptyString(broadcaster['profileImageURL']),
      areaName: _firstNonEmpty([
        normalizeDisplayText(game['displayName']?.toString()),
        normalizeDisplayText(game['name']?.toString()),
      ]),
      viewerCount: _asInt(payload['viewersCount']),
      isLive: (payload['type']?.toString().toLowerCase() ?? '') == 'live',
    );
  }

  static LiveRoom mapSearchRoom(Map<String, dynamic> payload) {
    final stream = _asMap(payload['stream']);
    final settings = _asMap(payload['broadcastSettings']);
    final game = _asMap(stream['game']);
    final roomId = _firstNonEmpty([
      payload['login']?.toString(),
      payload['displayName']?.toString(),
    ]);
    final isLive = stream.isNotEmpty;
    return LiveRoom(
      providerId: ProviderId.twitch.value,
      roomId: roomId,
      title: _firstNonEmpty([
        normalizeDisplayText(settings['title']?.toString()),
        normalizeDisplayText(payload['displayName']?.toString()),
        roomId,
      ]),
      streamerName: _firstNonEmpty([
        normalizeDisplayText(payload['displayName']?.toString()),
        roomId,
      ]),
      coverUrl: _firstNonEmpty([
        stream['previewImageURL']?.toString(),
        payload['profileImageURL']?.toString(),
      ]),
      streamerAvatarUrl: _nonEmptyString(payload['profileImageURL']),
      areaName: _firstNonEmpty([
        normalizeDisplayText(game['displayName']?.toString()),
        normalizeDisplayText(game['name']?.toString()),
      ]),
      viewerCount: _asInt(stream['viewersCount']),
      isLive: isLive,
    );
  }

  static LiveRoom mapBrowseRoom(Map<String, dynamic> payload) {
    final broadcaster = _asMap(payload['broadcaster']);
    final game = _asMap(payload['game']);
    final roomId = _firstNonEmpty([
      broadcaster['login']?.toString(),
      broadcaster['displayName']?.toString(),
    ]);
    return LiveRoom(
      providerId: ProviderId.twitch.value,
      roomId: roomId,
      title: _firstNonEmpty([
        normalizeDisplayText(payload['title']?.toString()),
        normalizeDisplayText(broadcaster['displayName']?.toString()),
        roomId,
      ]),
      streamerName: _firstNonEmpty([
        normalizeDisplayText(broadcaster['displayName']?.toString()),
        roomId,
      ]),
      coverUrl: _firstNonEmpty([
        payload['previewImageURL']?.toString(),
        broadcaster['profileImageURL']?.toString(),
      ]),
      streamerAvatarUrl: _nonEmptyString(broadcaster['profileImageURL']),
      areaName: _firstNonEmpty([
        normalizeDisplayText(game['displayName']?.toString()),
        normalizeDisplayText(game['name']?.toString()),
      ]),
      viewerCount: _asInt(payload['viewersCount']),
      isLive: true,
    );
  }

  static LiveRoomDetail mapRoomDetail({
    required String login,
    required Map<String, dynamic> channelShell,
    required Map<String, dynamic> streamMetadata,
    required Map<String, dynamic> viewCount,
    required Map<String, dynamic> liveBroadcast,
  }) {
    final shellUser = _asMap(_asMap(channelShell['data'])['userOrError']);
    final metadataUser = _asMap(_asMap(streamMetadata['data'])['user']);
    final liveUser = _asMap(_asMap(viewCount['data'])['user']);
    final broadcastUser = _asMap(_asMap(liveBroadcast['data'])['user']);
    final stream = _asMap(metadataUser['stream']);
    final viewStream = _asMap(liveUser['stream']);
    final lastBroadcast = _asMap(broadcastUser['lastBroadcast']);
    final game = _asMap(lastBroadcast['game']).isNotEmpty
        ? _asMap(lastBroadcast['game'])
        : _asMap(stream['game']);
    final roomId = _firstNonEmpty([
      shellUser['login']?.toString(),
      login,
    ]);
    final metadata = <String, Object?>{
      'channelId': _firstNonEmpty([
        shellUser['id']?.toString(),
        metadataUser['id']?.toString(),
      ]),
      'login': roomId,
      'primaryColorHex': metadataUser['primaryColorHex'],
      'bannerImageUrl': shellUser['bannerImageURL'],
    };
    return LiveRoomDetail(
      providerId: ProviderId.twitch.value,
      roomId: roomId,
      title: _firstNonEmpty([
        normalizeDisplayText(lastBroadcast['title']?.toString()),
        normalizeDisplayText(
            _asMap(metadataUser['lastBroadcast'])['title']?.toString()),
        roomId,
      ]),
      streamerName: _firstNonEmpty([
        normalizeDisplayText(shellUser['displayName']?.toString()),
        roomId,
      ]),
      streamerAvatarUrl: _nonEmptyString(shellUser['profileImageURL']),
      coverUrl: _nonEmptyString(shellUser['bannerImageURL']),
      areaName: _firstNonEmpty([
        normalizeDisplayText(game['displayName']?.toString()),
        normalizeDisplayText(game['name']?.toString()),
      ]),
      description: normalizeDisplayText(shellUser['description']?.toString()),
      sourceUrl: roomId.isEmpty ? null : 'https://www.twitch.tv/$roomId',
      startedAt: _asDateTime(stream['createdAt']),
      isLive: (stream['type']?.toString().toLowerCase() ?? '') == 'live',
      viewerCount: _asInt(viewStream['viewersCount']),
      danmakuToken: roomId.isEmpty ? null : {'roomId': roomId},
      metadata: metadata,
    );
  }

  static List<LivePlayQuality> mapPlayQualitiesFromVariants({
    required List<TwitchHlsVariant> variants,
    required String masterPlaylistUrl,
    required Map<String, String> headers,
    List<TwitchPlaybackCandidate> masterCandidates = const [],
    List<TwitchPlaybackQualityGroup> candidateGroups = const [],
  }) {
    final resolvedMasterCandidates = masterCandidates.isEmpty
        ? [
            TwitchPlaybackCandidate(
              playlistUrl: masterPlaylistUrl,
              headers: headers,
              playerType: 'popout',
              platform: 'web',
              lineLabel: '默认 Popout',
            ),
          ]
        : masterCandidates;
    final resolvedCandidateGroups = candidateGroups.isEmpty
        ? variants
            .map(
              (variant) => TwitchPlaybackQualityGroup(
                id: variant.stableVariantId?.trim().isNotEmpty == true
                    ? variant.stableVariantId!.trim()
                    : variant.bandwidth.toString(),
                label: variant.label,
                sortOrder: variant.sortOrder,
                bandwidth: variant.bandwidth,
                width: variant.width,
                height: variant.height,
                frameRate: variant.frameRate,
                codecs: variant.codecs,
                candidates: [
                  TwitchPlaybackCandidate(
                    playlistUrl: variant.url,
                    headers: headers,
                    playerType: 'popout',
                    platform: 'web',
                    lineLabel: '默认 Popout',
                    source: variant.source,
                    bandwidth: variant.bandwidth,
                    width: variant.width,
                    height: variant.height,
                    frameRate: variant.frameRate,
                    codecs: variant.codecs,
                  ),
                ],
              ),
            )
            .toList(growable: false)
        : candidateGroups;
    final qualities = <LivePlayQuality>[
      LivePlayQuality(
        id: 'auto',
        label: 'Auto',
        isDefault: true,
        metadata: {
          'playlistUrl': masterPlaylistUrl,
          'headers': headers,
          'twitchPlaybackCandidates':
              resolvedMasterCandidates.map((item) => item.toJson()).toList(),
          'twitchPlaybackGroups':
              resolvedCandidateGroups.map((item) => item.toJson()).toList(),
        },
      ),
    ];
    for (final group in resolvedCandidateGroups) {
      qualities.add(
        LivePlayQuality(
          id: group.id,
          label: group.label,
          sortOrder: group.sortOrder,
          metadata: {
            'playlistUrl': group.candidates.first.playlistUrl,
            'headers': group.candidates.first.headers,
            'bandwidth': group.bandwidth,
            'source': group.candidates.first.source,
            'width': group.width,
            'height': group.height,
            'frameRate': group.frameRate,
            'codecs': group.codecs,
            'twitchPlaybackGroup': group.toJson(),
          },
        ),
      );
    }
    return qualities;
  }

  static List<LivePlayUrl> mapPlayUrls(
    LiveRoomDetail detail,
    LivePlayQuality quality,
  ) {
    final playbackGroup = TwitchPlaybackQualityGroup.fromJson(
      quality.metadata?['twitchPlaybackGroup'],
    );
    if (playbackGroup != null) {
      return playbackGroup.candidates
          .map(
            (candidate) => LivePlayUrl(
              url: candidate.playlistUrl,
              headers: candidate.headers,
              lineLabel: candidate.lineLabel,
              metadata: {
                'playerType': candidate.playerType,
                'platform': candidate.platform,
                'source': candidate.source,
                'bandwidth': candidate.bandwidth,
                'width': candidate.width,
                'height': candidate.height,
                'frameRate': candidate.frameRate,
                'codecs': candidate.codecs,
              },
            ),
          )
          .toList(growable: false);
    }
    final playbackCandidates = TwitchPlaybackCandidate.listFromJson(
      quality.metadata?['twitchPlaybackCandidates'],
    );
    if (playbackCandidates.isNotEmpty) {
      return playbackCandidates
          .map(
            (candidate) => LivePlayUrl(
              url: candidate.playlistUrl,
              headers: candidate.headers,
              lineLabel: candidate.lineLabel,
              metadata: {
                'playerType': candidate.playerType,
                'platform': candidate.platform,
                'source': candidate.source,
                'bandwidth': candidate.bandwidth,
                'width': candidate.width,
                'height': candidate.height,
                'frameRate': candidate.frameRate,
                'codecs': candidate.codecs,
              },
            ),
          )
          .toList(growable: false);
    }
    final selectedUrl = quality.metadata?['playlistUrl']?.toString().trim() ??
        detail.metadata?['masterPlaylistUrl']?.toString().trim() ??
        '';
    if (selectedUrl.isEmpty) {
      return const [];
    }
    final headers = _readHeaders(quality.metadata?['headers']);
    final source = quality.metadata?['source']?.toString().trim();
    return [
      LivePlayUrl(
        url: selectedUrl,
        headers: headers,
        lineLabel: source?.isEmpty ?? true ? null : source,
        metadata: quality.metadata,
      ),
    ];
  }

  static Map<String, String> _readHeaders(Object? raw) {
    if (raw is Map<String, String>) {
      return raw;
    }
    if (raw is Map) {
      final headers = <String, String>{};
      for (final entry in raw.entries) {
        final key = entry.key.toString().trim();
        final value = entry.value?.toString().trim() ?? '';
        if (key.isEmpty || value.isEmpty) {
          continue;
        }
        headers[key] = value;
      }
      return headers;
    }
    return const {};
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

  static String? _nonEmptyString(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  static String _firstNonEmpty(List<String?> values) {
    for (final value in values) {
      final normalized = value?.trim() ?? '';
      if (normalized.isNotEmpty) {
        return normalized;
      }
    }
    return '';
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
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw)?.toLocal();
  }
}
