import 'package:flutter/foundation.dart';
import 'package:live_core/live_core.dart';
import 'package:live_providers/live_providers.dart';
import 'package:live_storage/live_storage.dart';

import '../../../shared/application/app_log.dart';
import '../../../shared/application/secure_credential_store.dart';
import 'sensitive_setting_keys.dart';
import 'stripchat_mouflon_key_store.dart';

class ProviderAccountSettings {
  const ProviderAccountSettings({
    required this.bilibiliCookie,
    required this.bilibiliUserId,
    required this.chaturbateCookie,
    required this.douyinCookie,
    this.stripchatCookie = '',
    this.stripchatMouflonKeys = const StripchatMouflonKeyCache(),
    required this.twitchCookie,
    required this.youtubeCookie,
  });

  final String bilibiliCookie;
  final int bilibiliUserId;
  final String chaturbateCookie;
  final String douyinCookie;
  final String stripchatCookie;
  final StripchatMouflonKeyCache stripchatMouflonKeys;
  final String twitchCookie;
  final String youtubeCookie;

  ProviderAccountSettings copyWith({
    String? bilibiliCookie,
    int? bilibiliUserId,
    String? chaturbateCookie,
    String? douyinCookie,
    String? stripchatCookie,
    StripchatMouflonKeyCache? stripchatMouflonKeys,
    String? twitchCookie,
    String? youtubeCookie,
  }) {
    return ProviderAccountSettings(
      bilibiliCookie: bilibiliCookie ?? this.bilibiliCookie,
      bilibiliUserId: bilibiliUserId ?? this.bilibiliUserId,
      chaturbateCookie: chaturbateCookie ?? this.chaturbateCookie,
      douyinCookie: douyinCookie ?? this.douyinCookie,
      stripchatCookie: stripchatCookie ?? this.stripchatCookie,
      stripchatMouflonKeys: stripchatMouflonKeys ?? this.stripchatMouflonKeys,
      twitchCookie: twitchCookie ?? this.twitchCookie,
      youtubeCookie: youtubeCookie ?? this.youtubeCookie,
    );
  }
}

class LoadProviderAccountSettingsUseCase {
  const LoadProviderAccountSettingsUseCase(
    this.settingsRepository,
    this.secureCredentialStore,
  );

  final SettingsRepository settingsRepository;
  final SecureCredentialStore secureCredentialStore;

