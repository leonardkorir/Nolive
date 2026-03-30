import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:live_providers/live_providers.dart';
import 'package:live_storage/live_storage.dart';
import 'package:live_sync/live_sync.dart';
import 'package:nolive_app/src/app/bootstrap/default_state.dart';
import 'package:nolive_app/src/features/library/application/load_follow_watchlist_use_case.dart';

import 'manage_layout_preferences_use_case.dart';

class ExportSyncSnapshotJsonUseCase {
  const ExportSyncSnapshotJsonUseCase(this.snapshotService);

  final RepositorySyncSnapshotService snapshotService;

  Future<String> call() async {
    final snapshot = await snapshotService.exportSnapshot();
    return SyncSnapshotJsonCodec.encode(snapshot);
  }
}

class ExportLegacyConfigJsonUseCase {
  const ExportLegacyConfigJsonUseCase({
    required this.settingsRepository,
    required this.historyRepository,
    required this.followRepository,
    required this.tagRepository,
  });

  final SettingsRepository settingsRepository;
  final HistoryRepository historyRepository;
  final FollowRepository followRepository;
  final TagRepository tagRepository;

  Future<String> call() async {
    final snapshotService = RepositorySyncSnapshotService(
      settingsRepository: settingsRepository,
      historyRepository: historyRepository,
      followRepository: followRepository,
      tagRepository: tagRepository,
    );
    final snapshot = await snapshotService.exportSnapshot();
    final snapshotJson = jsonDecode(SyncSnapshotJsonCodec.encode(snapshot));

    final settings = Map<String, Object?>.from(snapshot.settings);
    final blockedKeywords = snapshot.blockedKeywords;

    return jsonEncode({
      'type': 'simple_live',
      'platform': _platformName(defaultTargetPlatform),
      'version': 1,
      'time': DateTime.now().millisecondsSinceEpoch,
      'config': _encodeLegacyConfigPayload(settings),
      'shield': {
        for (final keyword in blockedKeywords) keyword: keyword,
      },
      if (snapshotJson is Map<String, dynamic>) ...snapshotJson,
    });
  }
}

class ImportSyncSnapshotJsonUseCase {
  const ImportSyncSnapshotJsonUseCase({
    required this.snapshotService,
    required this.settingsRepository,
    required this.followRepository,
    required this.tagRepository,
    required this.themeModeNotifier,
    required this.layoutPreferencesNotifier,
    this.providerRegistry,
    this.providerCatalogRevision,
    this.followWatchlistSnapshot,
    this.followDataRevision,
  });

  final RepositorySyncSnapshotService snapshotService;
  final SettingsRepository settingsRepository;
  final FollowRepository followRepository;
  final TagRepository tagRepository;
  final ValueNotifier<ThemeMode> themeModeNotifier;
  final ValueNotifier<LayoutPreferences> layoutPreferencesNotifier;
  final ProviderRegistry? providerRegistry;
  final ValueNotifier<int>? providerCatalogRevision;
  final ValueNotifier<FollowWatchlist?>? followWatchlistSnapshot;
  final ValueNotifier<int>? followDataRevision;

  Future<SyncSnapshot> call(String rawJson) async {
    final payload = _decodeImportedSnapshot(rawJson);
    var followDataChanged = false;
    switch (payload.importMode) {
      case _ImportMode.legacyConfig:
        await _importLegacyConfig(payload.snapshot);
        break;
      case _ImportMode.legacyFollowList:
        await _importLegacyFollowList(payload.snapshot);
        followDataChanged = true;
        break;
      case _ImportMode.fullSnapshot:
        await snapshotService.importSnapshot(payload.snapshot);
        followDataChanged = true;
        break;
    }
    await syncThemeModeNotifierFromSettings(
      settingsRepository: settingsRepository,
      themeModeNotifier: themeModeNotifier,
    );
    await syncLayoutPreferencesNotifierFromSettings(
      settingsRepository: settingsRepository,
      preferencesNotifier: layoutPreferencesNotifier,
    );
    providerRegistry?.clearCache();
    if (providerCatalogRevision != null) {
      providerCatalogRevision!.value += 1;
    }
    if (followDataChanged) {
      followWatchlistSnapshot?.value = null;
      if (followDataRevision != null) {
        followDataRevision!.value += 1;
      }
    }
    return snapshotService.exportSnapshot();
  }

  Future<void> _importLegacyConfig(SyncSnapshot snapshot) async {
    final existingSettings = await settingsRepository.listAll();
    for (final key in existingSettings.keys) {
      await settingsRepository.remove(key);
    }

    for (final entry in snapshot.settings.entries) {
      await settingsRepository.writeValue(entry.key, entry.value);
    }
    await settingsRepository.writeValue(
      'blocked_keywords',
      snapshot.blockedKeywords,
    );
  }

