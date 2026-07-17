import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nolive_app/src/app/runtime_bridges/hls_proxy_platform_adapter_impl.dart';
import 'package:nolive_app/src/app/runtime_bridges/linux_desktop_webview_adapter.dart';
import 'package:nolive_app/src/shared/presentation/app_feedback.dart';
import 'package:nolive_app/src/shared/presentation/widgets/app_surface_card.dart';

/// Linux desktop web-login chrome that drives a separate WebKitGTK window
/// (via [LinuxDesktopWebLoginSession]) and saves cookies into app storage.
class LinuxDesktopWebLoginPage extends StatefulWidget {
  const LinuxDesktopWebLoginPage({
    required this.title,
    required this.initialUrl,
    required this.userAgent,
    required this.instructions,
    required this.allowedHostSuffixes,
    this.seedUrls = const <String>[],
    this.quickLinks = const <LinuxWebLoginQuickLink>[],
    super.key,
  });

  final String title;
  final String initialUrl;
  final String userAgent;
  final String instructions;
  final List<String> allowedHostSuffixes;
  final List<String> seedUrls;
  final List<LinuxWebLoginQuickLink> quickLinks;

  @override
  State<LinuxDesktopWebLoginPage> createState() =>
      _LinuxDesktopWebLoginPageState();
}

class LinuxWebLoginQuickLink {
  const LinuxWebLoginQuickLink({
    required this.label,
    required this.url,
    required this.icon,
  });

  final String label;
  final String url;
  final IconData icon;
}

class _LinuxDesktopWebLoginPageState extends State<LinuxDesktopWebLoginPage> {
  LinuxDesktopWebLoginSession? _session;
  Timer? _pollTimer;
  bool _saving = false;
  bool _opening = true;
  bool _closing = false;
  String _status = '正在打开桌面 WebView 窗口…';
  int _cookieCount = 0;
  String _cookiePreview = '';

  @override
  void initState() {
    super.initState();
    unawaited(_openSession());
  }

  Future<void> _openSession() async {
    try {
      final session = LinuxDesktopWebLoginSession(
        initialUrl: widget.initialUrl,
        title: widget.title,
        userAgent: widget.userAgent,
        cookieJar: linuxDesktopCookieJar,
        allowedHostSuffixes: widget.allowedHostSuffixes,
      );
      await session.open();
      if (!mounted) {
        await session.close();
        return;
      }
      setState(() {
        _session = session;
        _opening = false;
        _status = '请在弹出的浏览器窗口中完成登录，然后点「保存 Cookie」。';
      });
      _pollTimer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => unawaited(_refreshCookiePreview()),
      );
      await _refreshCookiePreview();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _opening = false;
        _status = '无法打开 WebView：$error';
      });
    }
  }

  Future<void> _refreshCookiePreview() async {
    final session = _session;
    if (session == null || !mounted || _closing) return;
    try {
      final header = await session.exportCookies().timeout(
        const Duration(seconds: 4),
      );
      if (!mounted || _closing || !identical(_session, session)) return;
      final map = _parseCookieHeader(header);
      if (!mounted) return;
      setState(() {
        _cookieCount = map.length;
        _cookiePreview = map.keys.take(12).join(', ');
      });
    } catch (_) {
      // ignore transient webview errors while user still navigates
    }
  }

  Map<String, String> _parseCookieHeader(String header) {
    final map = <String, String>{};
    for (final part in header.split(';')) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;
      final eq = trimmed.indexOf('=');
      if (eq <= 0) continue;
      final name = trimmed.substring(0, eq).trim();
      final value = trimmed.substring(eq + 1).trim();
      if (name.isEmpty || value.isEmpty) continue;
      map[name] = value;
    }
    return map;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final session = _session;
      if (session == null) {
        throw StateError('WebView 尚未就绪');
      }
      final header = await session.exportCookies();
      final cookies = _parseCookieHeader(header);
      if (cookies.isEmpty) {
        throw StateError('当前还没有可保存的 Cookie。');
      }
      final cookieHeader = cookies.entries
          .map((e) => '${e.key}=${e.value}')
          .join('; ');
      if (!mounted) return;
      Navigator.of(context).pop(cookieHeader);
    } catch (error) {
      if (!mounted) return;
      showAppErrorSnackBar(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _navigate(String url) async {
    await _session?.navigate(url);
    await _refreshCookiePreview();
  }

  @override
  void dispose() {
    _closing = true;
    _pollTimer?.cancel();
    _pollTimer = null;
    final session = _session;
    _session = null;
    // Close after detaching state so cookie poll cannot race native destroy.
    if (session != null) {
      unawaited(session.close());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          TextButton.icon(
            onPressed: (_saving || _opening) ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_alt_outlined),
            label: const Text('保存 Cookie'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: AppSurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.instructions,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Text(_status, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
              Text(
                '已捕获 Cookie：$_cookieCount'
                '${_cookiePreview.isEmpty ? '' : '（$_cookiePreview）'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              if (_opening) const LinearProgressIndicator(),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final link in widget.quickLinks)
                    OutlinedButton.icon(
                      onPressed: _opening ? null : () => _navigate(link.url),
                      icon: Icon(link.icon),
                      label: Text(link.label),
                    ),
                  OutlinedButton.icon(
                    onPressed: _opening
                        ? null
                        : () => _navigate(widget.initialUrl),
                    icon: const Icon(Icons.refresh),
                    label: const Text('重新打开首页'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _opening ? null : _refreshCookiePreview,
                    icon: const Icon(Icons.cookie_outlined),
                    label: const Text('刷新 Cookie 预览'),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                'Linux 桌面使用独立 WebKitGTK 窗口完成登录（与 Android 内嵌 WebView 等价能力）。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
