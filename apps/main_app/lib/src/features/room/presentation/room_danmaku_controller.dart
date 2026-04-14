import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:nolive_app/src/features/room/application/room_preview_dependencies.dart';
import 'package:nolive_app/src/rust/danmaku_batch_mask.dart';

import 'room_danmaku_batch.dart';

@immutable
class RoomDanmakuState {
  const RoomDanmakuState({
    required this.session,
    required this.blockedKeywords,
    required this.usingNativeBatchMask,
    required this.reconnectInFlight,
    required this.reconnectAttempt,
    required this.reconnectScheduled,
  });

  const RoomDanmakuState.initial()
      : session = null,
        blockedKeywords = const <String>[],
        usingNativeBatchMask = false,
        reconnectInFlight = false,
        reconnectAttempt = 0,
        reconnectScheduled = false;

  final DanmakuSession? session;
  final List<String> blockedKeywords;
  final bool usingNativeBatchMask;
  final bool reconnectInFlight;
  final int reconnectAttempt;
  final bool reconnectScheduled;

  RoomDanmakuState copyWith({
    DanmakuSession? session,
    bool clearSession = false,
    List<String>? blockedKeywords,
    bool? usingNativeBatchMask,
    bool? reconnectInFlight,
    int? reconnectAttempt,
    bool? reconnectScheduled,
  }) {
    return RoomDanmakuState(
      session: clearSession ? null : (session ?? this.session),
      blockedKeywords: blockedKeywords ?? this.blockedKeywords,
      usingNativeBatchMask: usingNativeBatchMask ?? this.usingNativeBatchMask,
      reconnectInFlight: reconnectInFlight ?? this.reconnectInFlight,
      reconnectAttempt: reconnectAttempt ?? this.reconnectAttempt,
      reconnectScheduled: reconnectScheduled ?? this.reconnectScheduled,
    );
  }
}

@visibleForTesting
bool shouldRetryDanmakuConnectionError({
  required ProviderId providerId,
  required Object error,
}) {
  if (providerId != ProviderId.chaturbate) {
    return true;
  }
  if (error is! ProviderParseException) {
    return true;
  }
  final message = error.message.toLowerCase();
  final blockedByCloudflare = message.contains('cloudflare challenge');
  final chaturbate403 = message.contains('status 403') &&
      (message.contains('/push_service/auth/') ||
          message.contains('/push_service/room_history/'));
  return !(blockedByCloudflare || chaturbate403);
}

class RoomDanmakuController {
  RoomDanmakuController({
    required this.dependencies,
    required this.providerId,
    this.trace,
  })  : _state = ValueNotifier<RoomDanmakuState>(
          const RoomDanmakuState.initial(),
        ),
        _messages = ValueNotifier<List<LiveMessage>>(const <LiveMessage>[]),
        _superChats = ValueNotifier<List<LiveMessage>>(const <LiveMessage>[]),
        _playerSuperChats = ValueNotifier<List<LiveMessage>>(
          const <LiveMessage>[],
        ) {
    _updateBatchMask(preferNative: false);
  }

  static const Duration _danmakuFlushInterval = Duration(milliseconds: 120);
  static const int _danmakuFlushBurstLimit = 18;
  static const List<String> _danmakuReconnectSignals = <String>[
    '连接已断开',
    '连接异常',
    '连接失败',
  ];

  final RoomDanmakuDependencies dependencies;
  final ProviderId providerId;
  final void Function(String message)? trace;
  final ValueNotifier<RoomDanmakuState> _state;
  final ValueNotifier<List<LiveMessage>> _messages;
  final ValueNotifier<List<LiveMessage>> _superChats;
  final ValueNotifier<List<LiveMessage>> _playerSuperChats;

  final List<LiveMessage> _pendingDanmakuMessages = <LiveMessage>[];

  DanmakuBatchMask _danmakuBatchMask = WindowedDanmakuBatchMask();
  DanmakuFilterService _filter = DanmakuFilterService(
    config: const DanmakuFilterConfig(blockedKeywords: <String>{}),
  );
  LiveRoomDetail? _activeRoomDetail;
  Timer? _danmakuFlushTimer;
  Timer? _playerSuperChatOverlayTimer;
  Timer? _danmakuReconnectTimer;
  StreamSubscription<LiveMessage>? _danmakuSubscription;
  int _playerSuperChatDisplaySeconds = 8;
  int _bindGeneration = 0;
  int _reconnectGeneration = 0;
  bool _suspendedByLifecycle = false;
  bool _disposed = false;

