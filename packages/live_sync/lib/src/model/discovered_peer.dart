class DiscoveredPeer {
  const DiscoveredPeer({
    required this.deviceId,
    required this.displayName,
    required this.address,
    required this.port,
  });

  final String deviceId;
  final String displayName;
  final String address;
  final int port;
}
