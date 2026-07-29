import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:live_core/live_core.dart';

/// Whether [error] is a transport-level blip worth another attempt.
///
/// This classifies by **type**, never by message text: a reworded or localized
/// exception message must not silently turn retries off. Provider failures that
/// already carry [ProviderException.transient] are trusted directly; anything
/// else is matched against the socket / HTTP client error types that mean "we
/// never got an answer from the site".
///
/// A definitive answer (auth rejection, not found, unparseable payload) is not
/// transient — retrying only wastes a request and delays the error the user
/// needs to see.
bool isTransientTransportFailure(Object? error) {
  if (error == null) {
    return false;
  }
  if (error is TimeoutException) {
    return true;
  }
  if (error is SocketException ||
      error is HttpException ||
      error is TlsException ||
      error is http.ClientException) {
    return true;
  }
  if (error is ProviderException) {
    if (error.transient) {
      return true;
    }
    // Transports wrap the raw failure as `cause`; a provider that has not been
    // migrated to the transient flag still classifies correctly through it.
    return isTransientTransportFailure(error.cause);
  }
  return false;
}
