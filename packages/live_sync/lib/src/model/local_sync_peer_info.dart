class LocalSyncPeerInfo {
  const LocalSyncPeerInfo({
    required this.displayName,
    this.snapshotPath = '/snapshot',
  });

  final String displayName;
  final String snapshotPath;

  Map<String, Object?> toJson() {
    return {
      'displayName': displayName,
      'snapshotPath': snapshotPath,
    };
  }

  factory LocalSyncPeerInfo.fromJson(Map<String, dynamic> json) {
    final displayName = json['displayName']?.toString().trim();
    final snapshotPath = json['snapshotPath']?.toString().trim();
    return LocalSyncPeerInfo(
      displayName:
          (displayName == null || displayName.isEmpty) ? '未知设备' : displayName,
      snapshotPath: (snapshotPath == null || snapshotPath.isEmpty)
          ? '/snapshot'
          : snapshotPath,
    );
  }
}
