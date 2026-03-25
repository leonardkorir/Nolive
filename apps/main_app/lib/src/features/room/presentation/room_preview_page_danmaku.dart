part of 'room_preview_page.dart';

extension _RoomPreviewPageDanmakuExtension on _RoomPreviewPageState {
  static const Duration _danmakuFlushInterval = Duration(milliseconds: 120);
  static const int _danmakuFlushBurstLimit = 18;
  static const List<String> _danmakuReconnectSignals = [
    '连接已断开',
    '连接异常',
    '连接失败',
  ];

  Future<void> _bindDanmakuSession(
    DanmakuSession? session,
    List<String> blockedKeywords,
  ) async {
    await _disposeDanmakuSession();
    _blockedDanmakuKeywords = List<String>.unmodifiable(blockedKeywords);
    _resetDanmakuReconnectState();
    if (session == null) {
      return;
    }
    final filter = DanmakuFilterService(
      config: DanmakuFilterConfig(
        blockedKeywords: blockedKeywords.toSet(),
      ),
    );
    _danmakuSession = session;
    _danmakuFlushTimer = Timer.periodic(_danmakuFlushInterval, (_) {
      _flushPendingDanmaku(filter);
    });
    _danmakuSubscription = session.messages.listen((message) {
      if (!mounted) {
        return;
      }
      if (_shouldReconnectDanmaku(message)) {
        _scheduleDanmakuReconnect();
      }
      _pendingDanmakuMessages.add(message);
      if (_pendingDanmakuMessages.length >= _danmakuFlushBurstLimit) {
        _flushPendingDanmaku(filter);
      }
    });
    try {
      // Some providers emit history or disconnect notices immediately during
      // connect(); subscribe first so those messages are not lost.
      await session.connect();
      _flushPendingDanmaku(filter);
    } catch (_) {
      await _disposeDanmakuSession();
      rethrow;
    }
  }

  Future<void> _disposeDanmakuSession() async {
    _danmakuFlushTimer?.cancel();
    _danmakuFlushTimer = null;
    _pendingDanmakuMessages.clear();
    _playerSuperChatOverlayTimer?.cancel();
    _playerSuperChatOverlayTimer = null;
    final subscription = _danmakuSubscription;
    _danmakuSubscription = null;
    final session = _danmakuSession;
    _danmakuSession = null;

    await subscription?.cancel();
    if (session != null) {
      await session.disconnect();
    }
  }

  void _disposeDanmakuSessionNow() {
    _danmakuFlushTimer?.cancel();
    _danmakuFlushTimer = null;
    _pendingDanmakuMessages.clear();
    _playerSuperChatOverlayTimer?.cancel();
    _playerSuperChatOverlayTimer = null;
    final subscription = _danmakuSubscription;
    _danmakuSubscription = null;
    final session = _danmakuSession;
    _danmakuSession = null;

    if (subscription != null) {
      unawaited(subscription.cancel());
    }
    if (session != null) {
      unawaited(session.disconnect());
    }
  }

  Duration get _playerSuperChatDisplayDuration =>
      Duration(seconds: _playerSuperChatDisplaySeconds.clamp(3, 30));

  bool _shouldReconnectDanmaku(LiveMessage message) {
    if (message.type != LiveMessageType.notice) {
      return false;
    }
    return _danmakuReconnectSignals
        .any((signal) => message.content.contains(signal));
  }

  void _resetDanmakuReconnectState() {
    _danmakuReconnectTimer?.cancel();
    _danmakuReconnectTimer = null;
    _danmakuReconnectInFlight = false;
    _danmakuReconnectAttempt = 0;
  }

  void _scheduleDanmakuReconnect() {
    if (_activeRoomDetail == null ||
        _isLeavingRoom ||
        _playbackCleanedUp ||
        _danmakuReconnectInFlight ||
        _danmakuReconnectTimer != null) {
      return;
    }
    _danmakuReconnectAttempt += 1;
    final delay = Duration(
      seconds: math.min(12, math.max(2, _danmakuReconnectAttempt * 2)),
    );
    _danmakuReconnectTimer = Timer(delay, () {
      _danmakuReconnectTimer = null;
      unawaited(_attemptDanmakuReconnect());
    });
  }

