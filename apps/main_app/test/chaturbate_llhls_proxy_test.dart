import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:nolive_app/src/app/runtime_bridges/chaturbate/chaturbate_llhls_proxy.dart';

void main() {
  test('chaturbate mp4 sniffing detects self-initialized fragments', () {
    expect(
      chaturbateMp4BytesContainInitialization(
        Uint8List.fromList(<int>[0, 0, 0, 8, 109, 111, 111, 118]),
      ),
      isTrue,
    );
    expect(
      chaturbateMp4BytesContainInitialization(
        Uint8List.fromList(<int>[0, 0, 0, 8, 109, 111, 111, 102]),
      ),
      isFalse,
    );
  });

  test('chaturbate ll-hls proxy rewrites media playlists into standard hls',
      () async {
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final baseUrl = 'http://${upstream.address.host}:${upstream.port}';
    const videoPlaylist = '''
#EXTM3U
#EXT-X-VERSION:6
#EXT-X-TARGETDURATION:2
#EXT-X-SERVER-CONTROL:CAN-BLOCK-RELOAD=YES,PART-HOLD-BACK=2.430000
#EXT-X-PART-INF:PART-TARGET=0.800000
#EXT-X-MEDIA-SEQUENCE:7245
#EXT-X-MAP:URI="/v1/edge/streams/origin.demo/init_2_video_llhls.m4s?session=test"
#EXT-X-PROGRAM-DATE-TIME:2026-04-22T09:52:16.461+00:00
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_2_7245_video_llhls.m4s?session=test
#EXT-X-PART:DURATION=0.800000,URI="/v1/edge/streams/origin.demo/part_2_7246_0_video_llhls.m4s?session=test",INDEPENDENT=YES
#EXT-X-PART:DURATION=0.800000,URI="/v1/edge/streams/origin.demo/part_2_7246_1_video_llhls.m4s?session=test",INDEPENDENT=YES
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_2_7246_video_llhls.m4s?session=test
#EXT-X-PRELOAD-HINT:TYPE=PART,URI="/v1/edge/streams/origin.demo/part_2_7247_0_video_llhls.m4s?session=test"
#EXT-X-RENDITION-REPORT:URI="/v1/edge/streams/origin.demo/chunklist_7_audio_llhls.m3u8?session=test",LAST-MSN=7246,LAST-PART=1
''';
    const audioPlaylist = '''
#EXTM3U
#EXT-X-VERSION:6
#EXT-X-TARGETDURATION:2
#EXT-X-SERVER-CONTROL:CAN-BLOCK-RELOAD=YES,PART-HOLD-BACK=2.430000
#EXT-X-PART-INF:PART-TARGET=0.811000
#EXT-X-MEDIA-SEQUENCE:7246
#EXT-X-MAP:URI="/v1/edge/streams/origin.demo/init_7_audio_llhls.m4s?session=test"
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_7_7246_audio_llhls.m4s?session=test
#EXT-X-PART:DURATION=0.810667,URI="/v1/edge/streams/origin.demo/part_7_7247_0_audio_llhls.m4s?session=test",INDEPENDENT=YES
#EXT-X-PART:DURATION=0.789333,URI="/v1/edge/streams/origin.demo/part_7_7247_1_audio_llhls.m4s?session=test",INDEPENDENT=YES
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_7_7247_audio_llhls.m4s?session=test
#EXT-X-PRELOAD-HINT:TYPE=PART,URI="/v1/edge/streams/origin.demo/part_7_7248_0_audio_llhls.m4s?session=test"
''';
    final assets = <String, List<int>>{
      '/v1/edge/streams/origin.demo/init_2_video_llhls.m4s?session=test':
          utf8.encode('video-init'),
      '/v1/edge/streams/origin.demo/seg_2_7245_video_llhls.m4s?session=test':
          utf8.encode('video-seg-7245'),
      '/v1/edge/streams/origin.demo/seg_2_7246_video_llhls.m4s?session=test':
          utf8.encode('video-seg-7246'),
      '/v1/edge/streams/origin.demo/init_7_audio_llhls.m4s?session=test':
          utf8.encode('audio-init'),
      '/v1/edge/streams/origin.demo/seg_7_7246_audio_llhls.m4s?session=test':
          utf8.encode('audio-seg-7246'),
      '/v1/edge/streams/origin.demo/seg_7_7247_audio_llhls.m4s?session=test':
          utf8.encode('audio-seg-7247'),
    };
    upstream.listen((request) async {
      final path = request.requestedUri.path;
      final fullPath = request.uri.toString();
      if (path.endsWith('chunklist_2_video_llhls.m3u8')) {
        request.response.headers.contentType = ContentType.text;
        request.response.write(videoPlaylist);
      } else if (path.endsWith('chunklist_7_audio_llhls.m3u8')) {
        request.response.headers.contentType = ContentType.text;
        request.response.write(audioPlaylist);
      } else if (assets.containsKey(fullPath)) {
        request.response.add(assets[fullPath]!);
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });

    final proxy = ChaturbateLlHlsProxy(enabledOverride: true);
    final wrapped = await proxy.wrapPlayUrls(
      quality: const LivePlayQuality(
        id: '2096000',
        label: '540p',
        sortOrder: 540,
        metadata: {
          'bandwidth': 2096000,
          'width': 960,
          'height': 540,
          'codecs': 'avc1.4d401f,mp4a.40.2',
        },
      ),
      playUrls: [
        LivePlayUrl(
          url:
              '$baseUrl/v1/edge/streams/origin.demo/chunklist_2_video_llhls.m3u8?session=test',
          headers: const {'referer': 'https://chaturbate.com/demo/'},
          lineLabel: 'LAX',
          metadata: {
            'audioUrl':
                '$baseUrl/v1/edge/streams/origin.demo/chunklist_7_audio_llhls.m3u8?session=test',
            'audioHeaders': {'referer': 'https://chaturbate.com/demo/'},
            'bandwidth': 2096000,
            'width': 960,
            'height': 540,
            'codecs': 'avc1.4d401f,mp4a.40.2',
          },
        ),
      ],
    );

    final proxiedUrl = Uri.parse(wrapped.single.url);
    final client = HttpClient();
    final masterResponse = await (await client.getUrl(proxiedUrl)).close();
    final masterText = utf8.decode(await masterResponse.fold<List<int>>(
      <int>[],
      (buffer, data) => buffer..addAll(data),
    ));
    expect(masterText, contains('/chaturbate-llhls/'));
    expect(masterText, contains('/video.m3u8'));
    expect(masterText, contains('/audio.m3u8'));

    final videoUri =
        RegExp(r'http://127\.0\.0\.1:\d+/chaturbate-llhls/[^\s]+/video\.m3u8')
            .firstMatch(masterText)!
            .group(0)!;
    final videoResponse =
        await (await client.getUrl(Uri.parse(videoUri))).close();
    final videoText = utf8.decode(await videoResponse.fold<List<int>>(
      <int>[],
      (buffer, data) => buffer..addAll(data),
    ));
    expect(videoText, isNot(contains('EXT-X-SERVER-CONTROL')));
    expect(videoText, isNot(contains('EXT-X-PART-INF')));
    expect(videoText, isNot(contains('EXT-X-PART:')));
    expect(videoText, isNot(contains('EXT-X-PRELOAD-HINT')));
    expect(videoText, isNot(contains('EXT-X-PROGRAM-DATE-TIME')));
    expect(videoText, contains('#EXT-X-MAP:'));
    expect(videoText, contains('#EXTINF:1.600000,'));
    expect(videoText, contains('/asset/'));

    final assetUri = RegExp(
            r'http://127\.0\.0\.1:\d+/chaturbate-llhls/[^\s"]+/asset/[0-9a-f]+')
        .firstMatch(videoText)!
        .group(0)!;
    final assetResponse =
        await (await client.getUrl(Uri.parse(assetUri))).close();
    final assetBody = utf8.decode(await assetResponse.fold<List<int>>(
      <int>[],
      (buffer, data) => buffer..addAll(data),
    ));
    expect(assetBody, 'video-init');
    expect(wrapped.single.metadata?['proxied'], isTrue);
    expect(wrapped.single.metadata?['proxyKind'], 'chaturbate-llhls');

    client.close(force: true);
    await proxy.dispose();
    await upstream.close(force: true);
  });

  test('chaturbate ll-hls proxy starts at self-initialized segment without map',
      () async {
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final baseUrl = 'http://${upstream.address.host}:${upstream.port}';
    const videoPlaylist = '''
#EXTM3U
#EXT-X-VERSION:6
#EXT-X-TARGETDURATION:2
#EXT-X-MEDIA-SEQUENCE:10
#EXT-X-MAP:URI="/v1/edge/streams/origin.demo/init_2_video_llhls.m4s?session=test"
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_2_10_video_llhls.m4s?session=test
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_2_11_video_llhls.m4s?session=test
''';
    const audioPlaylist = '''
#EXTM3U
#EXT-X-VERSION:6
#EXT-X-TARGETDURATION:2
#EXT-X-MEDIA-SEQUENCE:10
#EXT-X-MAP:URI="/v1/edge/streams/origin.demo/init_7_audio_llhls.m4s?session=test"
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_7_10_audio_llhls.m4s?session=test
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_7_11_audio_llhls.m4s?session=test
''';
    final selfInitializedVideo = Uint8List.fromList(
      <int>[0, 0, 0, 8, 109, 111, 111, 118, 115, 101, 108, 102],
    );
    final selfInitializedAudio = Uint8List.fromList(
      <int>[0, 0, 0, 8, 109, 111, 111, 118, 97, 117, 100, 105, 111],
    );
    final assets = <String, List<int>>{
      '/v1/edge/streams/origin.demo/init_2_video_llhls.m4s?session=test':
          utf8.encode('video-init'),
      '/v1/edge/streams/origin.demo/seg_2_10_video_llhls.m4s?session=test':
          utf8.encode('video-needs-init'),
      '/v1/edge/streams/origin.demo/seg_2_11_video_llhls.m4s?session=test':
          selfInitializedVideo,
      '/v1/edge/streams/origin.demo/init_7_audio_llhls.m4s?session=test':
          utf8.encode('audio-init'),
      '/v1/edge/streams/origin.demo/seg_7_10_audio_llhls.m4s?session=test':
          utf8.encode('audio-needs-init'),
      '/v1/edge/streams/origin.demo/seg_7_11_audio_llhls.m4s?session=test':
          selfInitializedAudio,
    };
    upstream.listen((request) async {
      final path = request.requestedUri.path;
      final fullPath = request.uri.toString();
      if (path.endsWith('chunklist_2_video_llhls.m3u8')) {
        request.response.headers.contentType = ContentType.text;
        request.response.write(videoPlaylist);
      } else if (path.endsWith('chunklist_7_audio_llhls.m3u8')) {
        request.response.headers.contentType = ContentType.text;
        request.response.write(audioPlaylist);
      } else if (assets.containsKey(fullPath)) {
        request.response.add(assets[fullPath]!);
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });

    final proxy = ChaturbateLlHlsProxy(enabledOverride: true);
    final wrapped = await proxy.wrapPlayUrls(
      quality: const LivePlayQuality(
        id: '1800000',
        label: '480p',
        sortOrder: 480,
        metadata: {'bandwidth': 1800000, 'height': 480},
      ),
      playUrls: [
        LivePlayUrl(
          url:
              '$baseUrl/v1/edge/streams/origin.demo/chunklist_2_video_llhls.m3u8?session=test',
          metadata: {
            'audioUrl':
                '$baseUrl/v1/edge/streams/origin.demo/chunklist_7_audio_llhls.m3u8?session=test',
          },
        ),
      ],
    );

    final client = HttpClient();
    final masterResponse =
        await (await client.getUrl(Uri.parse(wrapped.single.url))).close();
    final masterText = utf8.decode(await masterResponse.fold<List<int>>(
      <int>[],
      (buffer, data) => buffer..addAll(data),
    ));
    final videoUri =
        RegExp(r'http://127\.0\.0\.1:\d+/chaturbate-llhls/[^\s]+/video\.m3u8')
            .firstMatch(masterText)!
            .group(0)!;
    final videoResponse =
        await (await client.getUrl(Uri.parse(videoUri))).close();
    final videoText = utf8.decode(await videoResponse.fold<List<int>>(
      <int>[],
      (buffer, data) => buffer..addAll(data),
    ));

    expect(videoText, isNot(contains('#EXT-X-MAP:')));
    expect(videoText, contains('#EXT-X-MEDIA-SEQUENCE:11'));
    expect(videoText, isNot(contains('seg_2_10')));
    final assetUri = RegExp(
            r'http://127\.0\.0\.1:\d+/chaturbate-llhls/[^\s"]+/asset/[0-9a-f]+')
        .firstMatch(videoText)!
        .group(0)!;
    final assetResponse =
        await (await client.getUrl(Uri.parse(assetUri))).close();
    final assetBody = utf8.decode(await assetResponse.fold<List<int>>(
      <int>[],
      (buffer, data) => buffer..addAll(data),
    ));
    expect(assetBody, contains('moovself'));

    client.close(force: true);
    await proxy.dispose();
    await upstream.close(force: true);
  });

  test('chaturbate ll-hls proxy remembers delayed self-initialized segment',
      () async {
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final baseUrl = 'http://${upstream.address.host}:${upstream.port}';
    const videoPlaylist = '''
#EXTM3U
#EXT-X-VERSION:6
#EXT-X-TARGETDURATION:2
#EXT-X-MEDIA-SEQUENCE:20
#EXT-X-MAP:URI="/v1/edge/streams/origin.demo/init_2_video_llhls.m4s?session=test"
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_2_20_video_llhls.m4s?session=test
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_2_21_video_llhls.m4s?session=test
''';
    const audioPlaylist = '''
#EXTM3U
#EXT-X-VERSION:6
#EXT-X-TARGETDURATION:2
#EXT-X-MEDIA-SEQUENCE:20
#EXT-X-MAP:URI="/v1/edge/streams/origin.demo/init_7_audio_llhls.m4s?session=test"
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_7_20_audio_llhls.m4s?session=test
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_7_21_audio_llhls.m4s?session=test
''';
    final selfInitializedVideo = Uint8List.fromList(
      <int>[0, 0, 0, 8, 109, 111, 111, 118, 118, 50, 49],
    );
    final assets = <String, List<int>>{
      '/v1/edge/streams/origin.demo/init_2_video_llhls.m4s?session=test':
          utf8.encode('video-init'),
      '/v1/edge/streams/origin.demo/seg_2_20_video_llhls.m4s?session=test':
          utf8.encode('video-needs-init'),
      '/v1/edge/streams/origin.demo/seg_2_21_video_llhls.m4s?session=test':
          selfInitializedVideo,
      '/v1/edge/streams/origin.demo/init_7_audio_llhls.m4s?session=test':
          utf8.encode('audio-init'),
      '/v1/edge/streams/origin.demo/seg_7_20_audio_llhls.m4s?session=test':
          utf8.encode('audio-needs-init'),
      '/v1/edge/streams/origin.demo/seg_7_21_audio_llhls.m4s?session=test':
          utf8.encode('audio-still-map'),
    };
    upstream.listen((request) async {
      final path = request.requestedUri.path;
      final fullPath = request.uri.toString();
      if (path.endsWith('chunklist_2_video_llhls.m3u8')) {
        request.response.headers.contentType = ContentType.text;
        request.response.write(videoPlaylist);
      } else if (path.endsWith('chunklist_7_audio_llhls.m3u8')) {
        request.response.headers.contentType = ContentType.text;
        request.response.write(audioPlaylist);
      } else if (assets.containsKey(fullPath)) {
        if (fullPath.contains('seg_2_21_video_llhls')) {
          await Future<void>.delayed(const Duration(milliseconds: 2000));
        }
        request.response.add(assets[fullPath]!);
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });

    final proxy = ChaturbateLlHlsProxy(enabledOverride: true);
    final wrapped = await proxy.wrapPlayUrls(
      quality: const LivePlayQuality(id: '1800000', label: '480p'),
      playUrls: [
        LivePlayUrl(
          url:
              '$baseUrl/v1/edge/streams/origin.demo/chunklist_2_video_llhls.m3u8?session=test',
          metadata: {
            'audioUrl':
                '$baseUrl/v1/edge/streams/origin.demo/chunklist_7_audio_llhls.m3u8?session=test',
          },
        ),
      ],
    );

    final client = HttpClient();
    final masterResponse =
        await (await client.getUrl(Uri.parse(wrapped.single.url))).close();
    final masterText = utf8.decode(await masterResponse.fold<List<int>>(
      <int>[],
      (buffer, data) => buffer..addAll(data),
    ));
    final videoUri =
        RegExp(r'http://127\.0\.0\.1:\d+/chaturbate-llhls/[^\s]+/video\.m3u8')
            .firstMatch(masterText)!
            .group(0)!;
    final firstVideoResponse =
        await (await client.getUrl(Uri.parse(videoUri))).close();
    final firstVideoText = utf8.decode(await firstVideoResponse.fold<List<int>>(
      <int>[],
      (buffer, data) => buffer..addAll(data),
    ));
    expect(firstVideoText, contains('#EXT-X-MAP:'));
    expect(firstVideoText, contains('#EXT-X-MEDIA-SEQUENCE:20'));

    expect('#EXTINF:'.allMatches(firstVideoText), hasLength(1));
    await Future<void>.delayed(const Duration(milliseconds: 2200));

    final secondVideoResponse =
        await (await client.getUrl(Uri.parse(videoUri))).close();
    final secondVideoText =
        utf8.decode(await secondVideoResponse.fold<List<int>>(
      <int>[],
      (buffer, data) => buffer..addAll(data),
    ));
    expect(secondVideoText, isNot(contains('#EXT-X-MAP:')));
    expect(secondVideoText, contains('#EXT-X-MEDIA-SEQUENCE:21'));

    client.close(force: true);
    await proxy.dispose();
    await upstream.close(force: true);
  });

  test('chaturbate ll-hls proxy can serve startup playlist before full cache',
      () {
    expect(
      shouldServeChaturbateStartupPlaylistEarly(
        startupSegmentCount: 6,
        cachedStartupPrefixCount: 4,
        minimumStartupPlayableSegmentCount: 6,
        minimumStartupImmediateServeSegmentCount: 4,
      ),
      isTrue,
    );
    expect(
      shouldServeChaturbateStartupPlaylistEarly(
        startupSegmentCount: 5,
        cachedStartupPrefixCount: 4,
        minimumStartupPlayableSegmentCount: 6,
        minimumStartupImmediateServeSegmentCount: 4,
      ),
      isFalse,
    );
    expect(
      shouldServeChaturbateStartupPlaylistEarly(
        startupSegmentCount: 6,
        cachedStartupPrefixCount: 3,
        minimumStartupPlayableSegmentCount: 6,
        minimumStartupImmediateServeSegmentCount: 4,
      ),
      isFalse,
    );
  });

  test('chaturbate ll-hls proxy resolves startup policy by bitrate tier', () {
    expect(
      resolveChaturbateLlHlsStartupPolicy(
        bandwidth: 1800000,
        height: 480,
      ),
      (
        warmSegmentCount: 6,
        minimumStartupPlayableSegmentCount: 4,
        minimumStartupImmediateServeSegmentCount: 3,
        initialPlaylistStartupWaitTimeout: const Duration(milliseconds: 1400),
      ),
    );
    expect(
      resolveChaturbateLlHlsStartupPolicy(
        bandwidth: 2096000,
        height: 540,
      ),
      (
        warmSegmentCount: 8,
        minimumStartupPlayableSegmentCount: 5,
        minimumStartupImmediateServeSegmentCount: 4,
        initialPlaylistStartupWaitTimeout: const Duration(milliseconds: 2200),
      ),
    );
    expect(
      resolveChaturbateLlHlsStartupPolicy(
        bandwidth: 5128000,
        height: 1080,
      ),
      (
        warmSegmentCount: 10,
        minimumStartupPlayableSegmentCount: 6,
        minimumStartupImmediateServeSegmentCount: 5,
        initialPlaylistStartupWaitTimeout: const Duration(milliseconds: 2600),
      ),
    );
  });

  test(
      'chaturbate ll-hls proxy can recover from a master-only auto fallback url',
      () async {
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final baseUrl = 'http://${upstream.address.host}:${upstream.port}';
    const masterPlaylist = '''
#EXTM3U
#EXT-X-VERSION:6
#EXT-X-INDEPENDENT-SEGMENTS
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio_aac_96",NAME="Audio",DEFAULT=NO,AUTOSELECT=NO,FORCED=NO,CHANNELS="2",URI="/v1/edge/streams/origin.demo/chunklist_7_audio_llhls.m3u8?session=test"
#EXT-X-STREAM-INF:BANDWIDTH=2096000,RESOLUTION=960x540,FRAME-RATE=30.000,CODECS="avc1.4d401f,mp4a.40.2",AUDIO="audio_aac_96"
/v1/edge/streams/origin.demo/chunklist_2_video_llhls.m3u8?session=test
#EXT-X-STREAM-INF:BANDWIDTH=5128000,RESOLUTION=1920x1080,FRAME-RATE=30.000,CODECS="avc1.640028,mp4a.40.2",AUDIO="audio_aac_96"
/v1/edge/streams/origin.demo/chunklist_4_video_llhls.m3u8?session=test
''';
    const mediaPlaylist = '''
#EXTM3U
#EXT-X-VERSION:6
#EXT-X-TARGETDURATION:2
#EXT-X-MEDIA-SEQUENCE:7245
#EXT-X-MAP:URI="/v1/edge/streams/origin.demo/init_2_video_llhls.m4s?session=test"
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_2_7245_video_llhls.m4s?session=test
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_2_7246_video_llhls.m4s?session=test
''';
    const audioPlaylist = '''
#EXTM3U
#EXT-X-VERSION:6
#EXT-X-TARGETDURATION:2
#EXT-X-MEDIA-SEQUENCE:7245
#EXT-X-MAP:URI="/v1/edge/streams/origin.demo/init_7_audio_llhls.m4s?session=test"
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_7_7245_audio_llhls.m4s?session=test
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_7_7246_audio_llhls.m4s?session=test
''';
    final assets = <String, List<int>>{
      '/v1/edge/streams/origin.demo/init_2_video_llhls.m4s?session=test':
          utf8.encode('video-init'),
      '/v1/edge/streams/origin.demo/seg_2_7245_video_llhls.m4s?session=test':
          utf8.encode('video-seg-7245'),
      '/v1/edge/streams/origin.demo/seg_2_7246_video_llhls.m4s?session=test':
          utf8.encode('video-seg-7246'),
      '/v1/edge/streams/origin.demo/init_7_audio_llhls.m4s?session=test':
          utf8.encode('audio-init'),
      '/v1/edge/streams/origin.demo/seg_7_7245_audio_llhls.m4s?session=test':
          utf8.encode('audio-seg-7245'),
      '/v1/edge/streams/origin.demo/seg_7_7246_audio_llhls.m4s?session=test':
          utf8.encode('audio-seg-7246'),
    };
    upstream.listen((request) async {
      final path = request.requestedUri.path;
      final fullPath = request.uri.toString();
      if (path.endsWith('/llhls.m3u8')) {
        request.response.headers.contentType = ContentType.text;
        request.response.write(masterPlaylist);
      } else if (path.endsWith('chunklist_2_video_llhls.m3u8')) {
        request.response.headers.contentType = ContentType.text;
        request.response.write(mediaPlaylist);
      } else if (path.endsWith('chunklist_7_audio_llhls.m3u8')) {
        request.response.headers.contentType = ContentType.text;
        request.response.write(audioPlaylist);
      } else if (assets.containsKey(fullPath)) {
        request.response.add(assets[fullPath]!);
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });

    final proxy = ChaturbateLlHlsProxy(enabledOverride: true);
    final wrapped = await proxy.wrapPlayUrls(
      quality: const LivePlayQuality(
        id: 'auto',
        label: 'Auto',
        isDefault: true,
      ),
      playUrls: [
        LivePlayUrl(
          url: '$baseUrl/v1/edge/streams/origin.demo/llhls.m3u8?session=test',
          headers: const {'referer': 'https://chaturbate.com/demo/'},
        ),
      ],
    );

    expect(wrapped.single.url, contains('/chaturbate-llhls/'));
    expect(wrapped.single.metadata?['proxyKind'], 'chaturbate-llhls');

    final client = HttpClient();
    final masterResponse =
        await (await client.getUrl(Uri.parse(wrapped.single.url))).close();
    final masterText = utf8.decode(await masterResponse.fold<List<int>>(
      <int>[],
      (buffer, data) => buffer..addAll(data),
    ));
    final videoUri =
        RegExp(r'http://127\.0\.0\.1:\d+/chaturbate-llhls/[^\s]+/video\.m3u8')
            .firstMatch(masterText)!
            .group(0)!;
    final videoResponse =
        await (await client.getUrl(Uri.parse(videoUri))).close();
    final videoText = utf8.decode(await videoResponse.fold<List<int>>(
      <int>[],
      (buffer, data) => buffer..addAll(data),
    ));

    expect(videoText, contains('#EXTINF:1.600000,'));
    expect(videoText, contains('/asset/'));

    client.close(force: true);
    await proxy.dispose();
    await upstream.close(force: true);
  });

  test('chaturbate ll-hls proxy keeps a stable rolling segment window',
      () async {
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final baseUrl = 'http://${upstream.address.host}:${upstream.port}';
    final videoPlaylists = <String>[
      '''
#EXTM3U
#EXT-X-VERSION:6
#EXT-X-TARGETDURATION:2
#EXT-X-MEDIA-SEQUENCE:10
#EXT-X-MAP:URI="/v1/edge/streams/origin.demo/init_2_video_llhls.m4s?session=test"
#EXT-X-PROGRAM-DATE-TIME:2026-04-22T10:00:00.000+00:00
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_2_10_video_llhls.m4s?session=test
#EXT-X-PROGRAM-DATE-TIME:2026-04-22T10:00:01.600+00:00
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_2_11_video_llhls.m4s?session=test
#EXT-X-PROGRAM-DATE-TIME:2026-04-22T10:00:03.200+00:00
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_2_12_video_llhls.m4s?session=test
''',
      '''
#EXTM3U
#EXT-X-VERSION:6
#EXT-X-TARGETDURATION:2
#EXT-X-MEDIA-SEQUENCE:12
#EXT-X-MAP:URI="/v1/edge/streams/origin.demo/init_2_video_llhls.m4s?session=test"
#EXT-X-PROGRAM-DATE-TIME:2026-04-22T10:00:03.200+00:00
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_2_12_video_llhls.m4s?session=test
#EXT-X-PROGRAM-DATE-TIME:2026-04-22T10:00:04.800+00:00
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_2_13_video_llhls.m4s?session=test
#EXT-X-PROGRAM-DATE-TIME:2026-04-22T10:00:06.400+00:00
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_2_14_video_llhls.m4s?session=test
''',
    ];
    final audioPlaylists = <String>[
      '''
#EXTM3U
#EXT-X-VERSION:6
#EXT-X-TARGETDURATION:2
#EXT-X-MEDIA-SEQUENCE:10
#EXT-X-MAP:URI="/v1/edge/streams/origin.demo/init_7_audio_llhls.m4s?session=test"
#EXT-X-PROGRAM-DATE-TIME:2026-04-22T10:00:00.000+00:00
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_7_10_audio_llhls.m4s?session=test
#EXT-X-PROGRAM-DATE-TIME:2026-04-22T10:00:01.600+00:00
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_7_11_audio_llhls.m4s?session=test
#EXT-X-PROGRAM-DATE-TIME:2026-04-22T10:00:03.200+00:00
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_7_12_audio_llhls.m4s?session=test
''',
      '''
#EXTM3U
#EXT-X-VERSION:6
#EXT-X-TARGETDURATION:2
#EXT-X-MEDIA-SEQUENCE:12
#EXT-X-MAP:URI="/v1/edge/streams/origin.demo/init_7_audio_llhls.m4s?session=test"
#EXT-X-PROGRAM-DATE-TIME:2026-04-22T10:00:03.200+00:00
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_7_12_audio_llhls.m4s?session=test
#EXT-X-PROGRAM-DATE-TIME:2026-04-22T10:00:04.800+00:00
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_7_13_audio_llhls.m4s?session=test
#EXT-X-PROGRAM-DATE-TIME:2026-04-22T10:00:06.400+00:00
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_7_14_audio_llhls.m4s?session=test
''',
    ];
    var videoPlaylistRequests = 0;
    var audioPlaylistRequests = 0;
    final assets = <String, List<int>>{
      '/v1/edge/streams/origin.demo/init_2_video_llhls.m4s?session=test':
          utf8.encode('video-init'),
      '/v1/edge/streams/origin.demo/seg_2_10_video_llhls.m4s?session=test':
          utf8.encode('video-seg-10'),
      '/v1/edge/streams/origin.demo/seg_2_11_video_llhls.m4s?session=test':
          utf8.encode('video-seg-11'),
      '/v1/edge/streams/origin.demo/seg_2_12_video_llhls.m4s?session=test':
          utf8.encode('video-seg-12'),
      '/v1/edge/streams/origin.demo/seg_2_13_video_llhls.m4s?session=test':
          utf8.encode('video-seg-13'),
      '/v1/edge/streams/origin.demo/seg_2_14_video_llhls.m4s?session=test':
          utf8.encode('video-seg-14'),
      '/v1/edge/streams/origin.demo/init_7_audio_llhls.m4s?session=test':
          utf8.encode('audio-init'),
      '/v1/edge/streams/origin.demo/seg_7_10_audio_llhls.m4s?session=test':
          utf8.encode('audio-seg-10'),
      '/v1/edge/streams/origin.demo/seg_7_11_audio_llhls.m4s?session=test':
          utf8.encode('audio-seg-11'),
      '/v1/edge/streams/origin.demo/seg_7_12_audio_llhls.m4s?session=test':
          utf8.encode('audio-seg-12'),
      '/v1/edge/streams/origin.demo/seg_7_13_audio_llhls.m4s?session=test':
          utf8.encode('audio-seg-13'),
      '/v1/edge/streams/origin.demo/seg_7_14_audio_llhls.m4s?session=test':
          utf8.encode('audio-seg-14'),
    };
    upstream.listen((request) async {
      final path = request.requestedUri.path;
      final fullPath = request.uri.toString();
      if (path.endsWith('chunklist_2_video_llhls.m3u8')) {
        final index = videoPlaylistRequests.clamp(0, videoPlaylists.length - 1);
        videoPlaylistRequests += 1;
        request.response.headers.contentType = ContentType.text;
        request.response.write(videoPlaylists[index]);
      } else if (path.endsWith('chunklist_7_audio_llhls.m3u8')) {
        final index = audioPlaylistRequests.clamp(0, audioPlaylists.length - 1);
        audioPlaylistRequests += 1;
        request.response.headers.contentType = ContentType.text;
        request.response.write(audioPlaylists[index]);
      } else if (assets.containsKey(fullPath)) {
        request.response.add(assets[fullPath]!);
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });

    final proxy = ChaturbateLlHlsProxy(enabledOverride: true);
    final wrapped = await proxy.wrapPlayUrls(
      quality: const LivePlayQuality(
        id: '2096000',
        label: '540p',
        sortOrder: 540,
      ),
      playUrls: [
        LivePlayUrl(
          url:
              '$baseUrl/v1/edge/streams/origin.demo/chunklist_2_video_llhls.m3u8?session=test',
          headers: const {'referer': 'https://chaturbate.com/demo/'},
          metadata: {
            'audioUrl':
                '$baseUrl/v1/edge/streams/origin.demo/chunklist_7_audio_llhls.m3u8?session=test',
            'audioHeaders': {'referer': 'https://chaturbate.com/demo/'},
          },
        ),
      ],
    );

    final client = HttpClient();
    final masterResponse =
        await (await client.getUrl(Uri.parse(wrapped.single.url))).close();
    final masterText = utf8.decode(await masterResponse.fold<List<int>>(
      <int>[],
      (buffer, data) => buffer..addAll(data),
    ));
    final videoUri =
        RegExp(r'http://127\.0\.0\.1:\d+/chaturbate-llhls/[^\s]+/video\.m3u8')
            .firstMatch(masterText)!
            .group(0)!;

    await (await client.getUrl(Uri.parse(videoUri))).close();
    await Future<void>.delayed(const Duration(milliseconds: 800));

    final secondVideoResponse =
        await (await client.getUrl(Uri.parse(videoUri))).close();
    final secondVideoText =
        utf8.decode(await secondVideoResponse.fold<List<int>>(
      <int>[],
      (buffer, data) => buffer..addAll(data),
    ));

    expect(
      RegExp(r'#EXTINF:').allMatches(secondVideoText).length,
      3,
    );
    expect(secondVideoText, isNot(contains('EXT-X-PROGRAM-DATE-TIME')));

    final assetUris = RegExp(
      r'http://127\.0\.0\.1:\d+/chaturbate-llhls/[^\s"]+/asset/[0-9a-f]+',
    ).allMatches(secondVideoText).map((match) => match.group(0)!).toList();
    final bodies = <String>[];
    for (final assetUri in assetUris) {
      final assetResponse =
          await (await client.getUrl(Uri.parse(assetUri))).close();
      bodies.add(
        utf8.decode(await assetResponse.fold<List<int>>(
          <int>[],
          (buffer, data) => buffer..addAll(data),
        )),
      );
    }

    expect(bodies, contains('video-init'));
    expect(bodies, contains('video-seg-10'));
    expect(bodies, contains('video-seg-11'));
    expect(bodies, contains('video-seg-12'));
    expect(bodies, isNot(contains('video-seg-13')));
    expect(bodies, isNot(contains('video-seg-14')));

    client.close(force: true);
    await proxy.dispose();
    await upstream.close(force: true);
  });

  test('chaturbate ll-hls proxy warms startup video assets before playback',
      () async {
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final baseUrl = 'http://${upstream.address.host}:${upstream.port}';
    const videoPlaylist = '''
#EXTM3U
#EXT-X-VERSION:6
#EXT-X-TARGETDURATION:2
#EXT-X-MEDIA-SEQUENCE:40
#EXT-X-MAP:URI="/v1/edge/streams/origin.demo/init_2_video_llhls.m4s?session=test"
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_2_40_video_llhls.m4s?session=test
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_2_41_video_llhls.m4s?session=test
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_2_42_video_llhls.m4s?session=test
''';
    const audioPlaylist = '''
#EXTM3U
#EXT-X-VERSION:6
#EXT-X-TARGETDURATION:2
#EXT-X-MEDIA-SEQUENCE:40
#EXT-X-MAP:URI="/v1/edge/streams/origin.demo/init_7_audio_llhls.m4s?session=test"
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_7_40_audio_llhls.m4s?session=test
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_7_41_audio_llhls.m4s?session=test
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_7_42_audio_llhls.m4s?session=test
''';
    const firstVideoSegmentPath =
        '/v1/edge/streams/origin.demo/seg_2_40_video_llhls.m4s?session=test';
    var allowAssetOrigin = true;
    final firstVideoPrefetched = Completer<void>();
    final assets = <String, List<int>>{
      '/v1/edge/streams/origin.demo/init_2_video_llhls.m4s?session=test':
          utf8.encode('video-init'),
      firstVideoSegmentPath: utf8.encode('video-seg-40'),
      '/v1/edge/streams/origin.demo/seg_2_41_video_llhls.m4s?session=test':
          utf8.encode('video-seg-41'),
      '/v1/edge/streams/origin.demo/seg_2_42_video_llhls.m4s?session=test':
          utf8.encode('video-seg-42'),
      '/v1/edge/streams/origin.demo/init_7_audio_llhls.m4s?session=test':
          utf8.encode('audio-init'),
      '/v1/edge/streams/origin.demo/seg_7_40_audio_llhls.m4s?session=test':
          utf8.encode('audio-seg-40'),
      '/v1/edge/streams/origin.demo/seg_7_41_audio_llhls.m4s?session=test':
          utf8.encode('audio-seg-41'),
      '/v1/edge/streams/origin.demo/seg_7_42_audio_llhls.m4s?session=test':
          utf8.encode('audio-seg-42'),
    };
    upstream.listen((request) async {
      final path = request.requestedUri.path;
      final fullPath = request.uri.toString();
      if (path.endsWith('chunklist_2_video_llhls.m3u8')) {
        request.response.headers.contentType = ContentType.text;
        request.response.write(videoPlaylist);
      } else if (path.endsWith('chunklist_7_audio_llhls.m3u8')) {
        request.response.headers.contentType = ContentType.text;
        request.response.write(audioPlaylist);
      } else if (assets.containsKey(fullPath)) {
        if (!allowAssetOrigin) {
          request.response.statusCode = HttpStatus.notFound;
        } else {
          if (fullPath == firstVideoSegmentPath &&
              !firstVideoPrefetched.isCompleted) {
            firstVideoPrefetched.complete();
          }
          request.response.add(assets[fullPath]!);
        }
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });

    final proxy = ChaturbateLlHlsProxy(enabledOverride: true);
    final wrapped = await proxy.wrapPlayUrls(
      quality: const LivePlayQuality(
        id: '5128000',
        label: '1080p',
        sortOrder: 1080,
      ),
      playUrls: [
        LivePlayUrl(
          url:
              '$baseUrl/v1/edge/streams/origin.demo/chunklist_2_video_llhls.m3u8?session=test',
          headers: const {'referer': 'https://chaturbate.com/demo/'},
          metadata: {
            'audioUrl':
                '$baseUrl/v1/edge/streams/origin.demo/chunklist_7_audio_llhls.m3u8?session=test',
            'audioHeaders': {'referer': 'https://chaturbate.com/demo/'},
          },
        ),
      ],
    );

    final client = HttpClient();
    final masterResponse =
        await (await client.getUrl(Uri.parse(wrapped.single.url))).close();
    final masterText = utf8.decode(await masterResponse.fold<List<int>>(
      <int>[],
      (buffer, data) => buffer..addAll(data),
    ));
    final videoUri =
        RegExp(r'http://127\.0\.0\.1:\d+/chaturbate-llhls/[^\s]+/video\.m3u8')
            .firstMatch(masterText)!
            .group(0)!;

    final videoResponse =
        await (await client.getUrl(Uri.parse(videoUri))).close();
    final videoText = utf8.decode(await videoResponse.fold<List<int>>(
      <int>[],
      (buffer, data) => buffer..addAll(data),
    ));

    await firstVideoPrefetched.future.timeout(const Duration(seconds: 2));
    allowAssetOrigin = false;

    final assetUris = RegExp(
      r'http://127\.0\.0\.1:\d+/chaturbate-llhls/[^\s"]+/asset/[0-9a-f]+',
    ).allMatches(videoText).map((match) => match.group(0)!).toList();
    final firstSegmentResponse =
        await (await client.getUrl(Uri.parse(assetUris[1]))).close();
    final firstSegmentBody =
        utf8.decode(await firstSegmentResponse.fold<List<int>>(
      <int>[],
      (buffer, data) => buffer..addAll(data),
    ));

    expect(firstSegmentResponse.statusCode, HttpStatus.ok);
    expect(firstSegmentBody, 'video-seg-40');

    client.close(force: true);
    await proxy.dispose();
    await upstream.close(force: true);
  });

  test(
      'chaturbate ll-hls proxy primes timeline before first media playlist request',
      () async {
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final baseUrl = 'http://${upstream.address.host}:${upstream.port}';
    const videoPlaylist = '''
#EXTM3U
#EXT-X-VERSION:6
#EXT-X-TARGETDURATION:2
#EXT-X-MEDIA-SEQUENCE:60
#EXT-X-MAP:URI="/v1/edge/streams/origin.demo/init_2_video_llhls.m4s?session=test"
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_2_60_video_llhls.m4s?session=test
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_2_61_video_llhls.m4s?session=test
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_2_62_video_llhls.m4s?session=test
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_2_63_video_llhls.m4s?session=test
''';
    const audioPlaylist = '''
#EXTM3U
#EXT-X-VERSION:6
#EXT-X-TARGETDURATION:2
#EXT-X-MEDIA-SEQUENCE:60
#EXT-X-MAP:URI="/v1/edge/streams/origin.demo/init_7_audio_llhls.m4s?session=test"
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_7_60_audio_llhls.m4s?session=test
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_7_61_audio_llhls.m4s?session=test
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_7_62_audio_llhls.m4s?session=test
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_7_63_audio_llhls.m4s?session=test
''';
    final assets = <String, List<int>>{
      '/v1/edge/streams/origin.demo/init_2_video_llhls.m4s?session=test':
          utf8.encode('video-init'),
      '/v1/edge/streams/origin.demo/seg_2_60_video_llhls.m4s?session=test':
          utf8.encode('video-seg-60'),
      '/v1/edge/streams/origin.demo/seg_2_61_video_llhls.m4s?session=test':
          utf8.encode('video-seg-61'),
      '/v1/edge/streams/origin.demo/seg_2_62_video_llhls.m4s?session=test':
          utf8.encode('video-seg-62'),
      '/v1/edge/streams/origin.demo/seg_2_63_video_llhls.m4s?session=test':
          utf8.encode('video-seg-63'),
      '/v1/edge/streams/origin.demo/init_7_audio_llhls.m4s?session=test':
          utf8.encode('audio-init'),
      '/v1/edge/streams/origin.demo/seg_7_60_audio_llhls.m4s?session=test':
          utf8.encode('audio-seg-60'),
      '/v1/edge/streams/origin.demo/seg_7_61_audio_llhls.m4s?session=test':
          utf8.encode('audio-seg-61'),
      '/v1/edge/streams/origin.demo/seg_7_62_audio_llhls.m4s?session=test':
          utf8.encode('audio-seg-62'),
      '/v1/edge/streams/origin.demo/seg_7_63_audio_llhls.m4s?session=test':
          utf8.encode('audio-seg-63'),
    };
    final blockVideoRefresh = Completer<void>();
    final blockAudioRefresh = Completer<void>();
    var videoPlaylistRequests = 0;
    var audioPlaylistRequests = 0;

    Future<void> writeBlockedPlaylist(
      HttpRequest request,
      String body,
      Completer<void> blocker,
    ) async {
      await blocker.future;
      request.response.headers.contentType = ContentType.text;
      request.response.write(body);
      await request.response.close();
    }

    upstream.listen((request) async {
      final path = request.requestedUri.path;
      final fullPath = request.uri.toString();
      if (path.endsWith('chunklist_2_video_llhls.m3u8')) {
        videoPlaylistRequests += 1;
        if (videoPlaylistRequests == 1) {
          request.response.headers.contentType = ContentType.text;
          request.response.write(videoPlaylist);
          await request.response.close();
          return;
        }
        await writeBlockedPlaylist(request, videoPlaylist, blockVideoRefresh);
        return;
      }
      if (path.endsWith('chunklist_7_audio_llhls.m3u8')) {
        audioPlaylistRequests += 1;
        if (audioPlaylistRequests == 1) {
          request.response.headers.contentType = ContentType.text;
          request.response.write(audioPlaylist);
          await request.response.close();
          return;
        }
        await writeBlockedPlaylist(request, audioPlaylist, blockAudioRefresh);
        return;
      }
      if (assets.containsKey(fullPath)) {
        request.response.add(assets[fullPath]!);
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });

    final proxy = ChaturbateLlHlsProxy(enabledOverride: true);
    final wrapped = await proxy.wrapPlayUrls(
      quality: const LivePlayQuality(
        id: '5128000',
        label: '1080p',
        sortOrder: 1080,
      ),
      playUrls: [
        LivePlayUrl(
          url:
              '$baseUrl/v1/edge/streams/origin.demo/chunklist_2_video_llhls.m3u8?session=test',
          headers: const {'referer': 'https://chaturbate.com/demo/'},
          metadata: {
            'audioUrl':
                '$baseUrl/v1/edge/streams/origin.demo/chunklist_7_audio_llhls.m3u8?session=test',
            'audioHeaders': {'referer': 'https://chaturbate.com/demo/'},
          },
        ),
      ],
    );

    final client = HttpClient();
    final masterResponse =
        await (await client.getUrl(Uri.parse(wrapped.single.url))).close();
    final masterText = utf8.decode(await masterResponse.fold<List<int>>(
      <int>[],
      (buffer, data) => buffer..addAll(data),
    ));
    final videoUri =
        RegExp(r'http://127\.0\.0\.1:\d+/chaturbate-llhls/[^\s]+/video\.m3u8')
            .firstMatch(masterText)!
            .group(0)!;

    final stopwatch = Stopwatch()..start();
    final firstVideoResponse =
        await (await client.getUrl(Uri.parse(videoUri))).close();
    final firstVideoText = utf8.decode(await firstVideoResponse.fold<List<int>>(
      <int>[],
      (buffer, data) => buffer..addAll(data),
    ));
    stopwatch.stop();

    expect(
      stopwatch.elapsedMilliseconds,
      allOf(greaterThanOrEqualTo(700), lessThan(2200)),
    );
    expect(firstVideoText, contains('#EXT-X-MEDIA-SEQUENCE:60'));
    expect(videoPlaylistRequests, greaterThanOrEqualTo(1));
    expect(audioPlaylistRequests, greaterThanOrEqualTo(1));

    client.close(force: true);
    blockVideoRefresh.complete();
    blockAudioRefresh.complete();
    await proxy.dispose();
    await upstream.close(force: true);
  });

  test(
      'chaturbate ll-hls proxy serves audio playlist without waiting for video timeline prime',
      () async {
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final baseUrl = 'http://${upstream.address.host}:${upstream.port}';
    final releaseVideoPlaylist = Completer<void>();
    var videoPlaylistRequests = 0;
    var audioPlaylistRequests = 0;
    const videoPlaylist = '''
#EXTM3U
#EXT-X-VERSION:6
#EXT-X-TARGETDURATION:2
#EXT-X-MEDIA-SEQUENCE:90
#EXT-X-MAP:URI="/v1/edge/streams/origin.demo/init_2_video_llhls.m4s?session=test"
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_2_90_video_llhls.m4s?session=test
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_2_91_video_llhls.m4s?session=test
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_2_92_video_llhls.m4s?session=test
''';
    const audioPlaylist = '''
#EXTM3U
#EXT-X-VERSION:6
#EXT-X-TARGETDURATION:2
#EXT-X-MEDIA-SEQUENCE:90
#EXT-X-MAP:URI="/v1/edge/streams/origin.demo/init_7_audio_llhls.m4s?session=test"
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_7_90_audio_llhls.m4s?session=test
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_7_91_audio_llhls.m4s?session=test
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_7_92_audio_llhls.m4s?session=test
''';
    final assets = <String, List<int>>{
      '/v1/edge/streams/origin.demo/init_2_video_llhls.m4s?session=test':
          utf8.encode('video-init'),
      '/v1/edge/streams/origin.demo/init_7_audio_llhls.m4s?session=test':
          utf8.encode('audio-init'),
      for (final sequence in [90, 91, 92])
        '/v1/edge/streams/origin.demo/seg_2_${sequence}_video_llhls.m4s?session=test':
            utf8.encode('video-$sequence'),
      for (final sequence in [90, 91, 92])
        '/v1/edge/streams/origin.demo/seg_7_${sequence}_audio_llhls.m4s?session=test':
            utf8.encode('audio-$sequence'),
    };

    upstream.listen((request) async {
      final path = request.requestedUri.path;
      final fullPath = request.uri.toString();
      if (path.endsWith('chunklist_2_video_llhls.m3u8')) {
        videoPlaylistRequests += 1;
        await releaseVideoPlaylist.future;
        request.response.headers.contentType = ContentType.text;
        request.response.write(videoPlaylist);
      } else if (path.endsWith('chunklist_7_audio_llhls.m3u8')) {
        audioPlaylistRequests += 1;
        request.response.headers.contentType = ContentType.text;
        request.response.write(audioPlaylist);
      } else if (assets.containsKey(fullPath)) {
        request.response.add(assets[fullPath]!);
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });

    final proxy = ChaturbateLlHlsProxy(enabledOverride: true);
    final wrapped = await proxy.wrapPlayUrls(
      quality: const LivePlayQuality(
        id: '5128000',
        label: '1080p',
        sortOrder: 1080,
      ),
      playUrls: [
        LivePlayUrl(
          url:
              '$baseUrl/v1/edge/streams/origin.demo/chunklist_2_video_llhls.m3u8?session=test',
          headers: const {'referer': 'https://chaturbate.com/demo/'},
          metadata: {
            'audioUrl':
                '$baseUrl/v1/edge/streams/origin.demo/chunklist_7_audio_llhls.m3u8?session=test',
            'audioHeaders': {'referer': 'https://chaturbate.com/demo/'},
          },
        ),
      ],
    );

    final client = HttpClient();
    final masterResponse =
        await (await client.getUrl(Uri.parse(wrapped.single.url))).close();
    final masterText = utf8.decode(await masterResponse.fold<List<int>>(
      <int>[],
      (buffer, data) => buffer..addAll(data),
    ));
    final audioUri =
        RegExp(r'http://127\.0\.0\.1:\d+/chaturbate-llhls/[^\s]+/audio\.m3u8')
            .firstMatch(masterText)!
            .group(0)!;

    final stopwatch = Stopwatch()..start();
    final audioResponse =
        await (await client.getUrl(Uri.parse(audioUri))).close();
    final audioText = utf8.decode(await audioResponse.fold<List<int>>(
      <int>[],
      (buffer, data) => buffer..addAll(data),
    ));
    stopwatch.stop();

    expect(stopwatch.elapsedMilliseconds, lessThan(3500));
    expect(audioText, contains('#EXT-X-MEDIA-SEQUENCE:90'));
    expect(RegExp(r'#EXTINF:').allMatches(audioText).length,
        greaterThanOrEqualTo(3));
    expect(audioPlaylistRequests, greaterThanOrEqualTo(1));
    expect(videoPlaylistRequests, greaterThanOrEqualTo(1));

    client.close(force: true);
    releaseVideoPlaylist.complete();
    await proxy.dispose();
    await upstream.close(force: true);
  });

  test(
      'chaturbate ll-hls proxy serves cached media playlist while refresh runs in background',
      () async {
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final baseUrl = 'http://${upstream.address.host}:${upstream.port}';
    const initialVideoPlaylist = '''
#EXTM3U
#EXT-X-VERSION:6
#EXT-X-TARGETDURATION:2
#EXT-X-MEDIA-SEQUENCE:20
#EXT-X-MAP:URI="/v1/edge/streams/origin.demo/init_2_video_llhls.m4s?session=test"
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_2_20_video_llhls.m4s?session=test
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_2_21_video_llhls.m4s?session=test
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_2_22_video_llhls.m4s?session=test
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_2_23_video_llhls.m4s?session=test
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_2_24_video_llhls.m4s?session=test
''';
    const refreshedVideoPlaylist = '''
#EXTM3U
#EXT-X-VERSION:6
#EXT-X-TARGETDURATION:2
#EXT-X-MEDIA-SEQUENCE:22
#EXT-X-MAP:URI="/v1/edge/streams/origin.demo/init_2_video_llhls.m4s?session=test"
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_2_22_video_llhls.m4s?session=test
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_2_23_video_llhls.m4s?session=test
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_2_24_video_llhls.m4s?session=test
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_2_25_video_llhls.m4s?session=test
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_2_26_video_llhls.m4s?session=test
''';
    const initialAudioPlaylist = '''
#EXTM3U
#EXT-X-VERSION:6
#EXT-X-TARGETDURATION:2
#EXT-X-MEDIA-SEQUENCE:20
#EXT-X-MAP:URI="/v1/edge/streams/origin.demo/init_7_audio_llhls.m4s?session=test"
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_7_20_audio_llhls.m4s?session=test
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_7_21_audio_llhls.m4s?session=test
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_7_22_audio_llhls.m4s?session=test
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_7_23_audio_llhls.m4s?session=test
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_7_24_audio_llhls.m4s?session=test
''';
    const refreshedAudioPlaylist = '''
#EXTM3U
#EXT-X-VERSION:6
#EXT-X-TARGETDURATION:2
#EXT-X-MEDIA-SEQUENCE:22
#EXT-X-MAP:URI="/v1/edge/streams/origin.demo/init_7_audio_llhls.m4s?session=test"
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_7_22_audio_llhls.m4s?session=test
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_7_23_audio_llhls.m4s?session=test
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_7_24_audio_llhls.m4s?session=test
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_7_25_audio_llhls.m4s?session=test
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_7_26_audio_llhls.m4s?session=test
''';
    final releaseVideoRefresh = Completer<void>();
    final releaseAudioRefresh = Completer<void>();
    var videoPlaylistRequests = 0;
    var audioPlaylistRequests = 0;

    Future<void> writeDelayedPlaylist(
      HttpRequest request,
      String body,
      Completer<void> blocker,
    ) async {
      await blocker.future;
      request.response.headers.contentType = ContentType.text;
      request.response.write(body);
      await request.response.close();
    }

    upstream.listen((request) async {
      final path = request.requestedUri.path;
      if (path.endsWith('chunklist_2_video_llhls.m3u8')) {
        videoPlaylistRequests += 1;
        if (videoPlaylistRequests == 1) {
          request.response.headers.contentType = ContentType.text;
          request.response.write(initialVideoPlaylist);
          await request.response.close();
          return;
        }
        await writeDelayedPlaylist(
          request,
          refreshedVideoPlaylist,
          releaseVideoRefresh,
        );
        return;
      }
      if (path.endsWith('chunklist_7_audio_llhls.m3u8')) {
        audioPlaylistRequests += 1;
        if (audioPlaylistRequests == 1) {
          request.response.headers.contentType = ContentType.text;
          request.response.write(initialAudioPlaylist);
          await request.response.close();
          return;
        }
        await writeDelayedPlaylist(
          request,
          refreshedAudioPlaylist,
          releaseAudioRefresh,
        );
        return;
      }
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    });

    final proxy = ChaturbateLlHlsProxy(enabledOverride: true);
    final wrapped = await proxy.wrapPlayUrls(
      quality: const LivePlayQuality(
        id: '2096000',
        label: '540p',
        sortOrder: 540,
      ),
      playUrls: [
        LivePlayUrl(
          url:
              '$baseUrl/v1/edge/streams/origin.demo/chunklist_2_video_llhls.m3u8?session=test',
          headers: const {'referer': 'https://chaturbate.com/demo/'},
          metadata: {
            'audioUrl':
                '$baseUrl/v1/edge/streams/origin.demo/chunklist_7_audio_llhls.m3u8?session=test',
            'audioHeaders': {'referer': 'https://chaturbate.com/demo/'},
          },
        ),
      ],
    );

    final client = HttpClient();
    final masterResponse =
        await (await client.getUrl(Uri.parse(wrapped.single.url))).close();
    final masterText = utf8.decode(await masterResponse.fold<List<int>>(
      <int>[],
      (buffer, data) => buffer..addAll(data),
    ));
    final videoUri =
        RegExp(r'http://127\.0\.0\.1:\d+/chaturbate-llhls/[^\s]+/video\.m3u8')
            .firstMatch(masterText)!
            .group(0)!;

    final initialVideoResponse =
        await (await client.getUrl(Uri.parse(videoUri))).close();
    final initialVideoText =
        utf8.decode(await initialVideoResponse.fold<List<int>>(
      <int>[],
      (buffer, data) => buffer..addAll(data),
    ));
    expect(initialVideoText, contains('#EXT-X-MEDIA-SEQUENCE:20'));
    expect(videoPlaylistRequests, greaterThanOrEqualTo(1));
    expect(audioPlaylistRequests, greaterThanOrEqualTo(1));

    await Future<void>.delayed(const Duration(milliseconds: 400));

    final stopwatch = Stopwatch()..start();
    final cachedVideoResponse =
        await (await client.getUrl(Uri.parse(videoUri))).close();
    final cachedVideoText =
        utf8.decode(await cachedVideoResponse.fold<List<int>>(
      <int>[],
      (buffer, data) => buffer..addAll(data),
    ));
    stopwatch.stop();

    expect(stopwatch.elapsedMilliseconds, lessThan(250));
    expect(cachedVideoText, contains('#EXT-X-MEDIA-SEQUENCE:20'));
    expect(cachedVideoText, isNot(contains('#EXT-X-MEDIA-SEQUENCE:22')));

    releaseVideoRefresh.complete();
    releaseAudioRefresh.complete();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(videoPlaylistRequests, greaterThanOrEqualTo(2));
    expect(audioPlaylistRequests, greaterThanOrEqualTo(2));

    client.close(force: true);
    await proxy.dispose();
    await upstream.close(force: true);
  });

  test(
      'chaturbate ll-hls proxy waits briefly for cached playlist advance on repeated stale requests',
      () async {
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final baseUrl = 'http://${upstream.address.host}:${upstream.port}';
    const initialVideoPlaylist = '''
#EXTM3U
#EXT-X-VERSION:6
#EXT-X-TARGETDURATION:1
#EXT-X-MEDIA-SEQUENCE:100
#EXT-X-MAP:URI="/v1/edge/streams/origin.demo/init_2_video_llhls.m4s?session=test"
#EXT-X-PROGRAM-DATE-TIME:2026-04-22T10:00:00.000+00:00
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_2_100_video_llhls.m4s?session=test
#EXT-X-PROGRAM-DATE-TIME:2026-04-22T10:00:01.600+00:00
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_2_101_video_llhls.m4s?session=test
#EXT-X-PROGRAM-DATE-TIME:2026-04-22T10:00:03.200+00:00
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_2_102_video_llhls.m4s?session=test
#EXT-X-PROGRAM-DATE-TIME:2026-04-22T10:00:04.800+00:00
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_2_103_video_llhls.m4s?session=test
#EXT-X-PROGRAM-DATE-TIME:2026-04-22T10:00:06.400+00:00
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_2_104_video_llhls.m4s?session=test
''';
    const refreshedVideoPlaylist = '''
#EXTM3U
#EXT-X-VERSION:6
#EXT-X-TARGETDURATION:1
#EXT-X-MEDIA-SEQUENCE:102
#EXT-X-MAP:URI="/v1/edge/streams/origin.demo/init_2_video_llhls.m4s?session=test"
#EXT-X-PROGRAM-DATE-TIME:2026-04-22T10:00:03.200+00:00
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_2_102_video_llhls.m4s?session=test
#EXT-X-PROGRAM-DATE-TIME:2026-04-22T10:00:04.800+00:00
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_2_103_video_llhls.m4s?session=test
#EXT-X-PROGRAM-DATE-TIME:2026-04-22T10:00:06.400+00:00
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_2_104_video_llhls.m4s?session=test
#EXT-X-PROGRAM-DATE-TIME:2026-04-22T10:00:08.000+00:00
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_2_105_video_llhls.m4s?session=test
#EXT-X-PROGRAM-DATE-TIME:2026-04-22T10:00:09.600+00:00
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_2_106_video_llhls.m4s?session=test
''';
    const initialAudioPlaylist = '''
#EXTM3U
#EXT-X-VERSION:6
#EXT-X-TARGETDURATION:1
#EXT-X-MEDIA-SEQUENCE:100
#EXT-X-MAP:URI="/v1/edge/streams/origin.demo/init_7_audio_llhls.m4s?session=test"
#EXT-X-PROGRAM-DATE-TIME:2026-04-22T10:00:00.000+00:00
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_7_100_audio_llhls.m4s?session=test
#EXT-X-PROGRAM-DATE-TIME:2026-04-22T10:00:01.600+00:00
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_7_101_audio_llhls.m4s?session=test
#EXT-X-PROGRAM-DATE-TIME:2026-04-22T10:00:03.200+00:00
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_7_102_audio_llhls.m4s?session=test
#EXT-X-PROGRAM-DATE-TIME:2026-04-22T10:00:04.800+00:00
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_7_103_audio_llhls.m4s?session=test
#EXT-X-PROGRAM-DATE-TIME:2026-04-22T10:00:06.400+00:00
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_7_104_audio_llhls.m4s?session=test
''';
    const refreshedAudioPlaylist = '''
#EXTM3U
#EXT-X-VERSION:6
#EXT-X-TARGETDURATION:1
#EXT-X-MEDIA-SEQUENCE:102
#EXT-X-MAP:URI="/v1/edge/streams/origin.demo/init_7_audio_llhls.m4s?session=test"
#EXT-X-PROGRAM-DATE-TIME:2026-04-22T10:00:03.200+00:00
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_7_102_audio_llhls.m4s?session=test
#EXT-X-PROGRAM-DATE-TIME:2026-04-22T10:00:04.800+00:00
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_7_103_audio_llhls.m4s?session=test
#EXT-X-PROGRAM-DATE-TIME:2026-04-22T10:00:06.400+00:00
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_7_104_audio_llhls.m4s?session=test
#EXT-X-PROGRAM-DATE-TIME:2026-04-22T10:00:08.000+00:00
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_7_105_audio_llhls.m4s?session=test
#EXT-X-PROGRAM-DATE-TIME:2026-04-22T10:00:09.600+00:00
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_7_106_audio_llhls.m4s?session=test
''';
    final releaseVideoRefresh = Completer<void>();
    final releaseAudioRefresh = Completer<void>();
    var videoPlaylistRequests = 0;
    var audioPlaylistRequests = 0;
    final assets = <String, List<int>>{
      '/v1/edge/streams/origin.demo/init_2_video_llhls.m4s?session=test':
          utf8.encode('video-init'),
      for (final seq in [100, 101, 102, 103, 104, 105, 106])
        '/v1/edge/streams/origin.demo/seg_2_${seq}_video_llhls.m4s?session=test':
            utf8.encode('video-seg-$seq'),
      '/v1/edge/streams/origin.demo/init_7_audio_llhls.m4s?session=test':
          utf8.encode('audio-init'),
      for (final seq in [100, 101, 102, 103, 104, 105, 106])
        '/v1/edge/streams/origin.demo/seg_7_${seq}_audio_llhls.m4s?session=test':
            utf8.encode('audio-seg-$seq'),
    };

    Future<void> writeDelayedPlaylist(
      HttpRequest request,
      String body,
      Completer<void> blocker,
    ) async {
      await blocker.future;
      request.response.headers.contentType = ContentType.text;
      request.response.write(body);
      await request.response.close();
    }

    upstream.listen((request) async {
      final path = request.requestedUri.path;
      final fullPath = request.uri.toString();
      if (path.endsWith('chunklist_2_video_llhls.m3u8')) {
        videoPlaylistRequests += 1;
        if (videoPlaylistRequests == 1) {
          request.response.headers.contentType = ContentType.text;
          request.response.write(initialVideoPlaylist);
          await request.response.close();
          return;
        }
        await writeDelayedPlaylist(
          request,
          refreshedVideoPlaylist,
          releaseVideoRefresh,
        );
        return;
      }
      if (path.endsWith('chunklist_7_audio_llhls.m3u8')) {
        audioPlaylistRequests += 1;
        if (audioPlaylistRequests == 1) {
          request.response.headers.contentType = ContentType.text;
          request.response.write(initialAudioPlaylist);
          await request.response.close();
          return;
        }
        await writeDelayedPlaylist(
          request,
          refreshedAudioPlaylist,
          releaseAudioRefresh,
        );
        return;
      }
      if (assets.containsKey(fullPath)) {
        request.response.add(assets[fullPath]!);
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });

    final proxy = ChaturbateLlHlsProxy(enabledOverride: true);
    final wrapped = await proxy.wrapPlayUrls(
      quality: const LivePlayQuality(
        id: '5128000',
        label: '1080p',
        sortOrder: 1080,
      ),
      playUrls: [
        LivePlayUrl(
          url:
              '$baseUrl/v1/edge/streams/origin.demo/chunklist_2_video_llhls.m3u8?session=test',
          headers: const {'referer': 'https://chaturbate.com/demo/'},
          metadata: {
            'audioUrl':
                '$baseUrl/v1/edge/streams/origin.demo/chunklist_7_audio_llhls.m3u8?session=test',
            'audioHeaders': {'referer': 'https://chaturbate.com/demo/'},
          },
        ),
      ],
    );

    final client = HttpClient();
    final masterResponse =
        await (await client.getUrl(Uri.parse(wrapped.single.url))).close();
    final masterText = utf8.decode(await masterResponse.fold<List<int>>(
      <int>[],
      (buffer, data) => buffer..addAll(data),
    ));
    final videoUri =
        RegExp(r'http://127\.0\.0\.1:\d+/chaturbate-llhls/[^\s]+/video\.m3u8')
            .firstMatch(masterText)!
            .group(0)!;

    final firstVideoResponse =
        await (await client.getUrl(Uri.parse(videoUri))).close();
    final firstVideoText = utf8.decode(await firstVideoResponse.fold<List<int>>(
      <int>[],
      (buffer, data) => buffer..addAll(data),
    ));
    final firstSegmentCount =
        RegExp(r'#EXTINF:').allMatches(firstVideoText).length;
    expect(firstSegmentCount, greaterThanOrEqualTo(4));

    await Future<void>.delayed(const Duration(milliseconds: 400));

    final stopwatch = Stopwatch()..start();
    final pendingVideoResponse =
        (await client.getUrl(Uri.parse(videoUri))).close();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    releaseVideoRefresh.complete();
    releaseAudioRefresh.complete();
    final secondVideoResponse = await pendingVideoResponse;
    final secondVideoText =
        utf8.decode(await secondVideoResponse.fold<List<int>>(
      <int>[],
      (buffer, data) => buffer..addAll(data),
    ));
    stopwatch.stop();

    expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(200));
    expect(
      RegExp(r'#EXTINF:').allMatches(secondVideoText).length,
      greaterThan(firstSegmentCount),
    );
    expect(videoPlaylistRequests, greaterThanOrEqualTo(2));
    expect(audioPlaylistRequests, greaterThanOrEqualTo(2));

    client.close(force: true);
    await proxy.dispose();
    await upstream.close(force: true);
  });

  test(
      'chaturbate ll-hls proxy exposes a deeper startup window for the first playlist',
      () async {
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final baseUrl = 'http://${upstream.address.host}:${upstream.port}';

    String buildPlaylist({
      required String initPath,
      required String segmentPrefix,
    }) {
      final buffer = StringBuffer()
        ..writeln('#EXTM3U')
        ..writeln('#EXT-X-VERSION:6')
        ..writeln('#EXT-X-TARGETDURATION:2')
        ..writeln('#EXT-X-MEDIA-SEQUENCE:200')
        ..writeln('#EXT-X-MAP:URI="$initPath"');
      final start = DateTime.parse('2026-04-22T10:00:00.000Z');
      for (var index = 0; index < 10; index += 1) {
        final timestamp = start.add(Duration(milliseconds: 1600 * index));
        final sequence = 200 + index;
        buffer
          ..writeln('#EXT-X-PROGRAM-DATE-TIME:${timestamp.toIso8601String()}')
          ..writeln('#EXTINF:1.600000,')
          ..writeln('$segmentPrefix$sequence.m4s?session=test');
      }
      return buffer.toString();
    }

    final videoPlaylist = buildPlaylist(
      initPath:
          '/v1/edge/streams/origin.demo/init_2_video_llhls.m4s?session=test',
      segmentPrefix: '/v1/edge/streams/origin.demo/seg_2_',
    );
    final audioPlaylist = buildPlaylist(
      initPath:
          '/v1/edge/streams/origin.demo/init_7_audio_llhls.m4s?session=test',
      segmentPrefix: '/v1/edge/streams/origin.demo/seg_7_',
    );

    final assets = <String, List<int>>{
      '/v1/edge/streams/origin.demo/init_2_video_llhls.m4s?session=test':
          utf8.encode('video-init'),
      '/v1/edge/streams/origin.demo/init_7_audio_llhls.m4s?session=test':
          utf8.encode('audio-init'),
      for (var sequence = 200; sequence < 210; sequence += 1)
        '/v1/edge/streams/origin.demo/seg_2_$sequence.m4s?session=test':
            utf8.encode('video-$sequence'),
      for (var sequence = 200; sequence < 210; sequence += 1)
        '/v1/edge/streams/origin.demo/seg_7_$sequence.m4s?session=test':
            utf8.encode('audio-$sequence'),
    };

    upstream.listen((request) async {
      final path = request.requestedUri.path;
      final fullPath = request.uri.toString();
      if (path.endsWith('chunklist_2_video_llhls.m3u8')) {
        request.response.headers.contentType = ContentType.text;
        request.response.write(videoPlaylist);
      } else if (path.endsWith('chunklist_7_audio_llhls.m3u8')) {
        request.response.headers.contentType = ContentType.text;
        request.response.write(audioPlaylist);
      } else if (assets.containsKey(fullPath)) {
        request.response.add(assets[fullPath]!);
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });

    final proxy = ChaturbateLlHlsProxy(enabledOverride: true);
    final wrapped = await proxy.wrapPlayUrls(
      quality: const LivePlayQuality(
        id: '7128000',
        label: '1080p',
        sortOrder: 1080,
      ),
      playUrls: [
        LivePlayUrl(
          url:
              '$baseUrl/v1/edge/streams/origin.demo/chunklist_2_video_llhls.m3u8?session=test',
          headers: const {'referer': 'https://chaturbate.com/demo/'},
          metadata: {
            'audioUrl':
                '$baseUrl/v1/edge/streams/origin.demo/chunklist_7_audio_llhls.m3u8?session=test',
            'audioHeaders': {'referer': 'https://chaturbate.com/demo/'},
          },
        ),
      ],
    );

    final client = HttpClient();
    final masterResponse =
        await (await client.getUrl(Uri.parse(wrapped.single.url))).close();
    final masterText = utf8.decode(await masterResponse.fold<List<int>>(
      <int>[],
      (buffer, data) => buffer..addAll(data),
    ));
    final videoUri =
        RegExp(r'http://127\.0\.0\.1:\d+/chaturbate-llhls/[^\s]+/video\.m3u8')
            .firstMatch(masterText)!
            .group(0)!;
    final audioUri =
        RegExp(r'http://127\.0\.0\.1:\d+/chaturbate-llhls/[^\s]+/audio\.m3u8')
            .firstMatch(masterText)!
            .group(0)!;

    final videoResponse =
        await (await client.getUrl(Uri.parse(videoUri))).close();
    final videoText = utf8.decode(await videoResponse.fold<List<int>>(
      <int>[],
      (buffer, data) => buffer..addAll(data),
    ));
    final audioResponse =
        await (await client.getUrl(Uri.parse(audioUri))).close();
    final audioText = utf8.decode(await audioResponse.fold<List<int>>(
      <int>[],
      (buffer, data) => buffer..addAll(data),
    ));

    expect(RegExp(r'#EXTINF:').allMatches(videoText).length, 8);
    expect(RegExp(r'#EXTINF:').allMatches(audioText).length, 8);
    expect(videoText, contains('#EXT-X-MEDIA-SEQUENCE:201'));
    expect(audioText, contains('#EXT-X-MEDIA-SEQUENCE:201'));

    client.close(force: true);
    await proxy.dispose();
    await upstream.close(force: true);
  });

  test(
      'chaturbate ll-hls proxy does not block wrapPlayUrls on startup asset warming',
      () async {
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final baseUrl = 'http://${upstream.address.host}:${upstream.port}';
    final releaseAssets = Completer<void>();
    const videoPlaylist = '''
#EXTM3U
#EXT-X-VERSION:6
#EXT-X-TARGETDURATION:2
#EXT-X-MEDIA-SEQUENCE:200
#EXT-X-MAP:URI="/v1/edge/streams/origin.demo/init_2_video_llhls.m4s?session=test"
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_2_200.m4s?session=test
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_2_201.m4s?session=test
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_2_202.m4s?session=test
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_2_203.m4s?session=test
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_2_204.m4s?session=test
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_2_205.m4s?session=test
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_2_206.m4s?session=test
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_2_207.m4s?session=test
''';
    const audioPlaylist = '''
#EXTM3U
#EXT-X-VERSION:6
#EXT-X-TARGETDURATION:2
#EXT-X-MEDIA-SEQUENCE:200
#EXT-X-MAP:URI="/v1/edge/streams/origin.demo/init_7_audio_llhls.m4s?session=test"
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_7_200.m4s?session=test
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_7_201.m4s?session=test
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_7_202.m4s?session=test
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_7_203.m4s?session=test
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_7_204.m4s?session=test
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_7_205.m4s?session=test
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_7_206.m4s?session=test
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_7_207.m4s?session=test
''';

    upstream.listen((request) async {
      final path = request.requestedUri.path;
      if (path.endsWith('chunklist_2_video_llhls.m3u8')) {
        request.response.headers.contentType = ContentType.text;
        request.response.write(videoPlaylist);
      } else if (path.endsWith('chunklist_7_audio_llhls.m3u8')) {
        request.response.headers.contentType = ContentType.text;
        request.response.write(audioPlaylist);
      } else if (path.contains('/init_') || path.contains('/seg_')) {
        await releaseAssets.future;
        request.response.add(utf8.encode(path));
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });

    final proxy = ChaturbateLlHlsProxy(enabledOverride: true);
    final stopwatch = Stopwatch()..start();
    final wrapped = await proxy.wrapPlayUrls(
      quality: const LivePlayQuality(
        id: '5128000',
        label: '1080p',
        sortOrder: 1080,
      ),
      playUrls: [
        LivePlayUrl(
          url:
              '$baseUrl/v1/edge/streams/origin.demo/chunklist_2_video_llhls.m3u8?session=test',
          headers: const {'referer': 'https://chaturbate.com/demo/'},
          metadata: {
            'audioUrl':
                '$baseUrl/v1/edge/streams/origin.demo/chunklist_7_audio_llhls.m3u8?session=test',
            'audioHeaders': {'referer': 'https://chaturbate.com/demo/'},
          },
        ),
      ],
    );
    stopwatch.stop();

    expect(stopwatch.elapsedMilliseconds, lessThan(250));
    expect(wrapped.single.url, contains('/chaturbate-llhls/'));

    releaseAssets.complete();
    await proxy.dispose();
    await upstream.close(force: true);
  });

  test(
      'chaturbate ll-hls proxy keeps first playback playlist under the old 5s startup wait',
      () async {
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final baseUrl = 'http://${upstream.address.host}:${upstream.port}';
    var videoPlaylistRequests = 0;
    var audioPlaylistRequests = 0;

    String buildPlaylist({
      required String initPath,
      required String segmentPrefix,
      required int requestCount,
    }) {
      final availableSegments = min(13, 4 + requestCount);
      final start = DateTime.parse('2026-04-22T10:00:00.000Z');
      final buffer = StringBuffer()
        ..writeln('#EXTM3U')
        ..writeln('#EXT-X-VERSION:6')
        ..writeln('#EXT-X-TARGETDURATION:2')
        ..writeln('#EXT-X-MEDIA-SEQUENCE:300')
        ..writeln('#EXT-X-MAP:URI="$initPath"');
      for (var index = 0; index < availableSegments; index += 1) {
        final sequence = 300 + index;
        final timestamp = start.add(Duration(milliseconds: 1600 * index));
        buffer
          ..writeln('#EXT-X-PROGRAM-DATE-TIME:${timestamp.toIso8601String()}')
          ..writeln('#EXTINF:1.600000,')
          ..writeln('$segmentPrefix$sequence.m4s?session=test');
      }
      return buffer.toString();
    }

    final assets = <String, List<int>>{
      '/v1/edge/streams/origin.demo/init_2_video_llhls.m4s?session=test':
          utf8.encode('video-init'),
      '/v1/edge/streams/origin.demo/init_7_audio_llhls.m4s?session=test':
          utf8.encode('audio-init'),
      for (var sequence = 300; sequence < 313; sequence += 1)
        '/v1/edge/streams/origin.demo/seg_2_$sequence.m4s?session=test':
            utf8.encode('video-$sequence'),
      for (var sequence = 300; sequence < 313; sequence += 1)
        '/v1/edge/streams/origin.demo/seg_7_$sequence.m4s?session=test':
            utf8.encode('audio-$sequence'),
    };

    upstream.listen((request) async {
      final path = request.requestedUri.path;
      final fullPath = request.uri.toString();
      if (path.endsWith('chunklist_2_video_llhls.m3u8')) {
        videoPlaylistRequests += 1;
        request.response.headers.contentType = ContentType.text;
        request.response.write(
          buildPlaylist(
            initPath:
                '/v1/edge/streams/origin.demo/init_2_video_llhls.m4s?session=test',
            segmentPrefix: '/v1/edge/streams/origin.demo/seg_2_',
            requestCount: videoPlaylistRequests,
          ),
        );
      } else if (path.endsWith('chunklist_7_audio_llhls.m3u8')) {
        audioPlaylistRequests += 1;
        request.response.headers.contentType = ContentType.text;
        request.response.write(
          buildPlaylist(
            initPath:
                '/v1/edge/streams/origin.demo/init_7_audio_llhls.m4s?session=test',
            segmentPrefix: '/v1/edge/streams/origin.demo/seg_7_',
            requestCount: audioPlaylistRequests,
          ),
        );
      } else if (assets.containsKey(fullPath)) {
        request.response.add(assets[fullPath]!);
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });

    final proxy = ChaturbateLlHlsProxy(enabledOverride: true);
    final wrapped = await proxy.wrapPlayUrls(
      quality: const LivePlayQuality(
        id: '5128000',
        label: '1080p',
        sortOrder: 1080,
      ),
      playUrls: [
        LivePlayUrl(
          url:
              '$baseUrl/v1/edge/streams/origin.demo/chunklist_2_video_llhls.m3u8?session=test',
          headers: const {'referer': 'https://chaturbate.com/demo/'},
          metadata: {
            'audioUrl':
                '$baseUrl/v1/edge/streams/origin.demo/chunklist_7_audio_llhls.m3u8?session=test',
            'audioHeaders': {'referer': 'https://chaturbate.com/demo/'},
          },
        ),
      ],
    );

    final client = HttpClient();
    final masterResponse =
        await (await client.getUrl(Uri.parse(wrapped.single.url))).close();
    final masterText = utf8.decode(await masterResponse.fold<List<int>>(
      <int>[],
      (buffer, data) => buffer..addAll(data),
    ));
    final videoUri =
        RegExp(r'http://127\.0\.0\.1:\d+/chaturbate-llhls/[^\s]+/video\.m3u8')
            .firstMatch(masterText)!
            .group(0)!;
    final stopwatch = Stopwatch()..start();
    final videoResponse =
        await (await client.getUrl(Uri.parse(videoUri))).close();
    final videoText = utf8.decode(await videoResponse.fold<List<int>>(
      <int>[],
      (buffer, data) => buffer..addAll(data),
    ));
    stopwatch.stop();

    expect(stopwatch.elapsedMilliseconds, lessThan(2500));
    expect(
      RegExp(r'#EXTINF:').allMatches(videoText).length,
      greaterThanOrEqualTo(6),
    );
    expect(videoPlaylistRequests, greaterThanOrEqualTo(2));
    expect(audioPlaylistRequests, greaterThanOrEqualTo(2));

    client.close(force: true);
    await proxy.dispose();
    await upstream.close(force: true);
  });

  test(
      'chaturbate ll-hls proxy keeps a wider stable runway even when only the cached prefix is warmed',
      () async {
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final baseUrl = 'http://${upstream.address.host}:${upstream.port}';
    var allowLateStableAssets = false;
    const videoPlaylist = '''
#EXTM3U
#EXT-X-VERSION:6
#EXT-X-TARGETDURATION:2
#EXT-X-MEDIA-SEQUENCE:80
#EXT-X-MAP:URI="/v1/edge/streams/origin.demo/init_2_video_llhls.m4s?session=test"
#EXT-X-PROGRAM-DATE-TIME:2026-04-22T10:00:00.000+00:00
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_2_80_video_llhls.m4s?session=test
#EXT-X-PROGRAM-DATE-TIME:2026-04-22T10:00:01.600+00:00
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_2_81_video_llhls.m4s?session=test
#EXT-X-PROGRAM-DATE-TIME:2026-04-22T10:00:03.200+00:00
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_2_82_video_llhls.m4s?session=test
#EXT-X-PROGRAM-DATE-TIME:2026-04-22T10:00:04.800+00:00
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_2_83_video_llhls.m4s?session=test
#EXT-X-PROGRAM-DATE-TIME:2026-04-22T10:00:06.400+00:00
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_2_84_video_llhls.m4s?session=test
#EXT-X-PROGRAM-DATE-TIME:2026-04-22T10:00:08.000+00:00
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_2_85_video_llhls.m4s?session=test
#EXT-X-PROGRAM-DATE-TIME:2026-04-22T10:00:09.600+00:00
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_2_86_video_llhls.m4s?session=test
#EXT-X-PROGRAM-DATE-TIME:2026-04-22T10:00:11.200+00:00
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_2_87_video_llhls.m4s?session=test
#EXT-X-PROGRAM-DATE-TIME:2026-04-22T10:00:12.800+00:00
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_2_88_video_llhls.m4s?session=test
#EXT-X-PROGRAM-DATE-TIME:2026-04-22T10:00:14.400+00:00
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_2_89_video_llhls.m4s?session=test
''';
    const audioPlaylist = '''
#EXTM3U
#EXT-X-VERSION:6
#EXT-X-TARGETDURATION:2
#EXT-X-MEDIA-SEQUENCE:80
#EXT-X-MAP:URI="/v1/edge/streams/origin.demo/init_7_audio_llhls.m4s?session=test"
#EXT-X-PROGRAM-DATE-TIME:2026-04-22T10:00:00.000+00:00
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_7_80_audio_llhls.m4s?session=test
#EXT-X-PROGRAM-DATE-TIME:2026-04-22T10:00:01.600+00:00
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_7_81_audio_llhls.m4s?session=test
#EXT-X-PROGRAM-DATE-TIME:2026-04-22T10:00:03.200+00:00
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_7_82_audio_llhls.m4s?session=test
#EXT-X-PROGRAM-DATE-TIME:2026-04-22T10:00:04.800+00:00
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_7_83_audio_llhls.m4s?session=test
#EXT-X-PROGRAM-DATE-TIME:2026-04-22T10:00:06.400+00:00
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_7_84_audio_llhls.m4s?session=test
#EXT-X-PROGRAM-DATE-TIME:2026-04-22T10:00:08.000+00:00
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_7_85_audio_llhls.m4s?session=test
#EXT-X-PROGRAM-DATE-TIME:2026-04-22T10:00:09.600+00:00
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_7_86_audio_llhls.m4s?session=test
#EXT-X-PROGRAM-DATE-TIME:2026-04-22T10:00:11.200+00:00
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_7_87_audio_llhls.m4s?session=test
#EXT-X-PROGRAM-DATE-TIME:2026-04-22T10:00:12.800+00:00
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_7_88_audio_llhls.m4s?session=test
#EXT-X-PROGRAM-DATE-TIME:2026-04-22T10:00:14.400+00:00
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_7_89_audio_llhls.m4s?session=test
''';
    final assets = <String, List<int>>{
      '/v1/edge/streams/origin.demo/init_2_video_llhls.m4s?session=test':
          utf8.encode('video-init'),
      '/v1/edge/streams/origin.demo/init_7_audio_llhls.m4s?session=test':
          utf8.encode('audio-init'),
      for (var sequence = 80; sequence < 90; sequence += 1)
        '/v1/edge/streams/origin.demo/seg_2_$sequence'
            '_video_llhls.m4s?session=test': utf8.encode('video-seg-$sequence'),
      for (var sequence = 80; sequence < 90; sequence += 1)
        '/v1/edge/streams/origin.demo/seg_7_$sequence'
            '_audio_llhls.m4s?session=test': utf8.encode('audio-seg-$sequence'),
    };
    upstream.listen((request) async {
      final path = request.requestedUri.path;
      final fullPath = request.uri.toString();
      if (path.endsWith('chunklist_2_video_llhls.m3u8')) {
        request.response.headers.contentType = ContentType.text;
        request.response.write(videoPlaylist);
      } else if (path.endsWith('chunklist_7_audio_llhls.m3u8')) {
        request.response.headers.contentType = ContentType.text;
        request.response.write(audioPlaylist);
      } else if (assets.containsKey(fullPath)) {
        final isLateStableSegment = fullPath.contains('seg_2_84_video_llhls') ||
            fullPath.contains('seg_2_85_video_llhls') ||
            fullPath.contains('seg_2_86_video_llhls') ||
            fullPath.contains('seg_2_87_video_llhls') ||
            fullPath.contains('seg_2_88_video_llhls') ||
            fullPath.contains('seg_2_89_video_llhls') ||
            fullPath.contains('seg_7_84_audio_llhls') ||
            fullPath.contains('seg_7_85_audio_llhls') ||
            fullPath.contains('seg_7_86_audio_llhls') ||
            fullPath.contains('seg_7_87_audio_llhls') ||
            fullPath.contains('seg_7_88_audio_llhls') ||
            fullPath.contains('seg_7_89_audio_llhls');
        if (isLateStableSegment && !allowLateStableAssets) {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          return;
        }
        request.response.add(assets[fullPath]!);
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });

    final proxy = ChaturbateLlHlsProxy(enabledOverride: true);
    final wrapped = await proxy.wrapPlayUrls(
      quality: const LivePlayQuality(
        id: '5128000',
        label: '1080p',
        sortOrder: 1080,
      ),
      playUrls: [
        LivePlayUrl(
          url:
              '$baseUrl/v1/edge/streams/origin.demo/chunklist_2_video_llhls.m3u8?session=test',
          headers: const {'referer': 'https://chaturbate.com/demo/'},
          metadata: {
            'audioUrl':
                '$baseUrl/v1/edge/streams/origin.demo/chunklist_7_audio_llhls.m3u8?session=test',
            'audioHeaders': {'referer': 'https://chaturbate.com/demo/'},
          },
        ),
      ],
    );

    final client = HttpClient();
    final masterResponse =
        await (await client.getUrl(Uri.parse(wrapped.single.url))).close();
    final masterText = utf8.decode(await masterResponse.fold<List<int>>(
      <int>[],
      (buffer, data) => buffer..addAll(data),
    ));
    final videoUri =
        RegExp(r'http://127\.0\.0\.1:\d+/chaturbate-llhls/[^\s]+/video\.m3u8')
            .firstMatch(masterText)!
            .group(0)!;

    final initialVideoResponse =
        await (await client.getUrl(Uri.parse(videoUri))).close();
    final initialVideoText =
        utf8.decode(await initialVideoResponse.fold<List<int>>(
      <int>[],
      (buffer, data) => buffer..addAll(data),
    ));
    final initialAssetUris = RegExp(
      r'http://127\.0\.0\.1:\d+/chaturbate-llhls/[^\s"]+/asset/[0-9a-f]+',
    ).allMatches(initialVideoText).map((match) => match.group(0)!).toList();
    for (final assetUri in initialAssetUris.take(5)) {
      await (await client.getUrl(Uri.parse(assetUri))).close();
    }

    allowLateStableAssets = true;
    await Future<void>.delayed(const Duration(milliseconds: 400));

    final stableVideoResponse =
        await (await client.getUrl(Uri.parse(videoUri))).close();
    final stableVideoText =
        utf8.decode(await stableVideoResponse.fold<List<int>>(
      <int>[],
      (buffer, data) => buffer..addAll(data),
    ));
    final assetUris = RegExp(
      r'http://127\.0\.0\.1:\d+/chaturbate-llhls/[^\s"]+/asset/[0-9a-f]+',
    ).allMatches(stableVideoText).map((match) => match.group(0)!).toList();
    final assetBodies = <String>[];
    for (final assetUri in assetUris) {
      final assetResponse =
          await (await client.getUrl(Uri.parse(assetUri))).close();
      expect(assetResponse.statusCode, HttpStatus.ok);
      assetBodies.add(
        utf8.decode(await assetResponse.fold<List<int>>(
          <int>[],
          (buffer, data) => buffer..addAll(data),
        )),
      );
    }

    expect(RegExp(r'#EXTINF:').allMatches(stableVideoText).length, 8);
    expect(assetBodies, contains('video-init'));
    expect(assetBodies, contains('video-seg-80'));
    expect(assetBodies, contains('video-seg-81'));
    expect(assetBodies, contains('video-seg-82'));
    expect(assetBodies, contains('video-seg-83'));
    expect(assetBodies, contains('video-seg-84'));
    expect(assetBodies, contains('video-seg-85'));
    expect(assetBodies, contains('video-seg-86'));
    expect(assetBodies, contains('video-seg-87'));
    expect(assetBodies, isNot(contains('video-seg-88')));

    client.close(force: true);
    await proxy.dispose();
    await upstream.close(force: true);
  });

  test(
      'chaturbate ll-hls proxy waits briefly for a late segment before surfacing an asset failure',
      () async {
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final baseUrl = 'http://${upstream.address.host}:${upstream.port}';
    var lateAssetAvailable = false;

    String buildPlaylist({
      required String initPath,
      required String segmentPrefix,
    }) {
      final buffer = StringBuffer()
        ..writeln('#EXTM3U')
        ..writeln('#EXT-X-VERSION:6')
        ..writeln('#EXT-X-TARGETDURATION:2')
        ..writeln('#EXT-X-MEDIA-SEQUENCE:200')
        ..writeln('#EXT-X-MAP:URI="$initPath"');
      final start = DateTime.parse('2026-04-22T10:00:00.000Z');
      for (var index = 0; index < 14; index += 1) {
        final timestamp = start.add(Duration(milliseconds: 1600 * index));
        final sequence = 200 + index;
        buffer
          ..writeln('#EXT-X-PROGRAM-DATE-TIME:${timestamp.toIso8601String()}')
          ..writeln('#EXTINF:1.600000,')
          ..writeln('$segmentPrefix$sequence.m4s?session=test');
      }
      return buffer.toString();
    }

    final videoPlaylist = buildPlaylist(
      initPath:
          '/v1/edge/streams/origin.demo/init_2_video_llhls.m4s?session=test',
      segmentPrefix: '/v1/edge/streams/origin.demo/seg_2_',
    );
    final audioPlaylist = buildPlaylist(
      initPath:
          '/v1/edge/streams/origin.demo/init_7_audio_llhls.m4s?session=test',
      segmentPrefix: '/v1/edge/streams/origin.demo/seg_7_',
    );

    final assets = <String, List<int>>{
      '/v1/edge/streams/origin.demo/init_2_video_llhls.m4s?session=test':
          utf8.encode('video-init'),
      '/v1/edge/streams/origin.demo/init_7_audio_llhls.m4s?session=test':
          utf8.encode('audio-init'),
      for (var sequence = 200; sequence < 214; sequence += 1)
        '/v1/edge/streams/origin.demo/seg_2_$sequence.m4s?session=test':
            utf8.encode('video-$sequence'),
      for (var sequence = 200; sequence < 214; sequence += 1)
        '/v1/edge/streams/origin.demo/seg_7_$sequence.m4s?session=test':
            utf8.encode('audio-$sequence'),
    };

    upstream.listen((request) async {
      final path = request.requestedUri.path;
      final fullPath = request.uri.toString();
      if (path.endsWith('chunklist_2_video_llhls.m3u8')) {
        request.response.headers.contentType = ContentType.text;
        request.response.write(videoPlaylist);
      } else if (path.endsWith('chunklist_7_audio_llhls.m3u8')) {
        request.response.headers.contentType = ContentType.text;
        request.response.write(audioPlaylist);
      } else if (assets.containsKey(fullPath)) {
        if (fullPath.contains('seg_2_210.m4s') && !lateAssetAvailable) {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          return;
        }
        request.response.add(assets[fullPath]!);
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });

    final proxy = ChaturbateLlHlsProxy(enabledOverride: true);
    final wrapped = await proxy.wrapPlayUrls(
      quality: const LivePlayQuality(
        id: '1800000',
        label: '480p',
        sortOrder: 480,
        metadata: {
          'bandwidth': 1800000,
          'width': 854,
          'height': 480,
        },
      ),
      playUrls: [
        LivePlayUrl(
          url:
              '$baseUrl/v1/edge/streams/origin.demo/chunklist_2_video_llhls.m3u8?session=test',
          headers: const {'referer': 'https://chaturbate.com/demo/'},
          metadata: {
            'audioUrl':
                '$baseUrl/v1/edge/streams/origin.demo/chunklist_7_audio_llhls.m3u8?session=test',
            'audioHeaders': {'referer': 'https://chaturbate.com/demo/'},
          },
        ),
      ],
    );

    final client = HttpClient();
    final masterUri = Uri.parse(wrapped.single.url);
    final masterResponse = await (await client.getUrl(masterUri)).close();
    final masterText = utf8.decode(await masterResponse.fold<List<int>>(
      <int>[],
      (buffer, data) => buffer..addAll(data),
    ));
    final videoUri =
        RegExp(r'http://127\.0\.0\.1:\d+/chaturbate-llhls/[^\s]+/video\.m3u8')
            .firstMatch(masterText)!
            .group(0)!;
    await (await client.getUrl(Uri.parse(videoUri))).close();

    String encodeAssetId(String url) {
      final buffer = StringBuffer();
      for (final code in utf8.encode(url)) {
        buffer.write(code.toRadixString(16).padLeft(2, '0'));
      }
      return buffer.toString();
    }

    final lateAssetId = encodeAssetId(
      '$baseUrl/v1/edge/streams/origin.demo/seg_2_210.m4s?session=test',
    );
    final lateAssetUri = masterUri.replace(
      pathSegments: <String>[
        masterUri.pathSegments[0],
        masterUri.pathSegments[1],
        'asset',
        lateAssetId,
      ],
    );

    final stopwatch = Stopwatch()..start();
    final lateAssetResponseFuture = (await client.getUrl(lateAssetUri)).close();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    lateAssetAvailable = true;
    final lateAssetResponse = await lateAssetResponseFuture;
    final lateAssetBody = utf8.decode(await lateAssetResponse.fold<List<int>>(
      <int>[],
      (buffer, data) => buffer..addAll(data),
    ));
    stopwatch.stop();

    expect(lateAssetResponse.statusCode, HttpStatus.ok);
    expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(250));
    expect(stopwatch.elapsedMilliseconds, lessThan(1200));
    expect(lateAssetBody, 'video-210');

    client.close(force: true);
    await proxy.dispose();
    await upstream.close(force: true);
  });

  test(
      'chaturbate ll-hls proxy serves cached assets after upstream segments expire',
      () async {
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final baseUrl = 'http://${upstream.address.host}:${upstream.port}';
    const videoPlaylist = '''
#EXTM3U
#EXT-X-VERSION:6
#EXT-X-TARGETDURATION:2
#EXT-X-MEDIA-SEQUENCE:30
#EXT-X-MAP:URI="/v1/edge/streams/origin.demo/init_2_video_llhls.m4s?session=test"
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_2_30_video_llhls.m4s?session=test
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_2_31_video_llhls.m4s?session=test
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_2_32_video_llhls.m4s?session=test
''';
    const audioPlaylist = '''
#EXTM3U
#EXT-X-VERSION:6
#EXT-X-TARGETDURATION:2
#EXT-X-MEDIA-SEQUENCE:30
#EXT-X-MAP:URI="/v1/edge/streams/origin.demo/init_7_audio_llhls.m4s?session=test"
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_7_30_audio_llhls.m4s?session=test
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_7_31_audio_llhls.m4s?session=test
#EXTINF:1.600000,
/v1/edge/streams/origin.demo/seg_7_32_audio_llhls.m4s?session=test
''';
    const targetAudioSegmentPath =
        '/v1/edge/streams/origin.demo/seg_7_31_audio_llhls.m4s?session=test';
    var allowAssetOrigin = true;
    final targetAudioPrefetched = Completer<void>();
    final lastAudioPrefetched = Completer<void>();
    final assets = <String, List<int>>{
      '/v1/edge/streams/origin.demo/init_2_video_llhls.m4s?session=test':
          utf8.encode('video-init'),
      '/v1/edge/streams/origin.demo/seg_2_30_video_llhls.m4s?session=test':
          utf8.encode('video-seg-30'),
      '/v1/edge/streams/origin.demo/seg_2_31_video_llhls.m4s?session=test':
          utf8.encode('video-seg-31'),
      '/v1/edge/streams/origin.demo/seg_2_32_video_llhls.m4s?session=test':
          utf8.encode('video-seg-32'),
      '/v1/edge/streams/origin.demo/init_7_audio_llhls.m4s?session=test':
          utf8.encode('audio-init'),
      '/v1/edge/streams/origin.demo/seg_7_30_audio_llhls.m4s?session=test':
          utf8.encode('audio-seg-30'),
      targetAudioSegmentPath: utf8.encode('audio-seg-31'),
      '/v1/edge/streams/origin.demo/seg_7_32_audio_llhls.m4s?session=test':
          utf8.encode('audio-seg-32'),
    };
    upstream.listen((request) async {
      final path = request.requestedUri.path;
      final fullPath = request.uri.toString();
      if (path.endsWith('chunklist_2_video_llhls.m3u8')) {
        request.response.headers.contentType = ContentType.text;
        request.response.write(videoPlaylist);
      } else if (path.endsWith('chunklist_7_audio_llhls.m3u8')) {
        request.response.headers.contentType = ContentType.text;
        request.response.write(audioPlaylist);
      } else if (assets.containsKey(fullPath)) {
        if (!allowAssetOrigin) {
          request.response.statusCode = HttpStatus.notFound;
        } else {
          if (fullPath == targetAudioSegmentPath &&
              !targetAudioPrefetched.isCompleted) {
            targetAudioPrefetched.complete();
          }
          if (fullPath ==
                  '/v1/edge/streams/origin.demo/seg_7_32_audio_llhls.m4s?session=test' &&
              !lastAudioPrefetched.isCompleted) {
            lastAudioPrefetched.complete();
          }
          request.response.add(assets[fullPath]!);
        }
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });

    final proxy = ChaturbateLlHlsProxy(enabledOverride: true);
    final wrapped = await proxy.wrapPlayUrls(
      quality: const LivePlayQuality(
        id: '2096000',
        label: '540p',
        sortOrder: 540,
      ),
      playUrls: [
        LivePlayUrl(
          url:
              '$baseUrl/v1/edge/streams/origin.demo/chunklist_2_video_llhls.m3u8?session=test',
          headers: const {'referer': 'https://chaturbate.com/demo/'},
          metadata: {
            'audioUrl':
                '$baseUrl/v1/edge/streams/origin.demo/chunklist_7_audio_llhls.m3u8?session=test',
            'audioHeaders': {'referer': 'https://chaturbate.com/demo/'},
          },
        ),
      ],
    );

    final client = HttpClient();
    final masterResponse =
        await (await client.getUrl(Uri.parse(wrapped.single.url))).close();
    final masterText = utf8.decode(await masterResponse.fold<List<int>>(
      <int>[],
      (buffer, data) => buffer..addAll(data),
    ));
    final audioUri =
        RegExp(r'http://127\.0\.0\.1:\d+/chaturbate-llhls/[^\s"]+/audio\.m3u8')
            .firstMatch(masterText)!
            .group(0)!;

    final audioResponse =
        await (await client.getUrl(Uri.parse(audioUri))).close();
    final audioText = utf8.decode(await audioResponse.fold<List<int>>(
      <int>[],
      (buffer, data) => buffer..addAll(data),
    ));

    await targetAudioPrefetched.future.timeout(const Duration(seconds: 2));
    await lastAudioPrefetched.future.timeout(const Duration(seconds: 2));
    allowAssetOrigin = false;

    final assetUris = RegExp(
      r'http://127\.0\.0\.1:\d+/chaturbate-llhls/[^\s"]+/asset/[0-9a-f]+',
    ).allMatches(audioText).map((match) => match.group(0)!).toList();
    final assetBodies = <String>[];
    final assetStatuses = <int>[];
    for (final assetUri in assetUris) {
      final assetResponse =
          await (await client.getUrl(Uri.parse(assetUri))).close();
      assetStatuses.add(assetResponse.statusCode);
      assetBodies.add(
        utf8.decode(await assetResponse.fold<List<int>>(
          <int>[],
          (buffer, data) => buffer..addAll(data),
        )),
      );
    }

    expect(assetStatuses, everyElement(HttpStatus.ok));
    expect(assetBodies, contains('audio-seg-31'));

    client.close(force: true);
    await proxy.dispose();
    await upstream.close(force: true);
  });
}