  Future<void> _importLegacyFollowList(SyncSnapshot snapshot) async {
    for (final tag in snapshot.tags) {
      await tagRepository.create(tag);
    }
    for (final record in snapshot.follows) {
      await followRepository.upsert(record);
    }
  }
}

class ResetAppDataUseCase {
  const ResetAppDataUseCase({
    required this.settingsRepository,
    required this.historyRepository,
    required this.followRepository,
    required this.tagRepository,
    required this.themeModeNotifier,
    required this.layoutPreferencesNotifier,
    this.providerRegistry,
    this.providerCatalogRevision,
    this.followWatchlistSnapshot,
    this.followDataRevision,
  });

  final SettingsRepository settingsRepository;
  final HistoryRepository historyRepository;
  final FollowRepository followRepository;
  final TagRepository tagRepository;
  final ValueNotifier<ThemeMode> themeModeNotifier;
  final ValueNotifier<LayoutPreferences> layoutPreferencesNotifier;
  final ProviderRegistry? providerRegistry;
  final ValueNotifier<int>? providerCatalogRevision;
  final ValueNotifier<FollowWatchlist?>? followWatchlistSnapshot;
  final ValueNotifier<int>? followDataRevision;

  Future<void> call() async {
    final settings = await settingsRepository.listAll();
    for (final key in settings.keys) {
      await settingsRepository.remove(key);
    }
    await historyRepository.clear();
    await followRepository.clear();
    await tagRepository.clear();
    await ensureDefaultAppState(
      settingsRepository: settingsRepository,
      tagRepository: tagRepository,
      themeModeNotifier: themeModeNotifier,
    );
    await syncLayoutPreferencesNotifierFromSettings(
      settingsRepository: settingsRepository,
      preferencesNotifier: layoutPreferencesNotifier,
    );
    providerRegistry?.clearCache();
    if (providerCatalogRevision != null) {
      providerCatalogRevision!.value += 1;
    }
    followWatchlistSnapshot?.value = const FollowWatchlist(entries: []);
    if (followDataRevision != null) {
      followDataRevision!.value += 1;
    }
  }
}

enum _ImportMode {
  fullSnapshot,
  legacyConfig,
  legacyFollowList,
}

class _DecodedImportPayload {
  const _DecodedImportPayload({
    required this.snapshot,
    required this.importMode,
  });

  final SyncSnapshot snapshot;
  final _ImportMode importMode;
}

_DecodedImportPayload _decodeImportedSnapshot(String rawJson) {
  final decoded = jsonDecode(rawJson);

  if (decoded is List && _isLegacyFollowListPayload(decoded)) {
    return _DecodedImportPayload(
      snapshot: _decodeLegacyFollowListPayload(decoded),
      importMode: _ImportMode.legacyFollowList,
    );
  }

  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('导入 JSON 必须是对象或旧版兼容关注列表数组。');
  }

  if (_isSyncSnapshotPayload(decoded)) {
    return _DecodedImportPayload(
      snapshot: SyncSnapshotJsonCodec.decode(rawJson),
      importMode: _ImportMode.fullSnapshot,
    );
  }

  if (_isLegacyConfigPayload(decoded)) {
    return _DecodedImportPayload(
      snapshot: _decodeLegacyConfigPayload(decoded),
      importMode: _ImportMode.legacyConfig,
    );
  }

  throw const FormatException(
    '不支持的导入 JSON 格式。请粘贴当前项目导出的快照 JSON、当前项目导出的 nolive_config.json、旧版兼容配置 JSON，或旧版兼容关注列表 JSON。',
  );
}

bool _isLegacyConfigPayload(Map<String, dynamic> json) {
  return json['type'] == 'simple_live' &&
      (json.containsKey('config') || json.containsKey('shield'));
}

bool _isLegacyFollowListPayload(List<dynamic> json) {
  return json.whereType<Map>().any(
        (item) => item.containsKey('siteId') || item.containsKey('roomId'),
      );
}

bool _isSyncSnapshotPayload(Map<String, dynamic> json) {
  return json.containsKey('settings') ||
      json.containsKey('blocked_keywords') ||
      json.containsKey('tags') ||
      json.containsKey('history') ||
      json.containsKey('follows');
}

SyncSnapshot _decodeLegacyConfigPayload(Map<String, dynamic> json) {
  final rawSettings = _stringKeyObjectMap(
    json['config'],
    fieldName: 'config',
  );
  final blockedKeywords = <String>{}
    ..addAll(_stringListFlexible(rawSettings.remove('blocked_keywords')))
    ..addAll(_decodeShieldKeywords(json['shield']));

  final normalizedBlockedKeywords = blockedKeywords.toList(growable: false)
    ..sort();

  return SyncSnapshot(
    settings: _normalizeLegacyConfigSettings(rawSettings),
    blockedKeywords: normalizedBlockedKeywords,
  );
}

