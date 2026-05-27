// Copyright (c) 2024, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Exception thrown when an error occurs in the QuickJS runtime.
class JsException implements Exception {
  /// The error message.
  final String message;

  /// The JavaScript stack trace, if available.
  final String? stack;

  /// Creates a new [JsException] with the given [message] and optional [stack].
  const JsException(this.message, [this.stack]);

  @override
  String toString() {
    if (stack != null && stack!.isNotEmpty) {
      return 'JsException: $message\n$stack';
    }
    return 'JsException: $message';
  }
}

/// Exception thrown when the JavaScript runtime is used after being disposed.
class JsRuntimeDisposedException implements Exception {
  /// Creates a new [JsRuntimeDisposedException].
  const JsRuntimeDisposedException();

  @override
  String toString() => 'JsRuntimeDisposedException: Runtime has been disposed';
}

/// Exception thrown when an invalid JavaScript value is encountered.
class JsInvalidValueException implements Exception {
  /// The error message.
  final String message;

  /// Creates a new [JsInvalidValueException] with the given [message].
  const JsInvalidValueException(this.message);

  @override
  String toString() => 'JsInvalidValueException: $message';
}