  Future<void> _attemptDanmakuReconnect() async {
    final detail = _activeRoomDetail;
    if (detail == null ||
        !mounted ||
        _isLeavingRoom ||
        _playbackCleanedUp ||
        _danmakuReconnectInFlight) {
      return;
    }
    _danmakuReconnectInFlight = true;
    try {
      final nextSession = await widget.bootstrap.openRoomDanmaku(
        providerId: widget.providerId,
        detail: detail,
      );
      if (!mounted || _isLeavingRoom || _playbackCleanedUp) {
        await nextSession?.disconnect();
        return;
      }
      await _bindDanmakuSession(nextSession, _blockedDanmakuKeywords);
    } catch (_) {
      _danmakuReconnectInFlight = false;
      if (mounted) {
        _scheduleDanmakuReconnect();
      }
      return;
    }
    _danmakuReconnectInFlight = false;
  }

  void _syncPlayerSuperChatOverlay([List<LiveMessage>? history]) {
    final source = history ?? _superChatMessagesNotifier.value;
    final visible = source.length <= 2
        ? source
        : source.sublist(source.length - 2, source.length);
    if (!listEquals(_playerSuperChatMessagesNotifier.value, visible)) {
      _playerSuperChatMessagesNotifier.value = visible;
    }
    _playerSuperChatOverlayTimer?.cancel();
    _playerSuperChatOverlayTimer = null;
    if (visible.isEmpty) {
      return;
    }
    _playerSuperChatOverlayTimer = Timer(
      _playerSuperChatDisplayDuration,
      () {
        if (!mounted) {
          return;
        }
        _playerSuperChatMessagesNotifier.value = const [];
      },
    );
  }

  void _flushPendingDanmaku(DanmakuFilterService filter) {
    if (!mounted || _pendingDanmakuMessages.isEmpty) {
      return;
    }

    final batch = List<LiveMessage>.from(_pendingDanmakuMessages);
    _pendingDanmakuMessages.clear();
    final filtered = filter.apply(batch);
    if (filtered.isEmpty) {
      return;
    }

    final merged = mergeRoomDanmakuBatch(
      messages: _messagesNotifier.value,
      superChats: _superChatMessagesNotifier.value,
      incoming: filtered,
    );
    if (merged.hasSuperChatUpdate) {
      _superChatMessagesNotifier.value = merged.superChats;
      _syncPlayerSuperChatOverlay(merged.superChats);
    }
    if (merged.hasMessageUpdate) {
      _messagesNotifier.value = merged.messages;
      _scheduleChatScrollToBottom();
    }
  }

  void _scheduleChatScrollToBottom({bool force = false}) {
    if (!force && _selectedPanel != _RoomPanel.chat) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_chatScrollController.hasClients) {
        return;
      }
      final position = _chatScrollController.position;
      if (!force && position.maxScrollExtent - position.pixels > 120) {
        return;
      }
      _chatScrollController.jumpTo(position.maxScrollExtent);
    });
  }
}

class _DanmakuOverlay extends StatefulWidget {
  const _DanmakuOverlay({
    required this.messages,
    required this.fullscreen,
    required this.preferences,
    super.key,
  });

  final List<LiveMessage> messages;
  final bool fullscreen;
  final DanmakuPreferences preferences;

  @override
  State<_DanmakuOverlay> createState() => _DanmakuOverlayState();
}

class _DanmakuOverlayState extends State<_DanmakuOverlay> {
  final List<_DanmakuTrackEntry> _entries = [];
  final Set<String> _seenMessageIds = <String>{};
  List<DateTime> _laneAvailableAt = const <DateTime>[];

  int get _laneCount {
    final playerHeight = widget.fullscreen
        ? MediaQuery.sizeOf(context).height
        : MediaQuery.sizeOf(context).width / (16 / 9);
    final topInset =
        (widget.fullscreen ? MediaQuery.paddingOf(context).top : 0.0) +
            widget.preferences.topMargin +
            8;
    final usableHeight =
        (playerHeight - topInset - widget.preferences.bottomMargin)
            .clamp(_laneHeight, playerHeight);
    final desired =
        ((usableHeight * widget.preferences.area) / _laneHeight).floor();
    final maxLanes = widget.fullscreen ? 6 : 4;
    return desired.clamp(1, maxLanes);
  }