SyncSnapshot _decodeLegacyFollowListPayload(List<dynamic> json) {
  final follows = <FollowRecord>[];
  final tags = <String>{};
  for (final item in json.whereType<Map>()) {
    final providerId = _trimmedString(item['siteId']) ?? '';
    final roomId = _trimmedString(item['roomId']) ?? '';
    if (providerId.isEmpty || roomId.isEmpty) {
      continue;
    }
    final tag = _trimmedString(item['tag'], allowEmpty: true) ?? '';
    final recordTags =
        tag.isEmpty || tag == '全部' ? const <String>[] : <String>[tag];
    tags.addAll(recordTags);
    follows.add(
      FollowRecord(
        providerId: providerId,
        roomId: roomId,
        streamerName: _trimmedString(item['userName']) ?? roomId,
        streamerAvatarUrl: _trimmedString(item['face'], allowEmpty: false),
        lastTitle: _trimmedString(item['title'], allowEmpty: false) ??
            _trimmedString(item['liveTitle'], allowEmpty: false),
        lastAreaName: _trimmedString(item['areaName'], allowEmpty: false) ??
            _trimmedString(item['liveAreaName'], allowEmpty: false),
        lastCoverUrl: _trimmedString(item['coverUrl'], allowEmpty: false) ??
            _trimmedString(item['cover'], allowEmpty: false),
        lastKeyframeUrl:
            _trimmedString(item['keyframeUrl'], allowEmpty: false) ??
                _trimmedString(item['keyframe'], allowEmpty: false),
        tags: recordTags,
      ),
    );
  }

  return SyncSnapshot(
    follows: follows,
    tags: tags.toList(growable: false)..sort(),
  );
}

Map<String, Object?> _encodeLegacyConfigPayload(
  Map<String, Object?> settings,
) {
  final encoded = <String, Object?>{};

  _putIfNotNull(
      encoded, 'ThemeMode', _encodeLegacyThemeMode(settings['theme_mode']));
  _putIfNotNull(
    encoded,
    'BilibiliCookie',
    _trimmedString(settings['account_bilibili_cookie']),
  );
  _putIfNotNull(
    encoded,
    'DouyinCookie',
    _trimmedString(settings['account_douyin_cookie']),
  );
  _putIfNotNull(
    encoded,
    'ChaturbateCookie',
    _trimmedString(settings['account_chaturbate_cookie']),
  );
  _putIfNotNull(
    encoded,
    'YouTubeCookie',
    _trimmedString(settings['account_youtube_cookie']),
  );
  _putIfNotNull(
      encoded, 'DanmuEnable', _asBool(settings['danmaku_enabled_by_default']));
  _putIfNotNull(encoded, 'DanmuSize', _asDouble(settings['danmaku_font_size']));
  _putIfNotNull(encoded, 'DanmuArea', _asDouble(settings['danmaku_area']));
  _putIfNotNull(encoded, 'DanmuSpeed', _asDouble(settings['danmaku_speed']));
  _putIfNotNull(
      encoded, 'DanmuOpacity', _asDouble(settings['danmaku_opacity']));
  _putIfNotNull(
    encoded,
    'DanmuStrokeWidth',
    _asDouble(settings['danmaku_stroke_width']),
  );
  _putIfNotNull(
    encoded,
    'DanmuLineHeight',
    _asDouble(settings['danmaku_line_height']),
  );
  _putIfNotNull(
    encoded,
    'DanmuTopMargin',
    _asDouble(settings['danmaku_top_margin']),
  );
  _putIfNotNull(
    encoded,
    'DanmuBottomMargin',
    _asDouble(settings['danmaku_bottom_margin']),
  );
  _putIfNotNull(
    encoded,
    'DanmuFontWeight',
    _asInt(settings['danmaku_font_weight']),
  );
  _putIfNotNull(
      encoded, 'ChatTextSize', _asDouble(settings['room_chat_text_size']));
  _putIfNotNull(
      encoded, 'ChatTextGap', _asDouble(settings['room_chat_text_gap']));
  _putIfNotNull(
    encoded,
    'ChatBubbleStyle',
    _asBool(settings['room_chat_bubble_style']),
  );
  _putIfNotNull(
    encoded,
    'PlayerShowSuperChat',
    _asBool(settings['room_show_player_super_chat']),
  );
  _putIfNotNull(
    encoded,
    'AutoUpdateFollowEnable',
    _asBool(settings['follow_auto_refresh_enabled']),
  );
  _putIfNotNull(
    encoded,
    'AutoUpdateFollowDuration',
    _asInt(settings['follow_auto_refresh_interval_minutes']),
  );
  _putIfNotNull(
    encoded,
    'FollowStyleNotGrid',
    _encodeLegacyFollowStyleNotGrid(settings['follow_display_mode']),
  );
  _putIfNotNull(
      encoded, 'PlayerCompatMode', _asBool(settings['player_mpv_compat_mode']));
  _putIfNotNull(
      encoded, 'PlayerForceHttps', _asBool(settings['player_force_https']));
  _putIfNotNull(
    encoded,
    'AutoFullScreen',
    _asBool(settings['player_android_auto_fullscreen']),
  );
  _putIfNotNull(
    encoded,
    'PlayerAutoPause',
    _asBool(settings['player_android_background_auto_pause']),
  );
  _putIfNotNull(
    encoded,
    'PIPHideDanmu',
    _asBool(settings['player_android_pip_hide_danmaku']),
  );
  _putIfNotNull(
    encoded,
    'MdkAndroidTunnel',
    _asBool(settings['player_mdk_android_tunnel']),
  );
  _putIfNotNull(encoded, 'PlayerType',
      _encodeLegacyPlayerType(settings['player_backend']));
  _putIfNotNull(
    encoded,
    'PlayerVolume',
    _encodeLegacyVolume(settings['player_volume']),
  );
  _putIfNotNull(
    encoded,
    'HardwareDecode',
    _asBool(settings['player_mpv_hardware_acceleration']),
  );
  _putIfNotNull(
    encoded,
    'VideoHardwareDecoder',
    _encodeLegacyHardwareDecoder(settings['player_mpv_hardware_acceleration']),
  );
  _putIfNotNull(
    encoded,
    'QualityLevel',
    _encodeLegacyQualityLevel(settings['player_prefer_highest_quality']),
  );
  _putIfNotNull(
    encoded,
    'QualityLevelCellular',
    _encodeLegacyQualityLevel(settings['player_prefer_highest_quality']),
  );
  final homeSort = _encodeLegacyHomeSort(settings['layout_shell_tab_order']);
  if (homeSort.isNotEmpty) {
    encoded['HomeSort'] = homeSort;
  }
  final siteSort = _encodeLegacySiteSort(settings['layout_provider_order']);
  if (siteSort.isNotEmpty) {
    encoded['SiteSort'] = siteSort;
  }

  _putIfNotNull(
      encoded, 'WebDAVUri', _trimmedString(settings['sync_webdav_base_url']));
  _putIfNotNull(
    encoded,
    'WebDAVDirectory',
    _encodeLegacyWebDavDirectory(settings['sync_webdav_remote_path']),
  );
  _putIfNotNull(
    encoded,
    'WebDAVUser',
    _trimmedString(settings['sync_webdav_username']),
  );
  _putIfNotNull(
    encoded,
    'kWebDAVPassword',
    _trimmedString(settings['sync_webdav_password']),
  );

  return encoded;
}

