import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:live_core/live_core.dart';
import 'package:nolive_app/src/app/bootstrap/bootstrap.dart';
import 'package:nolive_app/src/app/routing/app_routes.dart';
import 'package:nolive_app/src/features/settings/application/manage_provider_accounts_use_case.dart';
import 'package:nolive_app/src/features/settings/presentation/chaturbate_web_login_page.dart';
import 'package:nolive_app/src/shared/presentation/widgets/app_surface_card.dart';
import 'package:nolive_app/src/shared/presentation/widgets/empty_state_card.dart';
import 'package:nolive_app/src/shared/presentation/widgets/provider_badge.dart';
import 'package:nolive_app/src/shared/presentation/widgets/section_header.dart';

class AccountSettingsPage extends StatefulWidget {
  const AccountSettingsPage({required this.bootstrap, super.key});

  final AppBootstrap bootstrap;

  @override
  State<AccountSettingsPage> createState() => _AccountSettingsPageState();
}

class _AccountSettingsPageState extends State<AccountSettingsPage> {
  late Future<ProviderAccountDashboard> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.bootstrap.loadProviderAccountDashboard();
  }

  Future<void> _reload() async {
    setState(() {
      _future = widget.bootstrap.loadProviderAccountDashboard();
    });
    await _future;
  }

  Future<void> _openBilibiliQrLogin() async {
    final result =
        await Navigator.of(context).pushNamed(AppRoutes.bilibiliQrLogin);
    if (result == true && mounted) {
      await _reload();
    }
  }

  Future<void> _clearAccount(ProviderAccountKind kind) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除账号凭据'),
        content: Text(
          switch (kind) {
            ProviderAccountKind.bilibili => '确定要清除哔哩哔哩账号信息吗？',
            ProviderAccountKind.chaturbate => '确定要清除 Chaturbate Cookie 吗？',
            ProviderAccountKind.douyin => '确定要清除抖音账号 Cookie 吗？',
            ProviderAccountKind.twitch => '确定要清除 Twitch Cookie 吗？',
            ProviderAccountKind.youtube => '确定要清除 YouTube Cookie 吗？',
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await widget.bootstrap.clearProviderAccount(kind);
    if (!mounted) {
      return;
    }
    await _reload();
  }

  Future<void> _editBilibiliCookie(ProviderAccountDashboard dashboard) async {
    final result = await _showCookieEditor(
      title: '哔哩哔哩 Cookie',
      subtitle: '支持粘贴完整 Cookie header。保存后会自动校验昵称并同步 UID。',
      initialCookie: dashboard.settings.bilibiliCookie,
      initialUserId: dashboard.settings.bilibiliUserId,
      showUserId: true,
    );
    if (result == null) {
      return;
    }
    await widget.bootstrap.updateProviderAccountSettings(
      dashboard.settings.copyWith(
        bilibiliCookie: result.cookie,
        bilibiliUserId: result.userId,
      ),
    );
    if (!mounted) {
      return;
    }
    await _reload();
  }

  Future<void> _editDouyinCookie(ProviderAccountDashboard dashboard) async {
    final result = await _showCookieEditor(
      title: '抖音 Cookie',
      subtitle: '可粘贴网页登录保存的完整 Cookie。',
      initialCookie: dashboard.settings.douyinCookie,
    );
    if (result == null) {
      return;
    }
    await widget.bootstrap.updateProviderAccountSettings(
      dashboard.settings.copyWith(douyinCookie: result.cookie),
    );
    if (!mounted) {
      return;
    }
    await _reload();
  }

  Future<void> _editChaturbateCookie(ProviderAccountDashboard dashboard) async {
    final result = await _showCookieEditor(
      title: 'Chaturbate Cookie',
      subtitle: '建议直接粘贴浏览器完整 Cookie；有 `cf_clearance` 一起带上。',
      initialCookie: dashboard.settings.chaturbateCookie,
    );
    if (result == null) {
      return;
    }
    await widget.bootstrap.updateProviderAccountSettings(
      dashboard.settings.copyWith(chaturbateCookie: result.cookie),
    );
    if (!mounted) {
      return;
    }
    await _reload();
  }

  Future<void> _openChaturbateWebLogin(
    ProviderAccountDashboard dashboard,
  ) async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const ChaturbateWebLoginPage(),
      ),
    );
    if (result == null || result.trim().isEmpty) {
      return;
    }
    await widget.bootstrap.updateProviderAccountSettings(
      dashboard.settings.copyWith(chaturbateCookie: result.trim()),
    );
    if (!mounted) {
      return;
    }
    await _reload();
  }

  Future<void> _openDouyinWebLogin(ProviderAccountDashboard dashboard) async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const DouyinWebLoginPage(),
      ),
    );
    if (result == null || result.trim().isEmpty) {
      return;
    }
    await widget.bootstrap.updateProviderAccountSettings(
      dashboard.settings.copyWith(douyinCookie: result.trim()),
    );
    if (!mounted) {
      return;
    }
    await _reload();
  }

  Future<void> _editTwitchCookie(ProviderAccountDashboard dashboard) async {
    final result = await _showCookieEditor(
      title: 'Twitch Cookie',
      subtitle: '可粘贴网页登录保存的完整 Cookie；建议保留 `unique_id` 与登录态 Cookie。',
      initialCookie: dashboard.settings.twitchCookie,
    );
    if (result == null) {
      return;
    }
    await widget.bootstrap.updateProviderAccountSettings(
      dashboard.settings.copyWith(twitchCookie: result.cookie),
    );
    if (!mounted) {
      return;
    }
    await _reload();
  }

  Future<void> _editYouTubeCookie(ProviderAccountDashboard dashboard) async {
    final result = await _showCookieEditor(
      title: 'YouTube Cookie',
      subtitle: '可粘贴网页登录保存的完整 Cookie；当前播放链路不会直接消费这份设置。',
      initialCookie: dashboard.settings.youtubeCookie,
    );
    if (result == null) {
      return;
    }
    await widget.bootstrap.updateProviderAccountSettings(
      dashboard.settings.copyWith(youtubeCookie: result.cookie),
    );
    if (!mounted) {
      return;
    }
    await _reload();
  }

  Future<void> _openTwitchWebLogin(ProviderAccountDashboard dashboard) async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const TwitchWebLoginPage(),
      ),
    );
    if (result == null || result.trim().isEmpty) {
      return;
    }
    await widget.bootstrap.updateProviderAccountSettings(
      dashboard.settings.copyWith(twitchCookie: result.trim()),
    );
    if (!mounted) {
      return;
    }
    await _reload();
  }

  bool get _supportsEmbeddedWebLogin =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<_CookieDialogResult?> _showCookieEditor({
    required String title,
    required String subtitle,
    required String initialCookie,
    int initialUserId = 0,
    bool showUserId = false,
  }) {
    final cookieController = TextEditingController(text: initialCookie);
    final userIdController = TextEditingController(
      text: initialUserId == 0 ? '' : initialUserId.toString(),
    );

    return showDialog<_CookieDialogResult>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final preview = _parseCookieEntries(cookieController.text);
            return AlertDialog(
              title: Text(title),
              content: SizedBox(
                width: 640,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: cookieController,
                        maxLines: 6,
                        minLines: 4,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: '完整 Cookie',
                        ),
                      ),
                      if (showUserId) ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: userIdController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: '用户 ID（可留空，校验后会自动补齐）',
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Text(
                        'Cookie 预览',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      if (preview.isEmpty)
                        Text(
                          '当前还没有可识别字段。',
                          style: Theme.of(context).textTheme.bodySmall,
                        )
                      else
                        SizedBox(
                          height: 180,
                          child: ListView.separated(
                            itemCount: preview.length,
                            separatorBuilder: (context, dividerIndex) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final entry = preview[index];
                              return ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text(entry.key),
                                subtitle: Text(entry.value),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.of(context).pop(
                      _CookieDialogResult(
                        cookie: _normalizeCookie(cookieController.text),
                        userId: int.tryParse(userIdController.text.trim()) ?? 0,
                      ),
                    );
                  },
                  child: const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('账号管理'),
        actions: [
          IconButton(
            onPressed: _reload,
            tooltip: '刷新状态',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<ProviderAccountDashboard>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator.adaptive());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
              children: [
                EmptyStateCard(
                  title: '账号状态加载失败',
                  message: '${snapshot.error}',
                  icon: Icons.error_outline,
                ),
              ],
            );
          }

          final dashboard = snapshot.data!;
          final scheme = Theme.of(context).colorScheme;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
            children: [
              SectionHeader(
                title: '账号管理',
                trailing: FilledButton.tonalIcon(
                  onPressed: _reload,
                  icon: const Icon(Icons.refresh),
                  label: const Text('刷新状态'),
                ),
              ),
              const SizedBox(height: 12),
              AppSurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ProviderAccountListItem(
                      providerId: dashboard.bilibili.providerId,
                      title: dashboard.bilibili.providerName,
                      status: _statusMeta(
                        dashboard.bilibili.health,
                        scheme,
                      ),
                      credentialSummary: dashboard.bilibili.credentialSummary,
                      identitySummary: dashboard.bilibili.identitySummary,
                      errorMessage: dashboard.bilibili.errorMessage,
                      actions: [
                        FilledButton.tonalIcon(
                          onPressed: _openBilibiliQrLogin,
                          icon: const Icon(Icons.qr_code_2),
                          label: const Text('扫码登录'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _editBilibiliCookie(dashboard),
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('编辑 Cookie'),
                        ),
                        OutlinedButton.icon(
                          onPressed: dashboard.bilibili.isConfigured
                              ? () =>
                                  _clearAccount(ProviderAccountKind.bilibili)
                              : null,
                          icon: const Icon(Icons.logout),
                          label: const Text('清除凭据'),
                        ),
                        TextButton.icon(
                          onPressed: _reload,
                          icon: const Icon(Icons.verified_outlined),
                          label: const Text('校验状态'),
                        ),
                      ],
                    ),
                    const Divider(height: 32),
                    const _StaticProviderListItem(
                      providerId: ProviderId.douyu,
                      title: '斗鱼直播',
                    ),
                    const Divider(height: 32),
                    const _StaticProviderListItem(
                      providerId: ProviderId.huya,
                      title: '虎牙直播',
                    ),
                    const Divider(height: 32),
                    _ProviderAccountListItem(
                      providerId: dashboard.chaturbate.providerId,
                      title: dashboard.chaturbate.providerName,
                      status: _statusMeta(
                        dashboard.chaturbate.health,
                        scheme,
                      ),
                      credentialSummary: dashboard.chaturbate.credentialSummary,
                      identitySummary: dashboard.chaturbate.identitySummary,
                      errorMessage: dashboard.chaturbate.errorMessage,
                      actions: [
                        if (_supportsEmbeddedWebLogin)
                          FilledButton.tonalIcon(
                            onPressed: () => _openChaturbateWebLogin(dashboard),
                            icon: const Icon(Icons.language_outlined),
                            label: const Text('网页登录'),
                          ),
                        OutlinedButton.icon(
                          onPressed: () => _editChaturbateCookie(dashboard),
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('编辑 Cookie'),
                        ),
                        OutlinedButton.icon(
                          onPressed: dashboard.chaturbate.isConfigured
                              ? () =>
                                  _clearAccount(ProviderAccountKind.chaturbate)
                              : null,
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('清除 Cookie'),
                        ),
                        TextButton.icon(
                          onPressed: _reload,
                          icon: const Icon(Icons.verified_outlined),
                          label: const Text('刷新状态'),
                        ),
                      ],
                    ),
                    const Divider(height: 32),
                    _ProviderAccountListItem(
                      providerId: dashboard.douyin.providerId,
                      title: dashboard.douyin.providerName,
                      status: _statusMeta(
                        dashboard.douyin.health,
                        scheme,
                      ),
                      credentialSummary: dashboard.douyin.credentialSummary,
                      identitySummary: dashboard.douyin.identitySummary,
                      errorMessage: dashboard.douyin.errorMessage,
                      actions: [
                        if (_supportsEmbeddedWebLogin)
                          FilledButton.tonalIcon(
                            onPressed: () => _openDouyinWebLogin(dashboard),
                            icon: const Icon(Icons.language_outlined),
                            label: const Text('网页登录'),
                          ),
                        OutlinedButton.icon(
                          onPressed: () => _editDouyinCookie(dashboard),
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('编辑 Cookie'),
                        ),
                        OutlinedButton.icon(
                          onPressed: dashboard.douyin.isConfigured
                              ? () => _clearAccount(ProviderAccountKind.douyin)
                              : null,
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('清除 Cookie'),
                        ),
                        TextButton.icon(
                          onPressed: _reload,
                          icon: const Icon(Icons.verified_outlined),
                          label: const Text('校验状态'),
                        ),
                      ],
                    ),
                    const Divider(height: 32),
                    _ProviderAccountListItem(
                      providerId: dashboard.twitch.providerId,
                      title: dashboard.twitch.providerName,
                      status: _statusMeta(
                        dashboard.twitch.health,
                        scheme,
                      ),
                      credentialSummary: dashboard.twitch.credentialSummary,
                      identitySummary: dashboard.twitch.identitySummary,
                      errorMessage: dashboard.twitch.errorMessage,
                      actions: [
                        if (_supportsEmbeddedWebLogin)
                          FilledButton.tonalIcon(
                            onPressed: () => _openTwitchWebLogin(dashboard),
                            icon: const Icon(Icons.language_outlined),
                            label: const Text('网页登录'),
                          ),
                        OutlinedButton.icon(
                          onPressed: () => _editTwitchCookie(dashboard),
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('编辑 Cookie'),
                        ),
                        OutlinedButton.icon(
                          onPressed: dashboard.twitch.isConfigured
                              ? () => _clearAccount(ProviderAccountKind.twitch)
                              : null,
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('清除 Cookie'),
                        ),
                        TextButton.icon(
                          onPressed: _reload,
                          icon: const Icon(Icons.verified_outlined),
                          label: const Text('刷新状态'),
                        ),
                      ],
                    ),
                    const Divider(height: 32),
                    _ProviderAccountListItem(
                      providerId: dashboard.youtube.providerId,
                      title: dashboard.youtube.providerName,
                      status: _statusMeta(
                        dashboard.youtube.health,
                        scheme,
                      ),
                      credentialSummary: dashboard.youtube.credentialSummary,
                      identitySummary: dashboard.youtube.identitySummary,
                      errorMessage: dashboard.youtube.errorMessage,
                      actions: [
                        OutlinedButton.icon(
                          onPressed: () => _editYouTubeCookie(dashboard),
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('编辑 Cookie'),
                        ),
                        OutlinedButton.icon(
                          onPressed: dashboard.youtube.isConfigured
                              ? () => _clearAccount(ProviderAccountKind.youtube)
                              : null,
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('清除 Cookie'),
                        ),
                        TextButton.icon(
                          onPressed: _reload,
                          icon: const Icon(Icons.verified_outlined),
                          label: const Text('刷新状态'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ProviderAccountListItem extends StatelessWidget {
  const _ProviderAccountListItem({
    required this.providerId,
    required this.title,
    required this.status,
    required this.credentialSummary,
    required this.identitySummary,
    required this.actions,
    this.errorMessage,
  });

  final ProviderId providerId;
  final String title;
  final _StatusMeta status;
  final String credentialSummary;
  final String identitySummary;
  final String? errorMessage;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ProviderLogoBadge(providerId: providerId),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      _StatusChip(status: status),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(credentialSummary),
                  const SizedBox(height: 4),
                  Text(
                    identitySummary,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  if (errorMessage != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      errorMessage!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.error,
                          ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(left: 54),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: actions,
            ),
          ),
        ],
      ],
    );
  }
}

class _StaticProviderListItem extends StatelessWidget {
  const _StaticProviderListItem({
    required this.providerId,
    required this.title,
  });

  final ProviderId providerId;
  final String title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        _ProviderLogoBadge(providerId: providerId),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        _StatusChip(
          status: _StatusMeta(
            label: '无需登录',
            backgroundColor: scheme.surfaceContainerHighest,
            foregroundColor: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _ProviderLogoBadge extends StatelessWidget {
  const _ProviderLogoBadge({required this.providerId});

  final ProviderId providerId;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final assetPath = ProviderBadge.logoAssetOf(providerId);
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: assetPath == null
          ? Icon(
              ProviderBadge.iconOf(providerId),
              color: ProviderBadge.accentColorOf(providerId),
            )
          : Image.asset(
              assetPath,
              width: 24,
              height: 24,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
              errorBuilder: (context, error, stackTrace) => Icon(
                ProviderBadge.iconOf(providerId),
                color: ProviderBadge.accentColorOf(providerId),
              ),
            ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final _StatusMeta status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: status.backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: status.foregroundColor,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _StatusMeta {
  const _StatusMeta({
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final String label;
  final Color backgroundColor;
  final Color foregroundColor;
}

_StatusMeta _statusMeta(ProviderAccountHealth health, ColorScheme scheme) {
  return switch (health) {
    ProviderAccountHealth.notConfigured => _StatusMeta(
        label: '未配置',
        backgroundColor: scheme.surfaceContainerHighest,
        foregroundColor: scheme.onSurfaceVariant,
      ),
    ProviderAccountHealth.verified => _StatusMeta(
        label: '已验证',
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
      ),
    ProviderAccountHealth.invalid => _StatusMeta(
        label: '需更新',
        backgroundColor: scheme.errorContainer,
        foregroundColor: scheme.onErrorContainer,
      ),
  };
}

class _CookieDialogResult {
  const _CookieDialogResult({required this.cookie, required this.userId});

  final String cookie;
  final int userId;
}

List<MapEntry<String, String>> _parseCookieEntries(String raw) {
  final sanitized = raw
      .replaceAll('\n', ';')
      .replaceAll('\r', ';')
      .replaceFirst(RegExp(r'^cookie\s*:\s*', caseSensitive: false), '');
  final entries = <MapEntry<String, String>>[];
  for (final part in sanitized.split(';')) {
    final segment = part.trim();
    if (segment.isEmpty || !segment.contains('=')) {
      continue;
    }
    final index = segment.indexOf('=');
    final key = segment.substring(0, index).trim();
    final value = segment.substring(index + 1).trim();
    if (key.isEmpty || value.isEmpty) {
      continue;
    }
    entries.removeWhere((entry) => entry.key == key);
    entries.add(MapEntry(key, value));
  }
  return entries;
}

String _normalizeCookie(String raw) {
  final entries = _parseCookieEntries(raw);
  if (entries.isEmpty) {
    return raw.trim();
  }
  return entries.map((entry) => '${entry.key}=${entry.value}').join('; ');
}
