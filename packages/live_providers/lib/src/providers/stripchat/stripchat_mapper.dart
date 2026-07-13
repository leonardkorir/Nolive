import 'package:live_core/live_core.dart';

import '../provider_json.dart';

class StripchatMapper {
  const StripchatMapper._();

  static const String defaultCdnDomain = 'doppiocdn.org';
  static const String _imageCdnBase = 'https://static-proxy.strpst.com';
  static const String _originHost = 'zh.stripchat.com';

  static const Map<String, String> _categoryNames = {'ethnicity': '种族'};

  static const List<_CountryRegion> _countryRegions = [
    _CountryRegion('country-asia_pacific', '亚洲 & 太平洋', [
      'tagLanguageAustralian',
      'tagLanguageFilipino',
      'tagLanguageKorean',
      'tagLanguageJapanese',
      'tagLanguageSriLankan',
      'tagLanguageThai',
      'tagLanguageIndian',
      'tagLanguageVietnamese',
      'tagLanguageChinese',
      'tagLanguageIndonesian',
      'tagLanguageTaiwanese',
    ]),
    _CountryRegion('country-north_america', '北美', [
      'tagLanguageCanadian',
      'tagLanguageUSModels',
      'tagLanguageMexican',
    ]),
    _CountryRegion('country-south_america', '南美', [
      'tagLanguageArgentinian',
      'tagLanguageBrazilian',
      'tagLanguageChilean',
      'tagLanguageColombian',
      'tagLanguageCostaRican',
      'tagLanguageDominican',
      'tagLanguageEcuadorian',
      'tagLanguageJamaican',
      'tagLanguagePeruvian',
      'tagLanguageVenezuelan',
    ]),
    _CountryRegion('country-europe', '欧洲', [
      'tagLanguageAustrian',
      'tagLanguageBelgian',
      'tagLanguageBulgarian',
      'tagLanguageCzech',
      'tagLanguageDutch',
      'tagLanguageFrench',
      'tagLanguageGermanSpeaking',
      'tagLanguageGreek',
      'tagLanguageHungarian',
      'tagLanguageIrish',
      'tagLanguageItalian',
      'tagLanguageNordic',
      'tagLanguagePolish',
      'tagLanguagePortugueseSpeaking',
      'tagLanguageRomanian',
      'tagLanguageRussianSpeaking',
      'tagLanguageSerbian',
      'tagLanguageSpanish',
      'tagLanguageSpanishSpeaking',
      'tagLanguageSwedish',
      'tagLanguageSwiss',
      'tagLanguageUKModels',
      'tagLanguageUkrainian',
    ]),
    _CountryRegion('country-africa', '非洲', [
      'tagLanguageAfrican',
      'tagLanguageKenyan',
      'tagLanguageSouthAfrican',
      'tagLanguageUgandan',
      'tagLanguageZimbabwean',
    ]),
    _CountryRegion('country-middle_east', '中东', ['tagLanguageTurkish']),
    _CountryRegion('country-other', '其他', [
      'tagLanguageAssamese',
      'tagLanguageBangladeshi',
      'tagLanguageBengali',
      'tagLanguageGujarati',
      'tagLanguageHindi',
      'tagLanguageKannada',
      'tagLanguageMalayalam',
      'tagLanguageMarathi',
      'tagLanguagePunjabi',
      'tagLanguageTamil',
      'tagLanguageTelugu',
    ]),
  ];