  ValueListenable<RoomDanmakuState> get listenable => _state;

  ValueListenable<List<LiveMessage>> get messages => _messages;

  ValueListenable<List<LiveMessage>> get superChats => _superChats;

  ValueListenable<List<LiveMessage>> get playerSuperChats => _playerSuperChats;

  RoomDanmakuState get current => _state.value;

  void configure({
    required List<String> blockedKeywords,
    required bool preferNativeBatchMask,
    required int playerSuperChatDisplaySeconds,
  }) {
    if (_disposed) {
      return;
    }
    _playerSuperChatDisplaySeconds = playerSuperChatDisplaySeconds;
    _filter = DanmakuFilterService(
      config: DanmakuFilterConfig(
        blockedKeywords: blockedKeywords.toSet(),
      ),
    );
    final usingNative = _updateBatchMask(preferNative: preferNativeBatchMask);
    _emit(
      current.copyWith(
        blockedKeywords: List<String>.unmodifiable(blockedKeywords),
        usingNativeBatchMask: usingNative,
      ),
    );
    _syncPlayerSuperChatOverlay();
  }

  void clearFeed() {
    if (_disposed) {
      return;
    }
    resetReconnectState();
    _messages.value = const <LiveMessage>[];
    _superChats.value = const <LiveMessage>[];
    _playerSuperChats.value = const <LiveMessage>[];
  }

  Future<void> bindSession({
    required LiveRoomDetail activeRoomDetail,
    required DanmakuSession? session,
  }) async {
    final bindGeneration = ++_bindGeneration;
    _suspendedByLifecycle = false;
    _activeRoomDetail = activeRoomDetail;
    await _disposeSessionInternal(clearSession: true);
    resetReconnectState();
    if (_disposed || bindGeneration != _bindGeneration) {
      await session?.disconnect();
      return;
    }
    if (session == null) {
      _emit(current.copyWith(clearSession: true));
      return;
    }

    _emit(current.copyWith(session: session));
    _danmakuFlushTimer = Timer.periodic(_danmakuFlushInterval, (_) {
      _flushPendingDanmaku();
    });
    _danmakuSubscription = session.messages.listen((message) {
      if (_disposed) {
        return;
      }
      if (_shouldReconnectDanmaku(message)) {
        _scheduleDanmakuReconnect();
      }
      _pendingDanmakuMessages.add(message);
      if (_pendingDanmakuMessages.length >= _danmakuFlushBurstLimit) {
        _flushPendingDanmaku();
      }
    }, onError: (Object error, StackTrace stackTrace) {
      if (_disposed) {
        return;
      }
      _trace('danmaku stream error: $error');
      _pendingDanmakuMessages.add(
        _buildDanmakuNotice('弹幕连接异常：$error'),
      );
      _flushPendingDanmaku();
      _scheduleDanmakuReconnect();
    });

    try {
      await session.connect();
      if (_disposed || bindGeneration != _bindGeneration) {
        await session.disconnect();
        return;
      }
      _flushPendingDanmaku();
    } catch (error) {
      _trace('danmaku connect failed: $error');
      _pendingDanmakuMessages.add(
        _buildDanmakuNotice('弹幕连接失败：$error'),
      );
      _flushPendingDanmaku();
      if (!_disposed && bindGeneration == _bindGeneration) {
        await _disposeSessionInternal(clearSession: true);
        if (shouldRetryDanmakuConnectionError(
          providerId: providerId,
          error: error,
        )) {
          _scheduleDanmakuReconnect();
        } else {
          _trace('danmaku reconnect suppressed for non-retryable error');
          resetReconnectState();
        }
      } else {
        await session.disconnect();
      }
    }
  }

  Future<void> closeSession() async {
    _bindGeneration += 1;
    _suspendedByLifecycle = false;
    _activeRoomDetail = null;
    resetReconnectState();
    await _disposeSessionInternal(clearSession: true);
  }