  double get _laneHeight {
    return widget.preferences.fontSize * widget.preferences.lineHeight +
        (widget.fullscreen ? 14 : 12);
  }

  double get _topInset {
    return (widget.fullscreen ? MediaQuery.paddingOf(context).top : 0.0) +
        widget.preferences.topMargin +
        8;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _resetLanes();
      _ingest(widget.messages);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resetLanes();
  }

  @override
  void didUpdateWidget(covariant _DanmakuOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fullscreen != widget.fullscreen ||
        oldWidget.preferences != widget.preferences ||
        _laneAvailableAt.length != _laneCount) {
      _resetLanes();
    }
    _ingest(widget.messages);
  }

  void _resetLanes() {
    _laneAvailableAt = List<DateTime>.filled(
      _laneCount,
      DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  void _ingest(List<LiveMessage> messages) {
    if (!mounted || _laneAvailableAt.isEmpty) {
      return;
    }
    final now = DateTime.now();
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final incomingLimit = (_laneCount + 2).clamp(2, 8);
    final incoming = messages
        .skip(math.max(0, messages.length - incomingLimit))
        .toList(growable: true)
      ..sort((left, right) {
        final leftTime =
            left.timestamp ?? DateTime.fromMillisecondsSinceEpoch(0);
        final rightTime =
            right.timestamp ?? DateTime.fromMillisecondsSinceEpoch(0);
        return leftTime.compareTo(rightTime);
      });
    var changed = false;
    for (final message in incoming) {
      final text = _overlayText(message);
      if (text.isEmpty) {
        continue;
      }
      final id = _messageId(message, text);
      if (_seenMessageIds.contains(id)) {
        continue;
      }
      final lane = _pickAvailableLane(now);
      if (lane == null) {
        break;
      }
      final textWidth = _measureTextWidth(text, viewportWidth);
      final duration = _durationFor(
        viewportWidth: viewportWidth,
        textWidth: textWidth,
      );
      final travelDistance = viewportWidth + textWidth + 24;
      final occupyRatio = ((textWidth + 24) / travelDistance).clamp(0.10, 0.26);
      final occupy = Duration(
        milliseconds: (duration.inMilliseconds * occupyRatio).round(),
      );
      _laneAvailableAt[lane] = now.add(occupy);
      _seenMessageIds.add(id);
      _entries.add(
        _DanmakuTrackEntry(
          id: id,
          text: text,
          lane: lane,
          duration: duration,
          textWidth: textWidth,
        ),
      );
      changed = true;
    }
    if (changed && mounted) {
      setState(() {});
    }
  }

  int? _pickAvailableLane(DateTime now) {
    for (var index = 0; index < _laneAvailableAt.length; index += 1) {
      if (!_laneAvailableAt[index].isAfter(now)) {
        return index;
      }
    }
    return null;
  }

  double _measureTextWidth(String text, double viewportWidth) {
    final maxBubbleWidth = viewportWidth * (widget.fullscreen ? 0.96 : 0.98);
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: applyZhTextStyle().copyWith(
          fontSize: widget.preferences.fontSize,
          fontWeight: widget.preferences.resolveFontWeight(),
          height: widget.preferences.lineHeight,
        ),
      ),
      textDirection: Directionality.of(context),
      maxLines: 1,
    )..layout(maxWidth: maxBubbleWidth);
    return textPainter.width.clamp(32.0, maxBubbleWidth);
  }

  Duration _durationFor({
    required double viewportWidth,
    required double textWidth,
  }) {
    const baselineDistance = 390.0 + 120.0 + 24.0;
    final baseSeconds = widget.preferences.speed.clamp(4.0, 40.0);
    final travelDistance = viewportWidth + textWidth + 24.0;
    final distanceRatio = (travelDistance / baselineDistance).clamp(0.88, 2.4);
    final seconds = (baseSeconds * distanceRatio * 4.6).clamp(
      math.max(baseSeconds * 1.8, 14.0),
      180.0,
    );
    return Duration(milliseconds: (seconds * 1000).round());
  }

  String _overlayText(LiveMessage message) {
    if (message.type != LiveMessageType.chat) {
      return '';
    }
    return message.content.trim();
  }

  String _messageId(LiveMessage message, String text) {
    final timestamp = message.timestamp?.microsecondsSinceEpoch;
    if (timestamp != null) {
      return '$timestamp-$text-${message.type.name}';
    }
    return '${message.hashCode}-$text-${message.type.name}';
  }

  void _removeEntry(String id) {
    if (!mounted) {
      return;
    }
    setState(() {
      _entries.removeWhere((entry) => entry.id == id);
    });
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          for (final entry in _entries)
            _DanmakuTrackBubble(
              key: ValueKey(entry.id),
              text: entry.text,
              top: _topInset + (entry.lane * _laneHeight),
              duration: entry.duration,
              textWidth: entry.textWidth,
              fullscreen: widget.fullscreen,
              preferences: widget.preferences,
              onCompleted: () => _removeEntry(entry.id),
            ),
        ],
      ),
    );
  }
}

