import 'dart:io';

bool isLoopbackHost(String host) {
  final normalized = host.trim().toLowerCase();
  if (normalized == 'localhost') {
    return true;
  }
  final address = InternetAddress.tryParse(normalized);
  return address?.isLoopback ?? false;
}

bool isPrivateLanHost(String host) {
  final normalized = host.trim().toLowerCase();
  if (isLoopbackHost(normalized)) {
    return true;
  }
  final address = InternetAddress.tryParse(normalized);
  if (address == null) {
    return false;
  }
  if (address.type == InternetAddressType.IPv4) {
    final bytes = address.rawAddress;
    return bytes[0] == 10 ||
        (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
        (bytes[0] == 192 && bytes[1] == 168) ||
        (bytes[0] == 169 && bytes[1] == 254);
  }
  if (address.type == InternetAddressType.IPv6) {
    final bytes = address.rawAddress;
    return bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80 ||
        (bytes[0] & 0xfe) == 0xfc;
  }
  return false;
}

void assertAllowedLocalCleartext(Uri uri, {required String feature}) {
  if (uri.scheme != 'http') {
    return;
  }
  if (isPrivateLanHost(uri.host)) {
    return;
  }
  throw FormatException('$feature 明文 HTTP 只允许 localhost 或局域网地址。');
}
