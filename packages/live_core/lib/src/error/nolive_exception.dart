import '../provider/provider_capability.dart';
import '../provider/provider_id.dart';

abstract class NoliveException implements Exception {
  const NoliveException({
    required this.code,
    required this.message,
    this.cause,
    this.stackTrace,
  });

  final String code;
  final String message;
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  String toString() {
    return '$runtimeType($code): $message';
  }
}

class ProviderException extends NoliveException {
  const ProviderException({
    required super.code,
    required super.message,
    this.providerId,
    this.transient = false,
    super.cause,
    super.stackTrace,
  });

  final ProviderId? providerId;

  /// True when this failure is a transport blip (connection reset, closed
  /// client, timeout, retryable status) rather than a definitive answer from
  /// the site (auth, not-found, payload mismatch).
  ///
  /// Callers deciding whether to retry must read this instead of matching on
  /// [message]: the text is diagnostic, not a contract.
  final bool transient;
}

class ProviderCapabilityException extends ProviderException {
  ProviderCapabilityException.unsupported({
    required ProviderId providerId,
    required ProviderCapability capability,
  }) : super(
         code: 'provider.unsupported_capability',
         message:
             'Provider ${providerId.value} does not support capability ${capability.name}.',
         providerId: providerId,
       );
}

class ProviderContractException extends ProviderException {
  ProviderContractException.misaligned({
    required ProviderId providerId,
    required ProviderCapability capability,
    required String expectedContract,
  }) : super(
         code: 'provider.contract_misaligned',
         message:
             'Provider ${providerId.value} declares ${capability.name} but does not implement $expectedContract.',
         providerId: providerId,
       );
}

class ProviderNotImplementedException extends ProviderException {
  ProviderNotImplementedException.migration({
    required ProviderId providerId,
    required String feature,
  }) : super(
         code: 'provider.not_implemented',
         message:
             'Provider ${providerId.value} has not implemented $feature in the current migration phase.',
         providerId: providerId,
       );
}

class ProviderParseException extends ProviderException {
  ProviderParseException({
    required ProviderId providerId,
    required super.message,
    super.transient,
    super.cause,
    super.stackTrace,
  }) : super(code: 'provider.parse_failure', providerId: providerId);

  /// Returns this failure re-tagged as [transient].
  ProviderParseException asTransient() {
    if (transient) {
      return this;
    }
    return ProviderParseException(
      providerId: providerId!,
      message: message,
      transient: true,
      cause: cause,
      stackTrace: stackTrace,
    );
  }
}

class PlayerException extends NoliveException {
  const PlayerException({
    required super.code,
    required super.message,
    super.cause,
    super.stackTrace,
  });
}

class SyncException extends NoliveException {
  const SyncException({
    required super.code,
    required super.message,
    super.cause,
    super.stackTrace,
  });
}