  static const Map<String, String> _subCategoryNames = {
    // 种族 (ethnicity)
    'ethnicityMiddleEastern': '阿拉伯人',
    'ethnicityAsian': '亚洲人',
    'ethnicityEbony': '黑珍珠',
    'ethnicityIndian': '印度人',
    'ethnicityLatino': '拉丁人',
    'ethnicityMultiracial': '混血主播',
    'ethnicityWhite': '白人',

    // 亚洲 & 太平洋
    'tagLanguageAustralian': '澳大利亚人',
    'tagLanguageFilipino': '菲律宾',
    'tagLanguageKorean': '韩语',
    'tagLanguageJapanese': '日语',
    'tagLanguageSriLankan': '斯里兰卡人',
    'tagLanguageThai': '泰语',
    'tagLanguageIndian': '印度人',
    'tagLanguageVietnamese': '越语',
    'tagLanguageChinese': '中文',
    'tagLanguageIndonesian': '印度尼西亚人',
    'tagLanguageTaiwanese': '台湾人',

    // 北美
    'tagLanguageCanadian': '加拿大人',
    'tagLanguageUSModels': '美国人',
    'tagLanguageMexican': '墨西哥人',

    // 南美
    'tagLanguageArgentinian': '阿根廷人',
    'tagLanguageBrazilian': '巴西人',
    'tagLanguageChilean': '智利人',
    'tagLanguageColombian': '哥伦比亚人',
    'tagLanguageCostaRican': '哥斯达黎加人',
    'tagLanguageDominican': '多米尼加人',
    'tagLanguageEcuadorian': '厄瓜多尔人',
    'tagLanguageJamaican': '牙买加人',
    'tagLanguagePeruvian': '秘鲁人',
    'tagLanguageVenezuelan': '委内瑞拉人',

    // 欧洲
    'tagLanguageAustrian': '奥地利人',
    'tagLanguageBelgian': '比利时人',
    'tagLanguageBulgarian': '保加利亚人',
    'tagLanguageCzech': '捷克语',
    'tagLanguageDutch': '荷兰语',
    'tagLanguageFrench': '法语',
    'tagLanguageGermanSpeaking': '德语',
    'tagLanguageGreek': '希腊人',
    'tagLanguageHungarian': '匈牙利语',
    'tagLanguageIrish': '爱尔兰人',
    'tagLanguageItalian': '意大利语',
    'tagLanguageNordic': '北欧',
    'tagLanguagePolish': '波兰语',
    'tagLanguagePortugueseSpeaking': '说葡萄牙语',
    'tagLanguageRomanian': '罗马尼亚语',
    'tagLanguageRussianSpeaking': '俄国人',
    'tagLanguageSerbian': '塞尔维亚语',
    'tagLanguageSpanish': '西班牙语',
    'tagLanguageSpanishSpeaking': '西班牙人',
    'tagLanguageSwedish': '瑞语',
    'tagLanguageSwiss': '瑞士人',
    'tagLanguageUKModels': '英国主播',
    'tagLanguageUkrainian': '乌克兰女主播',

    // 非洲
    'tagLanguageAfrican': '非洲裔',
    'tagLanguageKenyan': '肯尼亚人',
    'tagLanguageSouthAfrican': '南非人',
    'tagLanguageUgandan': '乌干达',
    'tagLanguageZimbabwean': '津巴布韦人',

    // 中东
    'tagLanguageTurkish': '土耳其语',

    // 其他
    'tagLanguageAssamese': '阿萨姆语',
    'tagLanguageBangladeshi': '孟加拉人',
    'tagLanguageBengali': '孟加拉语',
    'tagLanguageGujarati': '古吉拉特语',
    'tagLanguageHindi': '印地语',
    'tagLanguageKannada': '卡纳达语',
    'tagLanguageMalayalam': '马拉雅拉姆语',
    'tagLanguageMarathi': '马拉地语',
    'tagLanguagePunjabi': '旁遮普语',
    'tagLanguageTamil': '泰米尔语',
    'tagLanguageTelugu': '泰卢固语',
  };

  static String _categoryName(String alias) => _categoryNames[alias] ?? alias;
  static String _subCategoryName(String tagId) =>
      _subCategoryNames[tagId] ?? tagId;

