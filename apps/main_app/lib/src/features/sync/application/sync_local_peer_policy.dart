import 'package:live_sync/live_sync.dart';

/// Pairing-code and peer-identity rules for local (LAN) sync.
///
/// These lived inside sync_local_page.dart — a 1,273 line StatefulWidget — so
/// the pairing URI format and, more importantly, the "is this peer actually
/// me?" test could only be exercised by mounting the page and tapping through
/// it. Getting self-detection wrong shows the device to itself as a sync
/// target, and syncing a device with itself is how follow lists and watch
/// history get duplicated.

/// A decoded `nolive-sync://pair` payload.
class SyncPairingPayload {
  const SyncPairingPayload({required this.accessToken, this.host, this.port});

  final String accessToken;
  final String? host;
  final int? port;

  @override
  bool operator ==(Object other) =>
      other is SyncPairingPayload &&
      other.accessToken == accessToken &&
      other.host == host &&
      other.port == port;

  @override
  int get hashCode => Object.hash(accessToken, host, port);

  @override
  String toString() =>
      'SyncPairingPayload(accessToken: $accessToken, host: $host, port: $port)';
}

/// Strips the scheme prefix and the human-readable grouping from a code.
String normalizeBareSyncPairingCode(String value) {
  return value
      .trim()
      .replaceFirst(RegExp(r'^nolive-sync:', caseSensitive: false), '')
      .replaceAll(RegExp(r'[\s-]'), '');
}

/// Decodes either a full `nolive-sync://pair?...` URI or a bare access token.
///
/// [allowBareToken] is false when the input came from a QR scan: a scanner can
/// read any barcode in frame, so accepting arbitrary text as a pairing token
/// would let an unrelated code silently point sync at a stranger's device.
SyncPairingPayload? parseSyncPairingPayload(
  String value, {
  bool allowBareToken = true,
}) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return null;
  }

  final uri = Uri.tryParse(trimmed);
  if (uri != null &&
      uri.scheme.toLowerCase() == 'nolive-sync' &&
      uri.host == 'pair') {
    final token = normalizeBareSyncPairingCode(
      uri.queryParameters['token'] ?? uri.queryParameters['accessToken'] ?? '',
    );
    if (token.isEmpty) {
      return null;
    }
    final host = uri.queryParameters['host'] ?? uri.queryParameters['address'];
    final normalizedHost = host?.trim();
    return SyncPairingPayload(
      accessToken: token,
      host: normalizedHost == null || normalizedHost.isEmpty
          ? null
          : normalizedHost,
      port: int.tryParse(uri.queryParameters['port'] ?? ''),
    );
  }

  if (!allowBareToken && !trimmed.toLowerCase().startsWith('nolive-sync:')) {
    return null;
  }

  final token = normalizeBareSyncPairingCode(trimmed);
  return token.isEmpty ? null : SyncPairingPayload(accessToken: token);
}

/// The bare access token carried by [value], or empty when it decodes to none.
String normalizeSyncPairingCode(String value) {
  return parseSyncPairingPayload(value)?.accessToken ?? '';
}

/// The access token in 4-character groups, for display and manual entry.
String formatSyncPairingCode(String value) {
  final normalized = normalizeSyncPairingCode(value);
  if (normalized.isEmpty) {
    return '';
  }
  final buffer = StringBuffer();
  for (var index = 0; index < normalized.length; index += 4) {
    if (index > 0) {
      buffer.write('-');
    }
    final end = (index + 4).clamp(0, normalized.length).toInt();
    buffer.write(normalized.substring(index, end));
  }
  return buffer.toString();
}

/// The QR payload this device advertises for pairing.
String buildSyncPairingQrData({
  required String deviceName,
  required List<String> addresses,
  required int port,
  required String accessToken,
}) {
  return Uri(
    scheme: 'nolive-sync',
    host: 'pair',
    queryParameters: <String, String>{
      if (addresses.isNotEmpty) 'host': addresses.first,
      'port': port.toString(),
      'token': accessToken,
      'name': deviceName,
    },
  ).toString();
}

/// Sync endpoints this device can be reached on.
List<String> syncShareableEndpoints({
  required List<String> addresses,
  required int port,
}) {
  if (addresses.isEmpty) {
    return const <String>[];
  }
  return addresses
      .map((address) => 'http://$address:$port/snapshot')
      .toList(growable: false);
}

/// Whether [peer] is this device rather than another one on the network.
///
/// Identity is checked three ways because discovery can surface the same
/// machine under different names: the literal `self` sentinel written by older
/// builds, the current device id, and finally address+port — a peer answering
/// on this device's own port at one of its own addresses is this device, no
/// matter what id it announced.
bool isSelfSyncPeer(
  DiscoveredPeer peer, {
  required String? selfDeviceId,
  required int selfPort,
  required List<String> localAddresses,
}) {
  if (peer.deviceId == 'self' ||
      (selfDeviceId != null && peer.deviceId == selfDeviceId)) {
    return true;
  }
  if (peer.port != selfPort) {
    return false;
  }
  return localAddresses.any((address) => address == peer.address);
}

/// Nearby devices: this device removed, then deduplicated by `address:port`.
///
/// When two records share an endpoint the newer one wins, except that a real
/// discovered peer always displaces a `manual-peer` placeholder even if the
/// placeholder was seen more recently — the manually entered entry carries no
/// device name or platform.
List<DiscoveredPeer> dedupeRemoteSyncPeers(
  Iterable<DiscoveredPeer> peers, {
  required String? selfDeviceId,
  required int selfPort,
  required List<String> localAddresses,
}) {
  final byEndpoint = <String, DiscoveredPeer>{};
  for (final peer in peers) {
    if (isSelfSyncPeer(
      peer,
      selfDeviceId: selfDeviceId,
      selfPort: selfPort,
      localAddresses: localAddresses,
    )) {
      continue;
    }
    final key = '${peer.address}:${peer.port}';
    final existing = byEndpoint[key];
    if (existing == null ||
        peer.lastSeenAt.isAfter(existing.lastSeenAt) ||
        (existing.deviceId == 'manual-peer' &&
            peer.deviceId != 'manual-peer')) {
      byEndpoint[key] = peer;
    }
  }
  return byEndpoint.values.toList(growable: false);
}

/// Coarse "last seen" label. [now] is injected so the rule is testable.
String relativeLastSeenLabel(DateTime lastSeenAt, {required DateTime now}) {
  final diff = now.difference(lastSeenAt);
  if (diff.inSeconds < 5) {
    return '刚刚在线';
  }
  if (diff.inMinutes < 1) {
    return '${diff.inSeconds} 秒前';
  }
  if (diff.inHours < 1) {
    return '${diff.inMinutes} 分钟前';
  }
  return '${diff.inHours} 小时前';
}
