import 'package:live_core/live_core.dart';

import 'danmaku_filter_config.dart';

class DanmakuFilterService {
  const DanmakuFilterService({required this.config});

  final DanmakuFilterConfig config;

  List<LiveMessage> apply(Iterable<LiveMessage> messages) {
    return messages.where(_allow).toList(growable: false);
  }

  bool _allow(LiveMessage message) {
    final haystack =
        config.caseSensitive ? message.content : message.content.toLowerCase();

    for (final keyword in config.blockedKeywords) {
      final normalized = keyword.trim();
      if (normalized.isEmpty) {
        continue;
      }
      if (_matchesRegex(normalized, message.content)) {
        return false;
      }
      final needle =
          config.caseSensitive ? normalized : normalized.toLowerCase();
      if (haystack.contains(needle)) {
        return false;
      }
    }

    return true;
  }

  bool _matchesRegex(String rule, String content) {
    if (!rule.startsWith('re:')) {
      return false;
    }
    final pattern = rule.substring(3).trim();
    if (pattern.isEmpty) {
      return false;
    }
    try {
      return RegExp(pattern, caseSensitive: config.caseSensitive)
          .hasMatch(content);
    } catch (_) {
      return false;
    }
  }
}
