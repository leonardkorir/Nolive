import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_providers/live_providers.dart';
import 'package:nolive_app/src/app/runtime_bridges/twitch/twitch_ad_guard_proxy.dart';

void main() {
  late HttpServer upstream;
  late TwitchAdGuardProxy proxy;

  setUp(() async {
    upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    proxy = TwitchAdGuardProxy(enabledOverride: true);
  });

  tearDown(() async {
    await proxy.dispose();
    await upstream.close(force: true);
  });

  test('fixed quality proxy falls back to clean backup playlist', () async {
    upstream.listen((request) async {
      switch (request.uri.path) {
        case '/primary.m3u8':
          request.response.write(_adPlaylist(segmentPath: '/ad-segment.ts'));
          break;
        case '/backup.m3u8':
          request.response
              .write(_cleanPlaylist(segmentPath: '/clean-segment.ts'));
          break;
        case '/clean-segment.ts':
          request.response.add(utf8.encode('clean-segment'));
          break;
        default:
          request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });

    final base = 'http://${upstream.address.address}:${upstream.port}';
    final quality = LivePlayQuality(
      id: '720p',
      label: '720p',
      metadata: {
        'twitchPlaybackGroup': TwitchPlaybackQualityGroup(
          id: '720p',
          label: '720p',
          sortOrder: 720,
          candidates: [
            TwitchPlaybackCandidate(
              playlistUrl: '$base/primary.m3u8',
              headers: const {'referer': 'https://www.twitch.tv/xqc'},
              playerType: 'embed',
              platform: 'web',
              lineLabel: '优选 Embed',
            ),
            TwitchPlaybackCandidate(
              playlistUrl: '$base/backup.m3u8',
              headers: const {'referer': 'https://www.twitch.tv/xqc'},
              playerType: 'site',
              platform: 'web',
              lineLabel: '备用 Site',
            ),
          ],
        ).toJson(),
      },
    );
    final wrapped = await proxy.wrapPlayUrls(
      quality: quality,
      playUrls: [
        LivePlayUrl(
          url: '$base/primary.m3u8',
          headers: const {'referer': 'https://www.twitch.tv/xqc'},
          lineLabel: '优选 Embed',
          metadata: const {'playerType': 'embed'},
        ),
        LivePlayUrl(
          url: '$base/backup.m3u8',
          headers: const {'referer': 'https://www.twitch.tv/xqc'},
          lineLabel: '备用 Site',
          metadata: const {'playerType': 'site'},
        ),
      ],
    );

    final playlistText = await _readText(Uri.parse(wrapped.first.url));
    expect(playlistText, isNot(contains('stitched-ad')));
    expect(playlistText, contains('/asset/'));

    final assetUrl = _firstAssetUrl(playlistText);
    final assetBytes = await _readBytes(Uri.parse(assetUrl));
    expect(utf8.decode(assetBytes), 'clean-segment');
  });

  test('auto proxy synthesizes master playlist and serves guarded variants',
      () async {
    upstream.listen((request) async {
      switch (request.uri.path) {
        case '/720-primary.m3u8':
          request.response.write(_adPlaylist(segmentPath: '/720-ad.ts'));
          break;
        case '/720-backup.m3u8':
          request.response.write(_cleanPlaylist(segmentPath: '/720-clean.ts'));
          break;
        case '/480-primary.m3u8':
          request.response.write(_cleanPlaylist(segmentPath: '/480-clean.ts'));
          break;
        case '/720-clean.ts':
          request.response.add(utf8.encode('720-clean'));
          break;
        case '/480-clean.ts':
          request.response.add(utf8.encode('480-clean'));
          break;
        default:
          request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });

    final base = 'http://${upstream.address.address}:${upstream.port}';
    final autoQuality = LivePlayQuality(
      id: 'auto',
      label: 'Auto',
      metadata: {
        'twitchPlaybackGroups': [
          TwitchPlaybackQualityGroup(
            id: '720p',
            label: '720p',
            sortOrder: 720,
            bandwidth: 3200000,
            width: 1280,
            height: 720,
            frameRate: 60,
            codecs: 'avc1.640020,mp4a.40.2',
            candidates: [
              TwitchPlaybackCandidate(
                playlistUrl: '$base/720-primary.m3u8',
                headers: const {},
                playerType: 'embed',
                platform: 'web',
                lineLabel: '优选 Embed',
                bandwidth: 3200000,
                width: 1280,
                height: 720,
                frameRate: 60,
                codecs: 'avc1.640020,mp4a.40.2',
              ),
              TwitchPlaybackCandidate(
                playlistUrl: '$base/720-backup.m3u8',
                headers: const {},
                playerType: 'site',
                platform: 'web',
                lineLabel: '备用 Site',
                bandwidth: 3200000,
                width: 1280,
                height: 720,
                frameRate: 60,
                codecs: 'avc1.640020,mp4a.40.2',
              ),
            ],
          ).toJson(),
          TwitchPlaybackQualityGroup(
            id: '480p',
            label: '480p',
            sortOrder: 480,
            bandwidth: 1800000,
            width: 854,
            height: 480,
            frameRate: 30,
            codecs: 'avc1.64001f,mp4a.40.2',
            candidates: [
              TwitchPlaybackCandidate(
                playlistUrl: '$base/480-primary.m3u8',
                headers: const {},
                playerType: 'embed',
                platform: 'web',
                lineLabel: '优选 Embed',
                bandwidth: 1800000,
                width: 854,
                height: 480,
                frameRate: 30,
                codecs: 'avc1.64001f,mp4a.40.2',
              ),
            ],
          ).toJson(),
        ],
        'twitchPlaybackCandidates': [
          TwitchPlaybackCandidate(
            playlistUrl: '$base/master-primary.m3u8',
            headers: const {},
            playerType: 'embed',
            platform: 'web',
            lineLabel: '优选 Embed',
          ).toJson(),
          TwitchPlaybackCandidate(
            playlistUrl: '$base/master-backup.m3u8',
            headers: const {},
            playerType: 'site',
            platform: 'web',
            lineLabel: '备用 Site',
          ).toJson(),
        ],
      },
    );

    final wrapped = await proxy.wrapPlayUrls(
      quality: autoQuality,
      playUrls: [
        LivePlayUrl(
          url: '$base/master-primary.m3u8',
          lineLabel: '优选 Embed',
          metadata: const {'playerType': 'embed'},
        ),
        LivePlayUrl(
          url: '$base/master-backup.m3u8',
          lineLabel: '备用 Site',
          metadata: const {'playerType': 'site'},
        ),
      ],
    );

    final masterText = await _readText(Uri.parse(wrapped.first.url));
    expect(masterText, contains('#EXT-X-STREAM-INF'));
    expect(masterText, contains('/variant/'));

    final variantUrl = masterText
        .split(RegExp(r'\r?\n'))
        .firstWhere((line) => line.contains('/variant/'));
    final variantText = await _readText(Uri.parse(variantUrl));
    expect(variantText, isNot(contains('stitched-ad')));
    expect(variantText, contains('/asset/'));
  });

  test('auto proxy writes lower quality variants first for faster startup',
      () async {
    upstream.listen((request) async {
      switch (request.uri.path) {
        case '/1080.m3u8':
          request.response.write(_cleanPlaylist(segmentPath: '/1080.ts'));
          break;
        case '/480.m3u8':
          request.response.write(_cleanPlaylist(segmentPath: '/480.ts'));
          break;
        case '/1080.ts':
          request.response.add(utf8.encode('1080'));
          break;
        case '/480.ts':
          request.response.add(utf8.encode('480'));
          break;
        default:
          request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });

    final base = 'http://${upstream.address.address}:${upstream.port}';
    final autoQuality = LivePlayQuality(
      id: 'auto',
      label: 'Auto',
      metadata: {
        'twitchPlaybackGroups': [
          TwitchPlaybackQualityGroup(
            id: '1080p',
            label: '1080p60',
            sortOrder: 1080,
            bandwidth: 5200000,
            width: 1920,
            height: 1080,
            frameRate: 60,
            codecs: 'avc1.640028,mp4a.40.2',
            candidates: [
              TwitchPlaybackCandidate(
                playlistUrl: '$base/1080.m3u8',
                headers: const {},
                playerType: 'popout',
                platform: 'web',
                lineLabel: '默认 Popout',
                bandwidth: 5200000,
                width: 1920,
                height: 1080,
                frameRate: 60,
                codecs: 'avc1.640028,mp4a.40.2',
              ),
            ],
          ).toJson(),
          TwitchPlaybackQualityGroup(
            id: '480p',
            label: '480p',
            sortOrder: 480,
            bandwidth: 1800000,
            width: 854,
            height: 480,
            frameRate: 30,
            codecs: 'avc1.64001f,mp4a.40.2',
            candidates: [
              TwitchPlaybackCandidate(
                playlistUrl: '$base/480.m3u8',
                headers: const {},
                playerType: 'embed',
                platform: 'web',
                lineLabel: '备用 Embed',
                bandwidth: 1800000,
                width: 854,
                height: 480,
                frameRate: 30,
                codecs: 'avc1.64001f,mp4a.40.2',
              ),
            ],
          ).toJson(),
        ],
        'twitchPlaybackCandidates': [
          TwitchPlaybackCandidate(
            playlistUrl: '$base/master-popout.m3u8',
            headers: const {},
            playerType: 'popout',
            platform: 'web',
            lineLabel: '默认 Popout',
          ).toJson(),
        ],
      },
    );

    final wrapped = await proxy.wrapPlayUrls(
      quality: autoQuality,
      playUrls: [
        LivePlayUrl(
          url: '$base/master-popout.m3u8',
          lineLabel: '默认 Popout',
          metadata: const {'playerType': 'popout'},
        ),
      ],
    );

    final masterText = await _readText(Uri.parse(wrapped.first.url));
    final variants = masterText
        .split(RegExp(r'\r?\n'))
        .where((line) => line.contains('/variant/'))
        .toList(growable: false);

    expect(variants, hasLength(2));
    expect(variants.first, contains('/variant/480p.m3u8'));
    expect(variants.last, contains('/variant/1080p.m3u8'));
  });

  test('startup auto proxy keeps a low-latency ladder before promotion',
      () async {
    upstream.listen((request) async {
      switch (request.uri.path) {
        case '/160.m3u8':
          request.response.write(_cleanPlaylist(segmentPath: '/160.ts'));
          break;
        case '/360.m3u8':
          request.response.write(_cleanPlaylist(segmentPath: '/360.ts'));
          break;
        case '/1080.m3u8':
          request.response.write(_cleanPlaylist(segmentPath: '/1080.ts'));
          break;
        case '/160.ts':
          request.response.add(utf8.encode('160'));
          break;
        case '/360.ts':
          request.response.add(utf8.encode('360'));
          break;
        case '/1080.ts':
          request.response.add(utf8.encode('1080'));
          break;
        default:
          request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });

    final base = 'http://${upstream.address.address}:${upstream.port}';
    final autoQuality = LivePlayQuality(
      id: 'auto',
      label: 'Auto',
      metadata: {
        'twitchStartupAuto': true,
        'twitchPlaybackGroups': [
          TwitchPlaybackQualityGroup(
            id: '160p',
            label: '160p',
            sortOrder: 160,
            bandwidth: 300000,
            width: 284,
            height: 160,
            frameRate: 30,
            codecs: 'avc1.42c00d,mp4a.40.2',
            candidates: [
              TwitchPlaybackCandidate(
                playlistUrl: '$base/160.m3u8',
                headers: const {},
                playerType: 'popout',
                platform: 'web',
                lineLabel: '默认 Popout',
                bandwidth: 300000,
                width: 284,
                height: 160,
                frameRate: 30,
                codecs: 'avc1.42c00d,mp4a.40.2',
              ),
            ],
          ).toJson(),
          TwitchPlaybackQualityGroup(
            id: '360p',
            label: '360p',
            sortOrder: 360,
            bandwidth: 800000,
            width: 640,
            height: 360,
            frameRate: 30,
            codecs: 'avc1.4d401f,mp4a.40.2',
            candidates: [
              TwitchPlaybackCandidate(
                playlistUrl: '$base/360.m3u8',
                headers: const {},
                playerType: 'site',
                platform: 'web',
                lineLabel: '备用 Site',
                bandwidth: 800000,
                width: 640,
                height: 360,
                frameRate: 30,
                codecs: 'avc1.4d401f,mp4a.40.2',
              ),
            ],
          ).toJson(),
          TwitchPlaybackQualityGroup(
            id: '1080p',
            label: '1080p60',
            sortOrder: 1080,
            bandwidth: 5200000,
            width: 1920,
            height: 1080,
            frameRate: 60,
            codecs: 'avc1.640028,mp4a.40.2',
            candidates: [
              TwitchPlaybackCandidate(
                playlistUrl: '$base/1080.m3u8',
                headers: const {},
                playerType: 'popout',
                platform: 'web',
                lineLabel: '默认 Popout',
                bandwidth: 5200000,
                width: 1920,
                height: 1080,
                frameRate: 60,
                codecs: 'avc1.640028,mp4a.40.2',
              ),
            ],
          ).toJson(),
        ],
        'twitchPlaybackCandidates': [
          TwitchPlaybackCandidate(
            playlistUrl: '$base/master-popout.m3u8',
            headers: const {},
            playerType: 'popout',
            platform: 'web',
            lineLabel: '默认 Popout',
          ).toJson(),
        ],
      },
    );

    final wrapped = await proxy.wrapPlayUrls(
      quality: autoQuality,
      playUrls: [
        LivePlayUrl(
          url: '$base/master-popout.m3u8',
          lineLabel: '默认 Popout',
          metadata: const {'playerType': 'popout'},
        ),
      ],
    );

    final masterText = await _readText(Uri.parse(wrapped.first.url));
    final variants = masterText
        .split(RegExp(r'\r?\n'))
        .where((line) => line.contains('/variant/'))
        .toList(growable: false);

    expect(variants, hasLength(2));
    expect(variants.first, contains('/variant/160p.m3u8'));
    expect(variants.last, contains('/variant/360p.m3u8'));
    expect(masterText, isNot(contains('/variant/1080p.m3u8')));
  });

  test('auto proxy prefers non-hevc candidates for mixed codec groups',
      () async {
    upstream.listen((request) async {
      switch (request.uri.path) {
        case '/1080-hevc.m3u8':
          request.response.write(_cleanPlaylist(segmentPath: '/1080-hevc.ts'));
          break;
        case '/1080-avc.m3u8':
          request.response.write(_cleanPlaylist(segmentPath: '/1080-avc.ts'));
          break;
        case '/1080-hevc.ts':
          request.response.add(utf8.encode('1080-hevc'));
          break;
        case '/1080-avc.ts':
          request.response.add(utf8.encode('1080-avc'));
          break;
        default:
          request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });

    final base = 'http://${upstream.address.address}:${upstream.port}';
    final autoQuality = LivePlayQuality(
      id: 'auto',
      label: 'Auto',
      metadata: {
        'twitchPlaybackGroups': [
          TwitchPlaybackQualityGroup(
            id: '1080p',
            label: '1080p60',
            sortOrder: 1080,
            bandwidth: 5200000,
            width: 1920,
            height: 1080,
            frameRate: 60,
            codecs: 'hvc1.1.6.L123.B0,mp4a.40.2',
            candidates: [
              TwitchPlaybackCandidate(
                playlistUrl: '$base/1080-hevc.m3u8',
                headers: const {},
                playerType: 'popout',
                platform: 'web',
                lineLabel: '默认 Popout',
                bandwidth: 5200000,
                width: 1920,
                height: 1080,
                frameRate: 60,
                codecs: 'hvc1.1.6.L123.B0,mp4a.40.2',
              ),
              TwitchPlaybackCandidate(
                playlistUrl: '$base/1080-avc.m3u8',
                headers: const {},
                playerType: 'embed',
                platform: 'web',
                lineLabel: '优选 Embed',
                bandwidth: 5000000,
                width: 1920,
                height: 1080,
                frameRate: 60,
                codecs: 'avc1.640028,mp4a.40.2',
              ),
            ],
          ).toJson(),
        ],
        'twitchPlaybackCandidates': [
          TwitchPlaybackCandidate(
            playlistUrl: '$base/master-popout.m3u8',
            headers: const {},
            playerType: 'popout',
            platform: 'web',
            lineLabel: '默认 Popout',
          ).toJson(),
        ],
      },
    );

    final wrapped = await proxy.wrapPlayUrls(
      quality: autoQuality,
      playUrls: [
        LivePlayUrl(
          url: '$base/master-popout.m3u8',
          lineLabel: '默认 Popout',
          metadata: const {'playerType': 'popout'},
        ),
      ],
    );

    final masterText = await _readText(Uri.parse(wrapped.first.url));
    expect(masterText, contains('CODECS="avc1.640028,mp4a.40.2"'));
    expect(masterText, isNot(contains('hvc1.1.6.L123.B0')));

    final variantUrl = masterText
        .split(RegExp(r'\r?\n'))
        .firstWhere((line) => line.contains('/variant/'));
    final variantText = await _readText(Uri.parse(variantUrl));
    final assetUrl = _firstAssetUrl(variantText);
    final assetBytes = await _readBytes(Uri.parse(assetUrl));
    expect(utf8.decode(assetBytes), '1080-avc');
  });

  test(
      'fixed quality proxy prefers backup with live segments over popout ad stream',
      () async {
    upstream.listen((request) async {
      switch (request.uri.path) {
        case '/popout.m3u8':
          request.response.write(_adPlaylist(segmentPath: '/popout-ad.ts'));
          break;
        case '/embed.m3u8':
          request.response.write(_mixedPlaylist(
            adSegmentPath: '/embed-ad.ts',
            liveSegmentPath: '/embed-live.ts',
          ));
          break;
        case '/embed-live.ts':
          request.response.add(utf8.encode('embed-live'));
          break;
        default:
          request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });

    final base = 'http://${upstream.address.address}:${upstream.port}';
    final quality = LivePlayQuality(
      id: '1080p60',
      label: '1080p60',
      metadata: {
        'twitchPlaybackGroup': TwitchPlaybackQualityGroup(
          id: '1080p60',
          label: '1080p60',
          sortOrder: 1080,
          candidates: [
            TwitchPlaybackCandidate(
              playlistUrl: '$base/popout.m3u8',
              headers: const {},
              playerType: 'popout',
              platform: 'web',
              lineLabel: '默认 Popout',
            ),
            TwitchPlaybackCandidate(
              playlistUrl: '$base/embed.m3u8',
              headers: const {},
              playerType: 'embed',
              platform: 'web',
              lineLabel: '备用 Embed',
            ),
          ],
        ).toJson(),
      },
    );

    final wrapped = await proxy.wrapPlayUrls(
      quality: quality,
      playUrls: [
        LivePlayUrl(
          url: '$base/popout.m3u8',
          lineLabel: '默认 Popout',
          metadata: const {'playerType': 'popout'},
        ),
        LivePlayUrl(
          url: '$base/embed.m3u8',
          lineLabel: '备用 Embed',
          metadata: const {'playerType': 'embed'},
        ),
      ],
    );

    final playlistText = await _readText(Uri.parse(wrapped.first.url));
    expect(playlistText, isNot(contains('stitched-ad')));
    final assetUrl = _firstAssetUrl(playlistText);
    final assetBytes = await _readBytes(Uri.parse(assetUrl));
    expect(utf8.decode(assetBytes), 'embed-live');
  });

  test(
      'fixed quality proxy waits for delayed live segments before returning ad fallback',
      () async {
    var popoutRequests = 0;
    var siteRequests = 0;
    upstream.listen((request) async {
      switch (request.uri.path) {
        case '/delayed-popout.m3u8':
          popoutRequests += 1;
          request.response
              .write(_adPlaylist(segmentPath: '/delayed-popout-ad.ts'));
          break;
        case '/delayed-site.m3u8':
          siteRequests += 1;
          request.response.write(
            siteRequests >= 3
                ? _mixedPlaylist(
                    adSegmentPath: '/delayed-site-ad.ts',
                    liveSegmentPath: '/delayed-site-live.ts',
                  )
                : _adPlaylist(segmentPath: '/delayed-site-ad.ts'),
          );
          break;
        case '/delayed-site-live.ts':
          request.response.add(utf8.encode('delayed-site-live'));
          break;
        default:
          request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });

    final base = 'http://${upstream.address.address}:${upstream.port}';
    final quality = LivePlayQuality(
      id: '720p',
      label: '720p',
      metadata: {
        'twitchPlaybackGroup': TwitchPlaybackQualityGroup(
          id: '720p',
          label: '720p',
          sortOrder: 720,
          candidates: [
            TwitchPlaybackCandidate(
              playlistUrl: '$base/delayed-popout.m3u8',
              headers: const {},
              playerType: 'popout',
              platform: 'web',
              lineLabel: '默认 Popout',
            ),
            TwitchPlaybackCandidate(
              playlistUrl: '$base/delayed-site.m3u8',
              headers: const {},
              playerType: 'site',
              platform: 'web',
              lineLabel: '备用 Site',
            ),
          ],
        ).toJson(),
      },
    );

    final wrapped = await proxy.wrapPlayUrls(
      quality: quality,
      playUrls: [
        LivePlayUrl(
          url: '$base/delayed-popout.m3u8',
          lineLabel: '默认 Popout',
          metadata: const {'playerType': 'popout'},
        ),
        LivePlayUrl(
          url: '$base/delayed-site.m3u8',
          lineLabel: '备用 Site',
          metadata: const {'playerType': 'site'},
        ),
      ],
    );

    final playlistText = await _readText(Uri.parse(wrapped.first.url));
    expect(playlistText, isNot(contains('stitched-ad')));
    final assetUrl = _firstAssetUrl(playlistText);
    final assetBytes = await _readBytes(Uri.parse(assetUrl));
    expect(utf8.decode(assetBytes), 'delayed-site-live');
    expect(popoutRequests, greaterThanOrEqualTo(3));
    expect(siteRequests, greaterThanOrEqualTo(3));
  });

  test(
      'fixed quality proxy retries clean prefetch-only playlist until live segments arrive',
      () async {
    var requestCount = 0;
    upstream.listen((request) async {
      switch (request.uri.path) {
        case '/prefetch-first.m3u8':
          requestCount += 1;
          request.response.write(
            requestCount >= 3
                ? _blankTitleLivePlaylist(segmentPath: '/prefetch-live.ts')
                : _prefetchOnlyPlaylist(segmentPath: '/prefetch.ts'),
          );
          break;
        case '/prefetch-live.ts':
          request.response.add(utf8.encode('prefetch-live'));
          break;
        default:
          request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });

    final base = 'http://${upstream.address.address}:${upstream.port}';
    final quality = LivePlayQuality(
      id: '720p',
      label: '720p',
      metadata: {
        'twitchPlaybackGroup': TwitchPlaybackQualityGroup(
          id: '720p',
          label: '720p',
          sortOrder: 720,
          candidates: [
            TwitchPlaybackCandidate(
              playlistUrl: '$base/prefetch-first.m3u8',
              headers: const {},
              playerType: 'popout',
              platform: 'web',
              lineLabel: '默认 Popout',
            ),
          ],
        ).toJson(),
      },
    );

    final wrapped = await proxy.wrapPlayUrls(
      quality: quality,
      playUrls: [
        LivePlayUrl(
          url: '$base/prefetch-first.m3u8',
          lineLabel: '默认 Popout',
          metadata: const {'playerType': 'popout'},
        ),
      ],
    );

    final playlistText = await _readText(Uri.parse(wrapped.first.url));
    expect(playlistText, isNot(contains('#EXT-X-TWITCH-PREFETCH')));
    final assetUrl = _firstAssetUrl(playlistText);
    final assetBytes = await _readBytes(Uri.parse(assetUrl));
    expect(utf8.decode(assetBytes), 'prefetch-live');
    expect(requestCount, greaterThanOrEqualTo(3));
  });

  test('fixed quality proxy keeps blank-title live segment after stripping ads',
      () async {
    upstream.listen((request) async {
      switch (request.uri.path) {
        case '/blank-title.m3u8':
          request.response.write(
            _mixedBlankTitlePlaylist(
              adSegmentPath: '/blank-ad.ts',
              liveSegmentPath: '/blank-live.ts',
            ),
          );
          break;
        case '/blank-live.ts':
          request.response.add(utf8.encode('blank-live'));
          break;
        default:
          request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });

    final base = 'http://${upstream.address.address}:${upstream.port}';
    final quality = LivePlayQuality(
      id: '1080p60',
      label: '1080p60',
      metadata: {
        'twitchPlaybackGroup': TwitchPlaybackQualityGroup(
          id: '1080p60',
          label: '1080p60',
          sortOrder: 1080,
          candidates: [
            TwitchPlaybackCandidate(
              playlistUrl: '$base/blank-title.m3u8',
              headers: const {},
              playerType: 'site',
              platform: 'web',
              lineLabel: '备用 Site',
            ),
          ],
        ).toJson(),
      },
    );

    final wrapped = await proxy.wrapPlayUrls(
      quality: quality,
      playUrls: [
        LivePlayUrl(
          url: '$base/blank-title.m3u8',
          lineLabel: '备用 Site',
          metadata: const {'playerType': 'site'},
        ),
      ],
    );

    final playlistText = await _readText(Uri.parse(wrapped.first.url));
    expect(playlistText, contains('#EXT-X-DISCONTINUITY'));
    final assetUrl = _firstAssetUrl(playlistText);
    final assetBytes = await _readBytes(Uri.parse(assetUrl));
    expect(utf8.decode(assetBytes), 'blank-live');
  });
}

String _adPlaylist({required String segmentPath}) {
  return [
    '#EXTM3U',
    '#EXT-X-TARGETDURATION:2',
    '#EXT-X-VERSION:3',
    '#EXT-X-DATERANGE:CLASS="twitch-stitched-ad"',
    '#EXT-X-CUE-OUT:30.0',
    '#EXTINF:2.0,live',
    segmentPath,
  ].join('\n');
}

String _cleanPlaylist({required String segmentPath}) {
  return [
    '#EXTM3U',
    '#EXT-X-TARGETDURATION:2',
    '#EXT-X-VERSION:3',
    '#EXTINF:2.0,live',
    segmentPath,
  ].join('\n');
}

String _mixedPlaylist({
  required String adSegmentPath,
  required String liveSegmentPath,
}) {
  return [
    '#EXTM3U',
    '#EXT-X-TARGETDURATION:2',
    '#EXT-X-VERSION:3',
    '#EXT-X-DATERANGE:CLASS="twitch-stitched-ad"',
    '#EXT-X-CUE-OUT:30.0',
    '#EXTINF:2.0,ad',
    adSegmentPath,
    '#EXT-X-CUE-IN',
    '#EXTINF:2.0,live',
    liveSegmentPath,
  ].join('\n');
}

String _mixedBlankTitlePlaylist({
  required String adSegmentPath,
  required String liveSegmentPath,
}) {
  return [
    '#EXTM3U',
    '#EXT-X-TARGETDURATION:2',
    '#EXT-X-VERSION:3',
    '#EXT-X-DATERANGE:CLASS="twitch-stitched-ad"',
    '#EXT-X-CUE-OUT:30.0',
    '#EXTINF:2.0,Amazon stitched ad',
    adSegmentPath,
    '#EXT-X-CUE-IN',
    '#EXTINF:2.0,',
    liveSegmentPath,
  ].join('\n');
}

String _prefetchOnlyPlaylist({required String segmentPath}) {
  return [
    '#EXTM3U',
    '#EXT-X-TARGETDURATION:2',
    '#EXT-X-VERSION:3',
    '#EXT-X-TWITCH-PREFETCH:$segmentPath',
  ].join('\n');
}

String _blankTitleLivePlaylist({required String segmentPath}) {
  return [
    '#EXTM3U',
    '#EXT-X-TARGETDURATION:2',
    '#EXT-X-VERSION:3',
    '#EXTINF:2.0,',
    segmentPath,
  ].join('\n');
}

String _firstAssetUrl(String playlistText) {
  return playlistText
      .split(RegExp(r'\r?\n'))
      .firstWhere((line) => line.contains('/asset/'));
}

Future<String> _readText(Uri uri) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    final response = await request.close();
    return utf8.decode(await consolidateHttpClientResponseBytes(response));
  } finally {
    client.close(force: true);
  }
}

Future<List<int>> _readBytes(Uri uri) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    final response = await request.close();
    return await consolidateHttpClientResponseBytes(response);
  } finally {
    client.close(force: true);
  }
}