class _DanmakuTrackEntry {
  const _DanmakuTrackEntry({
    required this.id,
    required this.text,
    required this.lane,
    required this.duration,
    required this.textWidth,
  });

  final String id;
  final String text;
  final int lane;
  final Duration duration;
  final double textWidth;
}

class _DanmakuTrackBubble extends StatefulWidget {
  const _DanmakuTrackBubble({
    required this.text,
    required this.top,
    required this.duration,
    required this.textWidth,
    required this.fullscreen,
    required this.preferences,
    required this.onCompleted,
    super.key,
  });

  final String text;
  final double top;
  final Duration duration;
  final double textWidth;
  final bool fullscreen;
  final DanmakuPreferences preferences;
  final VoidCallback onCompleted;

  @override
  State<_DanmakuTrackBubble> createState() => _DanmakuTrackBubbleState();
}

class _DanmakuTrackBubbleState extends State<_DanmakuTrackBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onCompleted();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _controller.forward();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fillStyle = applyZhTextStyle().copyWith(
      color: Colors.white.withValues(alpha: widget.preferences.opacity),
      fontSize: widget.preferences.fontSize,
      fontWeight: widget.preferences.resolveFontWeight(),
      height: widget.preferences.lineHeight,
    );
    final strokeStyle = fillStyle.copyWith(
      foreground: Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = widget.preferences.strokeWidth
        ..color = Colors.black.withValues(alpha: 0.78),
    );
    final maxBubbleWidth =
        MediaQuery.sizeOf(context).width * (widget.fullscreen ? 0.96 : 0.98);
    final bubbleWidth = widget.textWidth.clamp(32.0, maxBubbleWidth).toDouble();

    return Positioned(
      top: widget.top,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final start = constraints.maxWidth + 12;
            final end = -bubbleWidth - 12;

            return AnimatedBuilder(
              animation: _controller,
              child: SizedBox(
                width: bubbleWidth,
                child: Stack(
                  children: [
                    if (widget.preferences.strokeWidth > 0)
                      Text(
                        widget.text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: strokeStyle,
                      ),
                    Text(
                      widget.text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: fillStyle,
                    ),
                  ],
                ),
              ),
              builder: (context, child) {
                final dx = start + ((end - start) * _controller.value);
                return Transform.translate(
                  offset: Offset(dx, 0),
                  child: child,
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _RoomErrorState extends StatelessWidget {
  const _RoomErrorState({
    required this.title,
    required this.message,
    required this.detail,
    required this.onRetry,
    required this.onOpenSettings,
  });

  final String title;
  final String message;
  final String detail;
  final Future<void> Function() onRetry;
  final Future<void> Function() onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(20),
      children: [
        AppSurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(message),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('重试'),
                  ),
                  OutlinedButton.icon(
                    onPressed: onOpenSettings,
                    icon: const Icon(Icons.settings_suggest_outlined),
                    label: const Text('播放器设置'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                '错误详情',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              SelectableText(detail),
            ],
          ),
        ),
      ],
    );
  }
}