  Future<void> handleLifecycleState({
    required AppLifecycleState state,
    required bool backgroundAutoPauseEnabled,
    required bool inPictureInPictureMode,
    required bool enteringPictureInPicture,
  }) async {
    if (_disposed) {
      return;
    }
    if (state == AppLifecycleState.resumed) {
      await _resumeAfterLifecycleSuspendIfNeeded(
        inPictureInPictureMode: inPictureInPictureMode,
      );
      return;
    }
    if (state != AppLifecycleState.hidden &&
        state != AppLifecycleState.paused) {
      return;
    }
    if (!backgroundAutoPauseEnabled ||
        inPictureInPictureMode ||
        enteringPictureInPicture ||
        _suspendedByLifecycle ||
        _activeRoomDetail == null) {
      return;
    }
    _suspendedByLifecycle = true;
    resetReconnectState();
    await _disposeSessionInternal(clearSession: true);
  }

  void resetReconnectState() {
    _reconnectGeneration += 1;
    _danmakuReconnectTimer?.cancel();
    _danmakuReconnectTimer = null;
    if (_disposed) {
      return;
    }
    _emit(
      current.copyWith(
        reconnectInFlight: false,
        reconnectAttempt: 0,
        reconnectScheduled: false,
      ),
    );
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _suspendedByLifecycle = false;
    _bindGeneration += 1;
    _activeRoomDetail = null;
    _danmakuFlushTimer?.cancel();
    _danmakuFlushTimer = null;
    _playerSuperChatOverlayTimer?.cancel();
    _playerSuperChatOverlayTimer = null;
    _danmakuReconnectTimer?.cancel();
    _danmakuReconnectTimer = null;
    _pendingDanmakuMessages.clear();

    final subscription = _danmakuSubscription;
    _danmakuSubscription = null;
    final session = current.session;
    final disconnectFuture = session?.disconnect();

    if (subscription != null) {
      unawaited(subscription.cancel());
    }
    if (disconnectFuture != null) {
      unawaited(disconnectFuture);
    }
    _danmakuBatchMask.dispose();
    _state.dispose();
    _messages.dispose();
    _superChats.dispose();
    _playerSuperChats.dispose();
  }