  Future<ProviderAccountSettings> call() async {
    await secureCredentialStore.ensureReady();
    if (!secureCredentialStore.storesSecureValuesSeparately) {
      AppLog.instance.warn(
        'settings',
        'SecureCredentialStore is not available separately. Falling back to plaintext SharedPreferences for all credentials.',
      );
    }
    final bilibiliCookie = await secureCredentialStore.read(
      SensitiveSettingKeys.accountBilibiliCookie,
    );
    final chaturbateCookie = await secureCredentialStore.read(
      SensitiveSettingKeys.accountChaturbateCookie,
    );
    final douyinCookie = await secureCredentialStore.read(
      SensitiveSettingKeys.accountDouyinCookie,
    );
    final stripchatCookie = await secureCredentialStore.read(
      SensitiveSettingKeys.accountStripchatCookie,
    );
    final stripchatMouflonKeys = await secureCredentialStore.read(
      SensitiveSettingKeys.accountStripchatMouflonKeys,
    );
    final twitchCookie = await secureCredentialStore.read(
      SensitiveSettingKeys.accountTwitchCookie,
    );
    final youtubeCookie = await secureCredentialStore.read(
      SensitiveSettingKeys.accountYouTubeCookie,
    );

    if (bilibiliCookie.isEmpty) {
      final fallback = await settingsRepository.readValue<String>(
        SensitiveSettingKeys.accountBilibiliCookie,
      );
      if (fallback != null && fallback.isNotEmpty) {
        AppLog.instance.warn('settings', 'Bilibili cookie loaded from plaintext SharedPreferences fallback.');
      }
    }
    if (chaturbateCookie.isEmpty) {
      final fallback = await settingsRepository.readValue<String>(
        SensitiveSettingKeys.accountChaturbateCookie,
      );
      if (fallback != null && fallback.isNotEmpty) {
        AppLog.instance.warn('settings', 'Chaturbate cookie loaded from plaintext SharedPreferences fallback.');
      }
    }
    if (douyinCookie.isEmpty) {
      final fallback = await settingsRepository.readValue<String>(
        SensitiveSettingKeys.accountDouyinCookie,
      );
      if (fallback != null && fallback.isNotEmpty) {
        AppLog.instance.warn('settings', 'Douyin cookie loaded from plaintext SharedPreferences fallback.');
      }
    }
    if (stripchatCookie.isEmpty) {
      final fallback = await settingsRepository.readValue<String>(
        SensitiveSettingKeys.accountStripchatCookie,
      );
      if (fallback != null && fallback.isNotEmpty) {
        AppLog.instance.warn('settings', 'Stripchat cookie loaded from plaintext SharedPreferences fallback.');
      }
    }
    if (stripchatMouflonKeys.isEmpty) {
      final fallback = await settingsRepository.readValue<String>(
        SensitiveSettingKeys.accountStripchatMouflonKeys,
      );
      if (fallback != null && fallback.isNotEmpty) {
        AppLog.instance.warn('settings', 'Stripchat Mouflon keys loaded from plaintext SharedPreferences fallback.');
      }
    }
    if (twitchCookie.isEmpty) {
      final fallback = await settingsRepository.readValue<String>(
        SensitiveSettingKeys.accountTwitchCookie,
      );
      if (fallback != null && fallback.isNotEmpty) {
        AppLog.instance.warn('settings', 'Twitch cookie loaded from plaintext SharedPreferences fallback.');
      }
    }
    if (youtubeCookie.isEmpty) {
      final fallback = await settingsRepository.readValue<String>(
        SensitiveSettingKeys.accountYouTubeCookie,
      );
      if (fallback != null && fallback.isNotEmpty) {
        AppLog.instance.warn('settings', 'YouTube cookie loaded from plaintext SharedPreferences fallback.');
      }
    }
    return ProviderAccountSettings(
      bilibiliCookie: bilibiliCookie.isNotEmpty
          ? bilibiliCookie
          : await settingsRepository.readValue<String>(
                  SensitiveSettingKeys.accountBilibiliCookie,
                ) ??
                '',
      bilibiliUserId:
          await settingsRepository.readValue<int>('account_bilibili_user_id') ??
          0,
      chaturbateCookie: chaturbateCookie.isNotEmpty
          ? chaturbateCookie
          : await settingsRepository.readValue<String>(
                  SensitiveSettingKeys.accountChaturbateCookie,
                ) ??
                '',
      douyinCookie: douyinCookie.isNotEmpty
          ? douyinCookie
          : await settingsRepository.readValue<String>(
                  SensitiveSettingKeys.accountDouyinCookie,
                ) ??
                '',
      stripchatCookie: stripchatCookie.isNotEmpty
          ? stripchatCookie
          : await settingsRepository.readValue<String>(
                  SensitiveSettingKeys.accountStripchatCookie,
                ) ??
                '',
      stripchatMouflonKeys: StripchatMouflonKeyCache.decode(
        stripchatMouflonKeys.isNotEmpty
            ? stripchatMouflonKeys
            : await settingsRepository.readValue<String>(
                    SensitiveSettingKeys.accountStripchatMouflonKeys,
                  ) ??
                  '',
      ),
      twitchCookie: twitchCookie.isNotEmpty
          ? twitchCookie
          : await settingsRepository.readValue<String>(
                  SensitiveSettingKeys.accountTwitchCookie,
                ) ??
                '',
      youtubeCookie: youtubeCookie.isNotEmpty
          ? youtubeCookie
          : await settingsRepository.readValue<String>(
                  SensitiveSettingKeys.accountYouTubeCookie,
                ) ??
                '',
    );
  }
}

class UpdateProviderAccountSettingsUseCase {
  const UpdateProviderAccountSettingsUseCase(
    this.settingsRepository,
    this.secureCredentialStore, {
    this.providerRegistry,
    this.providerCatalogRevision,
  });

  final SettingsRepository settingsRepository;
  final SecureCredentialStore secureCredentialStore;
  final ProviderRegistry? providerRegistry;
  final ValueNotifier<int>? providerCatalogRevision;

