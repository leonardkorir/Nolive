import 'dart:async';

import 'package:live_core/live_core.dart';

import '../providers/youtube/youtube_api_client.dart';

class YouTubeDanmakuSession implements DanmakuSession {
  YouTubeDanmakuSession({
    required this.apiClient,
    required this.apiKey,
    required this.continuation,
    required this.visitorData,
    required this.referer,
    this.clientVersion = YouTubeApiClient.defaultWebClientVersion,
  });

  final YouTubeApiClient apiClient;
  final String apiKey;
  final String continuation;
  final String visitorData;
  final String referer;
  final String clientVersion;

  final StreamController<LiveMessage> _controller =
      StreamController<LiveMessage>.broadcast();
  final Set<String> _seenMessageIds = <String>{};

  bool _connected = false;
  bool _announcedReady = false;
  Future<void>? _pumpFuture;
  String? _nextContinuation;

  @override
  Stream<LiveMessage> get messages => _controller.stream;

  @override
  Future<void> connect() async {
    if (_connected) {
      return;
    }
    _connected = true;
    _announcedReady = false;
    _nextContinuation = continuation;
    _pumpFuture = _pump();
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    await _pumpFuture;
    _pumpFuture = null;
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }

  Future<void> _pump() async {
    while (_connected) {
      final currentContinuation = _nextContinuation?.trim() ?? '';
      if (currentContinuation.isEmpty) {
        _emitNotice('YouTube 当前没有可用直播聊天 continuation。');
        break;
      }
      try {
        final response = await apiClient.postLiveChat(
          apiKey: apiKey,
          continuation: currentContinuation,
          visitorData: visitorData,
          referer: referer,
          clientVersion: clientVersion,
        );
        if (!_connected) {
          break;
        }
        if (!_announcedReady) {
          _announcedReady = true;
          _emitNotice('YouTube 实时聊天已连接');
        }
        final poll = _parsePoll(response);
        _nextContinuation = poll.continuation;
        for (final message in poll.messages) {
          _emit(message);
        }
        final delay = Duration(
          milliseconds: poll.timeoutMs.clamp(1000, 15000),
        );
        if (_connected) {
          await _waitFor(delay);
        }
      } catch (error) {
        _emitNotice('YouTube 实时聊天轮询失败：$error');
        if (_connected) {
          await _waitFor(const Duration(seconds: 3));
        }
      }
    }
  }

  _YouTubeLiveChatPoll _parsePoll(Map<String, dynamic> response) {
    final continuationContents = _asMap(response['continuationContents']);
    final liveChatContinuation =
        _asMap(continuationContents['liveChatContinuation']);
    final actions = _asList(liveChatContinuation['actions']);
    final continuations = _asList(liveChatContinuation['continuations']);
    final messages = <LiveMessage>[];
    for (final action in actions) {
      messages.addAll(_messagesFromAction(_asMap(action)));
    }
    final continuationState = _readContinuationState(continuations);
    return _YouTubeLiveChatPoll(
      messages: messages,
      continuation: continuationState.continuation,
      timeoutMs: continuationState.timeoutMs,
    );
  }

  Iterable<LiveMessage> _messagesFromAction(Map<String, dynamic> action) sync* {
    final addChatItem = _asMap(_asMap(action['addChatItemAction'])['item']);
    if (addChatItem.isNotEmpty) {
      final message = _mapRendererEnvelope(addChatItem);
      if (message != null) {
        yield message;
      }
    }

    final replayAction = _asMap(action['replayChatItemAction']);
    if (replayAction.isNotEmpty) {
      for (final nested in _asList(replayAction['actions'])) {
        yield* _messagesFromAction(_asMap(nested));
      }
    }

    final bannerRenderer = _asMap(
      _asMap(
        _asMap(action['addBannerToLiveChatCommand'])['bannerRenderer'],
      )['liveChatBannerRenderer'],
    );
    if (bannerRenderer.isNotEmpty) {
      final message = _mapRendererEnvelope(
        _asMap(bannerRenderer['contents']),
      );
      if (message != null) {
        yield message;
      }
    }
  }