Map<String, Object?> _normalizeLegacyConfigSettings(
  Map<String, Object?> rawSettings,
) {
  final normalized = <String, Object?>{};
  int? legacyQualityLevel;
  int? legacyQualityLevelCellular;

  for (final entry in rawSettings.entries) {
    switch (entry.key) {
      case 'theme_mode':
      case 'ThemeMode':
        _putIfNotNull(
            normalized, 'theme_mode', _normalizeThemeMode(entry.value));
        break;
      case 'player_auto_play':
        _putIfNotNull(normalized, 'player_auto_play', _asBool(entry.value));
        break;
      case 'player_prefer_highest_quality':
        _putIfNotNull(
          normalized,
          'player_prefer_highest_quality',
          _asBool(entry.value),
        );
        break;
      case 'player_backend':
        _putIfNotNull(
          normalized,
          'player_backend',
          _normalizePlayerBackend(entry.value),
        );
        break;
      case 'PlayerType':
        _putIfNotNull(
          normalized,
          'player_backend',
          _legacyPlayerTypeToBackend(entry.value),
        );
        break;
      case 'player_volume':
      case 'PlayerVolume':
        _putIfNotNull(
            normalized, 'player_volume', _normalizeVolume(entry.value));
        break;
      case 'player_mpv_hardware_acceleration':
        _putIfNotNull(
          normalized,
          'player_mpv_hardware_acceleration',
          _asBool(entry.value),
        );
        break;
      case 'HardwareDecode':
        _putIfNotNull(
          normalized,
          'player_mpv_hardware_acceleration',
          _asBool(entry.value),
        );
        normalized.putIfAbsent('player_backend', () => 'mpv');
        break;
      case 'VideoHardwareDecoder':
        _putIfNotNull(
          normalized,
          'player_mpv_hardware_acceleration',
          _legacyHardwareAccelerationEnabled(entry.value),
        );
        normalized.putIfAbsent('player_backend', () => 'mpv');
        break;
      case 'VideoOutputDriver':
        if ((_trimmedString(entry.value) ?? '').isNotEmpty) {
          normalized.putIfAbsent('player_backend', () => 'mpv');
        }
        break;
      case 'CustomPlayerOutput':
        if ((_asBool(entry.value) ?? false) &&
            !normalized.containsKey('player_backend')) {
          normalized['player_backend'] = 'mpv';
        }
        break;
      case 'player_mpv_compat_mode':
      case 'PlayerCompatMode':
        _putIfNotNull(
            normalized, 'player_mpv_compat_mode', _asBool(entry.value));
        break;
      case 'player_mdk_android_tunnel':
      case 'MdkAndroidTunnel':
        _putIfNotNull(
          normalized,
          'player_mdk_android_tunnel',
          _asBool(entry.value),
        );
        break;
      case 'player_force_https':
      case 'PlayerForceHttps':
        _putIfNotNull(normalized, 'player_force_https', _asBool(entry.value));
        break;
      case 'player_android_auto_fullscreen':
      case 'AutoFullScreen':
        _putIfNotNull(
          normalized,
          'player_android_auto_fullscreen',
          _asBool(entry.value),
        );
        break;
      case 'player_android_background_auto_pause':
      case 'PlayerAutoPause':
        _putIfNotNull(
          normalized,
          'player_android_background_auto_pause',
          _asBool(entry.value),
        );
        break;
      case 'player_android_pip_hide_danmaku':
      case 'PIPHideDanmu':
        _putIfNotNull(
          normalized,
          'player_android_pip_hide_danmaku',
          _asBool(entry.value),
        );
        break;
      case 'danmaku_enabled_by_default':
      case 'DanmuEnable':
        _putIfNotNull(
          normalized,
          'danmaku_enabled_by_default',
          _asBool(entry.value),
        );
        break;
      case 'danmaku_font_size':
      case 'DanmuSize':
        _putIfNotNull(normalized, 'danmaku_font_size', _asDouble(entry.value));
        break;
      case 'danmaku_area':
      case 'DanmuArea':
        _putIfNotNull(normalized, 'danmaku_area', _asDouble(entry.value));
        break;
      case 'danmaku_speed':
      case 'DanmuSpeed':
        _putIfNotNull(normalized, 'danmaku_speed', _asDouble(entry.value));
        break;
      case 'danmaku_opacity':
      case 'DanmuOpacity':
        _putIfNotNull(normalized, 'danmaku_opacity', _asDouble(entry.value));
        break;
      case 'danmaku_stroke_width':
      case 'DanmuStrokeWidth':
        _putIfNotNull(
          normalized,
          'danmaku_stroke_width',
          _asDouble(entry.value),
        );
        break;
      case 'danmaku_line_height':
      case 'DanmuLineHeight':
        _putIfNotNull(
          normalized,
          'danmaku_line_height',
          _asDouble(entry.value),
        );
        break;
      case 'danmaku_top_margin':
      case 'DanmuTopMargin':
        _putIfNotNull(
          normalized,
          'danmaku_top_margin',
          _asDouble(entry.value),
        );
        break;
      case 'danmaku_bottom_margin':
      case 'DanmuBottomMargin':
        _putIfNotNull(
          normalized,
          'danmaku_bottom_margin',
          _asDouble(entry.value),
        );
        break;
      case 'danmaku_font_weight':
      case 'DanmuFontWeight':
        _putIfNotNull(normalized, 'danmaku_font_weight', _asInt(entry.value));
        break;
      case 'room_chat_text_size':
      case 'ChatTextSize':
        _putIfNotNull(
            normalized, 'room_chat_text_size', _asDouble(entry.value));
        break;
      case 'room_chat_text_gap':
      case 'ChatTextGap':
        _putIfNotNull(normalized, 'room_chat_text_gap', _asDouble(entry.value));
        break;
      case 'room_chat_bubble_style':
      case 'ChatBubbleStyle':
        _putIfNotNull(
            normalized, 'room_chat_bubble_style', _asBool(entry.value));
        break;
      case 'room_show_player_super_chat':
      case 'PlayerShowSuperChat':
        _putIfNotNull(
          normalized,
          'room_show_player_super_chat',
          _asBool(entry.value),
        );
        break;
      case 'follow_auto_refresh_enabled':
      case 'AutoUpdateFollowEnable':
        _putIfNotNull(
          normalized,
          'follow_auto_refresh_enabled',
          _asBool(entry.value),
        );
        break;
      case 'follow_auto_refresh_interval_minutes':
      case 'AutoUpdateFollowDuration':
        final minutes = _normalizeFollowAutoRefreshInterval(entry.value);
        if (minutes != null) {
          normalized['follow_auto_refresh_interval_minutes'] = minutes;
          normalized.putIfAbsent('follow_auto_refresh_enabled', () => true);
        }
        break;
      case 'follow_display_mode':
        _putIfNotNull(
          normalized,
          'follow_display_mode',
          _normalizeFollowDisplayMode(entry.value),
        );
        break;
      case 'FollowStyleNotGrid':
        _putIfNotNull(
          normalized,
          'follow_display_mode',
          _legacyFollowStyleNotGridToDisplayMode(entry.value),
        );
        break;
      case 'account_bilibili_cookie':
      case 'BilibiliCookie':
        _putIfNotNull(
          normalized,
          'account_bilibili_cookie',
          _trimmedString(entry.value, allowEmpty: true),
        );
        break;
      case 'account_bilibili_user_id':
        _putIfNotNull(
            normalized, 'account_bilibili_user_id', _asInt(entry.value));
        break;
      case 'account_douyin_cookie':
      case 'DouyinCookie':
        _putIfNotNull(
          normalized,
          'account_douyin_cookie',
          _trimmedString(entry.value, allowEmpty: true),
        );
        break;
      case 'account_chaturbate_cookie':
      case 'ChaturbateCookie':
        _putIfNotNull(
          normalized,
          'account_chaturbate_cookie',
          _trimmedString(entry.value, allowEmpty: true),
        );
        break;
      case 'account_youtube_cookie':
      case 'YouTubeCookie':
        _putIfNotNull(
          normalized,
          'account_youtube_cookie',
          _trimmedString(entry.value, allowEmpty: true),
        );
        break;
      case 'layout_shell_tab_order':
        final currentOrder = _normalizeCurrentShellTabOrder(entry.value);
        if (currentOrder.isNotEmpty) {
          normalized['layout_shell_tab_order'] = currentOrder;
        }
        break;
      case 'HomeSort':
        final legacyHomeSort = _decodeLegacyHomeSort(entry.value);
        if (legacyHomeSort.isNotEmpty) {
          normalized['layout_shell_tab_order'] = legacyHomeSort;
        }
        break;
      case 'layout_provider_order':
        final currentProviderOrder =
            _normalizeCurrentProviderOrder(entry.value);
        if (currentProviderOrder.isNotEmpty) {
          normalized['layout_provider_order'] = currentProviderOrder;
        }
        break;
      case 'layout_provider_enabled_ids':
        normalized['layout_provider_enabled_ids'] =
            _normalizeCurrentProviderEnabledIds(entry.value);
        break;
      case 'SiteSort':
        final legacyProviderOrder = _decodeLegacySiteSort(entry.value);
        if (legacyProviderOrder.isNotEmpty) {
          normalized['layout_provider_order'] = legacyProviderOrder;
        }
        break;
      case 'sync_webdav_base_url':
      case 'WebDAVUri':
        _putIfNotNull(
          normalized,
          'sync_webdav_base_url',
          _trimmedString(entry.value, allowEmpty: true),
        );
        break;
      case 'sync_webdav_remote_path':
        _putIfNotNull(
          normalized,
          'sync_webdav_remote_path',
          _normalizeCurrentWebDavPath(entry.value),
        );
        break;
      case 'WebDAVDirectory':
        _putIfNotNull(
          normalized,
          'sync_webdav_remote_path',
          _normalizeLegacyWebDavPath(entry.value),
        );
        break;
      case 'sync_webdav_username':
      case 'WebDAVUser':
        _putIfNotNull(
          normalized,
          'sync_webdav_username',
          _trimmedString(entry.value, allowEmpty: true),
        );
        break;
      case 'sync_webdav_password':
      case 'kWebDAVPassword':
      case 'WebDAVPassword':
        _putIfNotNull(
          normalized,
          'sync_webdav_password',
          _trimmedString(entry.value, allowEmpty: true),
        );
        break;
      case 'QualityLevel':
        legacyQualityLevel = _asInt(entry.value) ?? legacyQualityLevel;
        break;
      case 'QualityLevelCellular':
        legacyQualityLevelCellular =
            _asInt(entry.value) ?? legacyQualityLevelCellular;
        break;
      default:
        break;
    }
  }

  final effectiveQualityLevel = _pickLegacyQualityLevel(
    legacyQualityLevel,
    legacyQualityLevelCellular,
  );
  if (effectiveQualityLevel != null &&
      !normalized.containsKey('player_prefer_highest_quality')) {
    normalized['player_prefer_highest_quality'] = effectiveQualityLevel >= 2;
  }

  return normalized;
}