  Future<void> call(ProviderAccountSettings settings) async {
    await secureCredentialStore.ensureReady();
    await secureCredentialStore.write(
      SensitiveSettingKeys.accountBilibiliCookie,
      settings.bilibiliCookie,
    );
    await settingsRepository.writeValue(
      'account_bilibili_user_id',
      settings.bilibiliUserId,
    );
    await secureCredentialStore.write(
      SensitiveSettingKeys.accountChaturbateCookie,
      settings.chaturbateCookie,
    );
    await secureCredentialStore.write(
      SensitiveSettingKeys.accountDouyinCookie,
      settings.douyinCookie,
    );
    await secureCredentialStore.write(
      SensitiveSettingKeys.accountStripchatCookie,
      settings.stripchatCookie,
    );
    await secureCredentialStore.write(
      SensitiveSettingKeys.accountStripchatMouflonKeys,
      settings.stripchatMouflonKeys.encode(),
    );
    await secureCredentialStore.write(
      SensitiveSettingKeys.accountTwitchCookie,
      settings.twitchCookie,
    );
    await secureCredentialStore.write(
      SensitiveSettingKeys.accountYouTubeCookie,
      settings.youtubeCookie,
    );
    if (secureCredentialStore.storesSecureValuesSeparately) {
      await settingsRepository.remove(
        SensitiveSettingKeys.accountBilibiliCookie,
      );
      await settingsRepository.remove(
        SensitiveSettingKeys.accountChaturbateCookie,
      );
      await settingsRepository.remove(SensitiveSettingKeys.accountDouyinCookie);
      await settingsRepository.remove(
        SensitiveSettingKeys.accountStripchatCookie,
      );
      await settingsRepository.remove(
        SensitiveSettingKeys.accountStripchatMouflonKeys,
      );
      await settingsRepository.remove(SensitiveSettingKeys.accountTwitchCookie);
      await settingsRepository.remove(
        SensitiveSettingKeys.accountYouTubeCookie,
      );
    }
    providerRegistry?.invalidate(ProviderId.bilibili);
    providerRegistry?.invalidate(ProviderId.chaturbate);
    providerRegistry?.invalidate(ProviderId.douyin);
    providerRegistry?.invalidate(ProviderId.stripchat);
    providerRegistry?.invalidate(ProviderId.twitch);
    providerRegistry?.invalidate(ProviderId.youtube);
    if (providerCatalogRevision != null) {
      providerCatalogRevision!.value += 1;
    }
  }
}

enum ProviderAccountHealth { notConfigured, verified, invalid }

enum ProviderAccountKind {
  bilibili,
  chaturbate,
  douyin,
  stripchat,
  twitch,
  youtube,
}

class ProviderAccountView {
  const ProviderAccountView({
    required this.providerId,
    required this.providerName,
    required this.health,
    required this.credentialSummary,
    required this.identitySummary,
    required this.supportsQrLogin,
    this.playbackSummary,
    this.calibrationStatus,
    this.displayName,
    this.statusLabelOverride,
    this.userId,
    this.avatarUrl,
    this.errorMessage,
  });

  final ProviderId providerId;
  final String providerName;
  final ProviderAccountHealth health;
  final String credentialSummary;
  final String identitySummary;
  final bool supportsQrLogin;
  final String? playbackSummary;
  final StripchatCalibrationStatus? calibrationStatus;
  final String? displayName;
  final String? statusLabelOverride;
  final int? userId;
  final String? avatarUrl;
  final String? errorMessage;

  bool get isConfigured => health != ProviderAccountHealth.notConfigured;
}

class ProviderAccountDashboard {
  const ProviderAccountDashboard({
    required this.settings,
    required this.bilibili,
    required this.chaturbate,
    required this.douyin,
    required this.stripchat,
    required this.twitch,
    required this.youtube,
  });

  final ProviderAccountSettings settings;
  final ProviderAccountView bilibili;
  final ProviderAccountView chaturbate;
  final ProviderAccountView douyin;
  final ProviderAccountView stripchat;
  final ProviderAccountView twitch;
  final ProviderAccountView youtube;
}

class LoadProviderAccountDashboardUseCase {
  const LoadProviderAccountDashboardUseCase({
    required this.loadSettings,
    required this.updateSettings,
    required this.bilibiliAccountClient,
    required this.douyinAccountClient,
  });

  final LoadProviderAccountSettingsUseCase loadSettings;
  final UpdateProviderAccountSettingsUseCase updateSettings;
  final BilibiliAccountClient bilibiliAccountClient;
  final DouyinAccountClient douyinAccountClient;

