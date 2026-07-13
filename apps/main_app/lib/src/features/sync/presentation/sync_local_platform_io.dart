import 'dart:io';

import 'package:nolive_app/src/app/platform/app_platform_capabilities.dart';

bool supportsLocalSyncPairingScanner() {
  final platform = AppPlatformCapabilities.current();
  return platform.isWeb || platform.isMobile;
}

String currentLocalSyncPlatformName() {
  return AppPlatformCapabilities.current().operatingSystem;
}

/// Collect IPv4 addresses suitable for LAN sync sharing.
///
/// Filters loopback / link-local / Docker-like bridge gateways (e.g.
/// `172.19.0.1`), and ranks remaining addresses so real LAN
/// (`192.168` / `10.x`) wins over virtual NICs.
Future<List<String>> readLocalIPv4Addresses() async {
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    ).timeout(const Duration(seconds: 2), onTimeout: () => const []);
    final scored = <({String address, int score})>[];
    final seen = <String>{};
    for (final interface in interfaces) {
      final interfaceScore = scoreLocalNetworkInterfaceName(interface.name);
      for (final address in interface.addresses) {
        final raw = address.address.trim();
        if (raw.isEmpty || address.isLoopback) {
          continue;
        }
        if (!isShareableLocalIPv4Address(raw)) {
          continue;
        }
        if (!seen.add(raw)) {
          continue;
        }
        scored.add((
          address: raw,
          score: interfaceScore + scoreLocalIPv4Address(raw),
        ));
      }
    }
    scored.sort((left, right) {
      final byScore = right.score.compareTo(left.score);
      if (byScore != 0) {
        return byScore;
      }
      return left.address.compareTo(right.address);
    });
    return scored.map((entry) => entry.address).toList(growable: false);
  } catch (_) {
    return const [];
  }
}

/// Whether [address] may be advertised as a LAN sync endpoint.
bool isShareableLocalIPv4Address(String address) {
  final parts = address.split('.');
  if (parts.length != 4) {
    return false;
  }
  final octets = <int>[];
  for (final part in parts) {
    final value = int.tryParse(part);
    if (value == null || value < 0 || value > 255) {
      return false;
    }
    octets.add(value);
  }
  final a = octets[0];
  final b = octets[1];
  // Loopback
  if (a == 127) {
    return false;
  }
  // Link-local 169.254.0.0/16
  if (a == 169 && b == 254) {
    return false;
  }
  // Carrier / CGNAT 100.64.0.0/10
  if (a == 100 && b >= 64 && b <= 127) {
    return false;
  }
  // Multicast / reserved
  if (a >= 224) {
    return false;
  }
  // Docker-style bridge gateways: 172.16–31.0.0/1
  if (a == 172 && b >= 16 && b <= 31) {
    final c = octets[2];
    final d = octets[3];
    final looksLikeBridgeGateway = c == 0 && (d == 1 || d == 0);
    if (looksLikeBridgeGateway) {
      return false;
    }
  }
  return true;
}

/// Higher score = preferred for display / self-peer host selection.
int scoreLocalIPv4Address(String address) {
  final parts = address.split('.');
  if (parts.length != 4) {
    return 0;
  }
  final a = int.tryParse(parts[0]) ?? 0;
  final b = int.tryParse(parts[1]) ?? 0;
  if (a == 192 && b == 168) {
    return 100;
  }
  if (a == 10) {
    return 90;
  }
  if (a == 172 && b >= 16 && b <= 31) {
    return 40;
  }
  return 20;
}

int scoreLocalNetworkInterfaceName(String name) {
  final normalized = name.trim().toLowerCase();
  if (normalized.isEmpty) {
    return 0;
  }
  const preferred = <String>['wlan', 'wifi', 'en0', 'eth', 'rmnet_data', 'wlp'];
  for (final token in preferred) {
    if (normalized.contains(token)) {
      return 30;
    }
  }
  const virtual = <String>[
    'docker',
    'br-',
    'veth',
    'virbr',
    'vmnet',
    'vbox',
    'tun',
    'tap',
    'wg',
    'tailscale',
    'utun',
    'dummy',
    'lxc',
    'cni',
  ];
  for (final token in virtual) {
    if (normalized.contains(token)) {
      return -80;
    }
  }
  return 0;
}
