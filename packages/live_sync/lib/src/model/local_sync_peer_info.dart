class LocalSyncPeerInfo {
  const LocalSyncPeerInfo({
    required this.displayName,
    required this.deviceId,
    required this.platform,
    this.snapshotPath = '/snapshot',
  });

  final String displayName;
  final String deviceId;
  final String platform;
  final String snapshotPath;

  Map<String, Object?> toJson() {
    return {
      'displayName': displayName,
      'deviceId': deviceId,
      'platform': platform,
      'snapshotPath': snapshotPath,
    };
  }

  factory LocalSyncPeerInfo.fromJson(Map<String, dynamic> json) {
    final displayName = json['displayName']?.toString().trim();
    final deviceId = json['deviceId']?.toString().trim();
    final platform = json['platform']?.toString().trim();
    final snapshotPath = json['snapshotPath']?.toString().trim();
    return LocalSyncPeerInfo(
      displayName:
          (displayName == null || displayName.isEmpty) ? '未知设备' : displayName,
      deviceId:
          (deviceId == null || deviceId.isEmpty) ? 'unknown-device' : deviceId,
      platform: (platform == null || platform.isEmpty) ? 'unknown' : platform,
      snapshotPath: (snapshotPath == null || snapshotPath.isEmpty)
          ? '/snapshot'
          : snapshotPath,
    );
  }
}
