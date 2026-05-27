import 'dart:io';

import 'package:nolive_app/src/app/platform/app_platform_capabilities.dart';

bool supportsLocalSyncPairingScanner() {
  final platform = AppPlatformCapabilities.current();
  return platform.isWeb || platform.isMobile;
}

String currentLocalSyncPlatformName() {
  return AppPlatformCapabilities.current().operatingSystem;
}

Future<List<String>> readLocalIPv4Addresses() async {
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    ).timeout(const Duration(seconds: 2), onTimeout: () => const []);
    final addresses = <String>{};
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        if (address.address.trim().isEmpty || address.isLoopback) {
          continue;
        }
        addresses.add(address.address);
      }
    }
    final sorted = addresses.toList()..sort();
    return sorted;
  } catch (_) {
    return const [];
  }
}
