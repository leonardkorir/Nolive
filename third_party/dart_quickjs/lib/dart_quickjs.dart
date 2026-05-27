// Copyright (c) 2024, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// QuickJS JavaScript engine bindings for Dart.
///
/// This library provides FFI bindings to the QuickJS-ng JavaScript engine,
/// allowing you to execute JavaScript code from Dart applications.
///
/// Example:
/// ```dart
/// import 'package:dart_quickjs/dart_quickjs.dart';
///
/// void main() {
///   final runtime = JsRuntime();
///
///   // Evaluate JavaScript code
///   final result = runtime.eval('1 + 2');
///   print(result); // 3
///
///   // Evaluate a function
///   final fn = runtime.eval('(function(a, b) { return a * b; })');
///   final product = runtime.call(fn, [3, 4]);
///   print(product); // 12
///
///   runtime.dispose();
/// }
/// ```
library;

export 'src/runtime.dart';
export 'src/exceptions.dart';

// TODO: Export any libraries intended for clients of this package.