Map<String, Object?> _stringKeyObjectMap(
  Object? raw, {
  required String fieldName,
}) {
  if (raw == null) {
    return <String, Object?>{};
  }
  if (raw is! Map) {
    throw FormatException('旧版兼容配置中的 $fieldName 必须是对象。');
  }

  final map = <String, Object?>{};
  for (final entry in raw.entries) {
    final key = entry.key?.toString().trim() ?? '';
    if (key.isEmpty) {
      continue;
    }
    map[key] = entry.value;
  }
  return map;
}

Iterable<String> _decodeShieldKeywords(Object? raw) {
  if (raw == null) {
    return const <String>[];
  }
  if (raw is List) {
    return _stringListFlexible(raw);
  }
  if (raw is! Map) {
    throw const FormatException('旧版兼容配置中的 shield 必须是对象或数组。');
  }

  final keywords = <String>{};
  for (final entry in raw.entries) {
    final key = entry.key?.toString().trim() ?? '';
    final value = entry.value?.toString().trim() ?? '';
    if (key.isNotEmpty) {
      keywords.add(key);
      continue;
    }
    if (value.isNotEmpty) {
      keywords.add(value);
    }
  }
  return keywords;
}

List<String> _stringListFlexible(Object? raw) {
  if (raw is List) {
    return raw
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList(growable: false)
      ..sort();
  }
  if (raw is String) {
    return raw
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList(growable: false)
      ..sort();
  }
  return const <String>[];
}

