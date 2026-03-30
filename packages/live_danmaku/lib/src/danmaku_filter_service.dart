import 'package:live_core/live_core.dart';

import 'danmaku_filter_config.dart';

class DanmakuFilterService {
  DanmakuFilterService({required this.config})
      : _textRules = _buildTextRules(config),
        _regexRules = _buildRegexRules(config);

  final DanmakuFilterConfig config;
  final List<String> _textRules;
  final List<RegExp> _regexRules;

  List<LiveMessage> apply(Iterable<LiveMessage> messages) {
    return messages.where(_allow).toList(growable: false);
  }

  bool _allow(LiveMessage message) {
    final haystack =
        config.caseSensitive ? message.content : message.content.toLowerCase();

    for (final pattern in _regexRules) {
      if (pattern.hasMatch(message.content)) {
        return false;
      }
    }

    for (final needle in _textRules) {
      if (haystack.contains(needle)) {
        return false;
      }
    }

    return true;
  }

  static List<String> _buildTextRules(DanmakuFilterConfig config) {
    final rules = <String>[];
    for (final keyword in config.blockedKeywords) {
      final normalized = keyword.trim();
      if (normalized.isEmpty || normalized.startsWith('re:')) {
        continue;
      }
      rules.add(
        config.caseSensitive ? normalized : normalized.toLowerCase(),
      );
    }
    return List<String>.unmodifiable(rules);
  }

  static List<RegExp> _buildRegexRules(DanmakuFilterConfig config) {
    final rules = <RegExp>[];
    for (final keyword in config.blockedKeywords) {
      if (!keyword.startsWith('re:')) {
        continue;
      }
      final pattern = keyword.substring(3).trim();
      if (pattern.isEmpty) {
        continue;
      }
      try {
        rules.add(RegExp(pattern, caseSensitive: config.caseSensitive));
      } catch (_) {
        // Ignore invalid expressions instead of failing the room session.
      }
    }
    return List<RegExp>.unmodifiable(rules);
  }
}
