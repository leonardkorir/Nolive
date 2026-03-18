import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:live_providers/live_providers.dart';
import 'package:nolive_app/src/shared/presentation/widgets/app_surface_card.dart';

class ChaturbateWebLoginPage extends StatelessWidget {
  const ChaturbateWebLoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _WebCookieLoginPage(
      config: _WebCookieLoginConfig(
        title: 'Chaturbate 网页登录',
        initialUrl: 'https://chaturbate.com/',
        userAgent: ChaturbateProvider.browserUserAgent,
        instructions: '完成登录或验证后，直接保存当前 Cookie。',
        seedUrls: ['https://chaturbate.com/'],
        allowedHostSuffixes: ['chaturbate.com'],
        quickLinks: [
          _WebCookieQuickLink(
            label: '打开首页',
            url: 'https://chaturbate.com/',
            icon: Icons.home_outlined,
          ),
        ],
      ),
    );
  }
}

class DouyinWebLoginPage extends StatelessWidget {
  const DouyinWebLoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _WebCookieLoginPage(
      config: _WebCookieLoginConfig(
        title: '抖音网页登录',
        initialUrl: 'https://live.douyin.com/',
        userAgent: _kDouyinBrowserUserAgent,
        instructions: '完成登录后保存当前 Cookie。',
        seedUrls: [
          'https://live.douyin.com/',
          'https://www.douyin.com/',
        ],
        allowedHostSuffixes: ['douyin.com'],
        quickLinks: [
          _WebCookieQuickLink(
            label: '直播页',
            url: 'https://live.douyin.com/',
            icon: Icons.live_tv_outlined,
          ),
          _WebCookieQuickLink(
            label: '抖音首页',
            url: 'https://www.douyin.com/',
            icon: Icons.home_outlined,
          ),
        ],
      ),
    );
  }
}

class _WebCookieLoginPage extends StatefulWidget {
  const _WebCookieLoginPage({required this.config});

  final _WebCookieLoginConfig config;

  @override
  State<_WebCookieLoginPage> createState() => _WebCookieLoginPageState();
}

class _WebCookieLoginPageState extends State<_WebCookieLoginPage> {
  final CookieManager _cookieManager = CookieManager.instance();
  InAppWebViewController? _controller;
  late String _currentUrl;
  double _progress = 0;
  int _cookieCount = 0;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.config.initialUrl;
  }

  Future<void> _refreshCookieCount() async {
    final cookieMap = await _collectCookies();
    if (!mounted) {
      return;
    }
    setState(() {
      _cookieCount = cookieMap.length;
    });
  }

  Future<Map<String, String>> _collectCookies() async {
    final cookieMap = <String, String>{};
    for (final url in _candidateUrls()) {
      final cookies = await _cookieManager.getCookies(url: WebUri(url));
      for (final cookie in cookies) {
        final name = cookie.name.trim();
        final value = cookie.value?.trim() ?? '';
        if (name.isEmpty || value.isEmpty) {
          continue;
        }
        cookieMap[name] = value;
      }
    }
    return cookieMap;
  }

  Iterable<String> _candidateUrls() sync* {
    for (final url in widget.config.seedUrls) {
      yield url;
    }

    final current = Uri.tryParse(_currentUrl);
    if (current == null) {
      return;
    }
    if (!widget.config.allowedHostSuffixes.any(
      (suffix) => current.host.endsWith(suffix),
    )) {
      return;
    }
    yield current.replace(query: '', fragment: '').toString();
  }

  Future<void> _saveCookies() async {
    setState(() {
      _saving = true;
    });
    try {
      final cookies = await _collectCookies();
      if (cookies.isEmpty) {
        throw StateError('当前还没有可保存的 Cookie。');
      }
      final cookieHeader = cookies.entries
          .map((entry) => '${entry.key}=${entry.value}')
          .join('; ');
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(cookieHeader);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  void _openQuickLink(String url) {
    _controller?.loadUrl(
      urlRequest: URLRequest(url: WebUri(url)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.config.title),
        actions: [
          TextButton.icon(
            onPressed: _saving ? null : _saveCookies,
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
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: AppSurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.config.instructions,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '当前地址：$_currentUrl',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '已捕获 Cookie：$_cookieCount',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final link in widget.config.quickLinks)
                        OutlinedButton.icon(
                          onPressed: () => _openQuickLink(link.url),
                          icon: Icon(link.icon),
                          label: Text(link.label),
                        ),
                      OutlinedButton.icon(
                        onPressed: () => _controller?.reload(),
                        icon: const Icon(Icons.refresh),
                        label: const Text('刷新页面'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_progress < 1)
            LinearProgressIndicator(value: _progress)
          else
            const SizedBox(height: 4),
          Expanded(
            child: InAppWebView(
              initialUrlRequest: URLRequest(
                url: WebUri(widget.config.initialUrl),
              ),
              initialSettings: InAppWebViewSettings(
                isInspectable: kDebugMode,
                userAgent: widget.config.userAgent,
                useShouldOverrideUrlLoading: true,
                mediaPlaybackRequiresUserGesture: false,
                thirdPartyCookiesEnabled: true,
                sharedCookiesEnabled: true,
                allowsInlineMediaPlayback: true,
              ),
              onWebViewCreated: (controller) {
                _controller = controller;
              },
              onLoadStart: (controller, url) {
                setState(() {
                  _currentUrl = url?.toString() ?? _currentUrl;
                });
              },
              onLoadStop: (controller, url) async {
                if (!mounted) {
                  return;
                }
                setState(() {
                  _currentUrl = url?.toString() ?? _currentUrl;
                });
                await _refreshCookieCount();
              },
              onUpdateVisitedHistory: (controller, url, isReload) {
                setState(() {
                  _currentUrl = url?.toString() ?? _currentUrl;
                });
              },
              onProgressChanged: (controller, progress) {
                setState(() {
                  _progress = progress / 100;
                });
              },
              onReceivedError: (controller, request, error) {
                if (!mounted) {
                  return;
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('页面加载失败：${error.description}')),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _WebCookieLoginConfig {
  const _WebCookieLoginConfig({
    required this.title,
    required this.initialUrl,
    required this.userAgent,
    required this.instructions,
    required this.seedUrls,
    required this.allowedHostSuffixes,
    required this.quickLinks,
  });

  final String title;
  final String initialUrl;
  final String userAgent;
  final String instructions;
  final List<String> seedUrls;
  final List<String> allowedHostSuffixes;
  final List<_WebCookieQuickLink> quickLinks;
}

class _WebCookieQuickLink {
  const _WebCookieQuickLink({
    required this.label,
    required this.url,
    required this.icon,
  });

  final String label;
  final String url;
  final IconData icon;
}

const String _kDouyinBrowserUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36 Edg/125.0.0.0';