  LiveMessage? _mapRendererEnvelope(Map<String, dynamic> envelope) {
    if (envelope.isEmpty) {
      return null;
    }
    for (final entry in envelope.entries) {
      final renderer = _asMap(entry.value);
      if (renderer.isEmpty) {
        continue;
      }
      return switch (entry.key) {
        'liveChatTextMessageRenderer' => _buildTextMessage(renderer),
        'liveChatPaidMessageRenderer' => _buildPaidMessage(renderer),
        'liveChatPaidStickerRenderer' => _buildPaidSticker(renderer),
        'liveChatMembershipItemRenderer' => _buildMembershipMessage(renderer),
        'liveChatSponsorshipsGiftPurchaseAnnouncementRenderer' =>
          _buildGiftMessage(renderer),
        'liveChatSponsorshipsGiftRedemptionAnnouncementRenderer' =>
          _buildGiftMessage(renderer),
        'liveChatViewerEngagementMessageRenderer' =>
          _buildNoticeMessage(renderer),
        'liveChatModeChangeMessageRenderer' => _buildNoticeMessage(renderer),
        'liveChatPlaceholderItemRenderer' => null,
        _ => _buildFallbackMessage(renderer),
      };
    }
    return null;
  }

  LiveMessage? _buildTextMessage(Map<String, dynamic> renderer) {
    final content = _readText(renderer['message']);
    if (content.isEmpty) {
      return null;
    }
    return _dedupe(
      renderer,
      LiveMessage(
        type: LiveMessageType.chat,
        userName: _readText(renderer['authorName']),
        content: content,
        timestamp: _readTimestamp(renderer['timestampUsec']),
        payload: renderer,
      ),
    );
  }

  LiveMessage? _buildPaidMessage(Map<String, dynamic> renderer) {
    final amount = _readText(renderer['purchaseAmountText']);
    final message = _readText(renderer['message']);
    final content =
        [amount, message].where((item) => item.isNotEmpty).join(' · ');
    if (content.isEmpty) {
      return null;
    }
    return _dedupe(
      renderer,
      LiveMessage(
        type: LiveMessageType.superChat,
        userName: _readText(renderer['authorName']),
        content: content,
        timestamp: _readTimestamp(renderer['timestampUsec']),
        payload: renderer,
      ),
    );
  }

  LiveMessage? _buildPaidSticker(Map<String, dynamic> renderer) {
    final amount = _readText(renderer['purchaseAmountText']);
    final sticker = _readText(
      _asMap(_asMap(renderer['sticker'])['accessibility'])['accessibilityData'],
    );
    final content =
        [amount, sticker].where((item) => item.isNotEmpty).join(' · ');
    if (content.isEmpty) {
      return null;
    }
    return _dedupe(
      renderer,
      LiveMessage(
        type: LiveMessageType.superChat,
        userName: _readText(renderer['authorName']),
        content: content,
        timestamp: _readTimestamp(renderer['timestampUsec']),
        payload: renderer,
      ),
    );
  }

  LiveMessage? _buildMembershipMessage(Map<String, dynamic> renderer) {
    final content = _firstNonEmpty([
      _readText(renderer['headerPrimaryText']),
      _readText(renderer['headerSubtext']),
      _readText(renderer['message']),
    ]);
    if (content.isEmpty) {
      return null;
    }
    return _dedupe(
      renderer,
      LiveMessage(
        type: LiveMessageType.member,
        userName: _readText(renderer['authorName']),
        content: content,
        timestamp: _readTimestamp(renderer['timestampUsec']),
        payload: renderer,
      ),
    );
  }

  LiveMessage? _buildGiftMessage(Map<String, dynamic> renderer) {
    final content = _firstNonEmpty([
      _readText(renderer['headerPrimaryText']),
      _readText(renderer['headerSubtext']),
      _readText(renderer['message']),
    ]);
    if (content.isEmpty) {
      return null;
    }
    return _dedupe(
      renderer,
      LiveMessage(
        type: LiveMessageType.gift,
        userName: _readText(renderer['authorName']),
        content: content,
        timestamp: _readTimestamp(renderer['timestampUsec']),
        payload: renderer,
      ),
    );
  }

  LiveMessage? _buildNoticeMessage(Map<String, dynamic> renderer) {
    final content = _firstNonEmpty([
      _readText(renderer['message']),
      _readText(renderer['text']),
      _readText(renderer['headerPrimaryText']),
      _readText(renderer['headerSubtext']),
    ]);
    if (content.isEmpty) {
      return null;
    }
    return _dedupe(
      renderer,
      LiveMessage(
        type: LiveMessageType.notice,
        content: content,
        timestamp: _readTimestamp(renderer['timestampUsec']),
        payload: renderer,
      ),
    );
  }