List<String> _normalizeCurrentShellTabOrder(Object? raw) {
  final values = _rawStringSequence(raw);
  if (values.isEmpty) {
    return const <String>[];
  }
  return LoadLayoutPreferencesUseCase.normalizeShellTabOrder(values)
      .map((item) => item.value)
      .toList(growable: false);
}

List<String> _decodeLegacyHomeSort(Object? raw) {
  final normalized = <String>[];
  final seen = <String>{};
  for (final item in _rawStringSequence(raw)) {
    final mapped = switch (item) {
      'follow' => 'library',
      'recommend' => 'home',
      'category' => 'browse',
      'user' => 'profile',
      'search' => 'search',
      _ => '',
    };
    if (mapped.isEmpty || mapped == 'search' || !seen.add(mapped)) {
      continue;
    }
    normalized.add(mapped);
  }
  return LoadLayoutPreferencesUseCase.normalizeShellTabOrder(normalized)
      .where((item) => item != ShellTabId.search)
      .map((item) => item.value)
      .toList(growable: false);
}

List<String> _encodeLegacyHomeSort(Object? raw) {
  final normalized = LoadLayoutPreferencesUseCase.normalizeShellTabOrder(
    _rawStringSequence(raw),
  );
  return normalized
      .where((item) => item != ShellTabId.search)
      .map((item) => switch (item) {
            ShellTabId.library => 'follow',
            ShellTabId.home => 'recommend',
            ShellTabId.browse => 'category',
            ShellTabId.profile => 'user',
            ShellTabId.search => 'search',
          })
      .toList(growable: false);
}

