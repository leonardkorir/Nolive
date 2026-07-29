import 'package:live_core/live_core.dart';
import 'package:live_providers/live_providers.dart';

class OpenRoomDanmakuUseCase {
  const OpenRoomDanmakuUseCase(this.registry);

  final ProviderRegistry registry;

  Future<DanmakuSession?> call({
    required ProviderId providerId,
    required LiveRoomDetail detail,
  }) async {
    // A danmaku session outlives this call, so the lease is held until the
    // session disconnects rather than released on return.
    final borrowed = registry.lease(providerId);
    try {
      final provider = borrowed.provider;
      if (!provider.supports(ProviderCapability.danmaku)) {
        borrowed.release();
        return null;
      }
      final danmaku = provider.requireContract<SupportsDanmaku>(
        ProviderCapability.danmaku,
      );
      final session = await danmaku.createDanmakuSession(detail);
      return LeasedDanmakuSession(session, borrowed);
    } catch (_) {
      borrowed.release();
      rethrow;
    }
  }
}

/// Keeps the provider lease alive for as long as [inner] is connected.
///
/// [inner] is public because room diagnostics report the session type to say
/// *why* danmaku is or isn't flowing — a wrapper that hid it behind its own
/// runtimeType would turn every `session=` trace into `LeasedDanmakuSession`
/// and lose the answer.
class LeasedDanmakuSession implements DanmakuSession {
  LeasedDanmakuSession(this.inner, this._lease);

  /// The provider-built session this delegates to.
  final DanmakuSession inner;
  final ProviderLease _lease;

  @override
  Stream<LiveMessage> get messages => inner.messages;

  /// Delegated, not defaulted: wrapping a placeholder session must not make it
  /// look like a live connection.
  @override
  String? get unavailableReason => inner.unavailableReason;

  @override
  Future<void> connect() => inner.connect();

  @override
  Future<void> disconnect() async {
    try {
      await inner.disconnect();
    } finally {
      _lease.release();
    }
  }
}

/// Unwraps [LeasedDanmakuSession] so diagnostics report the real session type.
DanmakuSession? unwrapDanmakuSession(DanmakuSession? session) {
  return session is LeasedDanmakuSession ? session.inner : session;
}
