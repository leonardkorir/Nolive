import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:nolive_app/src/features/settings/application/manage_provider_accounts_use_case.dart';
import 'package:nolive_app/src/shared/presentation/widgets/app_surface_card.dart';
import 'package:nolive_app/src/shared/presentation/app_feedback.dart';

@visibleForTesting
bool shouldReportWebLoginLoadFailure(WebResourceRequest request) {
  return request.isForMainFrame ?? true;
}

class ChaturbateWebLoginPage extends StatelessWidget {
  const ChaturbateWebLoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _WebCookieLoginPage(
      config: _WebCookieLoginConfig(
        title: 'Chaturbate 网页登录',
        initialUrl: 'https://chaturbate.com/',
        userAgent: _kEmbeddedAndroidBrowserUserAgent,
        instructions: '完成 Cloudflare 验证或登录后直接保存 Cookie。',
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
        instructions: '如需右上角登录入口，可先缩小页面后再登录；浏览直播通常只需要游客 Cookie。',
        seedUrls: ['https://live.douyin.com/', 'https://www.douyin.com/'],
        allowedHostSuffixes: ['douyin.com'],
        preferDesktopContent: true,
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

class TwitchWebLoginPage extends StatelessWidget {
  const TwitchWebLoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _WebCookieLoginPage(
      config: _WebCookieLoginConfig(
        title: 'Twitch 网页登录',
        initialUrl: 'https://www.twitch.tv/',
        userAgent: _kEmbeddedAndroidBrowserUserAgent,
        instructions: '如需补强 Twitch Web 辅助播放，可先完成网页登录后再保存 Cookie。',
        seedUrls: ['https://www.twitch.tv/', 'https://m.twitch.tv/'],
        allowedHostSuffixes: ['twitch.tv'],
        preferDesktopContent: true,
        quickLinks: [
          _WebCookieQuickLink(
            label: 'Twitch 首页',
            url: 'https://www.twitch.tv/',
            icon: Icons.home_outlined,
          ),
          _WebCookieQuickLink(
            label: '移动页',
            url: 'https://m.twitch.tv/',
            icon: Icons.smartphone_outlined,
          ),
        ],
      ),
    );
  }
}

class StripchatWebLoginPage extends StatelessWidget {
  const StripchatWebLoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _WebCookieLoginPage(
      config: _WebCookieLoginConfig(
        title: 'Stripchat 网页登录',
        initialUrl: 'https://zh.stripchat.com/',
        userAgent: _kEmbeddedAndroidBrowserUserAgent,
        instructions: '完成登录或 Cloudflare 验证后，打开任意直播间即可收集 Cookie。',
        seedUrls: ['https://zh.stripchat.com/'],
        allowedHostSuffixes: ['stripchat.com'],
        diagnosticsBuilder: buildStripchatWebLoginCookieDiagnostics,
        quickLinks: [
          _WebCookieQuickLink(
            label: '直播首页',
            url: 'https://zh.stripchat.com/',
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
  int _cookieHeaderLength = 0;
  List<String> _cookieNames = const <String>[];
  String _cookieStatusTitle = '未捕获 Cookie';
  String _cookieStatusDetail = '尚未检测到可保存的浏览器 Cookie。';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.config.initialUrl;
  }

  Future<void> _refreshCookieCount() async {
    try {
      final cookieMap = await _collectCookies();
      if (!mounted) {
        return;
      }
      final diagnostics = _resolveCookieDiagnostics(cookieMap);
      setState(() {
        _cookieCount = cookieMap.length;
        _cookieHeaderLength = diagnostics.headerLength;
        _cookieNames = diagnostics.cookieNames;
        _cookieStatusTitle = diagnostics.title;
        _cookieStatusDetail = diagnostics.detail;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _cookieCount = 0;
        _cookieHeaderLength = 0;
        _cookieNames = const <String>[];
        _cookieStatusTitle = '读取失败';
        _cookieStatusDetail = '$error';
      });
    }
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

  WebCookieDiagnostics _resolveCookieDiagnostics(Map<String, String> cookies) {
    final builder = widget.config.diagnosticsBuilder;
    if (builder != null) {
      return builder(cookies);
    }
    return buildGenericWebLoginCookieDiagnostics(cookies);
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
            showAppErrorSnackBar(context, error);
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  void _openQuickLink(String url) {
    _controller?.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
  }

  Future<void> _handleCreateWindow(CreateWindowAction action) async {
    final targetUrl = action.request.url;
    if (targetUrl == null) {
      return;
    }
    _controller?.loadUrl(urlRequest: URLRequest(url: targetUrl));
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
                  const SizedBox(height: 6),
                  Text(
                    '校验状态：$_cookieStatusTitle',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Cookie 长度：$_cookieHeaderLength 字符',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _cookieStatusDetail,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (_cookieNames.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final name in _cookieNames.take(8))
                          Chip(
                            visualDensity: VisualDensity.compact,
                            label: Text(name),
                          ),
                        if (_cookieNames.length > 8)
                          Chip(
                            visualDensity: VisualDensity.compact,
                            label: Text('+${_cookieNames.length - 8}'),
                          ),
                      ],
                    ),
                  ],
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
                javaScriptCanOpenWindowsAutomatically: true,
                mediaPlaybackRequiresUserGesture: false,
                supportMultipleWindows: true,
                thirdPartyCookiesEnabled: true,
                sharedCookiesEnabled: true,
                allowsInlineMediaPlayback: true,
                supportZoom: true,
                builtInZoomControls: true,
                displayZoomControls: false,
                useWideViewPort: true,
                loadWithOverviewMode: true,
                databaseEnabled: true,
                domStorageEnabled: true,
                cacheEnabled: true,
                clearSessionCache: false,
                mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
                useHybridComposition: true,
                preferredContentMode: widget.config.preferDesktopContent
                    ? UserPreferredContentMode.DESKTOP
                    : UserPreferredContentMode.RECOMMENDED,
              ),
              onWebViewCreated: (controller) {
                _controller = controller;
              },
              onCreateWindow: (controller, createWindowAction) async {
                await _handleCreateWindow(createWindowAction);
                return false;
              },
              onLoadStart: (controller, url) {
                debugPrint('_WebCookieLoadStart: $url');
                setState(() {
                  _currentUrl = url?.toString() ?? _currentUrl;
                });
              },
              onLoadStop: (controller, url) async {
                debugPrint('_WebCookieLoadStop: $url');
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
                if (progress > 0) debugPrint('_WebCookieProgress: $progress%');
                setState(() {
                  _progress = progress / 100;
                });
              },
              onReceivedError: (controller, request, error) {
                debugPrint(
                  '_WebCookieLoadError: ${error.description} type=${error.type} url=${request.url}',
                );
                if (!mounted) {
                  return;
                }
                if (!shouldReportWebLoginLoadFailure(request)) {
                  return;
                }
                final description = error.description.trim();
                if (description.isEmpty) {
                  return;
                }
                    showAppSnackBar(context, '页面加载失败：$description');
              },
              onConsoleMessage: (controller, consoleMessage) {
                debugPrint(
                  '_WebCookieConsole [${consoleMessage.messageLevel}]: ${consoleMessage.message}',
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
    this.diagnosticsBuilder,
    this.preferDesktopContent = false,
  });

  final String title;
  final String initialUrl;
  final String userAgent;
  final String instructions;
  final List<String> seedUrls;
  final List<String> allowedHostSuffixes;
  final List<_WebCookieQuickLink> quickLinks;
  final WebCookieDiagnosticsBuilder? diagnosticsBuilder;
  final bool preferDesktopContent;
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

typedef WebCookieDiagnosticsBuilder =
    WebCookieDiagnostics Function(Map<String, String> cookies);

class WebCookieDiagnostics {
  const WebCookieDiagnostics({
    required this.title,
    required this.detail,
    required this.cookieNames,
    required this.headerLength,
  });

  final String title;
  final String detail;
  final List<String> cookieNames;
  final int headerLength;
}

@visibleForTesting
WebCookieDiagnostics buildGenericWebLoginCookieDiagnostics(
  Map<String, String> cookies,
) {
  final cookieNames = cookies.keys.toList(growable: false);
  final headerLength = _cookieHeaderLengthFromMap(cookies);
  if (cookies.isEmpty) {
    return const WebCookieDiagnostics(
      title: '未捕获 Cookie',
      detail: '尚未检测到可保存的浏览器 Cookie。',
      cookieNames: <String>[],
      headerLength: 0,
    );
  }
  return WebCookieDiagnostics(
    title: '已捕获 ${cookies.length} 个 Cookie',
    detail: '已读取浏览器会话 Cookie，可直接保存当前 header。',
    cookieNames: cookieNames,
    headerLength: headerLength,
  );
}

@visibleForTesting
WebCookieDiagnostics buildStripchatWebLoginCookieDiagnostics(
  Map<String, String> cookies,
) {
  final header = _cookieHeaderFromMap(cookies);
  final status = inspectStripchatCookie(header);
  final cookieNames = parseCookieNames(header);
  return WebCookieDiagnostics(
    title: status.cookieKindLabel,
    detail: status.identitySummary,
    cookieNames: cookieNames,
    headerLength: header.length,
  );
}

String _cookieHeaderFromMap(Map<String, String> cookies) {
  return cookies.entries
      .map((entry) => '${entry.key}=${entry.value}')
      .join('; ');
}

int _cookieHeaderLengthFromMap(Map<String, String> cookies) {
  return _cookieHeaderFromMap(cookies).length;
}

const String _kDouyinBrowserUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36 Edg/125.0.0.0';

const String _kEmbeddedAndroidBrowserUserAgent =
    'Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/125.0.0.0 Mobile Safari/537.36';
