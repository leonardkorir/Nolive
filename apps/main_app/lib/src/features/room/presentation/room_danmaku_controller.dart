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

/// Whether a danmaku **connection/chrome** state change should schedule a full
/// room page rebuild (not the message list — that uses separate listenables).
bool shouldScheduleFullRoomPageRebuildForDanmakuState({
  required RoomDanmakuState previous,
  required RoomDanmakuState next,
}) {
  if (identical(previous, next)) {
    return false;
  }
  if (!identical(previous.session, next.session)) {
    return true;
  }
  if (previous.reconnectInFlight != next.reconnectInFlight) {
    return true;
  }
  if (previous.reconnectScheduled != next.reconnectScheduled) {
    return true;
  }
  if (previous.reconnectAttempt != next.reconnectAttempt) {
    return true;
  }
  if (previous.usingNativeBatchMask != next.usingNativeBatchMask) {
    return true;
  }
  if (!_danmakuKeywordListEqual(
    previous.blockedKeywords,
    next.blockedKeywords,
  )) {
    return true;
  }
  return false;
}

bool _danmakuKeywordListEqual(List<String> left, List<String> right) {
  if (identical(left, right)) {
    return true;
  }
  if (left.length != right.length) {
    return false;
  }
  for (var i = 0; i < left.length; i += 1) {
    if (left[i] != right[i]) {
      return false;
    }
  }
  return true;
}

@visibleForTesting
bool shouldRetryDanmakuConnectionError({
  required ProviderId providerId,
  required Object error,
  int reconnectAttempt = 0,
}) {
  if (providerId == ProviderId.stripchat && error is TimeoutException) {
    return reconnectAttempt < 2;
  }
  if (providerId != ProviderId.chaturbate) {
    return true;
  }
  if (error is! ProviderParseException) {
    return true;
  }
  final message = error.message.toLowerCase();
  final blockedByCloudflare = message.contains('cloudflare challenge');
  final chaturbate403 =
      message.contains('status 403') &&
      (message.contains('/push_service/auth/') ||
          message.contains('/push_service/room_history/'));
  return !(blockedByCloudflare || chaturbate403);
}

class RoomDanmakuController {
  static const Duration _defaultConnectTimeout = Duration(seconds: 6);
  static const Duration _douyuConnectTimeout = Duration(seconds: 20);
  static const Duration _chaturbateConnectTimeout = Duration(seconds: 20);
  static const Duration _stripchatConnectTimeout = Duration(seconds: 20);
  static const Duration _defaultDanmakuTelemetryInterval = Duration(
    seconds: 10,
  );

  RoomDanmakuController({
    required this.dependencies,
    required this.providerId,
    this.trace,
    this.connectTimeout = _defaultConnectTimeout,
    this.danmakuTelemetryInterval = _defaultDanmakuTelemetryInterval,
    this.reconnectDelayBuilder,
  }) : _state = ValueNotifier<RoomDanmakuState>(
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
    '活动超时',
  ];

  final RoomDanmakuDependencies dependencies;
  ProviderId providerId;
  final void Function(String message)? trace;

  void retargetRoom({required ProviderId providerId}) {
    this.providerId = providerId;
  }
  final Duration connectTimeout;
  final Duration danmakuTelemetryInterval;
  final Duration Function(int attempt)? reconnectDelayBuilder;
  final ValueNotifier<RoomDanmakuState> _state;
  final ValueNotifier<List<LiveMessage>> _messages;
  final ValueNotifier<List<LiveMessage>> _superChats;
  final ValueNotifier<List<LiveMessage>> _playerSuperChats;
  Future<void>? _disposeFuture;

  final List<LiveMessage> _pendingDanmakuMessages = <LiveMessage>[];

