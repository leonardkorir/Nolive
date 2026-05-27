import 'package:flutter/foundation.dart';

bool supportsLocalSyncPairingScanner() {
  return kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
}

String currentLocalSyncPlatformName() {
  return kIsWeb ? 'web' : defaultTargetPlatform.name;
}

Future<List<String>> readLocalIPv4Addresses() async {
  return const [];
}