  Future<ProviderAccountDashboard> call() async {
    var settings = await loadSettings();
    final bilibili = await _loadBilibili(settings);
    if (bilibili.userId != null &&
        bilibili.userId != 0 &&
        bilibili.userId != settings.bilibiliUserId) {
      settings = settings.copyWith(bilibiliUserId: bilibili.userId);
      await updateSettings(settings);
    }
    final chaturbate = _loadChaturbate(settings);
    final douyin = await _loadDouyin(settings);
    final stripchat = _loadStripchat(settings);
    final twitch = _loadTwitch(settings);
    final youtube = _loadYouTube(settings);
    return ProviderAccountDashboard(
      settings: settings,
      bilibili: bilibili,
      chaturbate: chaturbate,
      douyin: douyin,
      stripchat: stripchat,
      twitch: twitch,
      youtube: youtube,
    );
  }

  Future<ProviderAccountView> _loadBilibili(
    ProviderAccountSettings settings,
  ) async {
    if (settings.bilibiliCookie.isEmpty) {
      return const ProviderAccountView(
        providerId: ProviderId.bilibili,
        providerName: '哔哩哔哩',
        health: ProviderAccountHealth.notConfigured,
        credentialSummary: '未配置 Cookie',
        identitySummary: '可扫码登录或手动填写 Cookie',
        supportsQrLogin: true,
      );
    }

    try {
      final profile = await bilibiliAccountClient.loadProfile(
        cookie: settings.bilibiliCookie,
      );
      return ProviderAccountView(
        providerId: ProviderId.bilibili,
        providerName: '哔哩哔哩',
        health: ProviderAccountHealth.verified,
        credentialSummary: '已配置 ${settings.bilibiliCookie.length} 字符 Cookie',
        identitySummary: '${profile.displayName} · UID ${profile.userId}',
        supportsQrLogin: true,
        displayName: profile.displayName,
        userId: profile.userId,
        avatarUrl: profile.avatarUrl,
      );
    } catch (error) {
      return ProviderAccountView(
        providerId: ProviderId.bilibili,
        providerName: '哔哩哔哩',
        health: ProviderAccountHealth.invalid,
        credentialSummary: 'Cookie 已配置，但校验失败',
        identitySummary: settings.bilibiliUserId == 0
            ? '请重新扫码或更新 Cookie'
            : '上次记录 UID ${settings.bilibiliUserId}',
        supportsQrLogin: true,
        userId: settings.bilibiliUserId == 0 ? null : settings.bilibiliUserId,
        errorMessage: error.toString(),
      );
    }
  }

  Future<ProviderAccountView> _loadDouyin(
    ProviderAccountSettings settings,
  ) async {
    if (settings.douyinCookie.isEmpty) {
      return const ProviderAccountView(
        providerId: ProviderId.douyin,
        providerName: '抖音直播',
        health: ProviderAccountHealth.notConfigured,
        credentialSummary: '未配置 Cookie',
        identitySummary: '浏览直播通常只需游客 Cookie；只有识别账号身份时才需要登录 Cookie',
        supportsQrLogin: false,
      );
    }

    try {
      final profile = await douyinAccountClient.loadProfile(
        cookie: settings.douyinCookie,
      );
      return ProviderAccountView(
        providerId: ProviderId.douyin,
        providerName: '抖音直播',
        health: ProviderAccountHealth.verified,
        credentialSummary: '已配置 ${settings.douyinCookie.length} 字符 Cookie',
        identitySummary: profile.displayName,
        supportsQrLogin: false,
        displayName: profile.displayName,
        avatarUrl: profile.avatarUrl,
      );
    } catch (error) {
      return ProviderAccountView(
        providerId: ProviderId.douyin,
        providerName: '抖音直播',
        health: ProviderAccountHealth.invalid,
        credentialSummary: 'Cookie 已配置，但校验失败',
        identitySummary: '如果只是浏览直播，可继续使用游客 Cookie；若要识别账号身份，请重新登录',
        supportsQrLogin: false,
        errorMessage: error.toString(),
      );
    }
  }

