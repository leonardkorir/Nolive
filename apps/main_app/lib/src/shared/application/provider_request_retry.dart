import 'package:live_core/live_core.dart';
import 'package:live_providers/live_providers.dart';

/// Retries [action] against a freshly rebuilt provider instance.
///
/// This is the app-layer counterpart to [runProviderRequestWithRetry]: that one
/// retries a single HTTP call inside a transport, this one retries a whole
/// provider operation and drops the cached instance in between, for failures
/// that poison provider state rather than a single request. Bilibili's web
/// endpoints intermittently answer a cold-start request with an unparseable or
/// empty payload, and only a rebuilt instance recovers.
///
/// [shouldRetryResult] additionally retries a *successful* result that is not
/// usable yet (an empty first page, say).
///
/// Each attempt holds a [ProviderLease], so the eviction between attempts never
/// disposes an instance a concurrent caller is still reading from.
Future<T> retryProviderRequestWithRebuild<T>({
  required ProviderRegistry registry,
  required ProviderId providerId,
  required String operation,
  required Future<T> Function(LiveProvider provider) action,
  int maxAttempts = 1,
  Duration retryDelay = Duration.zero,
  bool Function(T result)? shouldRetryResult,
}) async {
  final attempts = maxAttempts < 1 ? 1 : maxAttempts;
  ProviderParseException? lastError;

  for (var attempt = 1; attempt <= attempts; attempt += 1) {
    if (attempt > 1) {
      registry.invalidate(providerId);
      if (retryDelay > Duration.zero) {
        await Future<void>.delayed(retryDelay);
      }
    }
    try {
      final result = await registry.use(providerId, action);
      if (attempt >= attempts || shouldRetryResult?.call(result) != true) {
        return result;
      }
    } on ProviderParseException catch (error) {
      lastError = error;
      if (attempt >= attempts) {
        rethrow;
      }
    }
  }

  throw lastError ??
      ProviderParseException(
        providerId: providerId,
        message: '${providerId.value} $operation failed unexpectedly.',
      );
}
