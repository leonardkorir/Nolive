import 'package:flutter_test/flutter_test.dart';
import 'package:live_sync/live_sync.dart';
import 'package:nolive_app/src/features/sync/application/sync_local_peer_policy.dart';

DiscoveredPeer peer({
  String deviceId = 'peer-1',
  String address = '192.168.1.50',
  int port = 8848,
  DateTime? lastSeenAt,
}) {
  return DiscoveredPeer(
    deviceId: deviceId,
    displayName: deviceId,
    address: address,
    port: port,
    lastSeenAt: lastSeenAt ?? DateTime(2026, 7, 26, 12),
  );
}

void main() {
  group('parseSyncPairingPayload', () {
    test('decodes a full pairing URI', () {
      final payload = parseSyncPairingPayload(
        'nolive-sync://pair?host=192.168.1.10&port=8848&token=ABCD1234',
      );

      expect(payload?.accessToken, 'ABCD1234');
      expect(payload?.host, '192.168.1.10');
      expect(payload?.port, 8848);
    });

    test('accepts accessToken as an alias for token', () {
      expect(
        parseSyncPairingPayload(
          'nolive-sync://pair?accessToken=ABCD1234',
        )?.accessToken,
        'ABCD1234',
      );
    });

    test('accepts address as an alias for host', () {
      expect(
        parseSyncPairingPayload(
          'nolive-sync://pair?address=10.0.0.2&token=ABCD',
        )?.host,
        '10.0.0.2',
      );
    });

    test('strips the display grouping from the token', () {
      expect(
        parseSyncPairingPayload(
          'nolive-sync://pair?token=ABCD-1234-EFGH',
        )?.accessToken,
        'ABCD1234EFGH',
      );
    });

    test('a bare grouped token decodes by default', () {
      expect(parseSyncPairingPayload('ABCD-1234')?.accessToken, 'ABCD1234');
    });

    test('a scan refuses arbitrary text as a token', () {
      // A scanner reads whatever barcode is in frame. Accepting any string
      // would let an unrelated code silently point sync at another device.
      expect(
        parseSyncPairingPayload(
          'https://example.com/promo',
          allowBareToken: false,
        ),
        isNull,
      );
      expect(
        parseSyncPairingPayload('ABCD1234', allowBareToken: false),
        isNull,
      );
    });

    test('a scan still accepts a real pairing URI', () {
      expect(
        parseSyncPairingPayload(
          'nolive-sync://pair?token=ABCD1234',
          allowBareToken: false,
        )?.accessToken,
        'ABCD1234',
      );
    });

    test('empty and token-less inputs decode to nothing', () {
      expect(parseSyncPairingPayload(''), isNull);
      expect(parseSyncPairingPayload('   '), isNull);
      expect(parseSyncPairingPayload('nolive-sync://pair?port=8848'), isNull);
    });

    test('a missing or unparsable port stays null rather than guessing', () {
      expect(
        parseSyncPairingPayload('nolive-sync://pair?token=A')?.port,
        isNull,
      );
      expect(
        parseSyncPairingPayload('nolive-sync://pair?token=A&port=abc')?.port,
        isNull,
      );
    });

    test('the scheme is matched case-insensitively', () {
      expect(
        parseSyncPairingPayload('NOLIVE-SYNC://pair?token=ABCD')?.accessToken,
        'ABCD',
      );
    });
  });

  group('formatSyncPairingCode', () {
    test('groups the token in fours', () {
      expect(formatSyncPairingCode('ABCD1234EFGH'), 'ABCD-1234-EFGH');
    });

    test('a trailing partial group is kept whole', () {
      expect(formatSyncPairingCode('ABCD12'), 'ABCD-12');
    });

    test('formatting is idempotent', () {
      final once = formatSyncPairingCode('ABCD1234');
      expect(formatSyncPairingCode(once), once);
    });

    test('nothing decodable formats to empty', () {
      expect(formatSyncPairingCode(''), '');
      expect(formatSyncPairingCode('  -- '), '');
    });
  });

  group('buildSyncPairingQrData', () {
    test('round-trips through the parser', () {
      final data = buildSyncPairingQrData(
        deviceName: 'Desk',
        addresses: const ['192.168.1.10', '10.0.0.2'],
        port: 8848,
        accessToken: 'ABCD1234',
      );

      final parsed = parseSyncPairingPayload(data, allowBareToken: false);
      expect(parsed?.accessToken, 'ABCD1234');
      expect(
        parsed?.host,
        '192.168.1.10',
        reason: 'advertises the first address',
      );
      expect(parsed?.port, 8848);
    });

    test('omits the host when this device has no address yet', () {
      final data = buildSyncPairingQrData(
        deviceName: 'Desk',
        addresses: const [],
        port: 8848,
        accessToken: 'ABCD',
      );

      expect(parseSyncPairingPayload(data)?.host, isNull);
    });
  });

  group('isSelfSyncPeer', () {
    test('the legacy self sentinel is this device', () {
      expect(
        isSelfSyncPeer(
          peer(deviceId: 'self'),
          selfDeviceId: 'device-a',
          selfPort: 8848,
          localAddresses: const [],
        ),
        isTrue,
      );
    });

    test('a matching device id is this device', () {
      expect(
        isSelfSyncPeer(
          peer(deviceId: 'device-a'),
          selfDeviceId: 'device-a',
          selfPort: 8848,
          localAddresses: const [],
        ),
        isTrue,
      );
    });

    test(
      'this device is recognised by address and port even under a new id',
      () {
        // Discovery can re-announce the same machine with a fresh id; without
        // this the app offers to sync with itself.
        expect(
          isSelfSyncPeer(
            peer(deviceId: 'unknown-id', address: '192.168.1.50'),
            selfDeviceId: 'device-a',
            selfPort: 8848,
            localAddresses: const ['192.168.1.50'],
          ),
          isTrue,
        );
      },
    );

    test('the same address on another port is a different device', () {
      expect(
        isSelfSyncPeer(
          peer(deviceId: 'other', address: '192.168.1.50', port: 9999),
          selfDeviceId: 'device-a',
          selfPort: 8848,
          localAddresses: const ['192.168.1.50'],
        ),
        isFalse,
      );
    });

    test('a genuine peer is not this device', () {
      expect(
        isSelfSyncPeer(
          peer(deviceId: 'device-b', address: '192.168.1.77'),
          selfDeviceId: 'device-a',
          selfPort: 8848,
          localAddresses: const ['192.168.1.50'],
        ),
        isFalse,
      );
    });

    test('an unknown self id still allows address-based detection', () {
      expect(
        isSelfSyncPeer(
          peer(deviceId: 'anything', address: '192.168.1.50'),
          selfDeviceId: null,
          selfPort: 8848,
          localAddresses: const ['192.168.1.50'],
        ),
        isTrue,
      );
    });
  });

  group('dedupeRemoteSyncPeers', () {
    List<String> idsOf(Iterable<DiscoveredPeer> peers) =>
        peers.map((item) => item.deviceId).toList()..sort();

    test('this device never appears in nearby devices', () {
      final result = dedupeRemoteSyncPeers(
        [
          peer(deviceId: 'device-a'),
          peer(deviceId: 'device-b', address: '192.168.1.77'),
        ],
        selfDeviceId: 'device-a',
        selfPort: 8848,
        localAddresses: const [],
      );

      expect(idsOf(result), ['device-b']);
    });

    test('the newer record wins for one endpoint', () {
      final result = dedupeRemoteSyncPeers(
        [
          peer(deviceId: 'old', lastSeenAt: DateTime(2026, 7, 26, 11)),
          peer(deviceId: 'new', lastSeenAt: DateTime(2026, 7, 26, 12)),
        ],
        selfDeviceId: 'device-a',
        selfPort: 8848,
        localAddresses: const [],
      );

      expect(idsOf(result), ['new']);
    });

    test('a discovered peer displaces a stale manual entry', () {
      final result = dedupeRemoteSyncPeers(
        [
          peer(deviceId: 'manual-peer', lastSeenAt: DateTime(2026, 7, 26, 13)),
          peer(deviceId: 'real', lastSeenAt: DateTime(2026, 7, 26, 11)),
        ],
        selfDeviceId: 'device-a',
        selfPort: 8848,
        localAddresses: const [],
      );

      expect(
        idsOf(result),
        ['real'],
        reason:
            'the manual entry carries no device name or platform, so a real '
            'peer on the same endpoint is better even when seen earlier',
      );
    });

    test('different endpoints are kept apart', () {
      final result = dedupeRemoteSyncPeers(
        [
          peer(deviceId: 'a', address: '192.168.1.10'),
          peer(deviceId: 'b', address: '192.168.1.11'),
          peer(deviceId: 'c', address: '192.168.1.10', port: 9999),
        ],
        selfDeviceId: 'device-x',
        selfPort: 8848,
        localAddresses: const [],
      );

      expect(idsOf(result), ['a', 'b', 'c']);
    });

    test('an empty discovery list yields nothing', () {
      expect(
        dedupeRemoteSyncPeers(
          const <DiscoveredPeer>[],
          selfDeviceId: 'device-a',
          selfPort: 8848,
          localAddresses: const [],
        ),
        isEmpty,
      );
    });
  });

  group('syncShareableEndpoints', () {
    test('builds a snapshot URL per address', () {
      expect(
        syncShareableEndpoints(
          addresses: const ['192.168.1.10', '10.0.0.2'],
          port: 8848,
        ),
        ['http://192.168.1.10:8848/snapshot', 'http://10.0.0.2:8848/snapshot'],
      );
    });

    test('no addresses means nothing to share', () {
      expect(syncShareableEndpoints(addresses: const [], port: 8848), isEmpty);
    });
  });

  group('relativeLastSeenLabel', () {
    final now = DateTime(2026, 7, 26, 12);

    String label(Duration ago) =>
        relativeLastSeenLabel(now.subtract(ago), now: now);

    test('under five seconds reads as just now', () {
      expect(label(const Duration(seconds: 4)), '刚刚在线');
    });

    test('seconds, minutes and hours each get their own unit', () {
      expect(label(const Duration(seconds: 30)), '30 秒前');
      expect(label(const Duration(minutes: 5)), '5 分钟前');
      expect(label(const Duration(hours: 3)), '3 小时前');
    });

    test('boundaries fall on the coarser unit', () {
      expect(label(const Duration(seconds: 5)), '5 秒前');
      expect(label(const Duration(minutes: 1)), '1 分钟前');
      expect(label(const Duration(hours: 1)), '1 小时前');
    });

    test('very old timestamps keep counting in hours', () {
      expect(label(const Duration(days: 2)), '48 小时前');
    });
  });
}