  ProviderAccountView _loadChaturbate(ProviderAccountSettings settings) {
    if (settings.chaturbateCookie.isEmpty) {
      return const ProviderAccountView(
        providerId: ProviderId.chaturbate,
        providerName: 'Chaturbate',
        health: ProviderAccountHealth.notConfigured,
        credentialSummary: '未配置 Cookie',
        identitySummary: '默认可匿名解析；如遇 Cloudflare 或房间页加载失败，再补浏览器 Cookie',
        supportsQrLogin: false,
      );
    }

    final hasClearance = containsChaturbateClearance(settings.chaturbateCookie);
    return ProviderAccountView(
      providerId: ProviderId.chaturbate,
      providerName: 'Chaturbate',
      health: ProviderAccountHealth.verified,
      credentialSummary: hasClearance
          ? '已配置 ${settings.chaturbateCookie.length} 字符 Cookie'
          : '已配置 ${settings.chaturbateCookie.length} 字符 Cookie（未检测到 cf_clearance）',
      identitySummary: hasClearance
          ? '已保存浏览器会话，可用于 Cloudflare / 弹幕预热'
          : '已保存 Cookie；如遇 Cloudflare 建议补全 cf_clearance',
      supportsQrLogin: false,
    );
  }

  ProviderAccountView _loadTwitch(ProviderAccountSettings settings) {
    if (settings.twitchCookie.isEmpty) {
      return const ProviderAccountView(
        providerId: ProviderId.twitch,
        providerName: 'Twitch',
        health: ProviderAccountHealth.notConfigured,
        credentialSummary: '未配置 Cookie',
        identitySummary: '如需补强 Web 辅助播放，可保存网页登录 Cookie',
        supportsQrLogin: false,
      );
    }

    final hasAuthToken = containsCookie(settings.twitchCookie, 'auth-token');
    final hasUniqueId = containsCookie(settings.twitchCookie, 'unique_id');
    return ProviderAccountView(
      providerId: ProviderId.twitch,
      providerName: 'Twitch',
      health: ProviderAccountHealth.verified,
      credentialSummary: '已配置 ${settings.twitchCookie.length} 字符 Cookie',
      identitySummary: hasAuthToken
          ? '已保存登录会话${hasUniqueId ? '，包含 unique_id' : ''}'
          : hasUniqueId
          ? '已保存浏览器会话，包含 unique_id'
          : '已保存浏览器会话',
      supportsQrLogin: false,
    );
  }

  ProviderAccountView _loadStripchat(ProviderAccountSettings settings) {
    final calibrationStatus = settings.stripchatMouflonKeys.effectiveStatus();
    final cookieStatus = inspectStripchatCookie(settings.stripchatCookie);
    final playbackSummary = switch (calibrationStatus) {
      StripchatCalibrationStatus.missing => '未配置手动导入密钥；将使用内置兜底',
      StripchatCalibrationStatus.ready =>
        '已导入 ${settings.stripchatMouflonKeys.records.length} 组手动密钥，可作为 MOUFLON 解码兜底',
      StripchatCalibrationStatus.stale =>
        '已导入 ${settings.stripchatMouflonKeys.records.length} 组手动密钥，建议检查是否仍有效',
      StripchatCalibrationStatus.failed =>
        settings.stripchatMouflonKeys.records.isEmpty
            ? '当前未检测到可用手动密钥'
            : '最近一次手动密钥导入数据无效，当前将继续尝试旧缓存',
    };
    final hasCookie = settings.stripchatCookie.trim().isNotEmpty;
    final hasManualKeys = settings.stripchatMouflonKeys.records.isNotEmpty;
    final credentialParts = <String>[
      hasCookie
          ? '已封存 ${settings.stripchatCookie.length} 字符旧 Cookie（${cookieStatus.cookieCount} 个键）'
          : 'Cookie 已封存',
      hasManualKeys
          ? '已导入 ${settings.stripchatMouflonKeys.records.length} 组手动密钥'
          : '未导入手动密钥',
    ];
    final playbackParts = <String>[
      if (hasCookie) '已保存旧${cookieStatus.cookieKindLabel}，默认播放不会使用',
      '默认播放使用本地 MOUFLON 解码，不再依赖 WebView Cookie',
      playbackSummary,
    ];
    return ProviderAccountView(
      providerId: ProviderId.stripchat,
      providerName: 'Stripchat',
      health: hasManualKeys
          ? ProviderAccountHealth.verified
          : ProviderAccountHealth.notConfigured,
      credentialSummary: credentialParts.join('；'),
      identitySummary: hasManualKeys
          ? '已保存播放兜底密钥；Cookie/WebView 路径已封存'
          : hasCookie
          ? '仅保留旧 Cookie 记录；当前主线路不会使用'
          : '当前未保存手动密钥；将只尝试内置兜底密钥',
      playbackSummary: playbackParts.join('；'),
      calibrationStatus: calibrationStatus,
      supportsQrLogin: false,
      statusLabelOverride: hasManualKeys ? null : '未配置',
    );
  }

