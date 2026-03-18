class DanmakuFilterConfig {
  const DanmakuFilterConfig({
    this.blockedKeywords = const {},
    this.caseSensitive = false,
  });

  final Set<String> blockedKeywords;
  final bool caseSensitive;
}