List<String> _normalizeCurrentProviderOrder(Object? raw) {
  final values = _rawStringSequence(raw);
  if (values.isEmpty) {
    return const <String>[];
  }
  return LoadLayoutPreferencesUseCase.normalizeProviderOrder(values);
}

List<String> _normalizeCurrentProviderEnabledIds(Object? raw) {
  return LoadLayoutPreferencesUseCase.normalizeEnabledProviderIds(
    _rawStringSequence(raw),
  );
}

List<String> _decodeLegacySiteSort(Object? raw) {
  final normalized = <String>[];
  final seen = <String>{};
  const supported = {
    'bilibili',
    'chaturbate',
    'douyu',
    'huya',
    'douyin',
    'twitch',
    'youtube',
  };
  for (final item in _rawStringSequence(raw)) {
    if (!supported.contains(item) || !seen.add(item)) {
      continue;
    }
    normalized.add(item);
  }
  return LoadLayoutPreferencesUseCase.normalizeProviderOrder(normalized);
}

List<String> _encodeLegacySiteSort(Object? raw) {
  return LoadLayoutPreferencesUseCase.normalizeProviderOrder(
    _rawStringSequence(raw),
  );
}

Iterable<String> _rawStringSequence(Object? raw) {
  if (raw is List) {
    return raw
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty);
  }
  if (raw is String) {
    return raw
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty);
  }
  return const <String>[];
}

String? _normalizeFollowDisplayMode(Object? raw) {
  final value = _trimmedString(raw, allowEmpty: true)?.toLowerCase();
  return switch (value) {
    'list' => 'list',
    'grid' => 'grid',
    _ => null,
  };
}

String? _legacyFollowStyleNotGridToDisplayMode(Object? raw) {
  final value = _asBool(raw);
  if (value == null) {
    return null;
  }
  return value ? 'list' : 'grid';
}

bool? _encodeLegacyFollowStyleNotGrid(Object? raw) {
  return switch (_normalizeFollowDisplayMode(raw)) {
    'list' => true,
    'grid' => false,
    _ => null,
  };
}

String? _normalizeThemeMode(Object? raw) {
  final stringValue = _trimmedString(raw, allowEmpty: true);
  switch (stringValue) {
    case 'system':
    case '0':
      return 'system';
    case 'light':
    case '1':
      return 'light';
    case 'dark':
    case '2':
      return 'dark';
  }
  if (raw is num) {
    switch (raw.toInt()) {
      case 1:
        return 'light';
      case 2:
        return 'dark';
      default:
        return 'system';
    }
  }
  return null;
}

int? _encodeLegacyThemeMode(Object? raw) {
  return switch (_normalizeThemeMode(raw)) {
    'light' => 1,
    'dark' => 2,
    'system' => 0,
    _ => null,
  };
}

String? _normalizePlayerBackend(Object? raw) {
  final value = _trimmedString(raw, allowEmpty: true);
  if (value == null || value.isEmpty) {
    return null;
  }
  return switch (value) {
    'mpv' => 'mpv',
    'mdk' => 'mdk',
    'memory' => 'memory',
    _ => null,
  };
}