  DanmakuBatchMask? _danmakuBatchMask;
  DanmakuFilterService _filter = DanmakuFilterService(
    config: DanmakuFilterConfig(blockedKeywords: <String>{}),
  );
  LiveRoomDetail? _activeRoomDetail;
  Timer? _danmakuFlushTimer;
  Timer? _danmakuTelemetryTimer;
  Timer? _playerSuperChatOverlayTimer;
  Timer? _danmakuReconnectTimer;
  StreamSubscription<LiveMessage>? _danmakuSubscription;
  int _playerSuperChatDisplaySeconds = 8;
  int _frequencyWindowSeconds = 8;
  int _maxFrequency = 2;
  int _bindGeneration = 0;
  int _reconnectGeneration = 0;
  bool _suspendedByLifecycle = false;
  bool _disposed = false;
  DateTime? _danmakuTelemetryWindowStartedAt;
  int _danmakuWindowReceived = 0;
  int _danmakuWindowDisplayed = 0;
  int _danmakuWindowFilteredDropped = 0;
  int _danmakuWindowBatchMaskDropped = 0;
  int _danmakuTotalReceived = 0;
  int _danmakuTotalDisplayed = 0;
  int _danmakuTotalFilteredDropped = 0;
  int _danmakuTotalBatchMaskDropped = 0;

  ValueListenable<RoomDanmakuState> get listenable => _state;

  ValueListenable<List<LiveMessage>> get messages => _messages;

  ValueListenable<List<LiveMessage>> get superChats => _superChats;

  ValueListenable<List<LiveMessage>> get playerSuperChats => _playerSuperChats;

  RoomDanmakuState get current => _state.value;

