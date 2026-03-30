class DiscoveredPeer {
  const DiscoveredPeer({
    required this.deviceId,
    required this.displayName,
    required this.address,
    required this.port,
    this.platform = 'unknown',
    required this.lastSeenAt,
  });

  final String deviceId;
  final String displayName;
  final String address;
  final int port;
  final String platform;
  final DateTime lastSeenAt;

  DiscoveredPeer copyWith({
    String? deviceId,
    String? displayName,
    String? address,
    int? port,
    String? platform,
    DateTime? lastSeenAt,
  }) {
    return DiscoveredPeer(
      deviceId: deviceId ?? this.deviceId,
      displayName: displayName ?? this.displayName,
      address: address ?? this.address,
      port: port ?? this.port,
      platform: platform ?? this.platform,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
    );
  }
}
