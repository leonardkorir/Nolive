import 'package:flutter_test/flutter_test.dart';
import 'package:nolive_app/src/features/sync/presentation/sync_local_platform_io.dart';

void main() {
  group('isShareableLocalIPv4Address', () {
    test('accepts common private LAN addresses', () {
      expect(isShareableLocalIPv4Address('192.168.1.23'), isTrue);
      expect(isShareableLocalIPv4Address('10.0.0.8'), isTrue);
      expect(isShareableLocalIPv4Address('172.16.5.10'), isTrue);
    });

    test('rejects loopback link-local docker bridge gateways', () {
      expect(isShareableLocalIPv4Address('127.0.0.1'), isFalse);
      expect(isShareableLocalIPv4Address('169.254.1.1'), isFalse);
      expect(isShareableLocalIPv4Address('172.19.0.1'), isFalse);
      expect(isShareableLocalIPv4Address('172.17.0.1'), isFalse);
      expect(isShareableLocalIPv4Address('100.64.1.2'), isFalse);
    });
  });

  group('scoreLocalIPv4Address', () {
    test('prefers 192.168 over docker-like 172 ranges', () {
      expect(
        scoreLocalIPv4Address('192.168.0.12'),
        greaterThan(scoreLocalIPv4Address('172.20.1.5')),
      );
      expect(
        scoreLocalIPv4Address('10.0.0.3'),
        greaterThan(scoreLocalIPv4Address('172.20.1.5')),
      );
    });
  });

  group('scoreLocalNetworkInterfaceName', () {
    test('penalizes virtual adapters', () {
      expect(
        scoreLocalNetworkInterfaceName('wlan0'),
        greaterThan(scoreLocalNetworkInterfaceName('docker0')),
      );
      expect(scoreLocalNetworkInterfaceName('br-abc123'), lessThan(0));
    });
  });
}
