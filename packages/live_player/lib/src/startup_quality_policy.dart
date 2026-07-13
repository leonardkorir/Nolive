/// Quality ladder: 0 lowest, 1 middle, 2 highest.
enum NetworkQualityPreference {
  lowest,
  middle,
  highest,
}

/// Selects a quality index for a descending-quality list (index 0 = best).
int selectQualityIndex({
  required int qualityCount,
  required NetworkQualityPreference preference,
}) {
  if (qualityCount <= 0) {
    return -1;
  }
  return switch (preference) {
    NetworkQualityPreference.highest => 0,
    NetworkQualityPreference.lowest => qualityCount - 1,
    NetworkQualityPreference.middle => (qualityCount / 2).floor(),
  };
}

/// Resolve Wi-Fi vs cellular preference for play settings.
NetworkQualityPreference resolveNetworkQualityPreference({
  required bool isCellular,
  required NetworkQualityPreference wifiPreference,
  required NetworkQualityPreference cellularPreference,
}) {
  return isCellular ? cellularPreference : wifiPreference;
}
