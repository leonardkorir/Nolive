import 'dart:collection';

class DanmakuFilterConfig {
  DanmakuFilterConfig({
    Set<String> blockedKeywords = const {},
    this.caseSensitive = false,
  }) : blockedKeywords = UnmodifiableSetView(Set<String>.of(blockedKeywords));

  final Set<String> blockedKeywords;
  final bool caseSensitive;

  DanmakuFilterConfig copyWith({
    Set<String>? blockedKeywords,
    bool? caseSensitive,
  }) {
    return DanmakuFilterConfig(
      blockedKeywords: blockedKeywords ?? this.blockedKeywords,
      caseSensitive: caseSensitive ?? this.caseSensitive,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) {
      return true;
    }
    if (other is! DanmakuFilterConfig) {
      return false;
    }
    return _setEquals(other.blockedKeywords, blockedKeywords) &&
        other.caseSensitive == caseSensitive;
  }

  @override
  int get hashCode {
    final sortedKeywords = blockedKeywords.toList()..sort();
    return Object.hash(Object.hashAll(sortedKeywords), caseSensitive);
  }

  static bool _setEquals(Set<String> a, Set<String> b) {
    if (a.length != b.length) {
      return false;
    }
    return a.containsAll(b);
  }
}
