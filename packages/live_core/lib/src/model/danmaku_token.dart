import 'model_equality.dart';

/// Opaque handle a provider needs in order to open its danmaku session.
///
/// The core contract deliberately does **not** know the per-site shape. Each
/// provider declares its own subclass inside `live_providers`, next to the
/// provider that produces and consumes it, and nothing outside that provider
/// reads the fields back. Adding a live platform must not require editing this
/// package — that is why this type is `abstract` rather than `sealed`.
///
/// Only the two site-independent cases live here: [PreviewDanmakuToken] (the
/// deterministic preview runtime) and [UnavailableDanmakuToken] (the provider
/// answered, but there is no chat to join).
abstract class DanmakuToken {
  const DanmakuToken();

  /// Value-identity fields, in a stable order.
  List<Object?> get props;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other.runtimeType == runtimeType &&
            modelListEquals((other as DanmakuToken).props, props);
  }

  @override
  int get hashCode => Object.hash(runtimeType, modelListHash(props));
}

/// Preview/demo runtime: sessions replay a deterministic ticker.
final class PreviewDanmakuToken extends DanmakuToken {
  const PreviewDanmakuToken();

  @override
  List<Object?> get props => const [];
}

/// The provider resolved the room but chat cannot be joined.
final class UnavailableDanmakuToken extends DanmakuToken {
  const UnavailableDanmakuToken({required this.reason, this.cause});

  final String reason;
  final String? cause;

  @override
  List<Object?> get props => [reason, cause];
}
