import 'dart:collection';

import 'package:live_core/live_core.dart';

abstract class DanmakuBatchMask {
  List<LiveMessage> allowListBatch(
    Iterable<LiveMessage> messages, {
    DateTime? now,
  });

  void dispose() {}
}

class WindowedDanmakuBatchMask extends DanmakuBatchMask {
  WindowedDanmakuBatchMask({
    this.window = const Duration(seconds: 8),
    this.burstLimit = 2,
    this.maxTrackedKeys = 256,
  });

  final Duration window;
  final int burstLimit;
  final int maxTrackedKeys;

  final Map<String, Queue<int>> _seenAtByKey = <String, Queue<int>>{};
  final Queue<String> _trackedKeys = ListQueue<String>();

  @override
  List<LiveMessage> allowListBatch(
    Iterable<LiveMessage> messages, {
    DateTime? now,
  }) {
    final currentMs = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final threshold = currentMs - window.inMilliseconds;
    _evictExpired(threshold);

    final allowed = <LiveMessage>[];
    for (final message in messages) {
      if (!_isMaskable(message)) {
        allowed.add(message);
        continue;
      }
      final key = _normalize(message.content);
      if (key.isEmpty) {
        allowed.add(message);
        continue;
      }
      final queue = _queueForKey(key);
      while (queue.isNotEmpty && queue.first < threshold) {
        queue.removeFirst();
      }
      if (queue.length >= burstLimit) {
        continue;
      }
      queue.addLast(currentMs);
      allowed.add(message);
    }
    return List<LiveMessage>.unmodifiable(allowed);
  }

  bool _isMaskable(LiveMessage message) {
    return switch (message.type) {
      LiveMessageType.chat => true,
      LiveMessageType.notice => true,
      LiveMessageType.gift => true,
      LiveMessageType.member => true,
      LiveMessageType.superChat => false,
      LiveMessageType.online => false,
    };
  }

  String _normalize(String raw) {
    final buffer = StringBuffer();
    for (final rune in raw.runes) {
      final code = rune;
      final isWhitespace = code == 0x20 || code == 0x0A || code == 0x0D;
      if (isWhitespace) {
        continue;
      }
      buffer.writeCharCode(code);
    }
    return buffer.toString().toLowerCase();
  }

  Queue<int> _queueForKey(String key) {
    final existing = _seenAtByKey[key];
    if (existing != null) {
      return existing;
    }
    if (_seenAtByKey.length >= maxTrackedKeys) {
      final oldestKey = _trackedKeys.removeFirst();
      _seenAtByKey.remove(oldestKey);
    }
    final queue = ListQueue<int>();
    _seenAtByKey[key] = queue;
    _trackedKeys.addLast(key);
    return queue;
  }

  void _evictExpired(int threshold) {
    final emptyKeys = <String>[];
    for (final entry in _seenAtByKey.entries) {
      while (entry.value.isNotEmpty && entry.value.first < threshold) {
        entry.value.removeFirst();
      }
      if (entry.value.isEmpty) {
        emptyKeys.add(entry.key);
      }
    }
    for (final key in emptyKeys) {
      _seenAtByKey.remove(key);
      _trackedKeys.remove(key);
    }
  }
}
