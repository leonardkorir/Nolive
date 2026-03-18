import 'package:flutter/foundation.dart';
import 'package:live_core/live_core.dart';
import 'package:live_providers/live_providers.dart';
import 'package:live_storage/live_storage.dart';

class ProviderAccountSettings {
  const ProviderAccountSettings({
    required this.bilibiliCookie,
    required this.bilibiliUserId,
    required this.chaturbateCookie,
    required this.douyinCookie,
  });

  final String bilibiliCookie;
  final int bilibiliUserId;
  final String chaturbateCookie;
  final String douyinCookie;

  ProviderAccountSettings copyWith({
    String? bilibiliCookie,
    int? bilibiliUserId,
    String? chaturbateCookie,
    String? douyinCookie,
  }) {
    return ProviderAccountSettings(
      bilibiliCookie: bilibiliCookie ?? this.bilibiliCookie,
      bilibiliUserId: bilibiliUserId ?? this.bilibiliUserId,
      chaturbateCookie: chaturbateCookie ?? this.chaturbateCookie,
      douyinCookie: douyinCookie ?? this.douyinCookie,
    );
  }
}

class LoadProviderAccountSettingsUseCase {
  const LoadProviderAccountSettingsUseCase(this.settingsRepository);

  final SettingsRepository settingsRepository;

  Future<ProviderAccountSettings> call() async {
    return ProviderAccountSettings(
      bilibiliCookie: await settingsRepository
              .readValue<String>('account_bilibili_cookie') ??
          '',
      bilibiliUserId:
          await settingsRepository.readValue<int>('account_bilibili_user_id') ??
              0,
      chaturbateCookie: await settingsRepository
              .readValue<String>('account_chaturbate_cookie') ??
          '',
      douyinCookie:
          await settingsRepository.readValue<String>('account_douyin_cookie') ??
              '',
    );
  }
}

class UpdateProviderAccountSettingsUseCase {
  const UpdateProviderAccountSettingsUseCase(
    this.settingsRepository, {
    this.providerRegistry,
    this.providerCatalogRevision,
  });

  final SettingsRepository settingsRepository;
  final ProviderRegistry? providerRegistry;
  final ValueNotifier<int>? providerCatalogRevision;

  Future<void> call(ProviderAccountSettings settings) async {
    await settingsRepository.writeValue(
      'account_bilibili_cookie',
      settings.bilibiliCookie,
    );
    await settingsRepository.writeValue(
      'account_bilibili_user_id',
      settings.bilibiliUserId,
    );
    await settingsRepository.writeValue(
      'account_chaturbate_cookie',
      settings.chaturbateCookie,
    );
    await settingsRepository.writeValue(
      'account_douyin_cookie',
      settings.douyinCookie,
    );
    providerRegistry?.invalidate(ProviderId.bilibili);
    providerRegistry?.invalidate(ProviderId.chaturbate);
    providerRegistry?.invalidate(ProviderId.douyin);
    if (providerCatalogRevision != null) {
      providerCatalogRevision!.value += 1;
    }
  }
}

enum ProviderAccountHealth { notConfigured, verified, invalid }

enum ProviderAccountKind { bilibili, chaturbate, douyin }

class ProviderAccountView {
  const ProviderAccountView({
    required this.providerId,
    required this.providerName,
    required this.health,
    required this.credentialSummary,
    required this.identitySummary,
    required this.supportsQrLogin,
    this.displayName,
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
  final String? displayName;
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
  });

  final ProviderAccountSettings settings;
  final ProviderAccountView bilibili;
  final ProviderAccountView chaturbate;
  final ProviderAccountView douyin;
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
    return ProviderAccountDashboard(
      settings: settings,
      bilibili: bilibili,
      chaturbate: chaturbate,
      douyin: douyin,
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
        identitySummary: '可网页登录或手动填写 Cookie',
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
        identitySummary: '建议重新登录并更新 Cookie',
        supportsQrLogin: false,
        errorMessage: error.toString(),
      );
    }
  }

  ProviderAccountView _loadChaturbate(
    ProviderAccountSettings settings,
  ) {
    if (settings.chaturbateCookie.isEmpty) {
      return const ProviderAccountView(
        providerId: ProviderId.chaturbate,
        providerName: 'Chaturbate',
        health: ProviderAccountHealth.notConfigured,
        credentialSummary: '未配置 Cookie',
        identitySummary: '建议网页登录后保存 Cookie',
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
      identitySummary: hasClearance ? '已保存浏览器会话' : '建议补全 cf_clearance',
      supportsQrLogin: false,
    );
  }
}

bool containsChaturbateClearance(String cookie) {
  return cookie
      .split(';')
      .map((part) => part.trim())
      .any((part) => part.startsWith('cf_clearance='));
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
    }
  }
}