  bool _updateBatchMask({required bool preferNative}) {
    _danmakuBatchMask.dispose();
    final resolution = resolveAppDanmakuBatchMask(preferNative: preferNative);
    _danmakuBatchMask = resolution.mask;
    return resolution.usingNative;
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

  void _scheduleDanmakuReconnect() {
    if (_activeRoomDetail == null ||
        _disposed ||
        current.reconnectInFlight ||
        current.reconnectScheduled) {
      return;
    }
    final attempt = current.reconnectAttempt + 1;
    final delay = Duration(
      seconds: math.min(12, math.max(2, attempt * 2)),
    );
    _emit(
      current.copyWith(
        reconnectAttempt: attempt,
        reconnectScheduled: true,
      ),
    );
    _trace(
      'danmaku reconnect scheduled attempt=$attempt '
      'delay=${delay.inSeconds}s',
    );
    final reconnectGeneration = _reconnectGeneration;
    _danmakuReconnectTimer = Timer(delay, () {
      _danmakuReconnectTimer = null;
      if (_disposed || reconnectGeneration != _reconnectGeneration) {
        return;
      }
      _emit(current.copyWith(reconnectScheduled: false));
      unawaited(
        _attemptDanmakuReconnect(
          attempt: attempt,
          reconnectGeneration: reconnectGeneration,
        ),
      );
    });
  }

  Future<void> _attemptDanmakuReconnect({
    required int attempt,
    required int reconnectGeneration,
  }) async {
    final detail = _activeRoomDetail;
    final bindGeneration = _bindGeneration;
    if (detail == null ||
        _disposed ||
        current.reconnectInFlight ||
        reconnectGeneration != _reconnectGeneration) {
      return;
    }
    _emit(current.copyWith(reconnectInFlight: true));
    try {
      final nextSession = await dependencies.openRoomDanmaku(
        providerId: providerId,
        detail: detail,
      );
      if (_disposed ||
          reconnectGeneration != _reconnectGeneration ||
          bindGeneration != _bindGeneration ||
          !_sameRoom(detail, _activeRoomDetail)) {
        await nextSession?.disconnect();
        return;
      }
      _trace('danmaku reconnect attempt=$attempt');
      await bindSession(
        activeRoomDetail: detail,
        session: nextSession,
      );
    } catch (error) {
      if (_disposed || reconnectGeneration != _reconnectGeneration) {
        return;
      }
      _trace('danmaku reconnect failed attempt=$attempt: $error');
      _emit(current.copyWith(reconnectInFlight: false));
      if (shouldRetryDanmakuConnectionError(
        providerId: providerId,
        error: error,
      )) {
        _scheduleDanmakuReconnect();
      } else {
        _trace('danmaku reconnect halted after non-retryable error');
        resetReconnectState();
      }
    }
  }

  Future<void> _disposeSessionInternal({required bool clearSession}) async {
    _danmakuFlushTimer?.cancel();
    _danmakuFlushTimer = null;
    _pendingDanmakuMessages.clear();
    _playerSuperChatOverlayTimer?.cancel();
    _playerSuperChatOverlayTimer = null;
    final subscription = _danmakuSubscription;
    _danmakuSubscription = null;
    final session = current.session;
    final disconnectFuture = session?.disconnect();
    if (!_disposed && clearSession) {
      _emit(current.copyWith(clearSession: true));
    }
    await subscription?.cancel();
    if (disconnectFuture != null) {
      unawaited(
        disconnectFuture.catchError((Object error, StackTrace stackTrace) {
          _trace('danmaku disconnect failed: $error');
        }),
      );
    }
  }

  Future<void> _resumeAfterLifecycleSuspendIfNeeded({
    required bool inPictureInPictureMode,
  }) async {
    if (!_suspendedByLifecycle || inPictureInPictureMode) {
      return;
    }
    final detail = _activeRoomDetail;
    _suspendedByLifecycle = false;
    if (detail == null || current.session != null) {
      return;
    }
    try {
      final nextSession = await dependencies.openRoomDanmaku(
        providerId: providerId,
        detail: detail,
      );
      if (_disposed ||
          _suspendedByLifecycle ||
          !_sameRoom(detail, _activeRoomDetail)) {
        await nextSession?.disconnect();
        return;
      }
      await bindSession(
        activeRoomDetail: detail,
        session: nextSession,
      );
    } catch (error) {
      if (_disposed) {
        return;
      }
      _trace('danmaku lifecycle resume failed: $error');
      _suspendedByLifecycle = true;
    }
  }

  void _syncPlayerSuperChatOverlay([List<LiveMessage>? history]) {
    final source = history ?? _superChats.value;
    final visible = source.length <= 2
        ? source
        : source.sublist(source.length - 2, source.length);
    if (!listEquals(_playerSuperChats.value, visible)) {
      _playerSuperChats.value = visible;
    }
    _playerSuperChatOverlayTimer?.cancel();
    _playerSuperChatOverlayTimer = null;
    if (visible.isEmpty) {
      return;
    }
    _playerSuperChatOverlayTimer = Timer(_playerSuperChatDisplayDuration, () {
      if (_disposed) {
        return;
      }
      _playerSuperChats.value = const <LiveMessage>[];
    });
  }

  void _flushPendingDanmaku() {
    if (_disposed || _pendingDanmakuMessages.isEmpty) {
      return;
    }
    final batch = List<LiveMessage>.from(_pendingDanmakuMessages);
    _pendingDanmakuMessages.clear();
    final filtered = _filter.apply(batch);
    final allowListed = _danmakuBatchMask.allowListBatch(filtered);
    if (allowListed.isEmpty) {
      return;
    }

    final merged = mergeRoomDanmakuBatch(
      messages: _messages.value,
      superChats: _superChats.value,
      incoming: allowListed,
    );
    if (merged.hasSuperChatUpdate) {
      _superChats.value = merged.superChats;
      _syncPlayerSuperChatOverlay(merged.superChats);
    }
    if (merged.hasMessageUpdate) {
      _messages.value = merged.messages;
    }
  }

  bool _sameRoom(LiveRoomDetail left, LiveRoomDetail? right) {
    if (right == null) {
      return false;
    }
    return left.providerId == right.providerId && left.roomId == right.roomId;
  }

  LiveMessage _buildDanmakuNotice(String content) {
    return LiveMessage(
      type: LiveMessageType.notice,
      content: content,
      timestamp: DateTime.now(),
    );
  }

  void _emit(RoomDanmakuState next) {
    if (_disposed) {
      return;
    }
    _state.value = next;
  }

  void _trace(String message) {
    trace?.call(message);
  }
}