String? _legacyPlayerTypeToBackend(Object? raw) {
  final value = _asInt(raw);
  return switch (value) {
    0 => 'mpv',
    1 => 'mdk',
    _ => null,
  };
}

int? _encodeLegacyPlayerType(Object? raw) {
  return switch (_normalizePlayerBackend(raw)) {
    'mpv' => 0,
    'mdk' => 1,
    _ => null,
  };
}

double? _normalizeVolume(Object? raw) {
  final value = _asDouble(raw);
  if (value == null) {
    return null;
  }
  return value > 1
      ? (value / 100).clamp(0, 1).toDouble()
      : value.clamp(0, 1).toDouble();
}

double? _encodeLegacyVolume(Object? raw) {
  final value = _normalizeVolume(raw);
  if (value == null) {
    return null;
  }
  return (value * 100).clamp(0, 100).toDouble();
}

bool? _legacyHardwareAccelerationEnabled(Object? raw) {
  if (raw is bool) {
    return raw;
  }
  final value = _trimmedString(raw, allowEmpty: true)?.toLowerCase();
  if (value == null || value.isEmpty) {
    return null;
  }
  if ({'no', 'none', 'false', 'software', 'sw'}.contains(value)) {
    return false;
  }
  return true;
}

String? _encodeLegacyHardwareDecoder(Object? raw) {
  final enabled = _asBool(raw);
  if (enabled == null) {
    return null;
  }
  return enabled ? 'mediacodec' : 'no';
}

int? _pickLegacyQualityLevel(int? primary, int? cellular) {
  if (primary == null) {
    return cellular;
  }
  if (cellular == null) {
    return primary;
  }
  return primary >= cellular ? primary : cellular;
}

int? _encodeLegacyQualityLevel(Object? raw) {
  final preferHighest = _asBool(raw);
  if (preferHighest == null) {
    return null;
  }
  return preferHighest ? 2 : 1;
}

int? _normalizeFollowAutoRefreshInterval(Object? raw) {
  final minutes = _asInt(raw);
  if (minutes == null || minutes <= 0) {
    return null;
  }
  return minutes.clamp(1, 24 * 60);
}

String? _normalizeLegacyWebDavPath(Object? raw) {
  final value = _trimmedString(raw, allowEmpty: true);
  if (value == null || value.isEmpty) {
    return null;
  }
  if (value.endsWith('.json')) {
    return value;
  }
  final normalized =
      value.endsWith('/') ? value.substring(0, value.length - 1) : value;
  return '$normalized/snapshot.json';
}

String? _normalizeCurrentWebDavPath(Object? raw) {
  final value = _trimmedString(raw, allowEmpty: true);
  if (value == null || value.isEmpty) {
    return null;
  }
  return value;
}

String? _encodeLegacyWebDavDirectory(Object? raw) {
  final value = _normalizeCurrentWebDavPath(raw);
  if (value == null || value.isEmpty) {
    return null;
  }
  if (!value.endsWith('.json')) {
    return value;
  }
  final separatorIndex = value.lastIndexOf('/');
  if (separatorIndex == -1) {
    return '';
  }
  return value.substring(0, separatorIndex);
}

String _platformName(TargetPlatform platform) {
  return switch (platform) {
    TargetPlatform.android => 'android',
    TargetPlatform.iOS => 'ios',
    TargetPlatform.macOS => 'macos',
    TargetPlatform.windows => 'windows',
    TargetPlatform.linux => 'linux',
    TargetPlatform.fuchsia => 'fuchsia',
  };
}

String? _trimmedString(Object? raw, {bool allowEmpty = false}) {
  if (raw == null) {
    return null;
  }
  final value = raw.toString().trim();
  if (value.isEmpty && !allowEmpty) {
    return null;
  }
  return value;
}

bool? _asBool(Object? raw) {
  if (raw is bool) {
    return raw;
  }
  if (raw is num) {
    return raw != 0;
  }
  final value = _trimmedString(raw, allowEmpty: true)?.toLowerCase();
  if (value == null || value.isEmpty) {
    return null;
  }
  switch (value) {
    case 'true':
    case '1':
    case 'yes':
    case 'on':
      return true;
    case 'false':
    case '0':
    case 'no':
    case 'off':
      return false;
  }
  return null;
}

int? _asInt(Object? raw) {
  if (raw is int) {
    return raw;
  }
  if (raw is num) {
    return raw.toInt();
  }
  return int.tryParse(_trimmedString(raw, allowEmpty: true) ?? '');
}

double? _asDouble(Object? raw) {
  if (raw is double) {
    return raw;
  }
  if (raw is num) {
    return raw.toDouble();
  }
  return double.tryParse(_trimmedString(raw, allowEmpty: true) ?? '');
}

void _putIfNotNull(Map<String, Object?> target, String key, Object? value) {
  if (value == null) {
    return;
  }
  target[key] = value;
}