  static List<LiveCategory> mapCategories(Map<String, dynamic> payload) {
    final tagGroups = ProviderJson.asList(payload['liveTagGroups']);
    final tagDetails = ProviderJson.asMap(payload['liveTagDetails']);
    final categories = <LiveCategory>[];

    for (final region in _countryRegions) {
      final children = <LiveSubCategory>[];
      for (final tagId in region.tagIds) {
        if (tagDetails.containsKey(tagId)) {
          children.add(
            LiveSubCategory(
              id: tagId,
              parentId: region.id,
              name: _subCategoryName(tagId),
            ),
          );
        }
      }
      if (children.isNotEmpty) {
        categories.add(
          LiveCategory(id: region.id, name: region.name, children: children),
        );
      }
    }

    for (final group in tagGroups) {
      final map = ProviderJson.asMap(group);
      final alias = map['alias']?.toString() ?? '';
      if (alias != 'ethnicity') continue;
      final tags = map['tags'];
      final children = <LiveSubCategory>[];
      if (tags is List) {
        for (final tag in tags) {
          final tagId = tag is Map ? tag['tag']?.toString() : tag.toString();
          if (tagId == null || tagId.isEmpty) continue;
          children.add(
            LiveSubCategory(
              id: tagId,
              parentId: alias,
              name: _subCategoryName(tagId),
            ),
          );
        }
      }
      if (children.isNotEmpty) {
        categories.add(
          LiveCategory(
            id: alias,
            name: _categoryName(alias),
            children: children,
          ),
        );
      }
    }

    return categories;
  }

  static PagedResponse<LiveRoom> mapRecommendResponse(
    Map<String, dynamic> payload, {
    required int page,
    required int limit,
  }) {
    final blocks = ProviderJson.asList(payload['blocks']);
    final items = <LiveRoom>[];
    for (final block in blocks) {
      final blockMap = ProviderJson.asMap(block);
      final models = ProviderJson.asList(blockMap['models']);
      for (final model in models) {
        final room = _mapRoom(ProviderJson.asMap(model));
        if (room != null) {
          items.add(room);
        }
      }
    }
    final totalCount =
        ProviderJson.asInt(payload['totalCount']) ?? items.length;
    return PagedResponse(
      items: items,
      hasMore: page * limit < totalCount,
      page: page,
    );
  }

  static PagedResponse<LiveRoom> mapCategoryRoomsResponse(
    Map<String, dynamic> payload, {
    required int page,
    required int limit,
  }) {
    final models = ProviderJson.asList(payload['models']);
    final items = models
        .map((m) => _mapRoom(ProviderJson.asMap(m)))
        .whereType<LiveRoom>()
        .toList(growable: false);
    final totalCount = ProviderJson.asInt(payload['totalCount']) ?? 0;
    final filteredCount = ProviderJson.asInt(payload['filteredCount']);
    final effectiveTotal = filteredCount ?? totalCount;
    return PagedResponse(
      items: items,
      hasMore: page * limit < effectiveTotal,
      page: page,
    );
  }

  /// Maps a search API response.
  /// Note: The Stripchat search endpoint returns a single payload grouped by match type
  /// (e.g., matching username, topic, etc.) in a single batch, and doesn't support offset-based
  /// pagination. Therefore, we parse all items in a single pass and set [hasMore] to false.
  static PagedResponse<LiveRoom> mapSearchResponse(
    Map<String, dynamic> payload, {
    required int page,
    required int limit,
  }) {
    final groups = ProviderJson.asMap(payload['groups']);
    const groupOrder = ['username', 'topic', 'tipMenu', 'activity', 'interest'];
    final seenModelIds = <int>{};
    final items = <LiveRoom>[];

    for (final groupName in groupOrder) {
      final group = ProviderJson.asMap(groups[groupName]);
      final models = ProviderJson.asList(group['models']);
      for (final model in models) {
        final map = ProviderJson.asMap(model);
        final modelId = ProviderJson.asInt(map['id']);
        if (modelId != null && seenModelIds.contains(modelId)) {
          continue;
        }
        if (modelId != null) {
          seenModelIds.add(modelId);
        }
        final room = _mapRoom(map);
        if (room != null) {
          items.add(room);
        }
      }
    }

    return PagedResponse(items: items, hasMore: false, page: page);
  }

