import 'dart:convert';
import 'dart:io';

import 'package:live_core/live_core.dart';
import 'package:live_hls_proxy/live_hls_proxy.dart';
import 'package:live_providers/live_providers.dart';

class _Adapter implements HlsProxyPlatformAdapter {
  @override
  bool get isMobile => false;
  @override
  bool get isAndroid => false;
  @override
  void debugPrint(String message) => print(message);
  @override
  void log(String tag, String message, [Object? error, StackTrace? st]) {
    print('[$tag] $message ${error ?? ''}');
  }
  @override
  Future<HlsHeadlessWebView> createHeadlessWebView({
    required String initialUrl,
    required String userAgent,
    required bool desktopMode,
    HlsWebViewResourceBlocker? shouldBlockRequest,
    void Function(String message)? onConsoleMessage,
    void Function(int statusCode, String url)? onHttpError,
    void Function(String description, String url)? onLoadError,
  }) {
    throw UnimplementedError();
  }
  @override
  HlsCookieManager get cookieManager => throw UnimplementedError();
}

Future<void> main() async {
  final provider = StripchatProvider.live();
  try {
    final rooms = await (provider as SupportsRecommendRooms).fetchRecommendRooms(page: 1);
    print('rooms=${rooms.items.length}');
    if (rooms.items.isEmpty) return;
    final room = rooms.items.first;
    print('room=${room.roomId}');
    final detail = await (provider as SupportsRoomDetail).fetchRoomDetail(room.roomId);
    print('live=${detail.isLive} source=${detail.sourceUrl}');
    final qualities = await (provider as SupportsPlayQualities).fetchPlayQualities(detail);
    print('qualities=${qualities.map((q) => '${q.id}/${q.label}').join(',')}');
    // try non-auto first if available
    final selected = qualities.firstWhere(
      (q) => q.id != 'auto',
      orElse: () => qualities.first,
    );
    print('selected=${selected.id}');
    final urls = await (provider as SupportsPlayUrls).fetchPlayUrls(detail: detail, quality: selected);
    print('urls=${urls.length}');
    if (urls.isEmpty) return;
    print('upstream=${urls.first.url}');
    print('headers=${urls.first.headers}');
    print('metaKeys=${urls.first.metadata?.keys.toList()}');

    final proxy = StripchatLlHlsProxy(platformAdapter: _Adapter());
    await proxy.ensureStarted();
    final wrapped = await proxy.wrapPlayUrls(
      roomId: detail.roomId,
      quality: selected,
      playUrls: urls,
    );
    final play = wrapped.first;
    print('wrapped=${play.url}');
    final client = HttpClient();
    Future<String> get(String url, {Map<String, String>? headers}) async {
      final req = await client.getUrl(Uri.parse(url));
      headers?.forEach(req.headers.set);
      final resp = await req.close().timeout(const Duration(seconds: 15));
      final body = await resp.transform(utf8.decoder).join();
      print('GET $url -> ${resp.statusCode} len=${body.length}');
      return body;
    }
    final pl = await get(play.url, headers: play.headers);
    final lines = pl.split('\n');
    print('--- playlist head ---');
    print(lines.take(50).join('\n'));
    // fetch first asset if present
    final asset = lines.map((l) => l.trim()).firstWhere(
      (l) => l.contains('/asset/') || l.endsWith('.mp4') || l.startsWith('http'),
      orElse: () => '',
    );
    if (asset.isNotEmpty) {
      final assetUrl = asset.startsWith('http') ? asset : Uri.parse(play.url).resolve(asset).toString();
      print('firstAsset=$assetUrl');
      final req = await client.getUrl(Uri.parse(assetUrl));
      play.headers.forEach(req.headers.set);
      final resp = await req.close().timeout(const Duration(seconds: 20));
      final bytes = await resp.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
      print('assetStatus=${resp.statusCode} bytes=${bytes.length} ct=${resp.headers.contentType}');
      if (bytes.length > 16) {
        print('assetMagic=${bytes.take(16).map((b) => b.toRadixString(16).padLeft(2, "0")).join(" ")}');
      }
    }
    print('--- mpv ---');
    final r = await Process.run('timeout', [
      '18', 'mpv', '--vo=null', '--ao=null', '--end=6', '--no-config',
      '--msg-level=all=warn',
      '--network-timeout=12',
      play.url,
    ]);
    print('mpvExit=${r.exitCode}');
    stderr.write(r.stderr);
    await proxy.dispose();
    client.close(force: true);
  } finally {
    provider.dispose();
  }
}