  void configure({
    required List<String> blockedKeywords,
    required bool preferNativeBatchMask,
    required int playerSuperChatDisplaySeconds,
    int frequencyWindowSeconds = 8,
    int maxFrequency = 2,
  }) {
    if (_disposed) {
      return;
    }
    _playerSuperChatDisplaySeconds = playerSuperChatDisplaySeconds;
    _frequencyWindowSeconds = frequencyWindowSeconds;
    _maxFrequency = maxFrequency;
    _filter = DanmakuFilterService(
      config: DanmakuFilterConfig(blockedKeywords: blockedKeywords.toSet()),
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
    _trace(
      'danmaku bind start room=${activeRoomDetail.roomId} '
      'bind=$bindGeneration session=${_describeSession(session)}',
    );
    await _disposeSessionInternal(clearSession: true, reason: 'bind start');
    resetReconnectState();
    if (_disposed || bindGeneration != _bindGeneration) {
      _trace(
        'danmaku bind abandoned room=${activeRoomDetail.roomId} '
        'bind=$bindGeneration disposed=$_disposed stale=${bindGeneration != _bindGeneration}',
      );
      await session?.disconnect();
      return;
    }
    if (session == null) {
      _trace(
        'danmaku bind ready room=${activeRoomDetail.roomId} '
        'bind=$bindGeneration session=-',
      );
      _emit(current.copyWith(clearSession: true));
      return;
    }

    _emit(current.copyWith(session: session));
    _startDanmakuTelemetry(
      activeRoomDetail: activeRoomDetail,
      session: session,
    );
    _danmakuFlushTimer = Timer.periodic(_danmakuFlushInterval, (_) {
      _flushPendingDanmaku();
    });
    _danmakuSubscription = session.messages.listen(
      (message) {
        if (_disposed) {
          return;
        }
        _recordDanmakuMessageReceived();
        if (_shouldReconnectDanmaku(message)) {
          _trace(
            'danmaku reconnect trigger room=${_describeRoom(_activeRoomDetail)} '
            'notice=${_summarizeReconnectCause(message.content)}',
          );
          _scheduleDanmakuReconnect(cause: message.content);
        }
        _pendingDanmakuMessages.add(message);
        if (_pendingDanmakuMessages.length >= _danmakuFlushBurstLimit) {
          _flushPendingDanmaku();
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (_disposed) {
          return;
        }
        _trace('danmaku stream error: $error');
        _pendingDanmakuMessages.add(_buildDanmakuNotice('弹幕连接异常：$error'));
        _flushPendingDanmaku();
        _scheduleDanmakuReconnect(cause: 'stream-error=$error');
      },
      onDone: () {
        if (_disposed) {
          return;
        }
        _trace('danmaku stream closed unexpectedly');
        _pendingDanmakuMessages.add(_buildDanmakuNotice('弹幕连接已断开'));
        _flushPendingDanmaku();
        _scheduleDanmakuReconnect(cause: 'stream-done');
      },
      cancelOnError: false,
    );

    try {
      final effectiveConnectTimeout = _resolveConnectTimeout();
      _trace(
        'danmaku connect start room=${activeRoomDetail.roomId} '
        'bind=$bindGeneration session=${_describeSession(session)} '
        'timeout=${effectiveConnectTimeout.inMilliseconds}ms',
      );
      await session.connect().timeout(effectiveConnectTimeout);
      if (_disposed || bindGeneration != _bindGeneration) {
        _trace(
          'danmaku connect stale room=${activeRoomDetail.roomId} '
          'bind=$bindGeneration disposed=$_disposed stale=${bindGeneration != _bindGeneration}',
        );
        await session.disconnect();
        return;
      }
      _trace(
        'danmaku connect ready room=${activeRoomDetail.roomId} '
        'bind=$bindGeneration session=${_describeSession(session)}',
      );
      _flushPendingDanmaku();
    } catch (error) {
      final staleAfterFailure = _disposed || bindGeneration != _bindGeneration;
      if (staleAfterFailure) {
        _trace(
          'danmaku connect stale after failure room=${activeRoomDetail.roomId} '
          'bind=$bindGeneration disposed=$_disposed stale=${bindGeneration != _bindGeneration} '
          'error=$error',
        );
        await session.disconnect();
        return;
      }
      _trace(
        'danmaku connect failed room=${activeRoomDetail.roomId} '
        'bind=$bindGeneration session=${_describeSession(session)} error=$error',
      );
      _pendingDanmakuMessages.add(_buildDanmakuNotice('弹幕连接失败：$error'));
      _flushPendingDanmaku();
      if (!_disposed && bindGeneration == _bindGeneration) {
        await _disposeSessionInternal(
          clearSession: true,
          reason: 'connect failure',
        );
        if (shouldRetryDanmakuConnectionError(
          providerId: providerId,
          error: error,
          reconnectAttempt: current.reconnectAttempt,
        )) {
          _scheduleDanmakuReconnect(cause: 'connect-failed=$error');
        } else {
          _trace('danmaku reconnect suppressed for non-retryable error');
          resetReconnectState();
        }
      } else {
        await session.disconnect();
      }
    }
  }

  Duration _resolveConnectTimeout() {
    return resolveDanmakuConnectTimeout(
      providerId: providerId,
      configuredTimeout: connectTimeout,
    );
  }

  Future<void> closeSession() async {
    final detail = _activeRoomDetail;
    _bindGeneration += 1;
    _suspendedByLifecycle = false;
    _activeRoomDetail = null;
    _trace(
      'danmaku close room=${_describeRoom(detail)} '
      'session=${_describeSession(current.session)}',
    );
    resetReconnectState();
    await _disposeSessionInternal(clearSession: true, reason: 'close session');
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
    _trace(
      'danmaku lifecycle suspend state=${state.name} '
      'room=${_describeRoom(_activeRoomDetail)} '
      'session=${_describeSession(current.session)}',
    );
    resetReconnectState();
    await _disposeSessionInternal(
      clearSession: true,
      reason: 'lifecycle ${state.name}',
    );
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

  Future<void> dispose() {
    return disposeAsync();
  }

  Future<void> disposeAsync() async {
    final pendingDispose = _disposeFuture;
    if (pendingDispose != null) {
      return pendingDispose;
    }
    final future = _disposeAsync();
    _disposeFuture = future;
    return future;
  }

  Future<void> _disposeAsync() async {
    if (_disposed) {
      return;
    }
    final detail = _activeRoomDetail;
    final session = current.session;
    _disposed = true;
    _suspendedByLifecycle = false;
    _bindGeneration += 1;
    _activeRoomDetail = null;
    _danmakuFlushTimer?.cancel();
    _danmakuFlushTimer = null;
    _stopDanmakuTelemetry(reason: 'dispose');
    _playerSuperChatOverlayTimer?.cancel();
    _playerSuperChatOverlayTimer = null;
    _danmakuReconnectTimer?.cancel();
    _danmakuReconnectTimer = null;
    _pendingDanmakuMessages.clear();
    _trace(
      'danmaku dispose room=${_describeRoom(detail)} '
      'session=${_describeSession(session)}',
    );

    final subscription = _danmakuSubscription;
    _danmakuSubscription = null;
    final disconnectFuture = session?.disconnect();

    if (subscription != null) {
      try {
        await subscription.cancel();
      } catch (error) {
        _trace('danmaku subscription cancel failed error=$error');
      }
    }
    if (disconnectFuture != null) {
      try {
        await disconnectFuture;
      } catch (error) {
        _trace('danmaku session disconnect failed error=$error');
      }
    }
    _danmakuBatchMask?.dispose();
    _state.dispose();
    _messages.dispose();
    _superChats.dispose();
    _playerSuperChats.dispose();
  }

  bool _updateBatchMask({required bool preferNative}) {
    _danmakuBatchMask?.dispose();
    final resolution = resolveAppDanmakuBatchMask(
      preferNative: preferNative,
      window: Duration(seconds: _frequencyWindowSeconds.clamp(2, 60)),
      burstLimit: _maxFrequency.clamp(1, 20),
    );
    _danmakuBatchMask = resolution.mask;
    return resolution.usingNative;
  }

  Duration get _playerSuperChatDisplayDuration =>
      Duration(seconds: _playerSuperChatDisplaySeconds.clamp(3, 30));

  bool _shouldReconnectDanmaku(LiveMessage message) {
    if (message.type != LiveMessageType.notice) {
      return false;
    }
    return _danmakuReconnectSignals.any(
      (signal) => message.content.contains(signal),
    );
  }

  void _scheduleDanmakuReconnect({String? cause}) {
    if (_activeRoomDetail == null ||
        _disposed ||
        _suspendedByLifecycle ||
        current.reconnectInFlight ||
        current.reconnectScheduled) {
      if (_suspendedByLifecycle && !_disposed && _activeRoomDetail != null) {
        _trace(
          'danmaku reconnect suppressed while lifecycle suspended '
          'room=${_describeRoom(_activeRoomDetail)}',
        );
      }
      return;
    }
    final attempt = current.reconnectAttempt + 1;
    final delay =
        reconnectDelayBuilder?.call(attempt) ??
        Duration(seconds: math.min(12, math.max(2, attempt * 2)));
    _emit(
      current.copyWith(reconnectAttempt: attempt, reconnectScheduled: true),
    );
    _trace(
      'danmaku reconnect scheduled attempt=$attempt '
      'delay=${delay.inMilliseconds}ms room=${_describeRoom(_activeRoomDetail)} '
      'cause=${_summarizeReconnectCause(cause)}',
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
        _suspendedByLifecycle ||
        current.reconnectInFlight ||
        reconnectGeneration != _reconnectGeneration) {
      return;
    }
    _emit(current.copyWith(reconnectInFlight: true));
    try {
      _trace(
        'danmaku reconnect open attempt=$attempt '
        'room=${_describeRoom(detail)}',
      );
      final nextSession = await dependencies.openRoomDanmaku(
        providerId: providerId,
        detail: detail,
      );
      if (_disposed ||
          _suspendedByLifecycle ||
          reconnectGeneration != _reconnectGeneration ||
          bindGeneration != _bindGeneration ||
          !_sameRoom(detail, _activeRoomDetail)) {
        await nextSession?.disconnect();
        return;
      }
      _trace(
        'danmaku reconnect bind attempt=$attempt '
        'room=${_describeRoom(detail)} '
        'session=${_describeSession(nextSession)}',
      );
      await bindSession(activeRoomDetail: detail, session: nextSession);
    } catch (error) {
      if (_disposed || reconnectGeneration != _reconnectGeneration) {
        return;
      }
      _trace('danmaku reconnect failed attempt=$attempt: $error');
      _emit(current.copyWith(reconnectInFlight: false));
      if (shouldRetryDanmakuConnectionError(
        providerId: providerId,
        error: error,
        reconnectAttempt: current.reconnectAttempt,
      )) {
        _scheduleDanmakuReconnect(cause: 'reconnect-failed=$error');
      } else {
        _trace('danmaku reconnect halted after non-retryable error');
        resetReconnectState();
      }
    }
  }

  Future<void> _disposeSessionInternal({
    required bool clearSession,
    required String reason,
  }) async {
    _danmakuFlushTimer?.cancel();
    _danmakuFlushTimer = null;
    _stopDanmakuTelemetry(reason: reason);
    _pendingDanmakuMessages.clear();
    _playerSuperChatOverlayTimer?.cancel();
    _playerSuperChatOverlayTimer = null;
    final subscription = _danmakuSubscription;
    _danmakuSubscription = null;
    final session = current.session;
    if (subscription != null || session != null) {
      _trace(
        'danmaku session dispose reason=$reason '
        'room=${_describeRoom(_activeRoomDetail)} '
        'session=${_describeSession(session)} clear=$clearSession',
      );
    }
    final disconnectFuture = session?.disconnect();
    if (!_disposed && clearSession) {
      _emit(current.copyWith(clearSession: true));
    }
    try {
      await subscription?.cancel();
    } catch (error) {
      _trace('danmaku subscription cancel failed: $error');
    }
    if (disconnectFuture != null) {
      try {
        await disconnectFuture;
      } catch (error) {
        _trace('danmaku disconnect failed: $error');
      }
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
    final bindGeneration = _bindGeneration;
    try {
      _trace('danmaku lifecycle resume open room=${_describeRoom(detail)}');
      final nextSession = await dependencies.openRoomDanmaku(
        providerId: providerId,
        detail: detail,
      );
      if (_disposed ||
          _suspendedByLifecycle ||
          bindGeneration != _bindGeneration ||
          !_sameRoom(detail, _activeRoomDetail)) {
        await nextSession?.disconnect();
        return;
      }
      _trace(
        'danmaku lifecycle resume bind room=${_describeRoom(detail)} '
        'session=${_describeSession(nextSession)}',
      );
      await bindSession(activeRoomDetail: detail, session: nextSession);
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
    final filteredDropped = batch.length - filtered.length;
    _recordDanmakuFilteredDropped(filteredDropped);
    final batchMask = _danmakuBatchMask;
    if (batchMask == null) {
      _trace('danmaku batch mask unavailable, dropping pending batch');
      _recordDanmakuBatchMaskDropped(filtered.length);
      return;
    }
    final allowListed = batchMask.allowListBatch(filtered);
    _recordDanmakuBatchMaskDropped(filtered.length - allowListed.length);
    if (allowListed.isEmpty) {
      return;
    }
    _recordDanmakuDisplayed(allowListed.length);

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

  void _startDanmakuTelemetry({
    required LiveRoomDetail activeRoomDetail,
    required DanmakuSession session,
  }) {
    _stopDanmakuTelemetry(reason: 'rebind');
    _resetDanmakuTelemetryCounters();
    _danmakuTelemetryWindowStartedAt = DateTime.now();
    if (danmakuTelemetryInterval <= Duration.zero) {
      return;
    }
    _trace(
      'danmaku throughput start room=${activeRoomDetail.roomId} '
      'provider=${providerId.value} session=${_describeSession(session)} '
      'intervalMs=${danmakuTelemetryInterval.inMilliseconds}',
    );
    _danmakuTelemetryTimer = Timer.periodic(danmakuTelemetryInterval, (_) {
      _emitDanmakuTelemetry(finalSample: false, reason: 'periodic');
    });
  }

  void _stopDanmakuTelemetry({required String reason}) {
    _danmakuTelemetryTimer?.cancel();
    _danmakuTelemetryTimer = null;
    _emitDanmakuTelemetry(finalSample: true, reason: reason);
    _danmakuTelemetryWindowStartedAt = null;
  }

  void _resetDanmakuTelemetryCounters() {
    _danmakuWindowReceived = 0;
    _danmakuWindowDisplayed = 0;
    _danmakuWindowFilteredDropped = 0;
    _danmakuWindowBatchMaskDropped = 0;
    _danmakuTotalReceived = 0;
    _danmakuTotalDisplayed = 0;
    _danmakuTotalFilteredDropped = 0;
    _danmakuTotalBatchMaskDropped = 0;
  }

  void _recordDanmakuMessageReceived() {
    _danmakuWindowReceived += 1;
    _danmakuTotalReceived += 1;
  }

  void _recordDanmakuDisplayed(int count) {
    if (count <= 0) {
      return;
    }
    _danmakuWindowDisplayed += count;
    _danmakuTotalDisplayed += count;
  }

  void _recordDanmakuFilteredDropped(int count) {
    if (count <= 0) {
      return;
    }
    _danmakuWindowFilteredDropped += count;
    _danmakuTotalFilteredDropped += count;
  }

  void _recordDanmakuBatchMaskDropped(int count) {
    if (count <= 0) {
      return;
    }
    _danmakuWindowBatchMaskDropped += count;
    _danmakuTotalBatchMaskDropped += count;
  }

  void _emitDanmakuTelemetry({
    required bool finalSample,
    required String reason,
  }) {
    final windowStartedAt = _danmakuTelemetryWindowStartedAt;
    if (windowStartedAt == null) {
      return;
    }
    final hasWindowActivity =
        _danmakuWindowReceived > 0 ||
        _danmakuWindowDisplayed > 0 ||
        _danmakuWindowFilteredDropped > 0 ||
        _danmakuWindowBatchMaskDropped > 0;
    if (!finalSample && !hasWindowActivity) {
      return;
    }
    if (finalSample &&
        !hasWindowActivity &&
        _danmakuTotalReceived == 0 &&
        _danmakuTotalDisplayed == 0) {
      return;
    }
    final now = DateTime.now();
    final elapsed = now.difference(windowStartedAt);
    final elapsedMs = math.max(1, elapsed.inMilliseconds);
    final elapsedSeconds = elapsedMs / Duration.millisecondsPerSecond;
    final receivedPerSecond = _danmakuWindowReceived / elapsedSeconds;
    final displayedPerSecond = _danmakuWindowDisplayed / elapsedSeconds;
    _trace(
      'danmaku throughput room=${_describeRoom(_activeRoomDetail)} '
      'provider=${providerId.value} session=${_describeSession(current.session)} '
      'intervalMs=$elapsedMs received=$_danmakuWindowReceived '
      'receivedPerSec=${receivedPerSecond.toStringAsFixed(2)} '
      'displayed=$_danmakuWindowDisplayed '
      'displayedPerSec=${displayedPerSecond.toStringAsFixed(2)} '
      'filteredDropped=$_danmakuWindowFilteredDropped '
      'batchMaskDropped=$_danmakuWindowBatchMaskDropped '
      'pending=${_pendingDanmakuMessages.length} '
      'totalReceived=$_danmakuTotalReceived '
      'totalDisplayed=$_danmakuTotalDisplayed '
      'totalFilteredDropped=$_danmakuTotalFilteredDropped '
      'totalBatchMaskDropped=$_danmakuTotalBatchMaskDropped '
      'final=$finalSample reason=$reason',
    );
    _danmakuTelemetryWindowStartedAt = now;
    _danmakuWindowReceived = 0;
    _danmakuWindowDisplayed = 0;
    _danmakuWindowFilteredDropped = 0;
    _danmakuWindowBatchMaskDropped = 0;
  }

  void _trace(String message) {
    trace?.call(message);
  }

  String _describeSession(DanmakuSession? session) {
    return session?.runtimeType.toString() ?? '-';
  }

  String _describeRoom(LiveRoomDetail? detail) {
    return detail?.roomId ?? '-';
  }

  String _summarizeReconnectCause(String? cause) {
    final normalized = cause?.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
    if (normalized.isEmpty) {
      return '-';
    }
    if (normalized.length <= 120) {
      return normalized;
    }
    return '${normalized.substring(0, 117)}...';
  }
}

@visibleForTesting
Duration resolveDanmakuConnectTimeout({
  required ProviderId providerId,
  required Duration configuredTimeout,
}) {
  if (configuredTimeout != RoomDanmakuController._defaultConnectTimeout) {
    return configuredTimeout;
  }
  if (providerId == ProviderId.douyu) {
    return RoomDanmakuController._douyuConnectTimeout;
  }
  if (providerId == ProviderId.stripchat) {
    return RoomDanmakuController._stripchatConnectTimeout;
  }
  if (providerId == ProviderId.chaturbate) {
    return RoomDanmakuController._chaturbateConnectTimeout;
  }
  return configuredTimeout;
}