  LiveMessage? _buildFallbackMessage(Map<String, dynamic> renderer) {
    final content = _firstNonEmpty([
      _readText(renderer['message']),
      _readText(renderer['text']),
      _readText(renderer['headerPrimaryText']),
      _readText(renderer['headerSubtext']),
    ]);
    if (content.isEmpty) {
      return null;
    }
    return _dedupe(
      renderer,
      LiveMessage(
        type: LiveMessageType.notice,
        userName: _readText(renderer['authorName']),
        content: content,
        timestamp: _readTimestamp(renderer['timestampUsec']),
        payload: renderer,
      ),
    );
  }

  LiveMessage? _dedupe(Map<String, dynamic> renderer, LiveMessage message) {
    final key = _firstNonEmpty([
      renderer['id']?.toString().trim() ?? '',
      '${message.userName ?? ''}|${message.content}|'
          '${message.timestamp?.microsecondsSinceEpoch ?? 0}',
    ]);
    if (key.isEmpty || _seenMessageIds.add(key)) {
      return message;
    }
    return null;
  }

  _YouTubeContinuationState _readContinuationState(List<dynamic> values) {
    for (final item in values) {
      final map = _asMap(item);
      for (final key in const [
        'invalidationContinuationData',
        'timedContinuationData',
        'reloadContinuationData',
        'liveChatReplayContinuationData',
      ]) {
        final data = _asMap(map[key]);
        final continuation = data['continuation']?.toString().trim() ?? '';
        if (continuation.isEmpty) {
          continue;
        }
        final timeoutMs = _toInt(data['timeoutMs']) ?? 5000;
        return _YouTubeContinuationState(
          continuation: continuation,
          timeoutMs: timeoutMs,
        );
      }
    }
    return _YouTubeContinuationState(
      continuation: _nextContinuation?.trim() ?? '',
      timeoutMs: 5000,
    );
  }

  DateTime? _readTimestamp(Object? raw) {
    final usec = raw?.toString().trim() ?? '';
    final value = int.tryParse(usec);
    if (value == null) {
      return null;
    }
    return DateTime.fromMicrosecondsSinceEpoch(value);
  }

  String _readText(Object? value) {
    if (value is String) {
      return value.trim();
    }
    final map = _asMap(value);
    final simpleText = map['simpleText']?.toString().trim() ?? '';
    if (simpleText.isNotEmpty) {
      return simpleText;
    }
    final accessibility = _asMap(map['accessibility']);
    final accessibilityText =
        _asMap(accessibility['accessibilityData'])['label']
                ?.toString()
                .trim() ??
            '';
    if (accessibilityText.isNotEmpty) {
      return accessibilityText;
    }
    final runs = _asList(map['runs']);
    if (runs.isEmpty) {
      return '';
    }
    return runs
        .map((item) {
          final run = _asMap(item);
          final text = run['text']?.toString() ?? '';
          if (text.trim().isNotEmpty) {
            return text;
          }
          final emoji = _asMap(run['emoji']);
          return _firstNonEmpty([
            _readText(emoji['shortcuts']),
            _readText(emoji['image']),
          ]);
        })
        .join()
        .trim();
  }

  String _firstNonEmpty(Iterable<String> values) {
    for (final value in values) {
      final normalized = value.trim();
      if (normalized.isNotEmpty) {
        return normalized;
      }
    }
    return '';
  }

  int? _toInt(Object? value) {
    if (value is int) {
      return value;
    }
    return int.tryParse(value?.toString() ?? '');
  }

  Future<void> _waitFor(Duration delay) async {
    final deadline = DateTime.now().add(delay);
    while (_connected) {
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        return;
      }
      await Future<void>.delayed(
        remaining > const Duration(milliseconds: 200)
            ? const Duration(milliseconds: 200)
            : remaining,
      );
    }
  }

  void _emitNotice(String content) {
    _emit(
      LiveMessage(
        type: LiveMessageType.notice,
        content: content,
        timestamp: DateTime.now(),
      ),
    );
  }

  void _emit(LiveMessage message) {
    if (_controller.isClosed) {
      return;
    }
    _controller.add(message);
  }

  Map<String, dynamic> _asMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.cast<String, dynamic>();
    }
    return const {};
  }

  List<dynamic> _asList(Object? value) {
    if (value is List) {
      return value;
    }
    return const [];
  }
}

class _YouTubeLiveChatPoll {
  const _YouTubeLiveChatPoll({
    required this.messages,
    required this.continuation,
    required this.timeoutMs,
  });

  final List<LiveMessage> messages;
  final String continuation;
  final int timeoutMs;
}

class _YouTubeContinuationState {
  const _YouTubeContinuationState({
    required this.continuation,
    required this.timeoutMs,
  });

  final String continuation;
  final int timeoutMs;
}
