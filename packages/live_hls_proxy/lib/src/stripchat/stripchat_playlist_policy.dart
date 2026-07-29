/// Pure Stripchat LL-HLS decisions, lifted out of [StripchatLlHlsProxy].
///
/// The proxy is a ~3,600 line class holding a live HTTP server, a key cache and
/// a warm-up scheduler, so the rules below could only be reached by standing
/// the whole thing up — and none of them had direct coverage. They take plain
/// values and return plain values, so they can be asserted on their own.
library;

import 'dart:collection';

/// How aggressively a rendition is buffered and published.
///
/// Stripchat's high tier needs a longer runway before the first publish; the
/// low tier is served as soon as anything is cached.
enum StripchatTierClass { high, mid, low }

/// Classifies a media URI into a publish tier.
///
/// Matching is deliberately generous — the preferred variant id, the file name
/// and the whole path are all searched — because Stripchat labels the same
/// rendition differently across the master playlist, the media playlist and the
/// account's saved preference. A bare `{id}.m3u8` is Stripchat's "source" /
/// max progressive rendition, not a low tier.
///
/// A pinned rendition with no recognisable quality token resolves to [mid]
/// rather than [low]: under-buffering a high stream stalls, over-buffering a
/// low one only costs memory.
StripchatTierClass stripchatTierClassFor({
  required String preferredVariantId,
  required Uri mediaUri,
  required bool pinSingleRendition,
}) {
  final preferred = preferredVariantId.trim().toLowerCase();
  final path = mediaUri.path.toLowerCase();
  final file = mediaUri.pathSegments.isEmpty
      ? ''
      : mediaUri.pathSegments.last.toLowerCase();

  bool looksHigh(String s) =>
      s.contains('1080') ||
      s.contains('source') ||
      s == 'auto-max' ||
      RegExp(r'^\d+\.m3u8$').hasMatch(s);
  bool looksMid(String s) => s.contains('720');

  if (looksHigh(preferred) || looksHigh(file) || looksHigh(path)) {
    return StripchatTierClass.high;
  }
  if (looksMid(preferred) || looksMid(file) || looksMid(path)) {
    return StripchatTierClass.mid;
  }
  if (pinSingleRendition && preferred.isNotEmpty) {
    return StripchatTierClass.mid;
  }
  return StripchatTierClass.low;
}

/// Stable CDN TLD preference for host failover.
///
/// `.net` first because that is what the official web player uses; unknown
/// domains sort after the known ones, alphabetically, so the order is
/// deterministic rather than dependent on however the caller assembled its
/// list. Duplicates are dropped case-insensitively.
List<String> orderStripchatCdnDomains(Iterable<String> domains) {
  const rank = <String, int>{
    'doppiocdn.net': 0,
    'doppiocdn.org': 1,
    'doppiocdn.com': 2,
    'doppiocdn.media': 3,
  };
  final seen = <String>{};
  final ordered = <String>[];
  for (final domain in domains) {
    final normalized = domain.trim().toLowerCase();
    if (normalized.isEmpty || !seen.add(normalized)) {
      continue;
    }
    ordered.add(normalized);
  }
  ordered.sort((a, b) {
    final ra = rank[a] ?? 50;
    final rb = rank[b] ?? 50;
    return ra != rb ? ra.compareTo(rb) : a.compareTo(b);
  });
  return ordered;
}

/// Media asset ids within a playlist's asset list.
///
/// Stripchat emits the init/MAP segment first when a playlist carries more than
/// one asset, so everything after the first entry is media. A single-entry list
/// is media on its own — there is no MAP to drop.
List<String> stripchatMediaAssetIds(List<String> assetIds) {
  if (assetIds.isEmpty) {
    return const <String>[];
  }
  if (assetIds.length == 1) {
    return List<String>.from(assetIds);
  }
  return assetIds.sublist(1);
}

/// Host-failover candidates for a playlist URI.
///
/// Keeps the `media-hls.` / `edge-hls.` prefix of the original host and swaps
/// only the CDN domain, in [orderStripchatCdnDomains] order. Hosts already
/// tried — including the current one — are skipped so a retry loop cannot spin
/// on the same edge.
UnmodifiableListView<Uri> stripchatPlaylistFallbackUris({
  required Uri uri,
  required List<String> cdnDomains,
  Set<String> attemptedHosts = const <String>{},
}) {
  final host = uri.host.trim().toLowerCase();
  final prefix = host.startsWith('media-hls.')
      ? 'media-hls.'
      : host.startsWith('edge-hls.')
      ? 'edge-hls.'
      : '';
  final seenHosts = <String>{
    host,
    ...attemptedHosts.map((item) => item.toLowerCase()),
  };
  final fallbacks = <Uri>[];
  for (final domain in orderStripchatCdnDomains(cdnDomains)) {
    final candidateHost = '$prefix$domain';
    if (!seenHosts.add(candidateHost)) {
      continue;
    }
    fallbacks.add(
      uri.replace(
        host: candidateHost,
        path: uri.path,
        query: uri.hasQuery ? uri.query : null,
      ),
    );
  }
  return UnmodifiableListView<Uri>(fallbacks);
}