  ProviderAccountView _loadYouTube(ProviderAccountSettings settings) {
    if (settings.youtubeCookie.isEmpty) {
      return const ProviderAccountView(
        providerId: ProviderId.youtube,
        providerName: 'YouTube',
        health: ProviderAccountHealth.notConfigured,
        credentialSummary: '无需登录',
        identitySummary: '如需手动保存网页登录 Cookie，可选配置；当前播放链路不会直接使用',
        supportsQrLogin: false,
        statusLabelOverride: '无需登录',
      );
    }

    final hasAuthSession =
        containsCookie(settings.youtubeCookie, '__Secure-1PSID') ||
        containsCookie(settings.youtubeCookie, 'SID') ||
        containsCookie(settings.youtubeCookie, 'SAPISID');
    return ProviderAccountView(
      providerId: ProviderId.youtube,
      providerName: 'YouTube',
      health: ProviderAccountHealth.verified,
      credentialSummary: '已配置 ${settings.youtubeCookie.length} 字符 Cookie',
      identitySummary: hasAuthSession
          ? '已保存登录会话；当前播放链路不会直接使用'
          : '已保存浏览器会话；当前播放链路不会直接使用',
      supportsQrLogin: false,
    );
  }
}

bool containsChaturbateClearance(String cookie) {
  return containsCookie(cookie, 'cf_clearance');
}

bool containsCookie(String cookie, String name) {
  return cookie
      .split(';')
      .map((part) => part.trim())
      .any((part) => part.startsWith('$name='));
}

StripchatCookieStatus inspectStripchatCookie(String cookie) {
  final names = parseCookieNames(cookie);
  final hasLoginSignals = names.any((name) {
    final lower = name.toLowerCase();
    if (lower == 'stripchat_com_guestid' ||
        lower == 'stripchat_com_firstvisit') {
      return false;
    }
    return const <String>[
      'auth',
      'token',
      'session',
      'remember',
      'login',
      'user',
      'member',
      'account',
      'jwt',
      'sid',
      'sess',
      'uid',
    ].any(lower.contains);
  });
  final hasVisitorSignals = names.any((name) {
    final lower = name.toLowerCase();
    return lower == 'stripchat_com_guestid' ||
        lower == 'stripchat_com_firstvisit' ||
        lower == '__cf_bm' ||
        lower == '_cfuvid' ||
        lower == 'cf_clearance' ||
        lower == 'alreadyvisited' ||
        lower == 'isvisitorsagreementaccepted' ||
        lower == 'localedomain';
  });
  final previewNames = names.take(4).join(', ');
  final cookieKindLabel = hasLoginSignals
      ? '疑似登录态 Cookie'
      : hasVisitorSignals
      ? '游客/风控 Cookie'
      : '浏览器 Cookie';
  final identitySummary = hasLoginSignals
      ? '已保存疑似登录态 Cookie${previewNames.isEmpty ? '' : '；关键字段：$previewNames'}'
      : hasVisitorSignals
      ? '已保存游客/风控 Cookie，可用于页面验证${previewNames.isEmpty ? '' : '；关键字段：$previewNames'}'
      : names.isEmpty
      ? '未检测到 Cookie'
      : '已保存浏览器 Cookie${previewNames.isEmpty ? '' : '；关键字段：$previewNames'}';
  return StripchatCookieStatus(
    cookieCount: names.length,
    hasLoginSignals: hasLoginSignals,
    hasVisitorSignals: hasVisitorSignals,
    cookieKindLabel: cookieKindLabel,
    identitySummary: identitySummary,
  );
}

List<String> parseCookieNames(String cookie) {
  final names = <String>[];
  final seen = <String>{};
  for (final part in cookie.split(';')) {
    final normalized = part.trim();
    if (normalized.isEmpty) {
      continue;
    }
    final separator = normalized.indexOf('=');
    if (separator <= 0) {
      continue;
    }
    final name = normalized.substring(0, separator).trim();
    if (name.isEmpty || !seen.add(name)) {
      continue;
    }
    names.add(name);
  }
  return List<String>.unmodifiable(names);
}

