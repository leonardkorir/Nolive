import 'package:live_hls_proxy/src/stripchat/stripchat_playlist_policy.dart';
import 'package:test/test.dart';

void main() {
  group('stripchatTierClassFor', () {
    StripchatTierClass classify(
      String path, {
      String preferred = '',
      bool pinned = false,
    }) {
      return stripchatTierClassFor(
        preferredVariantId: preferred,
        mediaUri: Uri.parse('https://media-hls.doppiocdn.net$path'),
        pinSingleRendition: pinned,
      );
    }

    test('1080 anywhere in the path is high', () {
      expect(classify('/hls/222064808/1080p.m3u8'), StripchatTierClass.high);
      expect(classify('/hls/1080/index.m3u8'), StripchatTierClass.high);
    });

    test('source renditions are high', () {
      expect(classify('/hls/222064808/source.m3u8'), StripchatTierClass.high);
    });

    test('a bare numeric playlist is the source rendition, not low', () {
      // Stripchat serves max progressive as `{id}.m3u8` with no quality token.
      // Reading that as "low" under-buffers the heaviest stream there is.
      expect(classify('/hls/222064808.m3u8'), StripchatTierClass.high);
    });

    test('auto-max as the preferred variant is high', () {
      expect(
        classify('/hls/222064808/index.m3u8', preferred: 'auto-max'),
        StripchatTierClass.high,
      );
    });

    test('720 is mid', () {
      expect(classify('/hls/222064808/720p.m3u8'), StripchatTierClass.mid);
    });

    test('high wins over mid when both tokens appear', () {
      expect(
        classify('/hls/720/1080p.m3u8'),
        StripchatTierClass.high,
        reason: 'buffering a 1080 stream as mid is the failure that stalls',
      );
    });

    test('the preferred variant id counts even when the path is plain', () {
      expect(
        classify('/hls/222064808/index.m3u8', preferred: '1080p60'),
        StripchatTierClass.high,
      );
      expect(
        classify('/hls/222064808/index.m3u8', preferred: '720p'),
        StripchatTierClass.mid,
      );
    });

    test('classification ignores case', () {
      expect(classify('/hls/222064808/SOURCE.M3U8'), StripchatTierClass.high);
    });

    test('a plain rendition with no pin is low', () {
      expect(classify('/hls/222064808/index.m3u8'), StripchatTierClass.low);
    });

    test('a pinned rendition with no quality token is mid, not low', () {
      // Over-buffering costs memory; under-buffering stalls. The safer guess
      // wins when the label says nothing.
      expect(
        classify('/hls/222064808/index.m3u8', preferred: 'fixed', pinned: true),
        StripchatTierClass.mid,
      );
    });

    test('pinning alone, with no preferred id, stays low', () {
      expect(
        classify('/hls/222064808/index.m3u8', pinned: true),
        StripchatTierClass.low,
      );
    });
  });

  group('orderStripchatCdnDomains', () {
    test('.net comes first because the official player uses it', () {
      expect(
        orderStripchatCdnDomains([
          'doppiocdn.media',
          'doppiocdn.com',
          'doppiocdn.net',
          'doppiocdn.org',
        ]),
        ['doppiocdn.net', 'doppiocdn.org', 'doppiocdn.com', 'doppiocdn.media'],
      );
    });

    test('unknown domains sort after known ones, alphabetically', () {
      expect(
        orderStripchatCdnDomains([
          'zzz.example',
          'aaa.example',
          'doppiocdn.com',
        ]),
        ['doppiocdn.com', 'aaa.example', 'zzz.example'],
      );
    });

    test('duplicates and case differences collapse', () {
      expect(
        orderStripchatCdnDomains([
          'DoppioCDN.NET',
          'doppiocdn.net',
          '  doppiocdn.net  ',
        ]),
        ['doppiocdn.net'],
      );
    });

    test('blank entries are dropped', () {
      expect(orderStripchatCdnDomains(['', '   ', 'doppiocdn.net']), [
        'doppiocdn.net',
      ]);
    });

    test('order does not depend on how the caller assembled the list', () {
      final a = orderStripchatCdnDomains(['doppiocdn.com', 'doppiocdn.net']);
      final b = orderStripchatCdnDomains(['doppiocdn.net', 'doppiocdn.com']);
      expect(a, b);
    });
  });

  group('stripchatMediaAssetIds', () {
    test('an empty list has no media', () {
      expect(stripchatMediaAssetIds(const []), isEmpty);
    });

    test('a single asset is media, with no MAP to drop', () {
      expect(stripchatMediaAssetIds(const ['a']), ['a']);
    });

    test('the first of several assets is the init segment', () {
      expect(stripchatMediaAssetIds(const ['map', 'a', 'b']), ['a', 'b']);
    });

    test('the input is not mutated', () {
      final input = ['map', 'a'];
      stripchatMediaAssetIds(input);
      expect(input, ['map', 'a']);
    });
  });

  group('stripchatPlaylistFallbackUris', () {
    Uri uri(String host) =>
        Uri.parse('https://$host/hls/222064808/index.m3u8?psch=v2');

    test('swaps the CDN domain and keeps the host prefix', () {
      final fallbacks = stripchatPlaylistFallbackUris(
        uri: uri('media-hls.doppiocdn.net'),
        cdnDomains: const ['doppiocdn.com', 'doppiocdn.org'],
      );

      expect(fallbacks.map((item) => item.host), [
        'media-hls.doppiocdn.org',
        'media-hls.doppiocdn.com',
      ]);
    });

    test('keeps the path and query untouched', () {
      final fallback = stripchatPlaylistFallbackUris(
        uri: uri('edge-hls.doppiocdn.net'),
        cdnDomains: const ['doppiocdn.com'],
      ).single;

      expect(fallback.host, 'edge-hls.doppiocdn.com');
      expect(fallback.path, '/hls/222064808/index.m3u8');
      expect(fallback.query, 'psch=v2');
    });

    test('never proposes the host it was already on', () {
      final fallbacks = stripchatPlaylistFallbackUris(
        uri: uri('media-hls.doppiocdn.net'),
        cdnDomains: const ['doppiocdn.net', 'doppiocdn.com'],
      );

      expect(fallbacks.map((item) => item.host), ['media-hls.doppiocdn.com']);
    });

    test('skips hosts a retry loop already tried', () {
      final fallbacks = stripchatPlaylistFallbackUris(
        uri: uri('media-hls.doppiocdn.net'),
        cdnDomains: const ['doppiocdn.org', 'doppiocdn.com'],
        attemptedHosts: {'media-hls.doppiocdn.org'},
      );

      expect(
        fallbacks.map((item) => item.host),
        ['media-hls.doppiocdn.com'],
        reason: 'a retry loop must not spin on an edge that already failed',
      );
    });

    test('a host with no recognised prefix gets bare domain candidates', () {
      final fallbacks = stripchatPlaylistFallbackUris(
        uri: uri('cdn.doppiocdn.net'),
        cdnDomains: const ['doppiocdn.com'],
      );

      expect(fallbacks.single.host, 'doppiocdn.com');
    });

    test(
      'exhausting every known domain yields nothing rather than looping',
      () {
        final fallbacks = stripchatPlaylistFallbackUris(
          uri: uri('media-hls.doppiocdn.net'),
          cdnDomains: const ['doppiocdn.net'],
        );

        expect(fallbacks, isEmpty);
      },
    );

    test('the result cannot be mutated by a caller', () {
      final fallbacks = stripchatPlaylistFallbackUris(
        uri: uri('media-hls.doppiocdn.net'),
        cdnDomains: const ['doppiocdn.com'],
      );

      expect(
        () => fallbacks.add(Uri.parse('https://x')),
        throwsUnsupportedError,
      );
    });
  });
}