  static bool _parseIsLive(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is int) return value == 1;
    final str = value.toString().trim().toLowerCase();
    return str == 'true' || str == '1';
  }

  static LiveRoom? _mapRoom(Map<String, dynamic> item) {
    final username = item['username']?.toString() ?? '';
    if (username.isEmpty) {
      return null;
    }

    final status = (item['status']?.toString() ?? '').toLowerCase();
    final isLive = _parseIsLive(item['isLive']);
    final streamName = item['streamName']?.toString() ?? '';

    if (status == 'off' ||
        status == 'idle' ||
        status == 'private' ||
        status == 'p2p') {
      return null;
    }

    final effectiveLive = isLive && streamName.isNotEmpty;
    final coverUrl =
        _normalizeUrl(item['previewUrlThumbBig']?.toString()) ??
        _normalizeUrl(item['previewUrlThumbSmall']?.toString()) ??
        _normalizeUrl(item['previewUrl']?.toString());

    return LiveRoom(
      providerId: ProviderId.stripchat,
      roomId: username,
      title: '',
      streamerName: username,
      coverUrl: coverUrl,
      keyframeUrl: _resolveSnapshotUrl(item),
      areaName: item['country']?.toString() ?? item['region']?.toString(),
      streamerAvatarUrl: _normalizeUrl(item['avatarUrl']?.toString()),
      viewerCount: ProviderJson.asInt(item['viewersCount']),
      isLive: effectiveLive,
    );
  }

  static LiveRoomDetail mapRoomDetail({
    required String roomId,
    required Map<String, dynamic> camPayload,
    Map<String, dynamic>? broadcastPayload,
    Map<String, dynamic>? membersPayload,
    String? userHash,
    String? csrfToken,
    int? guestId,
    Map<String, dynamic>? initialDynamicPayload,
    String requestCookie = '',
  }) {
    final cam = ProviderJson.asMap(camPayload['cam']);
    final user = ProviderJson.asMap(camPayload['user']);
    final userData = ProviderJson.asMap(user['user']);
    final show = ProviderJson.asMap(cam['show']);

    final username = userData['username']?.toString() ?? roomId;
    final modelIdStr = userData['id']?.toString() ?? '';
    final streamName = cam['streamName']?.toString() ?? '';
    final roomStatus = userData['status']?.toString().trim() ?? '';
    final showMode = show['mode']?.toString().trim() ?? '';
    final camAvailable = cam['isCamAvailable'] == true;
    final isLive = _parseIsLive(userData['isLive']);
    final broadcastItem = ProviderJson.asMap(broadcastPayload?['item']);
    final broadcastStatus = broadcastItem['status']?.toString().trim() ?? '';
    final broadcastStreamName =
        broadcastItem['streamName']?.toString().trim() ?? '';
    final broadcastIsLive = _parseIsLive(broadcastItem['isLive']);
    final effectiveStreamName = broadcastStreamName.isNotEmpty
        ? broadcastStreamName
        : streamName;
    final effectiveIsLive = isLive || broadcastIsLive;
    final hasActivePublicBroadcast =
        broadcastStatus.toLowerCase() == 'public' &&
        broadcastStreamName.isNotEmpty &&
        broadcastIsLive;
    final playbackUnavailableReason = _resolvePlaybackUnavailableReason(
      roomStatus: roomStatus,
      showMode: showMode,
      streamName: effectiveStreamName,
      isLive: effectiveIsLive,
      hasActivePublicBroadcast: hasActivePublicBroadcast,
    );

    final wsToken = _extractWsToken(initialDynamicPayload);
    final wsUrl = _extractWsUrl(initialDynamicPayload);
    final configCdnDomains = _extractCdnDomains(initialDynamicPayload);

    final danmakuToken =
        playbackUnavailableReason == null &&
            wsToken != null &&
            wsUrl != null &&
            modelIdStr.isNotEmpty
        ? StripchatDanmakuToken(
            modelId: modelIdStr,
            websocketUrl: wsUrl,
            jwt: wsToken,
            historyUrl:
                'https://$_originHost/api/front/v2/models/$modelIdStr/chat?source=regular',
            requestCookie: requestCookie,
            roomUrl: 'https://$_originHost/$username',
          )
        : UnavailableDanmakuToken(
            reason: playbackUnavailableReason ?? 'Stripchat 当前弹幕暂不可用。',
          );

    final metadata = <String, Object?>{
      if (modelIdStr.isNotEmpty) 'modelId': modelIdStr,
      if (effectiveStreamName.isNotEmpty) 'streamName': effectiveStreamName,
      if (userHash != null) 'userHash': userHash,
      if (csrfToken != null) 'csrfToken': csrfToken,
      if (guestId != null) 'guestId': guestId,
      if (configCdnDomains.isNotEmpty) 'cdnConfig': configCdnDomains,
      'stripchatRoomUrl': 'https://$_originHost/$username',
      if (modelIdStr.isNotEmpty) 'stripchatRoomId': modelIdStr,
      if (roomStatus.isNotEmpty) 'roomStatus': roomStatus,
      if (broadcastStatus.isNotEmpty) 'broadcastStatus': broadcastStatus,
      if (showMode.isNotEmpty) 'showMode': showMode,
      'camAvailable': camAvailable,
      'requiresLogin': false,
      if (requestCookie.trim().isNotEmpty)
        'requestCookie': requestCookie.trim(),
      if (playbackUnavailableReason != null)
        'playbackUnavailableReason': playbackUnavailableReason,
    };

    Map<String, dynamic> broadcastSettings;
    List<String> broadcastPresets;
    List<String> broadcastCdnDomains;

    if (broadcastPayload != null) {
      final item = ProviderJson.asMap(broadcastPayload['item']);
      final settings = ProviderJson.asMap(item['settings']);
      broadcastSettings = settings;
      broadcastPresets = ProviderJson.asList(
        settings['presets'],
      ).map((p) => p.toString()).toList();
      broadcastCdnDomains = ProviderJson.asList(
        item['cdnDomains'],
      ).map((d) => d.toString()).toList();
    } else {
      broadcastSettings = const {};
      broadcastPresets = const [];
      broadcastCdnDomains = const [];
    }

    if (broadcastPresets.isNotEmpty) {
      metadata['presets'] = broadcastPresets;
    }
    metadata['broadcastSettings'] = broadcastSettings;
    if (broadcastCdnDomains.isNotEmpty) {
      metadata['cdnDomains'] = broadcastCdnDomains;
    } else if (configCdnDomains.isNotEmpty) {
      metadata['cdnDomains'] = configCdnDomains;
    }

    final statusChangedAt = userData['statusChangedAt'];
    final int? membersViewerCount = membersPayload != null
        ? (ProviderJson.asInt(membersPayload['guests']) ?? 0) +
              (ProviderJson.asInt(membersPayload['regulars']) ?? 0) +
              (ProviderJson.asInt(membersPayload['greens']) ?? 0) +
              (ProviderJson.asInt(membersPayload['golds']) ?? 0) +
              (ProviderJson.asInt(membersPayload['invisibles']) ?? 0) +
              (ProviderJson.asInt(membersPayload['spies']) ?? 0)
        : null;

    final baseViewerCount =
        ProviderJson.asInt(userData['viewersCount']) ??
        ProviderJson.asInt(broadcastItem['viewersCount']) ??
        ProviderJson.asInt(cam['viewersCount']);

    final viewerCount = (membersViewerCount != null && membersViewerCount > 0)
        ? membersViewerCount
        : baseViewerCount;

    return LiveRoomDetail(
      providerId: ProviderId.stripchat,
      roomId: roomId,
      title: cam['topic']?.toString() ?? '',
      streamerName: username,
      streamerAvatarUrl: _normalizeUrl(userData['avatarUrl']?.toString()),
      coverUrl: _normalizeUrl(userData['previewUrl']?.toString()),
      keyframeUrl: _resolveSnapshotUrl(userData),
      areaName: userData['country']?.toString(),
      description: userData['description']?.toString(),
      sourceUrl: 'https://$_originHost/$username',
      isLive: effectiveIsLive,
      viewerCount: viewerCount,
      danmakuToken: danmakuToken,
      metadata: metadata,
      startedAt: statusChangedAt is int
          ? DateTime.fromMillisecondsSinceEpoch(statusChangedAt * 1000)
          : null,
    );
  }

  static List<LivePlayQuality> mapPlayQualities(
    LiveRoomDetail detail, {
    List<String> discoveredQualityIds = const <String>[],
  }) {
    final qualityIds = <String>['auto'];
    final normalizedQualities = <String>{};
    _collectPlayableQualityIds(
      normalizedQualities,
      detail.metadata?['presets'] as List?,
    );
    _collectPlayableQualityIds(normalizedQualities, discoveredQualityIds);
    final sortedIds = normalizedQualities.toList(growable: false)
      ..sort((a, b) => _qualitySortOrder(b).compareTo(_qualitySortOrder(a)));
    qualityIds.addAll(sortedIds);

    return qualityIds
        .map((id) {
          return LivePlayQuality(
            id: id,
            label: _qualityLabel(id),
            isDefault: id == 'auto',
            sortOrder: id == 'auto' ? 0 : _qualitySortOrder(id),
          );
        })
        .toList(growable: false);
  }

  static void _collectPlayableQualityIds(Set<String> qualityIds, List? rawIds) {
    if (rawIds == null || rawIds.isEmpty) {
      return;
    }
    for (final item in rawIds) {
      final label = item.toString().trim().toLowerCase();
      if (label.isEmpty ||
          label == 'auto' ||
          label.contains('blurred') ||
          label.contains('pixelate')) {
        continue;
      }
      qualityIds.add(label);
    }
  }

  static Future<List<LivePlayUrl>> mapPlayUrls({
    required LiveRoomDetail detail,
    required LivePlayQuality quality,
  }) {
    final blockedReason =
        detail.metadata?['playbackUnavailableReason']?.toString().trim() ?? '';
    if (blockedReason.isNotEmpty) {
      return Future.value(const <LivePlayUrl>[]);
    }
    final streamName = detail.metadata?['streamName']?.toString() ?? '';
    if (streamName.isEmpty) {
      return Future.value(const <LivePlayUrl>[]);
    }

    final cdnDomain = _resolveCdnDomain(detail);
    final url = _buildPlaylistUrl(
      streamName: streamName,
      cdnDomain: cdnDomain,
      qualityId: quality.id,
    );
    final stripchatRoomUrl =
        detail.metadata?['stripchatRoomUrl']?.toString().trim() ??
        detail.sourceUrl?.trim() ??
        '';
    final metadata = <String, Object?>{
      if (quality.id != 'auto') 'preferredVariantId': quality.id,
      if (stripchatRoomUrl.isNotEmpty) 'stripchatRoomUrl': stripchatRoomUrl,
    };
    final preferredCdnDomains = <String>[
      ...List<String>.from(detail.metadata?['cdnConfig'] as List? ?? const []),
      ...List<String>.from(detail.metadata?['cdnDomains'] as List? ?? const []),
    ].where((domain) => domain.trim().isNotEmpty).toList(growable: false);
    if (preferredCdnDomains.isNotEmpty) {
      metadata['stripchatCdnDomains'] = preferredCdnDomains;
    }

    return Future.value([
      LivePlayUrl(
        url: url,
        headers: _buildPlaybackHeaders(
          requestCookie: detail.metadata?['requestCookie']?.toString() ?? '',
        ),
        lineLabel: 'HLS ${quality.id}',
        metadata: metadata,
      ),
    ]);
  }

  /// Builds the playlist URL.
  /// Note: [qualityId] is passed to keep the signature aligned/extendable, but
  /// is not embedded in the URL as the edge master playlist parses sub-playlists
  /// downstream via [preferredVariantId].
  static String _buildPlaylistUrl({
    required String streamName,
    required String cdnDomain,
    required String qualityId,
  }) {
    return 'https://edge-hls.$cdnDomain/hls/$streamName/master/'
        '${streamName}_auto.m3u8'
        '?minHeight=240';
  }

  static Map<String, String> _buildPlaybackHeaders({
    required String requestCookie,
  }) {
    return {
      'user-agent':
          'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/137.0.0.0 Mobile Safari/537.36',
      'sec-ch-ua': '"Chromium";v="137", "Not/A)Brand";v="24"',
      'sec-ch-ua-mobile': '?1',
      'sec-ch-ua-platform': '"Android"',
      'accept': '*/*',
      'accept-language': 'zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7',
      'accept-encoding': 'gzip, deflate, br',
      'referer': 'https://$_originHost/',
      'origin': 'https://$_originHost',
      if (requestCookie.trim().isNotEmpty) 'cookie': requestCookie.trim(),
    };
  }

  static String? _resolvePlaybackUnavailableReason({
    required String roomStatus,
    required String showMode,
    required String streamName,
    required bool isLive,
    required bool hasActivePublicBroadcast,
  }) {
    final normalizedStatus = roomStatus.toLowerCase();
    if (_restrictedRoomStatuses.contains(normalizedStatus)) {
      return 'Stripchat 当前房间状态为 "$roomStatus"，暂时没有公开播放流。';
    }
    final normalizedMode = showMode.toLowerCase();
    if (_restrictedShowModes.contains(normalizedMode) &&
        !hasActivePublicBroadcast) {
      return 'Stripchat 当前房间处于 "$showMode" 模式，暂时没有公开播放流。';
    }
    if (streamName.trim().isEmpty &&
        (!isLive || normalizedStatus == 'off' || normalizedStatus == 'idle')) {
      return 'Stripchat 当前房间暂未开播，暂无可用播放流。';
    }
    return null;
  }

  static const Set<String> _restrictedRoomStatuses = {'private', 'p2p', 'spy'};

  static const Set<String> _restrictedShowModes = {
    'private',
    'virtualprivate',
    'spy',
  };

  static String? _normalizeUrl(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    final trimmed = raw.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    if (trimmed.startsWith('//')) {
      return 'https:$trimmed';
    }
    if (trimmed.startsWith('/')) {
      return '$_imageCdnBase$trimmed';
    }
    return 'https://$trimmed';
  }

  static String? _resolveSnapshotUrl(Map<String, dynamic> item) {
    final modelId = ProviderJson.asInt(item['id']);
    final timestamp = _resolveSnapshotTimestamp(item);
    if (modelId == null || timestamp == null || timestamp <= 0) {
      return null;
    }
    return 'https://img.doppiocdn.net/snapshot/$modelId/$timestamp';
  }

  static int? _resolveSnapshotTimestamp(Map<String, dynamic> item) {
    for (final key in const [
      'snapshotTimestamp',
      'verifiedSnapshotTimestamp',
      'mlSnapshotTimestamp',
      'popularSnapshotTimestamp',
    ]) {
      final value = ProviderJson.asInt(item[key]);
      if (value != null && value > 0) {
        return value;
      }
    }
    return null;
  }

  static String? _extractWsToken(Map<String, dynamic>? initialDynamic) {
    if (initialDynamic == null) return null;
    final ws = ProviderJson.asMap(initialDynamic['websocket']);
    return ws['token']?.toString();
  }

  static String? _extractWsUrl(Map<String, dynamic>? initialDynamic) {
    if (initialDynamic == null) return null;
    final ws = ProviderJson.asMap(initialDynamic['websocket']);
    return ws['url']?.toString();
  }

  static List<String> _extractCdnDomains(Map<String, dynamic>? initialDynamic) {
    if (initialDynamic == null) return [];
    final players = ProviderJson.asMap(initialDynamic['players']);
    final cdnConfig = ProviderJson.asList(players['cdnConfig']);
    return cdnConfig
        .map((item) {
          final map = ProviderJson.asMap(item);
          return map['domain']?.toString() ?? '';
        })
        .where((d) => d.isNotEmpty)
        .toList(growable: false);
  }

  static String _resolveCdnDomain(LiveRoomDetail detail) {
    final cdnConfig = List<String>.from(
      detail.metadata?['cdnConfig'] as List? ?? [],
    );
    final metaCdnDomains = List<String>.from(
      detail.metadata?['cdnDomains'] as List? ?? [],
    );

    // Use the first domain reported by CDN config; no TLD preference.
    if (cdnConfig.isNotEmpty) return cdnConfig.first;
    if (metaCdnDomains.isNotEmpty) return metaCdnDomains.first;
    return defaultCdnDomain;
  }

  static int _qualitySortOrder(String id) {
    if (id.trim().toLowerCase() == 'source') {
      return 10000;
    }
    final match = RegExp(r'(\d+)').firstMatch(id);
    if (match != null) {
      return int.tryParse(match.group(1) ?? '') ?? 100;
    }
    return 100;
  }

  static String _qualityLabel(String id) {
    final normalized = id.trim().toLowerCase();
    if (normalized == 'auto') {
      return 'Auto';
    }
    if (normalized == 'source') {
      return 'Source';
    }
    return id.toUpperCase();
  }
}

class _CountryRegion {
  const _CountryRegion(this.id, this.name, this.tagIds);

  final String id;
  final String name;
  final List<String> tagIds;
}
