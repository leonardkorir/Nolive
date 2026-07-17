import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_hls_proxy/live_hls_proxy.dart';

class _FakePlatformAdapter implements HlsProxyPlatformAdapter {
  _FakePlatformAdapter();

  @override
  bool get isMobile => true;

  @override
  bool get supportsHeadlessWebView => true;

  @override
  bool get kDebugMode => true;

  @override
  void log(
    String tag,
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) {}

  @override
  void debugPrint(String message) {}

  @override
  HlsProxyCookieManager get cookieManager => throw UnimplementedError();

  @override
  Future<HlsHeadlessWebView> createHeadlessWebView({
    required String initialUrl,
    required String userAgent,
    bool desktopMode = false,
    HlsWebViewResourceBlocker? shouldBlockRequest,
    void Function(String message)? onConsoleMessage,
    void Function(int statusCode, String url)? onHttpError,
    void Function(String description, String url)? onLoadError,
  }) => throw UnimplementedError();
}

void main() {
  test(
    'stripchat ll-hls proxy rewrites live child playlists transparently',
    () async {
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final upstreamBase = 'http://${upstream.address.host}:${upstream.port}';
      final requests = <Uri>[];

      upstream.listen((request) async {
        requests.add(request.requestedUri);
        if (request.uri.path.endsWith('/variant.m3u8')) {
          request.response.headers.contentType = ContentType.text;
          request.response.write('''
#EXTM3U
#EXT-X-VERSION:6
#EXT-X-MOUFLON:PSCH:v2:test
#EXT-X-TARGETDURATION:2
#EXT-X-MEDIA-SEQUENCE:3608
#EXT-X-MAP:URI="$upstreamBase/init.mp4"
#EXT-X-RENDITION-REPORT:URI="$upstreamBase/other.m3u8",LAST-MSN=3607,LAST-PART=1
#EXT-X-PART:DURATION=0.500,URI="$upstreamBase/seg_3608.part0.mp4"
#EXT-X-PART:DURATION=0.500,URI="$upstreamBase/seg_3608.part1.mp4"
#EXT-X-PART:DURATION=0.500,URI="$upstreamBase/seg_3608.part2.mp4"
#EXT-X-PART:DURATION=0.500,URI="$upstreamBase/seg_3608.part3.mp4"
#EXT-X-PART:DURATION=0.500,URI="$upstreamBase/seg_3608.part4.mp4"
#EXT-X-PART:DURATION=0.500,URI="$upstreamBase/seg_3608.part5.mp4"
#EXT-X-PART:DURATION=0.500,URI="$upstreamBase/seg_3608.part6.mp4"
#EXT-X-PART:DURATION=0.500,URI="$upstreamBase/seg_3608.part7.mp4"
#EXT-X-PART:DURATION=0.500,URI="$upstreamBase/seg_3608.part8.mp4"
#EXT-X-PRELOAD-HINT:TYPE=PART,URI="$upstreamBase/seg_3608.part1.mp4"
#EXTINF:2.000
$upstreamBase/seg_3607.mp4
#EXTINF:2.000
$upstreamBase/seg_3608.mp4
#EXTINF:2.000
$upstreamBase/seg_3609.mp4
''');
        } else if (request.uri.path.endsWith('.mp4')) {
          request.response.headers.contentType = ContentType.binary;
          request.response.add(utf8.encode(request.uri.path));
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      });

      final proxy = StripchatLlHlsProxy(
        platformAdapter: _FakePlatformAdapter(),
        enabledOverride: true,
      );
      addTearDown(proxy.dispose);
      addTearDown(() => upstream.close(force: true));

      final wrapped = await proxy.wrapPlayUrls(
        roomId: 'test_room',
        quality: LivePlayQuality(id: 'auto', label: 'Auto', isDefault: true),
        playUrls: [
          LivePlayUrl(
            url:
                '$upstreamBase/variant.m3u8?playlistType=lowLatency&psch=v2&pkey=test',
            headers: const {'referer': 'https://zh.stripchat.com/sample_room'},
            lineLabel: 'Auto',
            metadata: const {
              'masterPlaylistUrl':
                  'https://edge-hls.doppiocdn.com/hls/100/master/100_auto.m3u8?playlistType=lowLatency',
            },
          ),
        ],
      );

      final client = HttpClient();
      addTearDown(() => client.close(force: true));

      final firstResponse = await (await client.getUrl(
        Uri.parse(wrapped.single.url),
      )).close();
      final firstText = utf8.decode(
        await firstResponse.fold<List<int>>(
          <int>[],
          (buffer, data) => buffer..addAll(data),
        ),
      );

      expect(firstResponse.statusCode, HttpStatus.ok);
      expect(firstText, contains('#EXT-X-MEDIA-SEQUENCE:3608'));
      expect(firstText, isNot(contains('#EXT-X-PART:')));
      expect(firstText, isNot(contains('#EXT-X-PRELOAD-HINT:')));
      expect(firstText, contains('#EXT-X-MAP:'));
      expect(firstText, isNot(contains('#EXT-X-RENDITION-REPORT:')));
      expect(firstText, isNot(contains('#EXT-X-MOUFLON:')));
      final assetMatches = RegExp(
        r'http://127\.0\.0\.1:\d+/stripchat-llhls/[^/]+/asset/[a-f0-9]{40}',
      ).allMatches(firstText).toList(growable: false);
      expect(assetMatches.length, 4);
      final assetUris = assetMatches.map((match) => match.group(0)!).toList();
      expect(assetUris.toSet().length, 4);
      expect(
        RegExp(r'#EXTINF:').allMatches(firstText).length,
        lessThanOrEqualTo(3),
      );
      expect(
        RegExp(r'#EXTINF:').allMatches(firstText).length,
        greaterThanOrEqualTo(2),
      );
      expect(firstText, isNot(contains('/seg_3607.mp4')));

      final refreshed = Uri.parse(
        '${wrapped.single.url}?_HLS_msn=3610&_HLS_part=1',
      );
      final secondResponse = await (await client.getUrl(refreshed)).close();
      await secondResponse.drain<void>();

      // Sticky serves the local media playlist immediately; LL-HLS reload
      // query is applied on the background upstream refresh (not on the
      // blocking HTTP path).
      final deadline = DateTime.now().add(const Duration(seconds: 2));
      while (DateTime.now().isBefore(deadline)) {
        final hit = requests.any(
          (uri) =>
              uri.path.endsWith('/variant.m3u8') &&
              uri.query.contains('_HLS_part=1') &&
              uri.query.contains('_HLS_msn=3610'),
        );
        if (hit) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
      expect(
        requests.any(
          (uri) =>
              uri.path.endsWith('/variant.m3u8') &&
              uri.query.contains('_HLS_part=1'),
        ),
        isTrue,
      );
      expect(
        requests.any(
          (uri) =>
              uri.path.endsWith('/variant.m3u8') &&
              uri.query.contains('_HLS_msn=3610'),
        ),
        isTrue,
      );
    },
  );

  test(
    'stripchat auto keeps multi-variant master for platform ABR',
    () async {
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final upstreamBase = 'http://${upstream.address.host}:${upstream.port}';

      upstream.listen((request) async {
        if (request.uri.path.endsWith('/master.m3u8')) {
          request.response.headers.contentType = ContentType.text;
          request.response.write('''
#EXTM3U
#EXT-X-MOUFLON:PSCH:v2:test
#EXT-X-STREAM-INF:BANDWIDTH=800000
$upstreamBase/child_240p.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=2500000
$upstreamBase/child_720p.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=8000000
$upstreamBase/child_1080p60.m3u8
''');
        } else if (request.uri.path.endsWith('.m3u8')) {
          request.response.headers.contentType = ContentType.text;
          request.response.write('''
#EXTM3U
#EXT-X-TARGETDURATION:2
#EXTINF:2.000
$upstreamBase/seg.mp4
''');
        } else if (request.uri.path.endsWith('.mp4')) {
          request.response.headers.contentType = ContentType.binary;
          request.response.add(utf8.encode('segment'));
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      });

      final proxy = StripchatLlHlsProxy(
        platformAdapter: _FakePlatformAdapter(),
        enabledOverride: true,
        enablePriming: false,
      );
      addTearDown(proxy.dispose);
      addTearDown(() => upstream.close(force: true));

      final wrapped = await proxy.wrapPlayUrls(
        roomId: 'test_room',
        quality: LivePlayQuality(id: 'auto', label: 'Auto', isDefault: true),
        playUrls: [
          LivePlayUrl(
            url: '$upstreamBase/master.m3u8',
            headers: const {'referer': 'https://zh.stripchat.com/auto'},
            lineLabel: 'Auto',
            metadata: {
              'masterPlaylistUrl':
                  'https://edge-hls.doppiocdn.com/hls/101/master/101_auto.m3u8',
              // Probe may store a max child; Auto must still expose master ABR.
              'resolvedPlaylistUrl': '$upstreamBase/child_1080p60.m3u8',
            },
          ),
        ],
      );

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final response = await (await client.getUrl(
        Uri.parse(wrapped.single.url),
      )).close();
      final text = utf8.decode(
        await response.fold<List<int>>(
          <int>[],
          (buffer, data) => buffer..addAll(data),
        ),
      );

      expect(response.statusCode, HttpStatus.ok);
      // Business: Auto keeps multi-variant master for platform ABR.
      expect(text, contains('#EXT-X-STREAM-INF'));
      expect(text, contains('/stripchat-llhls/'));
      expect(text, contains('upstream='));
      expect(text, isNot(contains('#EXT-X-MOUFLON:')));
      expect(
        wrapped.single.metadata?['upstreamUrl'],
        contains('master.m3u8'),
      );
    },
  );

  test(
    'stripchat auto keeps independent sticky slots per media path for ABR',
    () async {
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final upstreamBase = 'http://${upstream.address.host}:${upstream.port}';
      var child1080Hits = 0;
      var child240Hits = 0;

      upstream.listen((request) async {
        final path = request.uri.path;
        if (path.endsWith('/master.m3u8')) {
          request.response.headers.contentType = ContentType.text;
          request.response.write('''
#EXTM3U
#EXT-X-MOUFLON:PSCH:v2:test
#EXT-X-STREAM-INF:BANDWIDTH=800000
$upstreamBase/child_240p.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=8000000
$upstreamBase/child_1080p.m3u8
''');
        } else if (path.endsWith('/child_1080p.m3u8')) {
          child1080Hits += 1;
          request.response.headers.contentType = ContentType.text;
          request.response.write('''
#EXTM3U
#EXT-X-TARGETDURATION:2
#EXTINF:2.000
$upstreamBase/seg1080_a.mp4
#EXTINF:2.000
$upstreamBase/seg1080_b.mp4
#EXTINF:2.000
$upstreamBase/seg1080_c.mp4
''');
        } else if (path.endsWith('/child_240p.m3u8')) {
          child240Hits += 1;
          request.response.headers.contentType = ContentType.text;
          request.response.write('''
#EXTM3U
#EXT-X-TARGETDURATION:2
#EXTINF:2.000
$upstreamBase/seg240_a.mp4
#EXTINF:2.000
$upstreamBase/seg240_b.mp4
#EXTINF:2.000
$upstreamBase/seg240_c.mp4
''');
        } else if (path.endsWith('.mp4')) {
          request.response.headers.contentType = ContentType.binary;
          request.response.add(utf8.encode('segment-$path'));
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      });

      final proxy = StripchatLlHlsProxy(
        platformAdapter: _FakePlatformAdapter(),
        enabledOverride: true,
        enablePriming: false,
      );
      addTearDown(proxy.dispose);
      addTearDown(() => upstream.close(force: true));

      final wrapped = await proxy.wrapPlayUrls(
        roomId: 'abr_room',
        quality: LivePlayQuality(id: 'auto', label: 'Auto', isDefault: true),
        playUrls: [
          LivePlayUrl(
            url: '$upstreamBase/master.m3u8',
            headers: const {'referer': 'https://zh.stripchat.com/auto'},
            lineLabel: 'Auto',
            metadata: {
              // Candidate host gate: loopback alone is not edge-hls/media-hls.
              'masterPlaylistUrl':
                  'https://edge-hls.doppiocdn.com/hls/101/master/101_auto.m3u8',
            },
          ),
        ],
      );

      final client = HttpClient();
      addTearDown(() => client.close(force: true));

      Future<String> fetch(Uri url) async {
        final response = await (await client.getUrl(url)).close();
        expect(response.statusCode, HttpStatus.ok);
        return utf8.decode(
          await response.fold<List<int>>(
            <int>[],
            (buffer, data) => buffer..addAll(data),
          ),
        );
      }

      // Request each media child via proxy upstream= (simulates ABR hop).
      final basePlaylist = Uri.parse(wrapped.single.url);
      Uri childProxy(String path) => basePlaylist.replace(
        queryParameters: <String, String>{
          'upstream': '$upstreamBase$path',
        },
      );

      final first1080 = await fetch(childProxy('/child_1080p.m3u8'));
      final first240 = await fetch(childProxy('/child_240p.m3u8'));
      expect(first1080, contains('asset/'));
      expect(first240, contains('asset/'));
      expect(child1080Hits, greaterThan(0));
      expect(child240Hits, greaterThan(0));

      Set<String> assetIds(String playlist) => RegExp(
        r'/asset/([a-f0-9]{40})',
      ).allMatches(playlist).map((m) => m.group(1)!).toSet();

      final assets1080 = assetIds(first1080);
      final assets240 = assetIds(first240);
      expect(assets1080, isNotEmpty);
      expect(assets240, isNotEmpty);
      // Different tiers must not share segment identity.
      expect(assets1080.intersection(assets240), isEmpty);

      // ABR hop 1080 → already have 240 → back to 1080: per-path sticky
      // must still expose 1080 assets (not overwrite with 240 slot).
      final second1080 = await fetch(childProxy('/child_1080p.m3u8'));
      final second240 = await fetch(childProxy('/child_240p.m3u8'));
      expect(assetIds(second1080).intersection(assets1080), isNotEmpty);
      expect(assetIds(second240).intersection(assets240), isNotEmpty);
      expect(assetIds(second1080).intersection(assets240), isEmpty);
    },
  );

  test(
    'stripchat fixed quality pins probed media playlist (not adaptive master)',
    () async {
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final upstreamBase = 'http://${upstream.address.host}:${upstream.port}';
      final requests = <Uri>[];

      upstream.listen((request) async {
        requests.add(request.requestedUri);
        if (request.uri.path.endsWith('/probed_240p.m3u8')) {
          request.response.headers.contentType = ContentType.text;
          request.response.write('''
#EXTM3U
#EXT-X-TARGETDURATION:2
#EXTINF:2.000
$upstreamBase/seg_240p.mp4
''');
        } else if (request.uri.path.endsWith('/master.m3u8')) {
          request.response.statusCode = HttpStatus.internalServerError;
          request.response.write('fixed quality must not re-fetch master');
        } else if (request.uri.path.endsWith('.mp4')) {
          request.response.headers.contentType = ContentType.binary;
          request.response.add(utf8.encode('segment'));
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      });

      final proxy = StripchatLlHlsProxy(
        platformAdapter: _FakePlatformAdapter(),
        enabledOverride: true,
        enablePriming: false,
      );
      addTearDown(proxy.dispose);
      addTearDown(() => upstream.close(force: true));

      final wrapped = await proxy.wrapPlayUrls(
        roomId: 'test_room',
        quality: LivePlayQuality(id: '240p', label: '240P'),
        playUrls: [
          LivePlayUrl(
            url: 'https://edge-hls.doppiocdn.com/hls/101/master/101_auto.m3u8',
            headers: const {'referer': 'https://zh.stripchat.com/fixed'},
            lineLabel: 'HLS 240p',
            metadata: {
              'preferredVariantId': '240p',
              'masterPlaylistUrl':
                  'https://edge-hls.doppiocdn.com/hls/101/master/101_auto.m3u8',
              'resolvedPlaylistUrl': '$upstreamBase/probed_240p.m3u8',
            },
          ),
        ],
      );

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final response = await (await client.getUrl(
        Uri.parse(wrapped.single.url),
      )).close();
      final text = utf8.decode(
        await response.fold<List<int>>(
          <int>[],
          (buffer, data) => buffer..addAll(data),
        ),
      );

      expect(response.statusCode, HttpStatus.ok);
      expect(text, isNot(contains('#EXT-X-STREAM-INF')));
      expect(text, contains('#EXTINF:2.000'));
      expect(
        requests.where((uri) => uri.path.endsWith('/probed_240p.m3u8')),
        isNotEmpty,
      );
      expect(
        requests.where((uri) => uri.path.endsWith('/master.m3u8')),
        isEmpty,
      );
      expect(
        wrapped.single.metadata?['upstreamUrl'],
        contains('probed_240p.m3u8'),
      );
    },
  );

  test(
    'stripchat fixed source recovers via master when preferred media 404s',
    () async {
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final upstreamBase = 'http://${upstream.address.host}:${upstream.port}';
      final requests = <String>[];

      upstream.listen((request) async {
        requests.add(request.uri.path);
        if (request.uri.path.endsWith('/master.m3u8')) {
          request.response.headers.contentType = ContentType.text;
          // Master lists working shard paths (Nicole: wrong b-hls-N 404s).
          request.response.write('''
#EXTM3U
#EXT-X-MOUFLON:PSCH:v2:test
#EXT-X-STREAM-INF:BANDWIDTH=800000
$upstreamBase/good/77771651_240p.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=2500000
$upstreamBase/good/77771651_720p.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=8000000
$upstreamBase/good/77771651.m3u8
''');
        } else if (request.uri.path.contains('/dead/')) {
          // Probed source + sibling qualities on dead shard all 404.
          request.response.statusCode = HttpStatus.notFound;
          request.response.write('gone');
        } else if (request.uri.path.endsWith('/good/77771651.m3u8')) {
          // Preferred Source on good shard also dead → try next BW.
          request.response.statusCode = HttpStatus.notFound;
          request.response.write('gone');
        } else if (request.uri.path.endsWith('/good/77771651_720p.m3u8')) {
          request.response.headers.contentType = ContentType.text;
          request.response.write('''
#EXTM3U
#EXT-X-TARGETDURATION:2
#EXTINF:2.000
$upstreamBase/seg_a.mp4
#EXTINF:2.000
$upstreamBase/seg_b.mp4
#EXTINF:2.000
$upstreamBase/seg_c.mp4
''');
        } else if (request.uri.path.endsWith('/good/77771651_240p.m3u8')) {
          request.response.headers.contentType = ContentType.text;
          request.response.write('''
#EXTM3U
#EXT-X-TARGETDURATION:2
#EXTINF:2.000
$upstreamBase/seg_low.mp4
''');
        } else if (request.uri.path.endsWith('.mp4')) {
          request.response.headers.contentType = ContentType.binary;
          request.response.add(utf8.encode('segment'));
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      });

      final proxy = StripchatLlHlsProxy(
        platformAdapter: _FakePlatformAdapter(),
        enabledOverride: true,
        enablePriming: false,
      );
      addTearDown(proxy.dispose);
      addTearDown(() => upstream.close(force: true));

      final wrapped = await proxy.wrapPlayUrls(
        roomId: 'nicole_room',
        quality: LivePlayQuality(id: 'source', label: 'Source'),
        playUrls: [
          LivePlayUrl(
            // Candidate host gate needs edge-hls/media-hls; recover uses
            // masterPlaylistUrl → local master with working shard children.
            url:
                'https://edge-hls.doppiocdn.com/hls/77771651/master/77771651_auto.m3u8',
            headers: const {'referer': 'https://zh.stripchat.com/nicole'},
            lineLabel: 'HLS Source',
            metadata: {
              'preferredVariantId': 'source',
              'masterPlaylistUrl': '$upstreamBase/master.m3u8',
              'resolvedPlaylistUrl': '$upstreamBase/dead/77771651.m3u8',
            },
          ),
        ],
      );

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final response = await (await client.getUrl(
        Uri.parse(wrapped.single.url),
      )).close();
      final text = utf8.decode(
        await response.fold<List<int>>(
          <int>[],
          (buffer, data) => buffer..addAll(data),
        ),
      );

      expect(response.statusCode, HttpStatus.ok);
      // Must publish media playlist, never empty master (assets=0).
      expect(text, isNot(contains('#EXT-X-STREAM-INF')));
      expect(text, contains('#EXTINF:2.000'));
      expect(text, contains('/asset/'));
      expect(requests.any((p) => p.contains('/dead/')), isTrue);
      expect(requests, contains('/master.m3u8'));
      // Highest working after source: 720p (not forced down to 240).
      expect(requests, contains('/good/77771651_720p.m3u8'));
    },
  );

  test(
    'stripchat playlist host/sibling fallbacks after media 404',
    () async {
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final upstreamBase = 'http://${upstream.address.host}:${upstream.port}';
      final requests = <String>[];

      upstream.listen((request) async {
        requests.add(request.uri.path);
        if (request.uri.path.endsWith('/77771651.m3u8')) {
          request.response.statusCode = HttpStatus.notFound;
          request.response.write('not found');
        } else if (request.uri.path.endsWith('/77771651_1080p.m3u8')) {
          request.response.headers.contentType = ContentType.text;
          request.response.write('''
#EXTM3U
#EXT-X-TARGETDURATION:2
#EXTINF:2.000
$upstreamBase/seg_ok.mp4
''');
        } else if (request.uri.path.endsWith('.mp4')) {
          request.response.headers.contentType = ContentType.binary;
          request.response.add(utf8.encode('segment'));
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      });

      final proxy = StripchatLlHlsProxy(
        platformAdapter: _FakePlatformAdapter(),
        enabledOverride: true,
      );
      addTearDown(proxy.dispose);
      addTearDown(() => upstream.close(force: true));

      final session = proxy.createSessionForTest(
        LivePlayUrl(
          url: '$upstreamBase/77771651.m3u8?psch=v2&pkey=test',
          headers: const {'referer': 'https://zh.stripchat.com/x'},
          lineLabel: 'source',
          metadata: const {
            'preferredVariantId': 'source',
            'stripchatCdnDomains': ['doppiocdn.com'],
          },
        ),
        keyCache: const StripchatMouflonKeyCache(),
      );
      final fetched = await proxy.fetchPlaylistWithFallbacksForTest(
        session: session,
        uri: Uri.parse('$upstreamBase/77771651.m3u8?psch=v2&pkey=test'),
        headers: const {'referer': 'https://zh.stripchat.com/x'},
      );

      expect(fetched.statusCode, HttpStatus.ok);
      expect(fetched.body, contains('#EXTINF:2.000'));
      expect(requests, contains('/77771651.m3u8'));
      expect(requests, contains('/77771651_1080p.m3u8'));
    },
  );

  test('stripchat ll-hls proxy detects initialization in mp4 bytes', () {
    final bytes = Uint8List.fromList(<int>[
      0x00,
      0x00,
      0x00,
      0x18,
      ...ascii.encode('ftyp'),
      0x69,
      0x73,
      0x6f,
      0x35,
      0x00,
      0x00,
      0x00,
      0x20,
      ...ascii.encode('moov'),
      0x00,
      0x00,
      0x00,
      0x00,
    ]);
    expect(stripchatMp4BytesContainInitialization(bytes), isTrue);
    expect(
      stripchatMp4BytesContainInitialization(
        Uint8List.fromList(ascii.encode('plain-mp4-fragment')),
      ),
      isFalse,
    );
  });

  test(
    'stripchat ll-hls proxy drops map when first retained segment already has moov',
    () async {
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final upstreamBase = 'http://${upstream.address.host}:${upstream.port}';

      upstream.listen((request) async {
        if (request.uri.path.endsWith('/variant.m3u8')) {
          request.response.headers.contentType = ContentType.text;
          request.response.write('''
#EXTM3U
#EXT-X-VERSION:6
#EXT-X-TARGETDURATION:2
#EXT-X-MEDIA-SEQUENCE:3608
#EXT-X-MAP:URI="$upstreamBase/init.mp4"
#EXTINF:2.000
$upstreamBase/seg_3608.mp4
#EXTINF:2.000
$upstreamBase/seg_3609.mp4
''');
        } else if (request.uri.path.endsWith('/init.mp4')) {
          request.response.headers.contentType = ContentType.binary;
          request.response.add(utf8.encode('init-segment'));
        } else if (request.uri.path.endsWith('/seg_3608.mp4')) {
          request.response.headers.contentType = ContentType.binary;
          request.response.add(
            Uint8List.fromList(<int>[
              0x00,
              0x00,
              0x00,
              0x18,
              ...ascii.encode('ftyp'),
              0x69,
              0x73,
              0x6f,
              0x35,
              0x00,
              0x00,
              0x00,
              0x20,
              ...ascii.encode('moov'),
              0x00,
              0x00,
              0x00,
              0x00,
            ]),
          );
        } else if (request.uri.path.endsWith('/seg_3609.mp4')) {
          request.response.headers.contentType = ContentType.binary;
          request.response.add(utf8.encode('plain-segment'));
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      });

      final proxy = StripchatLlHlsProxy(
        platformAdapter: _FakePlatformAdapter(),
        enabledOverride: true,
      );
      addTearDown(proxy.dispose);
      addTearDown(() => upstream.close(force: true));

      final wrapped = await proxy.wrapPlayUrls(
        roomId: 'test_room',
        quality: LivePlayQuality(id: 'auto', label: 'Auto', isDefault: true),
        playUrls: [
          LivePlayUrl(
            url: '$upstreamBase/variant.m3u8?playlistType=lowLatency',
            headers: const {'referer': 'https://zh.stripchat.com/moov_room'},
            lineLabel: 'Auto',
            metadata: const {
              'masterPlaylistUrl':
                  'https://edge-hls.doppiocdn.com/hls/109/master/109_auto.m3u8?playlistType=lowLatency',
            },
          ),
        ],
      );

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final response = await (await client.getUrl(
        Uri.parse(wrapped.single.url),
      )).close();
      final text = utf8.decode(
        await response.fold<List<int>>(
          <int>[],
          (buffer, data) => buffer..addAll(data),
        ),
      );

      expect(response.statusCode, HttpStatus.ok);
      expect(text, isNot(contains('#EXT-X-MAP:')));
      expect(RegExp(r'#EXTINF:').allMatches(text).length, 2);
    },
  );

  test(
    'stripchat ll-hls proxy drops map when fallback segment already has moov',
    () async {
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final upstreamBase = 'http://${upstream.address.host}:${upstream.port}';
      const clearSegment = 'clearsegment';
      const pdkey = 'pdkey-123';
      final encodedSegment = _encryptSegmentForTest(clearSegment, pdkey);
      final encodedPath = '/seg_100_${encodedSegment}_1777921201.mp4';
      final decodedPath = '/seg_100_${clearSegment}_1777921201.mp4';

      upstream.listen((request) async {
        if (request.uri.path.endsWith('/variant.m3u8')) {
          request.response.headers.contentType = ContentType.text;
          request.response.write('''
#EXTM3U
#EXT-X-VERSION:6
#EXT-X-MOUFLON:PSCH:v2:test
#EXT-X-TARGETDURATION:2
#EXT-X-MEDIA-SEQUENCE:100
#EXT-X-MAP:URI="$upstreamBase/init.mp4"
#EXT-X-MOUFLON:URI:$upstreamBase$encodedPath
#EXTINF:2.000
$upstreamBase/media.mp4
#EXTINF:2.000
$upstreamBase/seg_101_plain_1777921202.mp4
''');
        } else if (request.uri.path == decodedPath) {
          request.response.headers.contentType = ContentType.binary;
          request.response.add(
            Uint8List.fromList(<int>[
              0x00,
              0x00,
              0x00,
              0x18,
              ...ascii.encode('ftyp'),
              0x69,
              0x73,
              0x6f,
              0x35,
              0x00,
              0x00,
              0x00,
              0x20,
              ...ascii.encode('moov'),
              0x00,
              0x00,
              0x00,
              0x00,
            ]),
          );
        } else if (request.uri.path.endsWith('.mp4')) {
          request.response.headers.contentType = ContentType.binary;
          request.response.add(utf8.encode(request.uri.path));
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      });

      final proxy = StripchatLlHlsProxy(
        platformAdapter: _FakePlatformAdapter(),
        enabledOverride: true,
        pdkeyResolver: () async => StripchatMouflonKeyCache(
          records: [
            StripchatMouflonKeyRecord(
              pkey: 'test',
              pdkey: pdkey,
              capturedAt: DateTime(2026),
              source: StripchatCalibrationSource.manual,
            ),
          ],
        ),
      );
      addTearDown(proxy.dispose);
      addTearDown(() => upstream.close(force: true));

      final wrapped = await proxy.wrapPlayUrls(
        roomId: 'test_room',
        quality: LivePlayQuality(id: 'auto', label: 'Auto', isDefault: true),
        playUrls: [
          LivePlayUrl(
            url: '$upstreamBase/variant.m3u8?playlistType=lowLatency',
            headers: const {'referer': 'https://zh.stripchat.com/moov_room'},
            lineLabel: 'Auto',
            metadata: const {
              'masterPlaylistUrl':
                  'https://edge-hls.doppiocdn.com/hls/109/master/109_auto.m3u8?playlistType=lowLatency',
            },
          ),
        ],
      );

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final response = await (await client.getUrl(
        Uri.parse(wrapped.single.url),
      )).close();
      final text = utf8.decode(
        await response.fold<List<int>>(
          <int>[],
          (buffer, data) => buffer..addAll(data),
        ),
      );

      expect(response.statusCode, HttpStatus.ok);
      expect(text, isNot(contains('#EXT-X-MAP:')));
      expect(text, isNot(contains(encodedPath)));
    },
  );

  test(
    'stripchat ll-hls proxy builds playlist host fallbacks from cdn domains',
    () {
      final fallbacks = StripchatLlHlsProxy.buildStripchatPlaylistFallbackUris(
        uri: Uri.parse(
          'https://media-hls.doppiocdn.com/b-hls-01/243097153/243097153.m3u8?playlistType=lowLatency&psch=v2&pkey=Ook7quaiNgiyuhai',
        ),
        preferredCdnDomains: const ['doppiocdn.org', 'doppiocdn.net'],
        attemptedHosts: const {'media-hls.doppiocdn.com'},
      );

      expect(fallbacks, isNotEmpty);
      // Prefer .net first (official HAR path), then .org from preferred list.
      expect(fallbacks.first.host, 'media-hls.doppiocdn.net');
      expect(fallbacks[1].host, 'media-hls.doppiocdn.org');
      expect(
        fallbacks.every(
          (uri) => uri.path == '/b-hls-01/243097153/243097153.m3u8',
        ),
        isTrue,
      );
      expect(
        fallbacks.every(
          (uri) => uri.queryParameters['pkey'] == 'Ook7quaiNgiyuhai',
        ),
        isTrue,
      );
    },
  );

  test(
    'stripchat ll-hls proxy builds sibling playlist fallbacks for same stream',
    () {
      final fallbacks =
          StripchatLlHlsProxy.buildStripchatSiblingPlaylistFallbackUris(
            uri: Uri.parse(
              'https://media-hls.doppiocdn.com/b-hls-30/117759402/117759402_720p.m3u8?minHeight=240&playlistType=lowLatency&psch=v2&pkey=Ook7quaiNgiyuhai',
            ),
          );

      expect(fallbacks, isNotEmpty);
      expect(fallbacks.first.path, '/b-hls-30/117759402/117759402.m3u8');
      expect(
        fallbacks.any((uri) => uri.path.endsWith('/117759402_480p.m3u8')),
        isTrue,
      );
      expect(
        fallbacks.every(
          (uri) => uri.queryParameters['pkey'] == 'Ook7quaiNgiyuhai',
        ),
        isTrue,
      );
    },
  );

  test(
    'stripchat ll-hls proxy falls back to sibling playlist after child failures',
    () async {
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final upstreamBase = 'http://${upstream.address.host}:${upstream.port}';
      final requests = <String>[];

      upstream.listen((request) async {
        requests.add(request.requestedUri.path);
        if (request.uri.path.endsWith('/117759402_720p.m3u8')) {
          request.response.statusCode = HttpStatus.forbidden;
          request.response.write('forbidden');
        } else if (request.uri.path.endsWith('/117759402.m3u8')) {
          request.response.headers.contentType = ContentType.text;
          request.response.write('''
#EXTM3U
#EXT-X-TARGETDURATION:2
#EXTINF:2.000
$upstreamBase/seg_1.mp4
''');
        } else if (request.uri.path.endsWith('/seg_1.mp4')) {
          request.response.headers.contentType = ContentType.binary;
          request.response.add(utf8.encode('segment'));
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      });

      final proxy = StripchatLlHlsProxy(
        platformAdapter: _FakePlatformAdapter(),
        enabledOverride: true,
      );
      addTearDown(proxy.dispose);
      addTearDown(() => upstream.close(force: true));

      final session = proxy.createSessionForTest(
        LivePlayUrl(
          url:
              '$upstreamBase/117759402_720p.m3u8?minHeight=240&playlistType=lowLatency&psch=v2&pkey=test',
          headers: const {'referer': 'https://zh.stripchat.com/maataaan'},
          lineLabel: '720p',
          metadata: const {
            'stripchatRoomUrl': 'https://zh.stripchat.com/maataaan',
            'stripchatCdnDomains': ['doppiocdn.com'],
          },
        ),
        keyCache: const StripchatMouflonKeyCache(),
      );
      final fetched = await proxy.fetchPlaylistWithFallbacksForTest(
        session: session,
        uri: Uri.parse(
          '$upstreamBase/117759402_720p.m3u8?minHeight=240&playlistType=lowLatency&psch=v2&pkey=test',
        ),
        headers: const {'referer': 'https://zh.stripchat.com/maataaan'},
        fallbackUrisOverride: [
          Uri.parse(
            '$upstreamBase/117759402.m3u8?minHeight=240&playlistType=lowLatency&psch=v2&pkey=test',
          ),
        ],
      );

      expect(fetched.statusCode, HttpStatus.ok);
      expect(fetched.body, contains('#EXTM3U'));
      expect(requests, contains('/117759402_720p.m3u8'));
      expect(requests, contains('/117759402.m3u8'));
    },
  );

  test(
    'stripchat ll-hls proxy serves loopback assets and strips cookies',
    () async {
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final upstreamBase = 'http://${upstream.address.host}:${upstream.port}';
      final seenCookies = <String?>[];
      final seenPaths = <String>[];

      upstream.listen((request) async {
        seenCookies.add(request.headers.value(HttpHeaders.cookieHeader));
        if (request.uri.path.endsWith('/variant.m3u8')) {
          request.response.headers.contentType = ContentType.text;
          request.response.write('''
#EXTM3U
#EXT-X-TARGETDURATION:2
#EXTINF:2.000
$upstreamBase/seg_5000.mp4
''');
        } else if (request.uri.path.endsWith('.mp4')) {
          seenPaths.add(request.uri.path);
          request.response.headers.contentType = ContentType.binary;
          request.response.add(utf8.encode(request.uri.path));
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      });

      final proxy = StripchatLlHlsProxy(
        platformAdapter: _FakePlatformAdapter(),
        enabledOverride: true,
      );
      addTearDown(proxy.dispose);
      addTearDown(() => upstream.close(force: true));

      final wrapped = await proxy.wrapPlayUrls(
        roomId: 'test_room',
        quality: LivePlayQuality(id: 'auto', label: 'Auto', isDefault: true),
        playUrls: [
          LivePlayUrl(
            url: '$upstreamBase/variant.m3u8?playlistType=lowLatency',
            headers: const {
              'referer': 'https://zh.stripchat.com/cookie_room',
              'cookie': 'session=secret',
            },
            lineLabel: 'Auto',
            metadata: const {
              'masterPlaylistUrl':
                  'https://edge-hls.doppiocdn.com/hls/102/master/102_auto.m3u8?playlistType=lowLatency',
            },
          ),
        ],
      );

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final playlistResponse = await (await client.getUrl(
        Uri.parse(wrapped.single.url),
      )).close();
      final playlistText = utf8.decode(
        await playlistResponse.fold<List<int>>(
          <int>[],
          (buffer, data) => buffer..addAll(data),
        ),
      );
      final assetUri = Uri.parse(
        RegExp(
          r'http://127\.0\.0\.1:\d+/stripchat-llhls/[^/]+/asset/[a-f0-9]{40}',
        ).firstMatch(playlistText)!.group(0)!,
      );
      final assetResponse = await (await client.getUrl(assetUri)).close();
      final assetBytes = await assetResponse.fold<List<int>>(
        <int>[],
        (buffer, data) => buffer..addAll(data),
      );

      expect(assetResponse.statusCode, HttpStatus.ok);
      expect(utf8.decode(assetBytes), '/seg_5000.mp4');
      expect(seenPaths, contains('/seg_5000.mp4'));
      // cookie is not in the upstream header whitelist and should be stripped.
      expect(seenCookies.every((value) => value == null), isTrue);
    },
  );

  test(
    'stripchat ll-hls proxy serves prefetched assets after upstream expires',
    () async {
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final upstreamBase = 'http://${upstream.address.host}:${upstream.port}';
      final assetHits = <String, int>{};

      upstream.listen((request) async {
        if (request.uri.path.endsWith('/variant.m3u8')) {
          request.response.headers.contentType = ContentType.text;
          request.response.write('''
#EXTM3U
#EXT-X-TARGETDURATION:2
#EXTINF:2.000
$upstreamBase/seg_6000.mp4
''');
        } else if (request.uri.path.endsWith('.mp4')) {
          final count = (assetHits[request.uri.path] ?? 0) + 1;
          assetHits[request.uri.path] = count;
          if (count > 1) {
            request.response.statusCode = HttpStatus.notFound;
          } else {
            request.response.headers.contentType = ContentType.binary;
            request.response.add(utf8.encode('prefetched:${request.uri.path}'));
          }
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      });

      final proxy = StripchatLlHlsProxy(
        platformAdapter: _FakePlatformAdapter(),
        enabledOverride: true,
      );
      addTearDown(proxy.dispose);
      addTearDown(() => upstream.close(force: true));

      final wrapped = await proxy.wrapPlayUrls(
        roomId: 'test_room',
        quality: LivePlayQuality(id: 'auto', label: 'Auto', isDefault: true),
        playUrls: [
          LivePlayUrl(
            url: '$upstreamBase/variant.m3u8?playlistType=lowLatency',
            headers: const {
              'referer': 'https://zh.stripchat.com/prefetch_room',
            },
            lineLabel: 'Auto',
            metadata: const {
              'masterPlaylistUrl':
                  'https://edge-hls.doppiocdn.com/hls/105/master/105_auto.m3u8?playlistType=lowLatency',
            },
          ),
        ],
      );

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final playlistResponse = await (await client.getUrl(
        Uri.parse(wrapped.single.url),
      )).close();
      final playlistText = utf8.decode(
        await playlistResponse.fold<List<int>>(
          <int>[],
          (buffer, data) => buffer..addAll(data),
        ),
      );
      final assetUri = Uri.parse(
        RegExp(
          r'http://127\.0\.0\.1:\d+/stripchat-llhls/[^/]+/asset/[a-f0-9]{40}',
        ).firstMatch(playlistText)!.group(0)!,
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));

      final assetResponse = await (await client.getUrl(assetUri)).close();
      final assetText = utf8.decode(
        await assetResponse.fold<List<int>>(
          <int>[],
          (buffer, data) => buffer..addAll(data),
        ),
      );

      expect(assetResponse.statusCode, HttpStatus.ok);
      expect(assetText, 'prefetched:/seg_6000.mp4');
      expect(assetHits['/seg_6000.mp4'], greaterThanOrEqualTo(1));
    },
  );

  test(
    'stripchat ll-hls proxy decodes encrypted mouflon uris with pdkey',
    () async {
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final upstreamBase = 'http://${upstream.address.host}:${upstream.port}';
      final decryptedSegment = 'clearsegment';
      final pdkey = 'pdkey-123';
      final encodedSegment = _encryptSegmentForTest(decryptedSegment, pdkey);

      upstream.listen((request) async {
        if (request.uri.path.endsWith('/variant.m3u8')) {
          request.response.headers.contentType = ContentType.text;
          request.response.write('''
#EXTM3U
#EXT-X-MOUFLON:PSCH:v2:test
#EXTINF:2.000
#EXT-X-MOUFLON:URI:$upstreamBase/seg_100_${encodedSegment}_999.mp4
$upstreamBase/media.mp4
''');
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      });

      final proxy = StripchatLlHlsProxy(
        platformAdapter: _FakePlatformAdapter(),
        enabledOverride: true,
        pdkeyResolver: () async => StripchatMouflonKeyCache(
          records: [
            StripchatMouflonKeyRecord(
              pkey: 'test',
              pdkey: pdkey,
              capturedAt: DateTime(2026),
              source: StripchatCalibrationSource.manual,
            ),
          ],
        ),
      );
      addTearDown(proxy.dispose);
      addTearDown(() => upstream.close(force: true));

      final wrapped = await proxy.wrapPlayUrls(
        roomId: 'test_room',
        quality: LivePlayQuality(id: 'auto', label: 'Auto', isDefault: true),
        playUrls: [
          LivePlayUrl(
            url:
                '$upstreamBase/variant.m3u8?playlistType=lowLatency&psch=v2&pkey=test',
            headers: const {'referer': 'https://zh.stripchat.com/decrypt_room'},
            lineLabel: 'Auto',
            metadata: const {
              'masterPlaylistUrl':
                  'https://edge-hls.doppiocdn.com/hls/103/master/103_auto.m3u8?playlistType=lowLatency',
            },
          ),
        ],
      );

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final response = await (await client.getUrl(
        Uri.parse(wrapped.single.url),
      )).close();
      final text = utf8.decode(
        await response.fold<List<int>>(
          <int>[],
          (buffer, data) => buffer..addAll(data),
        ),
      );

      expect(response.statusCode, HttpStatus.ok);
      expect(text, contains('/asset/'));
      expect(text, isNot(contains(encodedSegment)));
    },
  );

  test('stripchat ll-hls proxy decodes slash-containing mouflon uris', () async {
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final upstreamBase = 'http://${upstream.address.host}:${upstream.port}';
    final pdkey = 'pdkey-123';
    const decryptedSegment = 'seg000001';
    const encodedSegment = '/lpmSoLMiiV2';

    upstream.listen((request) async {
      if (request.uri.path.endsWith('/variant.m3u8')) {
        request.response.headers.contentType = ContentType.text;
        request.response.write('''
#EXTM3U
#EXT-X-MOUFLON:PSCH:v2:test
#EXTINF:2.000
#EXT-X-MOUFLON:URI:$upstreamBase/95572201_720p_h264_5585_${encodedSegment}_1777921201_part0.mp4
$upstreamBase/media.mp4
''');
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });

    final proxy = StripchatLlHlsProxy(
      platformAdapter: _FakePlatformAdapter(),
      enabledOverride: true,
      pdkeyResolver: () async => StripchatMouflonKeyCache(
        records: [
          StripchatMouflonKeyRecord(
            pkey: 'test',
            pdkey: pdkey,
            capturedAt: DateTime(2026),
            source: StripchatCalibrationSource.manual,
          ),
        ],
      ),
    );
    addTearDown(proxy.dispose);
    addTearDown(() => upstream.close(force: true));

    final wrapped = await proxy.wrapPlayUrls(
      roomId: 'test_room',
      quality: LivePlayQuality(id: 'auto', label: 'Auto', isDefault: true),
      playUrls: [
        LivePlayUrl(
          url:
              '$upstreamBase/variant.m3u8?playlistType=lowLatency&psch=v2&pkey=test',
          headers: const {'referer': 'https://zh.stripchat.com/slash_room'},
          lineLabel: 'Auto',
          metadata: const {
            'masterPlaylistUrl':
                'https://edge-hls.doppiocdn.com/hls/108/master/108_auto.m3u8?playlistType=lowLatency',
          },
        ),
      ],
    );

    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final response = await (await client.getUrl(
      Uri.parse(wrapped.single.url),
    )).close();
    final text = utf8.decode(
      await response.fold<List<int>>(
        <int>[],
        (buffer, data) => buffer..addAll(data),
      ),
    );

    expect(response.statusCode, HttpStatus.ok);
    expect(text, contains('/asset/'));
    expect(text, isNot(contains(encodedSegment)));
    expect(text, isNot(contains('/$decryptedSegment/')));
  });

  test(
    'stripchat ll-hls proxy uses trusted fallback when account cache is missing',
    () async {
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final upstreamBase = 'http://${upstream.address.host}:${upstream.port}';
      final pdkey = 'EQueeGh2kaewa3ch';
      final encodedSegment = _encryptSegmentForTest('trustedsegment', pdkey);

      upstream.listen((request) async {
        if (request.uri.path.endsWith('/variant.m3u8')) {
          request.response.headers.contentType = ContentType.text;
          request.response.write('''
#EXTM3U
#EXT-X-MOUFLON:PSCH:v2:Ook7quaiNgiyuhai
#EXTINF:2.000
#EXT-X-MOUFLON:URI:$upstreamBase/seg_100_${encodedSegment}_999.mp4
$upstreamBase/media.mp4
''');
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      });

      final proxy = StripchatLlHlsProxy(
        platformAdapter: _FakePlatformAdapter(),
        enabledOverride: true,
        pdkeyResolver: () async => const StripchatMouflonKeyCache(),
      );
      addTearDown(proxy.dispose);
      addTearDown(() => upstream.close(force: true));

      final wrapped = await proxy.wrapPlayUrls(
        roomId: 'test_room',
        quality: LivePlayQuality(id: 'auto', label: 'Auto', isDefault: true),
        playUrls: [
          LivePlayUrl(
            url:
                '$upstreamBase/variant.m3u8?playlistType=lowLatency&psch=v2&pkey=Ook7quaiNgiyuhai',
            headers: const {'referer': 'https://zh.stripchat.com/fail_room'},
            lineLabel: 'Auto',
            metadata: const {
              'masterPlaylistUrl':
                  'https://edge-hls.doppiocdn.com/hls/104/master/104_auto.m3u8?playlistType=lowLatency',
            },
          ),
        ],
      );

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final response = await (await client.getUrl(
        Uri.parse(wrapped.single.url),
      )).close();
      final text = utf8.decode(
        await response.fold<List<int>>(
          <int>[],
          (buffer, data) => buffer..addAll(data),
        ),
      );

      expect(response.statusCode, HttpStatus.ok);
      expect(text, contains('/asset/'));
      expect(text, isNot(contains(encodedSegment)));
    },
  );

  test(
    'stripchat ll-hls proxy serves decoded urls from bridge before pdkey fallback',
    () async {
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final upstreamBase = 'http://${upstream.address.host}:${upstream.port}';
      final assetHits = <String>[];
      const decodedSegment = 'decodedFromBridge';
      const timestamp = '1777921201';
      final resolverCalls = <String>[];

      upstream.listen((request) async {
        if (request.uri.path.endsWith('/variant.m3u8')) {
          request.response.headers.contentType = ContentType.text;
          request.response.write('''
#EXTM3U
#EXT-X-MOUFLON:PSCH:v2:Ook7quaiNgiyuhai
#EXTINF:2.000
#EXT-X-MOUFLON:URI:$upstreamBase/seg_100_f5xEAgHTdyjAV9qA_$timestamp.mp4
$upstreamBase/media.mp4
''');
        } else if (request.uri.path.endsWith('.mp4')) {
          assetHits.add(request.requestedUri.toString());
          request.response.headers.contentType = ContentType.binary;
          request.response.add(utf8.encode(request.uri.path));
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      });

      final proxy = StripchatLlHlsProxy(
        platformAdapter: _FakePlatformAdapter(),
        enabledOverride: true,
        pdkeyResolver: () async => const StripchatMouflonKeyCache(),
        decodedUrlResolver:
            ({required String roomUrl, required String segmentKey}) {
              resolverCalls.add('$roomUrl|$segmentKey');
              if (roomUrl != 'https://zh.stripchat.com/direct_room') {
                return null;
              }
              if (segmentKey != '100_${timestamp}_') {
                return null;
              }
              return '$upstreamBase/seg_100_${decodedSegment}_$timestamp.mp4';
            },
      );
      addTearDown(proxy.dispose);
      addTearDown(() => upstream.close(force: true));

      final wrapped = await proxy.wrapPlayUrls(
        roomId: 'test_room',
        quality: LivePlayQuality(id: 'auto', label: 'Auto', isDefault: true),
        playUrls: [
          LivePlayUrl(
            url:
                '$upstreamBase/variant.m3u8?playlistType=lowLatency&psch=v2&pkey=Ook7quaiNgiyuhai',
            headers: const {'referer': 'https://zh.stripchat.com/direct_room'},
            lineLabel: 'Auto',
            metadata: const {
              'stripchatRoomUrl': 'https://zh.stripchat.com/direct_room',
              'masterPlaylistUrl':
                  'https://edge-hls.doppiocdn.com/hls/110/master/110_auto.m3u8?playlistType=lowLatency',
            },
          ),
        ],
      );

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final playlistResponse = await (await client.getUrl(
        Uri.parse(wrapped.single.url),
      )).close();
      final playlistText = utf8.decode(
        await playlistResponse.fold<List<int>>(
          <int>[],
          (buffer, data) => buffer..addAll(data),
        ),
      );
      final assetUri = Uri.parse(
        RegExp(
          r'http://127\.0\.0\.1:\d+/stripchat-llhls/[^/]+/asset/[a-f0-9]{40}',
        ).firstMatch(playlistText)!.group(0)!,
      );
      final assetResponse = await (await client.getUrl(assetUri)).close();
      final assetBytes = await assetResponse.fold<List<int>>(
        <int>[],
        (buffer, data) => buffer..addAll(data),
      );

      expect(playlistResponse.statusCode, HttpStatus.ok);
      expect(
        resolverCalls,
        contains('https://zh.stripchat.com/direct_room|100_${timestamp}_'),
      );
      expect(assetResponse.statusCode, HttpStatus.ok);
      expect(
        utf8.decode(assetBytes),
        '/seg_100_${decodedSegment}_$timestamp.mp4',
      );
      expect(
        assetHits.any(
          (uri) => uri.endsWith('/seg_100_${decodedSegment}_$timestamp.mp4'),
        ),
        isTrue,
      );
      expect(assetHits.any((uri) => uri.contains('f5xEAgHTdyjAV9qA')), isFalse);
    },
  );

  test(
    'stripchat ll-hls proxy warms decoded-url bridge for stripchat room playlists',
    () async {
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final upstreamBase = 'http://${upstream.address.host}:${upstream.port}';
      final warmedRooms = <String>[];

      upstream.listen((request) async {
        if (request.uri.path.endsWith('/variant.m3u8')) {
          request.response.headers.contentType = ContentType.text;
          request.response.write('''
#EXTM3U
#EXTINF:2.000
$upstreamBase/media.mp4
''');
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      });

      final proxy = StripchatLlHlsProxy(
        platformAdapter: _FakePlatformAdapter(),
        enabledOverride: true,
        pdkeyResolver: () async => const StripchatMouflonKeyCache(),
        warmDecodedUrlBridge: (roomUrl) async {
          warmedRooms.add(roomUrl);
        },
      );
      addTearDown(proxy.dispose);
      addTearDown(() => upstream.close(force: true));

      final wrapped = await proxy.wrapPlayUrls(
        roomId: 'test_room',
        quality: LivePlayQuality(id: 'auto', label: 'Auto', isDefault: true),
        playUrls: [
          LivePlayUrl(
            url: '$upstreamBase/variant.m3u8?playlistType=lowLatency',
            headers: const {'referer': 'https://zh.stripchat.com/warm_room'},
            lineLabel: 'Auto',
            metadata: const {
              'stripchatRoomUrl': 'https://zh.stripchat.com/warm_room',
              'masterPlaylistUrl':
                  'https://edge-hls.doppiocdn.com/hls/115/master/115_auto.m3u8?playlistType=lowLatency',
            },
          ),
        ],
      );

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final playlistResponse = await (await client.getUrl(
        Uri.parse(wrapped.single.url),
      )).close();
      await playlistResponse.drain<void>();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(playlistResponse.statusCode, HttpStatus.ok);
      expect(warmedRooms, contains('https://zh.stripchat.com/warm_room'));
    },
  );

  test(
    'stripchat ll-hls proxy only waits briefly for upfront bridge warmup',
    () async {
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final upstreamBase = 'http://${upstream.address.host}:${upstream.port}';
      final warmCompleter = Completer<void>();
      final warmedRooms = <String>[];

      upstream.listen((request) async {
        if (request.uri.path.endsWith('/variant.m3u8')) {
          request.response.headers.contentType = ContentType.text;
          request.response.write('''
#EXTM3U
#EXTINF:2.000
$upstreamBase/media.mp4
''');
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      });

      final proxy = StripchatLlHlsProxy(
        platformAdapter: _FakePlatformAdapter(),
        enabledOverride: true,
        pdkeyResolver: () async => const StripchatMouflonKeyCache(),
        warmDecodedUrlBridge: (roomUrl) async {
          warmedRooms.add(roomUrl);
          await warmCompleter.future;
        },
      );
      addTearDown(proxy.dispose);
      addTearDown(() => upstream.close(force: true));
      addTearDown(() {
        if (!warmCompleter.isCompleted) {
          warmCompleter.complete();
        }
      });

      final stopwatch = Stopwatch()..start();
      final wrapped = await proxy.wrapPlayUrls(
        roomId: 'test_room',
        quality: LivePlayQuality(id: 'auto', label: 'Auto', isDefault: true),
        playUrls: [
          LivePlayUrl(
            url: '$upstreamBase/variant.m3u8?playlistType=lowLatency',
            headers: const {'referer': 'https://zh.stripchat.com/fast_room'},
            lineLabel: 'Auto',
            metadata: const {
              'stripchatRoomUrl': 'https://zh.stripchat.com/fast_room',
              'masterPlaylistUrl':
                  'https://edge-hls.doppiocdn.com/hls/117/master/117_auto.m3u8?playlistType=lowLatency',
            },
          ),
        ],
      );
      stopwatch.stop();

      expect(wrapped, hasLength(1));
      expect(warmedRooms, contains('https://zh.stripchat.com/fast_room'));
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 3)));
    },
  );

  test(
    'stripchat ll-hls proxy queries bridge resolver before serving direct target',
    () async {
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final upstreamBase = 'http://${upstream.address.host}:${upstream.port}';
      final assetHits = <String>[];
      const timestamp = '1777921201';
      final resolverCalls = <String>[];

      upstream.listen((request) async {
        if (request.uri.path.endsWith('/variant.m3u8')) {
          request.response.headers.contentType = ContentType.text;
          request.response.write('''
#EXTM3U
#EXT-X-MOUFLON:PSCH:v2:Ook7quaiNgiyuhai
#EXTINF:2.000
#EXT-X-MOUFLON:URI:$upstreamBase/seg_100_f5xEAgHTdyjAV9qA_$timestamp.mp4
$upstreamBase/media.mp4
''');
        } else if (request.uri.path.endsWith('.mp4')) {
          assetHits.add(request.requestedUri.toString());
          request.response.headers.contentType = ContentType.binary;
          request.response.add(utf8.encode(request.uri.path));
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      });

      final proxy = StripchatLlHlsProxy(
        platformAdapter: _FakePlatformAdapter(),
        enabledOverride: true,
        enablePdkeyFallback: true,
        pdkeyResolver: () async => const StripchatMouflonKeyCache(),
        warmDecodedUrlBridge: (roomUrl) async {
          expect(roomUrl, 'https://zh.stripchat.com/race_room');
        },
        decodedUrlResolver:
            ({required String roomUrl, required String segmentKey}) {
              resolverCalls.add('$roomUrl|$segmentKey');
              return null;
            },
      );
      addTearDown(proxy.dispose);
      addTearDown(() => upstream.close(force: true));

      final wrapped = await proxy.wrapPlayUrls(
        roomId: 'test_room',
        quality: LivePlayQuality(id: 'auto', label: 'Auto', isDefault: true),
        playUrls: [
          LivePlayUrl(
            url:
                '$upstreamBase/variant.m3u8?playlistType=lowLatency&psch=v2&pkey=Ook7quaiNgiyuhai',
            headers: const {'referer': 'https://zh.stripchat.com/race_room'},
            lineLabel: 'Auto',
            metadata: const {
              'stripchatRoomUrl': 'https://zh.stripchat.com/race_room',
              'masterPlaylistUrl':
                  'https://edge-hls.doppiocdn.com/hls/116/master/116_auto.m3u8?playlistType=lowLatency',
            },
          ),
        ],
      );

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final playlistResponse = await (await client.getUrl(
        Uri.parse(wrapped.single.url),
      )).close();
      final playlistText = utf8.decode(
        await playlistResponse.fold<List<int>>(
          <int>[],
          (buffer, data) => buffer..addAll(data),
        ),
      );
      final assetUri = Uri.parse(
        RegExp(
          r'http://127\.0\.0\.1:\d+/stripchat-llhls/[^/]+/asset/[a-f0-9]{40}',
        ).firstMatch(playlistText)!.group(0)!,
      );
      final assetResponse = await (await client.getUrl(assetUri)).close();
      final assetBytes = await assetResponse.fold<List<int>>(
        <int>[],
        (buffer, data) => buffer..addAll(data),
      );

      expect(playlistResponse.statusCode, HttpStatus.ok);
      expect(assetResponse.statusCode, HttpStatus.ok);
      expect(
        utf8.decode(assetBytes),
        '/seg_100_f5xEAgHTdyjAV9qA_$timestamp.mp4',
      );
      expect(
        resolverCalls.any(
          (call) => call.startsWith('https://zh.stripchat.com/race_room|'),
        ),
        isTrue,
      );
      expect(assetHits.any((uri) => uri.contains('f5xEAgHTdyjAV9qA')), isTrue);
    },
  );

  test(
    'stripchat ll-hls proxy keeps playlist refresh responsive while asset request is in flight',
    () async {
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final upstreamBase = 'http://${upstream.address.host}:${upstream.port}';
      final assetGate = Completer<void>();

      upstream.listen((request) async {
        if (request.uri.path.endsWith('/variant.m3u8')) {
          request.response.headers.contentType = ContentType.text;
          request.response.write('''
#EXTM3U
#EXT-X-TARGETDURATION:2
#EXTINF:2.000
$upstreamBase/seg_7000.mp4
''');
        } else if (request.uri.path.endsWith('/seg_7000.mp4')) {
          await assetGate.future;
          request.response.headers.contentType = ContentType.binary;
          request.response.add(utf8.encode('segment'));
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      });

      final proxy = StripchatLlHlsProxy(
        platformAdapter: _FakePlatformAdapter(),
        enabledOverride: true,
      );
      addTearDown(proxy.dispose);
      addTearDown(() => upstream.close(force: true));

      final wrapped = await proxy.wrapPlayUrls(
        roomId: 'test_room',
        quality: LivePlayQuality(id: 'auto', label: 'Auto', isDefault: true),
        playUrls: [
          LivePlayUrl(
            url: '$upstreamBase/variant.m3u8?playlistType=lowLatency',
            headers: const {'referer': 'https://zh.stripchat.com/flight_room'},
            lineLabel: 'Auto',
            metadata: const {
              'masterPlaylistUrl':
                  'https://edge-hls.doppiocdn.com/hls/120/master/120_auto.m3u8?playlistType=lowLatency',
            },
          ),
        ],
      );

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final playlistUri = Uri.parse(wrapped.single.url);
      final firstPlaylistResponse = await (await client.getUrl(
        playlistUri,
      )).close();
      final firstPlaylistText = utf8.decode(
        await firstPlaylistResponse.fold<List<int>>(
          <int>[],
          (buffer, data) => buffer..addAll(data),
        ),
      );
      final assetUri = Uri.parse(
        RegExp(
          r'http://127\.0\.0\.1:\d+/stripchat-llhls/[^/]+/asset/[a-f0-9]{40}',
        ).firstMatch(firstPlaylistText)!.group(0)!,
      );

      final assetResponseFuture = client
          .getUrl(assetUri)
          .then((request) => request.close());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final refreshResponse = await (await client.getUrl(
        playlistUri,
      )).close().timeout(const Duration(milliseconds: 300));
      expect(refreshResponse.statusCode, HttpStatus.ok);
      await refreshResponse.drain<void>();

      assetGate.complete();
      final assetResponse = await assetResponseFuture;
      expect(assetResponse.statusCode, HttpStatus.ok);
      await assetResponse.drain<void>();
    },
  );

  test(
    'stripchat ll-hls proxy falls back to alternate host after playlist handshake failure',
    () async {
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => upstream.close(force: true));

      upstream.listen((request) async {
        request.response.headers.contentType = ContentType.text;
        request.response.write('''
#EXTM3U
#EXT-X-TARGETDURATION:2
#EXTINF:2.000
http://${upstream.address.host}:${upstream.port}/seg_1.mp4
''');
        await request.response.close();
      });

      final proxy = StripchatLlHlsProxy(
        platformAdapter: _FakePlatformAdapter(),
        enabledOverride: true,
      );
      addTearDown(proxy.dispose);

      final badUri = Uri.parse(
        'https://${upstream.address.host}:${upstream.port}/243097153.m3u8?playlistType=lowLatency&psch=v2&pkey=Ook7quaiNgiyuhai',
      );
      final goodUri = Uri.parse(
        'http://${upstream.address.host}:${upstream.port}/243097153.m3u8?playlistType=lowLatency&psch=v2&pkey=Ook7quaiNgiyuhai',
      );
      final session = proxy.createSessionForTest(
        LivePlayUrl(
          url: badUri.toString(),
          headers: const {'referer': 'https://zh.stripchat.com/test'},
          lineLabel: 'Auto',
          metadata: const {
            'stripchatRoomUrl': 'https://zh.stripchat.com/test',
            'stripchatCdnDomains': ['invalid-host.example'],
          },
        ),
        keyCache: const StripchatMouflonKeyCache(),
      );

      final fetched = await proxy.fetchPlaylistWithFallbacksForTest(
        session: session,
        uri: badUri,
        headers: const {'referer': 'https://zh.stripchat.com/test'},
        fallbackUrisOverride: [goodUri],
      );

      expect(fetched.statusCode, HttpStatus.ok);
      expect(fetched.finalUri.host, upstream.address.host);
      expect(fetched.body, contains('#EXTM3U'));
    },
  );

  test(
    'stripchat ll-hls proxy reuses last successful playlist on transient refresh failure',
    () async {
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => upstream.close(force: true));

      var requestCount = 0;
      upstream.listen((request) async {
        requestCount += 1;
        if (requestCount == 1) {
          request.response.headers.contentType = ContentType.text;
          request.response.write('''
#EXTM3U
#EXT-X-TARGETDURATION:2
#EXTINF:2.000
http://${upstream.address.host}:${upstream.port}/seg_1.mp4
''');
          await request.response.close();
          return;
        }
        final socket = await request.response.detachSocket();
        socket.destroy();
      });

      final proxy = StripchatLlHlsProxy(
        platformAdapter: _FakePlatformAdapter(),
        enabledOverride: true,
        enablePriming: false,
      );
      addTearDown(proxy.dispose);

      final wrapped = await proxy.wrapPlayUrls(
        roomId: 'test_room',
        quality: LivePlayQuality(id: 'auto', label: 'Auto', isDefault: true),
        playUrls: [
          LivePlayUrl(
            url:
                'http://${upstream.address.host}:${upstream.port}/variant.m3u8?playlistType=lowLatency',
            headers: const {'referer': 'https://zh.stripchat.com/stale_room'},
            lineLabel: 'Auto',
            metadata: const {
              'masterPlaylistUrl':
                  'https://edge-hls.doppiocdn.com/hls/121/master/121_auto.m3u8?playlistType=lowLatency',
            },
          ),
        ],
      );

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final playlistUri = Uri.parse(wrapped.single.url);

      final firstResponse = await (await client.getUrl(playlistUri)).close();
      final firstText = utf8.decode(
        await firstResponse.fold<List<int>>(
          <int>[],
          (buffer, data) => buffer..addAll(data),
        ),
      );

      expect(firstResponse.statusCode, HttpStatus.ok);
      expect(firstText, contains('#EXTM3U'));

      final secondResponse = await (await client.getUrl(playlistUri)).close();
      final secondText = utf8.decode(
        await secondResponse.fold<List<int>>(
          <int>[],
          (buffer, data) => buffer..addAll(data),
        ),
      );

      expect(secondResponse.statusCode, HttpStatus.ok);
      expect(secondText, firstText);
    },
  );

  test(
    'stripchat ll-hls proxy returns controlled failure when bridge misses and no pdkey fallback exists',
    () async {
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final upstreamBase = 'http://${upstream.address.host}:${upstream.port}';
      const encodedSegment = 'f5xEAgHTdyjAV9qA';
      const timestamp = '1777921201';

      upstream.listen((request) async {
        if (request.uri.path.endsWith('/variant.m3u8')) {
          request.response.headers.contentType = ContentType.text;
          request.response.write('''
#EXTM3U
#EXT-X-MOUFLON:PSCH:v2:Ook7quaiNgiyuhai
#EXTINF:2.000
#EXT-X-MOUFLON:URI:$upstreamBase/seg_100_${encodedSegment}_$timestamp.mp4
$upstreamBase/media.mp4
''');
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      });

      final proxy = StripchatLlHlsProxy(
        platformAdapter: _FakePlatformAdapter(),
        enabledOverride: true,
        enablePdkeyFallback: false,
        pdkeyResolver: () async => const StripchatMouflonKeyCache(),
      );
      addTearDown(proxy.dispose);
      addTearDown(() => upstream.close(force: true));

      final wrapped = await proxy.wrapPlayUrls(
        roomId: 'test_room',
        quality: LivePlayQuality(id: 'auto', label: 'Auto', isDefault: true),
        playUrls: [
          LivePlayUrl(
            url:
                '$upstreamBase/variant.m3u8?playlistType=lowLatency&psch=v2&pkey=Ook7quaiNgiyuhai',
            headers: const {
              'referer': 'https://zh.stripchat.com/direct_only_room',
            },
            lineLabel: 'Auto',
            metadata: const {
              'stripchatRoomUrl': 'https://zh.stripchat.com/direct_only_room',
              'masterPlaylistUrl':
                  'https://edge-hls.doppiocdn.com/hls/114/master/114_auto.m3u8?playlistType=lowLatency',
            },
          ),
        ],
      );

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final playlistResponse = await (await client.getUrl(
        Uri.parse(wrapped.single.url),
      )).close();
      final playlistText = utf8.decode(
        await playlistResponse.fold<List<int>>(
          <int>[],
          (buffer, data) => buffer..addAll(data),
        ),
      );
      expect(playlistResponse.statusCode, HttpStatus.ok);
      final assetMatch = RegExp(
        r'http://127\.0\.0\.1:\d+/stripchat-llhls/[^/]+/asset/[a-f0-9]{40}',
      ).firstMatch(playlistText);
      expect(assetMatch, isNotNull);
      final assetResponse = await (await client.getUrl(
        Uri.parse(assetMatch!.group(0)!),
      )).close();
      final assetBody = utf8.decode(
        await assetResponse.fold<List<int>>(
          <int>[],
          (buffer, data) => buffer..addAll(data),
        ),
      );
      expect(assetResponse.statusCode, HttpStatus.badGateway);
      expect(
        assetBody,
        contains(
          'stripchat decoded url unavailable and pdkey fallback disabled',
        ),
      );
    },
  );

  test(
    'stripchat ll-hls proxy leaves mouflon uri untouched when pdkey fallback is disabled',
    () async {
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final upstreamBase = 'http://${upstream.address.host}:${upstream.port}';

      upstream.listen((request) async {
        if (request.uri.path.endsWith('/variant.m3u8')) {
          request.response.headers.contentType = ContentType.text;
          request.response.write('''
#EXTM3U
#EXT-X-MOUFLON:PSCH:v2:Ook7quaiNgiyuhai
#EXT-X-MAP:URI="$upstreamBase/init.mp4"
#EXTINF:2.000
#EXT-X-MOUFLON:URI:$upstreamBase/seg_100_f5xEAgHTdyjAV9qA_1777921201.mp4
$upstreamBase/media.mp4
''');
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      });

      final proxy = StripchatLlHlsProxy(
        platformAdapter: _FakePlatformAdapter(),
        enabledOverride: true,
        enablePdkeyFallback: false,
        pdkeyResolver: () async => const StripchatMouflonKeyCache(),
      );
      addTearDown(proxy.dispose);
      addTearDown(() => upstream.close(force: true));

      final wrapped = await proxy.wrapPlayUrls(
        roomId: 'test_room',
        quality: LivePlayQuality(id: 'auto', label: 'Auto', isDefault: true),
        playUrls: [
          LivePlayUrl(
            url:
                '$upstreamBase/variant.m3u8?playlistType=lowLatency&psch=v2&pkey=Ook7quaiNgiyuhai',
            headers: const {'referer': 'https://zh.stripchat.com/no_fallback'},
            lineLabel: 'Auto',
            metadata: const {
              'stripchatRoomUrl': 'https://zh.stripchat.com/no_fallback',
            },
          ),
        ],
      );

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final response = await (await client.getUrl(
        Uri.parse(wrapped.single.url),
      )).close();
      final playlist = utf8.decode(
        await response.fold<List<int>>(
          <int>[],
          (buffer, data) => buffer..addAll(data),
        ),
      );

      expect(response.statusCode, HttpStatus.ok);
      expect(
        playlist,
        contains(
          '#EXT-X-MOUFLON:URI:$upstreamBase/seg_100_f5xEAgHTdyjAV9qA_1777921201.mp4',
        ),
      );
      expect(playlist, isNot(contains('/asset/')));
    },
  );

  test(
    'stripchat ll-hls proxy keeps direct target when no fallback uris are available',
    () async {
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final upstreamBase = 'http://${upstream.address.host}:${upstream.port}';

      upstream.listen((request) async {
        if (request.uri.path.endsWith('/variant.m3u8')) {
          request.response.headers.contentType = ContentType.text;
          request.response.write('''
#EXTM3U
#EXT-X-MAP:URI="$upstreamBase/init.mp4"
#EXTINF:2.000
$upstreamBase/media.mp4
''');
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      });

      final proxy = StripchatLlHlsProxy(
        platformAdapter: _FakePlatformAdapter(),
        enabledOverride: true,
        enablePdkeyFallback: false,
      );
      addTearDown(proxy.dispose);
      addTearDown(() => upstream.close(force: true));

      final wrapped = await proxy.wrapPlayUrls(
        roomId: 'test_room',
        quality: LivePlayQuality(id: 'auto', label: 'Auto', isDefault: true),
        playUrls: [
          LivePlayUrl(
            url: '$upstreamBase/variant.m3u8?playlistType=lowLatency',
            headers: const {
              'referer': 'https://zh.stripchat.com/direct_target',
            },
            lineLabel: 'Auto',
            metadata: const {
              'stripchatRoomUrl': 'https://zh.stripchat.com/direct_target',
            },
          ),
        ],
      );

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final response = await (await client.getUrl(
        Uri.parse(wrapped.single.url),
      )).close();
      final playlist = utf8.decode(
        await response.fold<List<int>>(
          <int>[],
          (buffer, data) => buffer..addAll(data),
        ),
      );

      expect(response.statusCode, HttpStatus.ok);
      expect(playlist, contains('$upstreamBase/init.mp4'));
      expect(playlist, contains('$upstreamBase/media.mp4'));
      expect(
        playlist,
        isNot(contains('da39a3ee5e6b4b0d3255bfef95601890afd80709')),
      );
    },
  );

  test(
    'stripchat ll-hls proxy falls back to another cached pkey when needed',
    () async {
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final upstreamBase = 'http://${upstream.address.host}:${upstream.port}';
      final pdkey = 'fallback-pdkey';
      final encodedSegment = _encryptSegmentForTest('fallbacksegment', pdkey);

      upstream.listen((request) async {
        if (request.uri.path.endsWith('/variant.m3u8')) {
          request.response.headers.contentType = ContentType.text;
          request.response.write('''
#EXTM3U
#EXT-X-MOUFLON:PSCH:v2:missing
#EXTINF:2.000
#EXT-X-MOUFLON:URI:$upstreamBase/seg_100_${encodedSegment}_999.mp4
$upstreamBase/media.mp4
''');
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      });

      final proxy = StripchatLlHlsProxy(
        platformAdapter: _FakePlatformAdapter(),
        enabledOverride: true,
        pdkeyResolver: () async => StripchatMouflonKeyCache(
          records: [
            StripchatMouflonKeyRecord(
              pkey: 'backup',
              pdkey: pdkey,
              capturedAt: DateTime(2026),
              source: StripchatCalibrationSource.manual,
            ),
          ],
        ),
      );
      addTearDown(proxy.dispose);
      addTearDown(() => upstream.close(force: true));

      final wrapped = await proxy.wrapPlayUrls(
        roomId: 'test_room',
        quality: LivePlayQuality(id: 'auto', label: 'Auto', isDefault: true),
        playUrls: [
          LivePlayUrl(
            url:
                '$upstreamBase/variant.m3u8?playlistType=lowLatency&psch=v2&pkey=missing',
            headers: const {
              'referer': 'https://zh.stripchat.com/fallback_room',
            },
            lineLabel: 'Auto',
            metadata: const {
              'masterPlaylistUrl':
                  'https://edge-hls.doppiocdn.com/hls/107/master/107_auto.m3u8?playlistType=lowLatency',
            },
          ),
        ],
      );

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final response = await (await client.getUrl(
        Uri.parse(wrapped.single.url),
      )).close();
      final text = utf8.decode(
        await response.fold<List<int>>(
          <int>[],
          (buffer, data) => buffer..addAll(data),
        ),
      );

      expect(response.statusCode, HttpStatus.ok);
      expect(text, contains('/asset/'));
      expect(text, isNot(contains(encodedSegment)));
    },
  );

  test(
    'stripchat ll-hls proxy decrypts with hardcoded pdkey for known pkey',
    () async {
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final upstreamBase = 'http://${upstream.address.host}:${upstream.port}';
      final pdkey = 'EQueeGh2kaewa3ch';
      final decryptedSegment = 'secretToken';
      final encodedSegment = _encryptSegmentForTest(decryptedSegment, pdkey);

      upstream.listen((request) async {
        if (request.uri.path.endsWith('/variant.m3u8')) {
          request.response.headers.contentType = ContentType.text;
          request.response.write('''
#EXTM3U
#EXT-X-MOUFLON:PSCH:v2:Ook7quaiNgiyuhai
#EXTINF:2.000
#EXT-X-MOUFLON:URI:$upstreamBase/seg_100_${encodedSegment}_999.mp4
$upstreamBase/media.mp4
''');
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      });

      final proxy = StripchatLlHlsProxy(
        platformAdapter: _FakePlatformAdapter(),
        enabledOverride: true,
        pdkeyResolver: () async => const StripchatMouflonKeyCache(),
      );
      addTearDown(proxy.dispose);
      addTearDown(() => upstream.close(force: true));

      final wrapped = await proxy.wrapPlayUrls(
        roomId: 'test_room',
        quality: LivePlayQuality(id: 'auto', label: 'Auto', isDefault: true),
        playUrls: [
          LivePlayUrl(
            url:
                '$upstreamBase/variant.m3u8?playlistType=lowLatency&psch=v2&pkey=Ook7quaiNgiyuhai',
            headers: const {
              'referer': 'https://zh.stripchat.com/hardcoded_room',
            },
            lineLabel: 'Auto',
            metadata: const {
              'masterPlaylistUrl':
                  'https://edge-hls.doppiocdn.com/hls/108/master/108_auto.m3u8?playlistType=lowLatency',
            },
          ),
        ],
      );

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final response = await (await client.getUrl(
        Uri.parse(wrapped.single.url),
      )).close();
      final text = utf8.decode(
        await response.fold<List<int>>(
          <int>[],
          (buffer, data) => buffer..addAll(data),
        ),
      );

      expect(response.statusCode, HttpStatus.ok);
      expect(text, isNot(contains('#EXT-X-MOUFLON:')));
      expect(text, isNot(contains('decrypt-failed')));
      expect(text, isNot(contains(encodedSegment)));
    },
  );

  test(
    'stripchat ll-hls proxy prefers saved account pdkey over hardcoded fallback',
    () async {
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final upstreamBase = 'http://${upstream.address.host}:${upstream.port}';
      const accountPdkey = 'AccountPdkey1234';
      const decryptedSegment = 'accountToken';
      final encodedSegment = _encryptSegmentForTest(
        decryptedSegment,
        accountPdkey,
      );

      upstream.listen((request) async {
        if (request.uri.path.endsWith('/variant.m3u8')) {
          request.response.headers.contentType = ContentType.text;
          request.response.write('''
#EXTM3U
#EXT-X-MOUFLON:PSCH:v2:Ook7quaiNgiyuhai
#EXTINF:2.000
#EXT-X-MOUFLON:URI:$upstreamBase/seg_100_${encodedSegment}_999.mp4
$upstreamBase/media.mp4
''');
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      });

      final proxy = StripchatLlHlsProxy(
        platformAdapter: _FakePlatformAdapter(),
        enabledOverride: true,
        pdkeyResolver: () async => StripchatMouflonKeyCache(
          records: [
            StripchatMouflonKeyRecord(
              pkey: 'Ook7quaiNgiyuhai',
              pdkey: accountPdkey,
              capturedAt: DateTime(2026),
              source: StripchatCalibrationSource.auto,
              captureSource: 'hash-cache-key',
            ),
          ],
        ),
      );
      addTearDown(proxy.dispose);
      addTearDown(() => upstream.close(force: true));

      final wrapped = await proxy.wrapPlayUrls(
        roomId: 'test_room',
        quality: LivePlayQuality(id: 'auto', label: 'Auto', isDefault: true),
        playUrls: [
          LivePlayUrl(
            url:
                '$upstreamBase/variant.m3u8?playlistType=lowLatency&psch=v2&pkey=Ook7quaiNgiyuhai',
            headers: const {'referer': 'https://zh.stripchat.com/account_room'},
            lineLabel: 'Auto',
            metadata: const {
              'masterPlaylistUrl':
                  'https://edge-hls.doppiocdn.com/hls/109/master/109_auto.m3u8?playlistType=lowLatency',
            },
          ),
        ],
      );

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final response = await (await client.getUrl(
        Uri.parse(wrapped.single.url),
      )).close();
      final text = utf8.decode(
        await response.fold<List<int>>(
          <int>[],
          (buffer, data) => buffer..addAll(data),
        ),
      );

      expect(response.statusCode, HttpStatus.ok);
      expect(text, isNot(contains('#EXT-X-MOUFLON:')));
      expect(text, isNot(contains(encodedSegment)));
    },
  );

  test(
    'stripchat ll-hls proxy falls back to decrypted mouflon asset when direct asset fails',
    () async {
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final upstreamBase = 'http://${upstream.address.host}:${upstream.port}';
      const accountPdkey = 'AccountPdkey1234';
      const decryptedSegment = 'accountToken';
      final encodedSegment = _encryptSegmentForTest(
        decryptedSegment,
        accountPdkey,
      );
      final seenRequests = <String>[];

      upstream.listen((request) async {
        seenRequests.add(request.requestedUri.toString());
        if (request.uri.path.endsWith('/variant.m3u8')) {
          request.response.headers.contentType = ContentType.text;
          request.response.write('''
#EXTM3U
#EXT-X-MOUFLON:PSCH:v2:Ook7quaiNgiyuhai
#EXTINF:2.000
#EXT-X-MOUFLON:URI:$upstreamBase/seg_100_${encodedSegment}_999.mp4
$upstreamBase/media.mp4
''');
        } else if (request.uri.path.contains(encodedSegment)) {
          request.response.statusCode = HttpStatus.notFound;
        } else if (request.uri.path.contains(decryptedSegment)) {
          request.response.headers.contentType = ContentType.binary;
          request.response.add(utf8.encode('decoded:${request.uri.path}'));
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      });

      final proxy = StripchatLlHlsProxy(
        platformAdapter: _FakePlatformAdapter(),
        enabledOverride: true,
        pdkeyResolver: () async => StripchatMouflonKeyCache(
          records: [
            StripchatMouflonKeyRecord(
              pkey: 'Ook7quaiNgiyuhai',
              pdkey: accountPdkey,
              capturedAt: DateTime(2026),
              source: StripchatCalibrationSource.auto,
              captureSource: 'hash-cache-key',
            ),
          ],
        ),
      );
      addTearDown(proxy.dispose);
      addTearDown(() => upstream.close(force: true));

      final wrapped = await proxy.wrapPlayUrls(
        roomId: 'test_room',
        quality: LivePlayQuality(id: 'auto', label: 'Auto', isDefault: true),
        playUrls: [
          LivePlayUrl(
            url:
                '$upstreamBase/variant.m3u8?playlistType=lowLatency&psch=v2&pkey=Ook7quaiNgiyuhai',
            headers: const {'referer': 'https://zh.stripchat.com/account_room'},
            lineLabel: 'Auto',
            metadata: const {
              'masterPlaylistUrl':
                  'https://edge-hls.doppiocdn.com/hls/111/master/111_auto.m3u8?playlistType=lowLatency',
            },
          ),
        ],
      );

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final playlistResponse = await (await client.getUrl(
        Uri.parse(wrapped.single.url),
      )).close();
      final playlistText = utf8.decode(
        await playlistResponse.fold<List<int>>(
          <int>[],
          (buffer, data) => buffer..addAll(data),
        ),
      );
      final assetUri = Uri.parse(
        RegExp(
          r'http://127\.0\.0\.1:\d+/stripchat-llhls/[^/]+/asset/[a-f0-9]{40}',
        ).firstMatch(playlistText)!.group(0)!,
      );
      final assetResponse = await (await client.getUrl(assetUri)).close();
      final assetText = utf8.decode(
        await assetResponse.fold<List<int>>(
          <int>[],
          (buffer, data) => buffer..addAll(data),
        ),
      );

      expect(playlistResponse.statusCode, HttpStatus.ok);
      expect(assetResponse.statusCode, HttpStatus.ok);
      expect(
        assetText,
        contains('decoded:/seg_100_${decryptedSegment}_999.mp4'),
      );
      expect(seenRequests.any((uri) => uri.contains(encodedSegment)), isFalse);
      expect(seenRequests.any((uri) => uri.contains(decryptedSegment)), isTrue);
    },
  );

  test(
    'stripchat ll-hls proxy ignores init-map cache records for mouflon decryption',
    () async {
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final upstreamBase = 'http://${upstream.address.host}:${upstream.port}';
      const trustedPdkey = 'EQueeGh2kaewa3ch';
      const badPdkey = 'MHk2qPZCinTI9TAv';
      const decryptedSegment = 'trustedsegment';
      final encodedSegment = _encryptSegmentForTest(
        decryptedSegment,
        trustedPdkey,
      );
      final seenRequests = <String>[];

      upstream.listen((request) async {
        seenRequests.add(request.requestedUri.toString());
        if (request.uri.path.endsWith('/variant.m3u8')) {
          request.response.headers.contentType = ContentType.text;
          request.response.write('''
#EXTM3U
#EXT-X-MOUFLON:PSCH:v2:Ook7quaiNgiyuhai
#EXTINF:2.000
#EXT-X-MOUFLON:URI:$upstreamBase/seg_100_${encodedSegment}_999.mp4
$upstreamBase/media.mp4
''');
        } else if (request.uri.path.contains(decryptedSegment)) {
          request.response.headers.contentType = ContentType.binary;
          request.response.add(utf8.encode('decoded:${request.uri.path}'));
        } else if (request.uri.path.contains(encodedSegment)) {
          request.response.statusCode = HttpStatus.notFound;
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      });

      final proxy = StripchatLlHlsProxy(
        platformAdapter: _FakePlatformAdapter(),
        enabledOverride: true,
        pdkeyResolver: () async => StripchatMouflonKeyCache(
          records: [
            StripchatMouflonKeyRecord(
              pkey: 'Ook7quaiNgiyuhai',
              pdkey: badPdkey,
              capturedAt: DateTime(2026),
              source: StripchatCalibrationSource.auto,
              captureSource: 'hash-cache-key:init-map',
            ),
          ],
        ),
      );
      addTearDown(proxy.dispose);
      addTearDown(() => upstream.close(force: true));

      final wrapped = await proxy.wrapPlayUrls(
        roomId: 'test_room',
        quality: LivePlayQuality(id: 'auto', label: 'Auto', isDefault: true),
        playUrls: [
          LivePlayUrl(
            url:
                '$upstreamBase/variant.m3u8?playlistType=lowLatency&psch=v2&pkey=Ook7quaiNgiyuhai',
            headers: const {
              'referer': 'https://zh.stripchat.com/init_map_room',
            },
            lineLabel: 'Auto',
            metadata: const {
              'masterPlaylistUrl':
                  'https://edge-hls.doppiocdn.com/hls/112/master/112_auto.m3u8?playlistType=lowLatency',
            },
          ),
        ],
      );

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final playlistResponse = await (await client.getUrl(
        Uri.parse(wrapped.single.url),
      )).close();
      final playlistText = utf8.decode(
        await playlistResponse.fold<List<int>>(
          <int>[],
          (buffer, data) => buffer..addAll(data),
        ),
      );
      final assetUri = Uri.parse(
        RegExp(
          r'http://127\.0\.0\.1:\d+/stripchat-llhls/[^/]+/asset/[a-f0-9]{40}',
        ).firstMatch(playlistText)!.group(0)!,
      );
      final assetResponse = await (await client.getUrl(assetUri)).close();
      final assetText = utf8.decode(
        await assetResponse.fold<List<int>>(
          <int>[],
          (buffer, data) => buffer..addAll(data),
        ),
      );

      expect(playlistResponse.statusCode, HttpStatus.ok);
      expect(assetResponse.statusCode, HttpStatus.ok);
      expect(
        assetText,
        contains('decoded:/seg_100_${decryptedSegment}_999.mp4'),
      );
      expect(
        seenRequests.where((uri) => uri.contains(encodedSegment)).length,
        0,
      );
      expect(seenRequests.any((uri) => uri.contains(decryptedSegment)), isTrue);
    },
  );

  test(
    'stripchat ll-hls proxy prefers fallback assets after repeated direct 404s in same session',
    () async {
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final upstreamBase = 'http://${upstream.address.host}:${upstream.port}';
      const accountPdkey = 'AccountPdkey1234';
      const decryptedA = 'segmentA';
      const decryptedB = 'segmentB';
      final encodedA = _encryptSegmentForTest(decryptedA, accountPdkey);
      final encodedB = _encryptSegmentForTest(decryptedB, accountPdkey);
      final seenRequests = <String>[];

      upstream.listen((request) async {
        seenRequests.add(request.requestedUri.toString());
        if (request.uri.path.endsWith('/variant.m3u8')) {
          request.response.headers.contentType = ContentType.text;
          request.response.write('''
#EXTM3U
#EXT-X-MOUFLON:PSCH:v2:Ook7quaiNgiyuhai
#EXTINF:2.000
#EXT-X-MOUFLON:URI:$upstreamBase/seg_100_${encodedA}_999.mp4
$upstreamBase/media_a.mp4
#EXTINF:2.000
#EXT-X-MOUFLON:URI:$upstreamBase/seg_200_${encodedB}_999.mp4
$upstreamBase/media_b.mp4
''');
        } else if (request.uri.path.contains(encodedA) ||
            request.uri.path.contains(encodedB)) {
          request.response.statusCode = HttpStatus.notFound;
        } else if (request.uri.path.contains(decryptedA) ||
            request.uri.path.contains(decryptedB)) {
          request.response.headers.contentType = ContentType.binary;
          request.response.add(utf8.encode('decoded:${request.uri.path}'));
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      });

      final proxy = StripchatLlHlsProxy(
        platformAdapter: _FakePlatformAdapter(),
        enabledOverride: true,
        pdkeyResolver: () async => StripchatMouflonKeyCache(
          records: [
            StripchatMouflonKeyRecord(
              pkey: 'Ook7quaiNgiyuhai',
              pdkey: accountPdkey,
              capturedAt: DateTime(2026),
              source: StripchatCalibrationSource.auto,
              captureSource: 'hash-cache-key',
            ),
          ],
        ),
      );
      addTearDown(proxy.dispose);
      addTearDown(() => upstream.close(force: true));

      final wrapped = await proxy.wrapPlayUrls(
        roomId: 'test_room',
        quality: LivePlayQuality(id: 'auto', label: 'Auto', isDefault: true),
        playUrls: [
          LivePlayUrl(
            url:
                '$upstreamBase/variant.m3u8?playlistType=lowLatency&psch=v2&pkey=Ook7quaiNgiyuhai',
            headers: const {
              'referer': 'https://zh.stripchat.com/direct_fail_room',
            },
            lineLabel: 'Auto',
            metadata: const {
              'masterPlaylistUrl':
                  'https://edge-hls.doppiocdn.com/hls/113/master/113_auto.m3u8?playlistType=lowLatency',
            },
          ),
        ],
      );

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final playlistResponse = await (await client.getUrl(
        Uri.parse(wrapped.single.url),
      )).close();
      final playlistText = utf8.decode(
        await playlistResponse.fold<List<int>>(
          <int>[],
          (buffer, data) => buffer..addAll(data),
        ),
      );
      final assetMatches = RegExp(
        r'http://127\.0\.0\.1:\d+/stripchat-llhls/[^/]+/asset/[a-f0-9]{40}',
      ).allMatches(playlistText).toList(growable: false);
      expect(assetMatches.length, 2);
      final firstAsset = Uri.parse(assetMatches[0].group(0)!);

      final firstResponse = await (await client.getUrl(firstAsset)).close();
      final firstText = utf8.decode(
        await firstResponse.fold<List<int>>(
          <int>[],
          (buffer, data) => buffer..addAll(data),
        ),
      );
      final directBCountBeforeSecond = seenRequests
          .where((uri) => uri.contains(encodedB))
          .length;

      final refreshedPlaylistResponse = await (await client.getUrl(
        Uri.parse(wrapped.single.url),
      )).close();
      final refreshedPlaylistText = utf8.decode(
        await refreshedPlaylistResponse.fold<List<int>>(
          <int>[],
          (buffer, data) => buffer..addAll(data),
        ),
      );
      final refreshedAssetMatches = RegExp(
        r'http://127\.0\.0\.1:\d+/stripchat-llhls/[^/]+/asset/[a-f0-9]{40}',
      ).allMatches(refreshedPlaylistText).toList(growable: false);
      expect(refreshedAssetMatches.length, 2);
      final refreshedSecondAsset = Uri.parse(
        refreshedAssetMatches[1].group(0)!,
      );

      final secondResponse = await (await client.getUrl(
        refreshedSecondAsset,
      )).close();
      final secondText = utf8.decode(
        await secondResponse.fold<List<int>>(
          <int>[],
          (buffer, data) => buffer..addAll(data),
        ),
      );
      final directBCountAfterSecond = seenRequests
          .where((uri) => uri.contains(encodedB))
          .length;
      final fallbackBCountAfterSecond = seenRequests
          .where((uri) => uri.contains(decryptedB))
          .length;

      expect(firstResponse.statusCode, HttpStatus.ok);
      expect(refreshedPlaylistResponse.statusCode, HttpStatus.ok);
      expect(secondResponse.statusCode, HttpStatus.ok);
      expect(firstText, contains('decoded:/seg_100_${decryptedA}_999.mp4'));
      expect(secondText, contains('decoded:/seg_200_${decryptedB}_999.mp4'));
      expect(directBCountAfterSecond, directBCountBeforeSecond);
      expect(fallbackBCountAfterSecond, greaterThanOrEqualTo(1));
    },
  );

  test(
    'stripchat ll-hls proxy forwards only chromium direct headers upstream',
    () async {
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final upstreamBase = 'http://${upstream.address.host}:${upstream.port}';
      final seenHeaders = <Map<String, String>>[];

      upstream.listen((request) async {
        final captured = <String, String>{};
        request.headers.forEach((name, values) {
          captured[name.toLowerCase()] = values.join(', ');
        });
        seenHeaders.add(captured);
        if (request.uri.path.endsWith('/variant.m3u8')) {
          request.response.headers.contentType = ContentType.text;
          request.response.write('''
#EXTM3U
#EXT-X-TARGETDURATION:2
#EXTINF:2.000
$upstreamBase/seg_7000.mp4
''');
        } else if (request.uri.path.endsWith('.mp4')) {
          request.response.headers.contentType = ContentType.binary;
          request.response.add(utf8.encode(request.uri.path));
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      });

      final proxy = StripchatLlHlsProxy(
        platformAdapter: _FakePlatformAdapter(),
        enabledOverride: true,
        enablePriming: false,
      );
      addTearDown(proxy.dispose);
      addTearDown(() => upstream.close(force: true));

      final wrapped = await proxy.wrapPlayUrls(
        roomId: 'test_room',
        quality: LivePlayQuality(id: 'auto', label: 'Auto', isDefault: true),
        playUrls: [
          LivePlayUrl(
            url: '$upstreamBase/variant.m3u8?playlistType=lowLatency',
            headers: const {
              'referer': 'https://zh.stripchat.com/',
              'user-agent': 'Mozilla/5.0 Test',
              'sec-ch-ua': '"Chromium";v="148"',
              'sec-ch-ua-mobile': '?0',
              'sec-ch-ua-platform': '"Android"',
              'origin': 'https://zh.stripchat.com',
              'cookie': 'session=secret',
              'accept': '*/*',
              'accept-language': 'zh-CN,zh;q=0.9',
              'sec-fetch-site': 'cross-site',
            },
            lineLabel: 'Auto',
            metadata: const {
              'masterPlaylistUrl':
                  'https://edge-hls.doppiocdn.com/hls/114/master/114_auto.m3u8?playlistType=lowLatency',
            },
          ),
        ],
      );

      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final playlistResponse = await (await client.getUrl(
        Uri.parse(wrapped.single.url),
      )).close();
      final playlistText = utf8.decode(
        await playlistResponse.fold<List<int>>(
          <int>[],
          (buffer, data) => buffer..addAll(data),
        ),
      );
      final assetUri = Uri.parse(
        RegExp(
          r'http://127\.0\.0\.1:\d+/stripchat-llhls/[^/]+/asset/[a-f0-9]{40}',
        ).firstMatch(playlistText)!.group(0)!,
      );
      final assetResponse = await (await client.getUrl(assetUri)).close();
      await assetResponse.drain<void>();

      expect(assetResponse.statusCode, HttpStatus.ok);
      expect(seenHeaders, hasLength(2));
      for (final headers in seenHeaders) {
        expect(headers['referer'], 'https://zh.stripchat.com/');
        expect(headers['user-agent'], 'Mozilla/5.0 Test');
        expect(headers['sec-ch-ua'], '"Chromium";v="148"');
        expect(headers['sec-ch-ua-mobile'], '?0');
        expect(headers['sec-ch-ua-platform'], '"Android"');
        // These are now in the whitelist and should be forwarded:
        expect(headers['origin'], 'https://zh.stripchat.com');
        expect(headers.containsKey('cookie'), isFalse);
        expect(headers['accept'], '*/*');
        expect(headers['accept-language'], 'zh-CN,zh;q=0.9');
        // sec-fetch-site is a navigation-only header and still blocked:
        expect(headers.containsKey('sec-fetch-site'), isFalse);
      }
    },
  );

  test(
    'stripchat ll-hls proxy picks known pkey when master has multiple PSCH lines',
    () async {
      // Simulate a master playlist that declares multiple PSCH pkeys:
      //   unknownKey11111  — no pdkey in hardcoded table (appears first)
      //   Fq6m2TO2ZeBkRPm9 — known pdkey xb6di1NF9EFXHUwb (appears second)
      //   rHQhP6lNYB8v13s1 — no pdkey in hardcoded table (appears last)
      //
      // The proxy must select Fq6m2TO2ZeBkRPm9 so it can decrypt segments,
      // not blindly use the last-seen pkey (rHQhP6lNYB8v13s1).
      const knownPkey = 'Fq6m2TO2ZeBkRPm9';
      const knownPdkey = 'xb6di1NF9EFXHUwb';

      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final upstreamBase = 'http://${upstream.address.host}:${upstream.port}';

      upstream.listen((request) async {
        if (request.uri.path.endsWith('/variant.m3u8')) {
          request.response.headers.contentType = ContentType.text;
          final encSeg = _encryptSegmentForTest('seg_5000', knownPdkey);
          request.response.write('''
#EXTM3U
#EXT-X-VERSION:6
#EXT-X-MOUFLON:PSCH:v2:unknownKey11111
#EXT-X-MOUFLON:PSCH:v2:$knownPkey
#EXT-X-MOUFLON:PSCH:v2:rHQhP6lNYB8v13s1
#EXT-X-TARGETDURATION:2
#EXT-X-MEDIA-SEQUENCE:100
#EXT-X-MOUFLON:URI:$upstreamBase/seg_100_${encSeg}_999.mp4
#EXTINF:2.000
$upstreamBase/seg_100_${encSeg}_999.mp4
''');
        } else if (request.uri.path.endsWith('.mp4')) {
          request.response.headers.contentType = ContentType.binary;
          request.response.add(utf8.encode(request.uri.path));
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      });

      final proxy = StripchatLlHlsProxy(
        platformAdapter: _FakePlatformAdapter(),
        enabledOverride: true,
        enablePdkeyFallback: true,
      );
      addTearDown(proxy.dispose);
      addTearDown(() => upstream.close(force: true));

      final wrapped = await proxy.wrapPlayUrls(
        roomId: 'test_room',
        quality: LivePlayQuality(id: 'auto', label: 'Auto', isDefault: true),
        playUrls: [
          LivePlayUrl(
            url: '$upstreamBase/variant.m3u8',
            headers: const {'referer': 'https://zh.stripchat.com/test_room'},
            lineLabel: 'Auto',
            metadata: const {
              'masterPlaylistUrl':
                  'https://edge-hls.doppiocdn.com/hls/999/master/999_auto.m3u8',
            },
          ),
        ],
      );

      final client = HttpClient();
      addTearDown(() => client.close(force: true));

      final playlistResponse = await (await client.getUrl(
        Uri.parse(wrapped.single.url),
      )).close();
      final playlistText = utf8.decode(
        await playlistResponse.fold<List<int>>(
          <int>[],
          (buffer, data) => buffer..addAll(data),
        ),
      );

      // The proxy must have produced a local asset URI (decryption succeeded
      // using Fq6m2TO2ZeBkRPm9, not the last pkey rHQhP6lNYB8v13s1).
      final assetMatch = RegExp(
        r'http://127\.0\.0\.1:\d+/stripchat-llhls/[^/]+/asset/[a-f0-9]{40}',
      ).firstMatch(playlistText);
      expect(
        assetMatch,
        isNotNull,
        reason:
            'Expected proxy to emit a local asset URI (known pkey selected); '
            'got playlist:\n$playlistText',
      );

      // Fetch the asset — it should serve the decrypted segment path
      final assetUri = Uri.parse(assetMatch!.group(0)!);
      final assetResponse = await (await client.getUrl(assetUri)).close();
      final assetBytes = await assetResponse.fold<List<int>>(
        <int>[],
        (buffer, data) => buffer..addAll(data),
      );
      expect(assetResponse.statusCode, HttpStatus.ok);
      expect(utf8.decode(assetBytes), contains('seg_5000'));
    },
  );

  test(
    'stripchat ll-hls proxy starts session priming and pre-fetches/rewrites master and child playlists',
    () async {
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final upstreamBase = 'http://${upstream.address.host}:${upstream.port}';

      final pdkey = 'priming-pdkey-123';
      final encodedSegment = _encryptSegmentForTest('primedsegment', pdkey);
      final seenUris = <String>{};

      upstream.listen((request) async {
        seenUris.add(request.uri.toString());
        if (request.uri.path.endsWith('/master.m3u8')) {
          request.response.headers.contentType = ContentType.text;
          request.response.write('''
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=1000000
$upstreamBase/variant.m3u8?playlistType=lowLatency
''');
        } else if (request.uri.path.endsWith('/variant.m3u8')) {
          request.response.headers.contentType = ContentType.text;
          request.response.write('''
#EXTM3U
#EXT-X-MOUFLON:PSCH:v2:Ook7quaiNgiyuhai
#EXT-X-MAP:URI="$upstreamBase/init.mp4"
#EXTINF:2.000
#EXT-X-MOUFLON:URI:$upstreamBase/seg_100_${encodedSegment}_999.mp4
$upstreamBase/media.mp4
''');
        } else if (request.uri.path.endsWith('/init.mp4')) {
          request.response.headers.contentType = ContentType.binary;
          request.response.add(Uint8List(100));
        } else if (request.uri.path.contains(encodedSegment)) {
          request.response.headers.contentType = ContentType.binary;
          request.response.add(utf8.encode('decryptedsegmentbytes'));
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      });

      final proxy = StripchatLlHlsProxy(
        platformAdapter: _FakePlatformAdapter(),
        enabledOverride: true,
        pdkeyResolver: () async => StripchatMouflonKeyCache(
          records: [
            StripchatMouflonKeyRecord(
              pkey: 'Ook7quaiNgiyuhai',
              pdkey: pdkey,
              capturedAt: DateTime(2026),
              source: StripchatCalibrationSource.manual,
            ),
          ],
        ),
      );
      addTearDown(proxy.dispose);
      addTearDown(() => upstream.close(force: true));

      final wrapped = await proxy.wrapPlayUrls(
        roomId: 'test_room',
        quality: LivePlayQuality(id: 'auto', label: 'Auto', isDefault: true),
        playUrls: [
          LivePlayUrl(
            url: '$upstreamBase/master.m3u8',
            headers: const {'referer': 'https://zh.stripchat.com/prime_room'},
            lineLabel: 'Auto',
            metadata: const {
              'stripchatRoomUrl': 'https://zh.stripchat.com/prime_room',
              'masterPlaylistUrl':
                  'https://edge-hls.doppiocdn.com/hls/999/master/999_auto.m3u8?playlistType=lowLatency',
            },
          ),
        ],
      );

      final url = Uri.parse(wrapped.single.url);
      final sessionId = url.pathSegments[1];
      final primeFuture = proxy.getSessionPrimeFuture(sessionId);
      expect(primeFuture, isNotNull);

      // Wait for priming to complete
      await primeFuture;

      // Auto ABR: prime rewrites multi-variant master only. Child media
      // playlists warm on first player request (not forced collapse).
      expect(seenUris, contains('/master.m3u8'));
      expect(
        seenUris.where((u) => u.contains('variant.m3u8')),
        isEmpty,
      );
    },
  );

  group('ensureStarted lifecycle', () {
    test('concurrent ensureStarted single-flight and post-dispose fails closed',
        () async {
      final proxy = StripchatLlHlsProxy(
        platformAdapter: _FakePlatformAdapter(),
        enabledOverride: true,
      );
      await Future.wait([
        proxy.ensureStarted(),
        proxy.ensureStarted(),
        proxy.ensureStarted(),
      ]);
      await proxy.ensureStarted();
      await proxy.dispose();
      await expectLater(
        proxy.ensureStarted(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('disposed'),
          ),
        ),
      );
    });

    test('dispose during ensureStarted fails closed', () async {
      final proxy = StripchatLlHlsProxy(
        platformAdapter: _FakePlatformAdapter(),
        enabledOverride: true,
      );
      final start = proxy.ensureStarted();
      await Future<void>.delayed(Duration.zero);
      await proxy.dispose();
      try {
        await start;
      } on StateError catch (error) {
        expect(
          error.message.contains('disposed') ||
              error.message.contains('failed to start'),
          isTrue,
        );
      }
      await expectLater(proxy.ensureStarted(), throwsA(isA<StateError>()));
    });
  });
}


String _encryptSegmentForTest(String value, String pdkey) {
  return _encryptBytesForTest(utf8.encode(value), pdkey);
}

String _encryptBytesForTest(List<int> input, String pdkey) {
  final hashBytes = sha256.convert(utf8.encode(pdkey)).bytes;
  final output = List<int>.generate(
    input.length,
    (index) => input[index] ^ hashBytes[index % hashBytes.length],
  );
  return base64.encode(output).split('').reversed.join();
}