class StripchatCookieStatus {
  const StripchatCookieStatus({
    required this.cookieCount,
    required this.hasLoginSignals,
    required this.hasVisitorSignals,
    required this.cookieKindLabel,
    required this.identitySummary,
  });

  final int cookieCount;
  final bool hasLoginSignals;
  final bool hasVisitorSignals;
  final String cookieKindLabel;
  final String identitySummary;
}

class CreateBilibiliQrLoginSessionUseCase {
  const CreateBilibiliQrLoginSessionUseCase(this.accountClient);

  final BilibiliAccountClient accountClient;

  Future<BilibiliQrLoginSession> call() {
    return accountClient.createQrLoginSession();
  }
}

class PollBilibiliQrLoginSessionUseCase {
  const PollBilibiliQrLoginSessionUseCase({
    required this.accountClient,
    required this.loadSettings,
    required this.updateSettings,
  });

  final BilibiliAccountClient accountClient;
  final LoadProviderAccountSettingsUseCase loadSettings;
  final UpdateProviderAccountSettingsUseCase updateSettings;

  Future<BilibiliQrLoginProgress> call(String qrcodeKey) async {
    final result = await accountClient.pollQrLogin(qrcodeKey: qrcodeKey);
    switch (result.status) {
      case BilibiliQrLoginStatus.pending:
        return const BilibiliQrLoginProgress.pending();
      case BilibiliQrLoginStatus.scanned:
        return const BilibiliQrLoginProgress.scanned();
      case BilibiliQrLoginStatus.expired:
        return const BilibiliQrLoginProgress.expired();
      case BilibiliQrLoginStatus.success:
        final profile = await accountClient.loadProfile(cookie: result.cookie);
        final current = await loadSettings();
        await updateSettings(
          current.copyWith(
            bilibiliCookie: result.cookie,
            bilibiliUserId: profile.userId,
          ),
        );
        return BilibiliQrLoginProgress.success(
          displayName: profile.displayName,
          userId: profile.userId,
        );
    }
  }
}

class BilibiliQrLoginProgress {
  const BilibiliQrLoginProgress._({
    required this.status,
    this.displayName,
    this.userId,
  });

  const BilibiliQrLoginProgress.pending()
    : this._(status: BilibiliQrLoginStatus.pending);

  const BilibiliQrLoginProgress.scanned()
    : this._(status: BilibiliQrLoginStatus.scanned);

  const BilibiliQrLoginProgress.expired()
    : this._(status: BilibiliQrLoginStatus.expired);

  const BilibiliQrLoginProgress.success({
    required String displayName,
    required int userId,
  }) : this._(
         status: BilibiliQrLoginStatus.success,
         displayName: displayName,
         userId: userId,
       );

  final BilibiliQrLoginStatus status;
  final String? displayName;
  final int? userId;
}

class ClearProviderAccountUseCase {
  const ClearProviderAccountUseCase({
    required this.loadSettings,
    required this.updateSettings,
  });

  final LoadProviderAccountSettingsUseCase loadSettings;
  final UpdateProviderAccountSettingsUseCase updateSettings;

  Future<void> call(ProviderAccountKind kind) async {
    final settings = await loadSettings();
    switch (kind) {
      case ProviderAccountKind.bilibili:
        await updateSettings(
          settings.copyWith(bilibiliCookie: '', bilibiliUserId: 0),
        );
        return;
      case ProviderAccountKind.chaturbate:
        await updateSettings(settings.copyWith(chaturbateCookie: ''));
        return;
      case ProviderAccountKind.douyin:
        await updateSettings(settings.copyWith(douyinCookie: ''));
        return;
      case ProviderAccountKind.stripchat:
        await updateSettings(
          settings.copyWith(
            stripchatCookie: '',
            stripchatMouflonKeys: settings.stripchatMouflonKeys.clear(),
          ),
        );
        return;
      case ProviderAccountKind.twitch:
        await updateSettings(settings.copyWith(twitchCookie: ''));
        return;
      case ProviderAccountKind.youtube:
        await updateSettings(settings.copyWith(youtubeCookie: ''));
        return;
    }
  }
}
