// Copyright (c) 2024, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'exceptions.dart';
import 'quickjs_bindings.g.dart';

/// A JavaScript runtime powered by QuickJS-ng.
///
/// Example:
/// ```dart
/// final runtime = JsRuntime();
///
/// final result = runtime.eval('1 + 2');
/// print(result); // 3
///
/// runtime.dispose();
/// ```
class JsRuntime {
  /// The QuickJS runtime pointer.
  late final Pointer<JSRuntime> _runtime;

  /// The QuickJS context pointer.
  late final Pointer<JSContext> _context;

  /// Whether the runtime has been disposed.
  bool _disposed = false;

  /// Default stack size: 512KB (conservative for mobile devices)
  static const int _defaultStackSize = 512 * 1024;

  /// Default memory limit: 64MB
  static const int _defaultMemoryLimit = 64 * 1024 * 1024;

  /// Creates a new JavaScript runtime.
  ///
  /// [memoryLimit] is the memory limit in bytes (defaults to 64MB, 0 for no limit).
  /// [maxStackSize] is the maximum stack size in bytes (defaults to 512KB, 0 for QuickJS default).
  ///
  /// For devices with limited resources (e.g., Android TV boxes), consider using
  /// smaller values to prevent crashes.
  JsRuntime({int? memoryLimit, int? maxStackSize}) {
    _runtime = JS_NewRuntime();
    if (_runtime == nullptr) {
      throw JsException('Failed to create JavaScript runtime');
    }

    // Set memory limit (default 64MB for safety on mobile devices)
    final effectiveMemoryLimit = memoryLimit ?? _defaultMemoryLimit;
    if (effectiveMemoryLimit > 0) {
      JS_SetMemoryLimit(_runtime, effectiveMemoryLimit);
    }

    // Set stack size (default 512KB to prevent stack overflow on limited devices)
    final effectiveStackSize = maxStackSize ?? _defaultStackSize;
    if (effectiveStackSize > 0) {
      JS_SetMaxStackSize(_runtime, effectiveStackSize);
    }

    _context = JS_NewContext(_runtime);
    if (_context == nullptr) {
      JS_FreeRuntime(_runtime);
      throw JsException('Failed to create JavaScript context');
    }
  }

  /// Returns true if this runtime has been disposed.
  bool get isDisposed => _disposed;

  /// Evaluates JavaScript code and returns the result.
  ///
  /// [code] is the JavaScript code to evaluate.
  /// [filename] is the filename used in error messages (defaults to '<eval>').
  /// [asModule] if true, evaluates the code as an ES module.
  ///
  /// Returns the result converted to a Dart value:
  /// - JS number -> Dart int or double
  /// - JS string -> Dart String
  /// - JS boolean -> Dart bool
  /// - JS null/undefined -> Dart null
  /// - JS array -> Dart List
  /// - JS object -> Dart Map<String, dynamic>
  /// - JS function -> throws (use evalFunction instead)
  ///
  /// Throws [JsException] if evaluation fails.
  /// Throws [JsRuntimeDisposedException] if the runtime has been disposed.
  dynamic eval(
    String code, {
    String filename = '<eval>',
    bool asModule = false,
  }) {
    _checkDisposed();

    final codePtr = code.toNativeUtf8();
    final filenamePtr = filename.toNativeUtf8();

    try {
      final flags = asModule ? JsEvalFlags.typeModule : JsEvalFlags.typeGlobal;
      final result = JS_Eval(
        _context,
        codePtr,
        code.length,
        filenamePtr,
        flags,
      );

      return _jsValueToDart(result, freeValue: true);
    } finally {
      calloc.free(codePtr);
      calloc.free(filenamePtr);
    }
  }

  /// Evaluates JavaScript code and returns a function that can be called.
  ///
  /// [code] is the JavaScript code that should return a function.
  /// [filename] is the filename used in error messages (defaults to '<eval>').
  ///
  /// Returns a [JsFunction] that can be called with arguments.
  ///
  /// Throws [JsException] if evaluation fails or the result is not a function.
  /// Throws [JsRuntimeDisposedException] if the runtime has been disposed.
  JsFunction evalFunction(String code, {String filename = '<eval>'}) {
    _checkDisposed();

    final codePtr = code.toNativeUtf8();
    final filenamePtr = filename.toNativeUtf8();

    try {
      final result = JS_Eval(
        _context,
        codePtr,
        code.length,
        filenamePtr,
        JsEvalFlags.typeGlobal,
      );

      if (result.isException) {
        _throwJsException();
      }

      if (!JS_IsFunction(_context, result)) {
        JS_FreeValue(_context, result);
        throw JsException('Evaluated code did not return a function');
      }

      return JsFunction._(this, result);
    } finally {
      calloc.free(codePtr);
      calloc.free(filenamePtr);
    }
  }

  /// Calls a JavaScript function with the given arguments.
  ///
  /// [function] is the JavaScript function to call.
  /// [args] are the arguments to pass to the function.
  /// [thisArg] is the 'this' value for the function (defaults to undefined).
  ///
  /// Returns the result converted to a Dart value.
  ///
  /// Throws [JsException] if the call fails.
  /// Throws [JsRuntimeDisposedException] if the runtime has been disposed.
  dynamic call(JsFunction function, [List<dynamic>? args, dynamic thisArg]) {
    _checkDisposed();

    final argc = args?.length ?? 0;
    Pointer<JSValue>? argv;

    // Prepare arguments
    if (argc > 0) {
      argv = calloc<JSValue>(argc);
      for (var i = 0; i < argc; i++) {
        argv[i] = _dartToJsValue(args![i]);
      }
    }

    // Prepare 'this' value
    final thisVal = thisArg != null
        ? _dartToJsValue(thisArg)
        : _createUndefined();

    try {
      final result = JS_Call(
        _context,
        function._value,
        thisVal,
        argc,
        argv ?? nullptr,
      );

      return _jsValueToDart(result, freeValue: true);
    } finally {
      // Free arguments
      if (argv != null) {
        for (var i = 0; i < argc; i++) {
          if (argv[i].hasRefCount) {
            JS_FreeValue(_context, argv[i]);
          }
        }
        calloc.free(argv);
      }

      // Free this value if it has ref count
      if (thisVal.hasRefCount) {
        JS_FreeValue(_context, thisVal);
      }
    }
  }

  /// Gets a global variable.
  ///
  /// [name] is the name of the global variable.
  ///
  /// Returns the value converted to a Dart value.
  dynamic getGlobal(String name) {
    _checkDisposed();

    final globalObj = JS_GetGlobalObject(_context);
    final namePtr = name.toNativeUtf8();

    try {
      final result = JS_GetPropertyStr(_context, globalObj, namePtr);
      return _jsValueToDart(result, freeValue: true);
    } finally {
      calloc.free(namePtr);
      JS_FreeValue(_context, globalObj);
    }
  }

  /// Sets a global variable.
  ///
  /// [name] is the name of the global variable.
  /// [value] is the value to set.
  void setGlobal(String name, dynamic value) {
    _checkDisposed();

    final globalObj = JS_GetGlobalObject(_context);
    final namePtr = name.toNativeUtf8();
    final jsValue = _dartToJsValue(value);

    try {
      final result = JS_SetPropertyStr(_context, globalObj, namePtr, jsValue);
      if (result < 0) {
        _throwJsException();
      }
    } finally {
      calloc.free(namePtr);
      JS_FreeValue(_context, globalObj);
    }
  }

  /// Runs the garbage collector.
  void runGC() {
    _checkDisposed();
    JS_RunGC(_runtime);
  }

  /// Executes pending async jobs (promises, etc.).
  ///
  /// Returns the number of jobs executed.
  int executePendingJobs() {
    _checkDisposed();

    final pctx = calloc<Pointer<JSContext>>();
    var count = 0;

    try {
      while (JS_IsJobPending(_runtime)) {
        final ret = JS_ExecutePendingJob(_runtime, pctx);
        if (ret < 0) {
          _throwJsException();
        }
        count++;
      }
    } finally {
      calloc.free(pctx);
    }

    return count;
  }

  /// Disposes this runtime and frees all resources.
  ///
  /// After calling this method, the runtime can no longer be used.
  void dispose() {
    if (_disposed) return;

    _disposed = true;
    JS_FreeContext(_context);
    JS_FreeRuntime(_runtime);
  }

  // ============================================================
  // Private methods
  // ============================================================

  void _checkDisposed() {
    if (_disposed) {
      throw const JsRuntimeDisposedException();
    }
  }

  /// Converts a JSValue to a Dart value.
  dynamic _jsValueToDart(JSValue value, {required bool freeValue}) {
    try {
      // Check for exception
      if (value.isException) {
        _throwJsException();
      }

      final tag = value.tag;

      switch (tag) {
        case JsTag.int_:
          return value.intValue;

        case JsTag.float64:
          return value.floatValue;

        case JsTag.bool_:
          return value.boolValue;

        case JsTag.null_:
        case JsTag.undefined:
          return null;

        case JsTag.string:
          final plen = calloc<Size>();
          final cstr = JS_ToCStringLen2(_context, plen, value, false);
          if (cstr == nullptr) {
            calloc.free(plen);
            throw JsException('Failed to convert string');
          }
          try {
            return cstr.toDartString(length: plen.value);
          } finally {
            calloc.free(plen);
            JS_FreeCString(_context, cstr);
          }

        case JsTag.shortBigInt:
        case JsTag.bigInt:
          final pres = calloc<Int64>();
          try {
            if (JS_ToBigInt64(_context, pres, value) < 0) {
              throw JsException('Failed to convert BigInt');
            }
            return BigInt.from(pres.value);
          } finally {
            calloc.free(pres);
          }

        case JsTag.object:
          // Check if it's an array
          if (JS_IsArray(value)) {
            return _jsArrayToList(value);
          }
          // Check if it's a function
          if (JS_IsFunction(_context, value)) {
            // Return a JsFunction that owns the value (don't free it)
            return JsFunction._(
              this,
              freeValue ? JS_DupValue(_context, value) : value,
            );
          }
          // Otherwise it's an object
          return _jsObjectToMap(value);

        default:
          return null;
      }
    } finally {
      if (freeValue && value.hasRefCount) {
        JS_FreeValue(_context, value);
      }
    }
  }

  /// Converts a JS array to a Dart List.
  List<dynamic> _jsArrayToList(JSValue value) {
    final plen = calloc<Int64>();

    try {
      if (JS_GetLength(_context, value, plen) < 0) {
        throw JsException('Failed to get array length');
      }

      final len = plen.value;
      final list = <dynamic>[];

      for (var i = 0; i < len; i++) {
        final elem = JS_GetPropertyUint32(_context, value, i);
        list.add(_jsValueToDart(elem, freeValue: true));
      }

      return list;
    } finally {
      calloc.free(plen);
    }
  }

  /// Converts a JS object to a Dart Map.
  Map<String, dynamic> _jsObjectToMap(JSValue value) {
    // Use JSON.stringify to convert the object to a string, then parse it
    final json = JS_JSONStringify(
      _context,
      value,
      _createUndefined(),
      _createUndefined(),
    );

    if (json.isException || json.isUndefined) {
      // If JSON.stringify fails (e.g., circular reference), return an empty map
      if (json.hasRefCount) {
        JS_FreeValue(_context, json);
      }
      return {};
    }

    final plen = calloc<Size>();
    final cstr = JS_ToCStringLen2(_context, plen, json, false);

    try {
      if (cstr == nullptr) {
        return {};
      }
      final jsonStr = cstr.toDartString(length: plen.value);
      JS_FreeCString(_context, cstr);
      JS_FreeValue(_context, json);

      // Parse the JSON string using Dart's JSON decoder
      final parseResult = jsonDecode(jsonStr);
      if (parseResult is Map) {
        return Map<String, dynamic>.from(parseResult);
      }
      return {};
    } finally {
      calloc.free(plen);
    }
  }

  /// Converts a Dart value to a JSValue.
  JSValue _dartToJsValue(dynamic value) {
    if (value == null) {
      return _createNull();
    }

    if (value is bool) {
      return _createBool(value);
    }

    if (value is int) {
      return _createNumber(value.toDouble());
    }

    if (value is double) {
      return _createNumber(value);
    }

    if (value is String) {
      final ptr = value.toNativeUtf8();
      final result = JS_NewStringLen(_context, ptr, value.length);
      calloc.free(ptr);
      return result;
    }

    if (value is List) {
      final arr = JS_NewArray(_context);
      for (var i = 0; i < value.length; i++) {
        final elem = _dartToJsValue(value[i]);
        JS_SetPropertyUint32(_context, arr, i, elem);
      }
      return arr;
    }

    if (value is Map) {
      final obj = JS_NewObject(_context);
      for (final entry in value.entries) {
        final keyStr = entry.key.toString();
        final keyPtr = keyStr.toNativeUtf8();
        final val = _dartToJsValue(entry.value);
        JS_SetPropertyStr(_context, obj, keyPtr, val);
        calloc.free(keyPtr);
      }
      return obj;
    }

    if (value is JsFunction) {
      return JS_DupValue(_context, value._value);
    }

    if (value is BigInt) {
      return JS_NewBigInt64(_context, value.toInt());
    }

    throw JsInvalidValueException(
      'Unsupported value type: ${value.runtimeType}',
    );
  }

  /// Creates a null JSValue.
  JSValue _createNull() {
    final v = calloc<JSValue>();
    v.ref.tag = JsTag.null_;
    v.ref.u = 0;
    final result = v.ref;
    calloc.free(v);
    return result;
  }

  /// Creates an undefined JSValue.
  JSValue _createUndefined() {
    final v = calloc<JSValue>();
    v.ref.tag = JsTag.undefined;
    v.ref.u = 0;
    final result = v.ref;
    calloc.free(v);
    return result;
  }

  /// Creates a boolean JSValue.
  JSValue _createBool(bool value) {
    final v = calloc<JSValue>();
    v.ref.tag = JsTag.bool_;
    v.ref.u = value ? 1 : 0;
    final result = v.ref;
    calloc.free(v);
    return result;
  }

  /// Creates a number JSValue.
  JSValue _createNumber(double value) {
    final v = calloc<JSValue>();
    v.ref.tag = JsTag.float64;
    // Store the double bits in the union field
    final bytes = calloc<Double>();
    bytes.value = value;
    v.ref.u = bytes.cast<Int64>().value;
    calloc.free(bytes);
    final result = v.ref;
    calloc.free(v);
    return result;
  }

  /// Throws a JsException with the current exception from the context.
  Never _throwJsException() {
    final exception = JS_GetException(_context);

    String message = 'Unknown error';
    String? stack;

    try {
      // Get error message
      final msgProp = 'message'.toNativeUtf8();
      final msgVal = JS_GetPropertyStr(_context, exception, msgProp);
      calloc.free(msgProp);

      if (!msgVal.isUndefined) {
        final plen = calloc<Size>();
        final cstr = JS_ToCStringLen2(_context, plen, msgVal, false);
        if (cstr != nullptr) {
          message = cstr.toDartString(length: plen.value);
          JS_FreeCString(_context, cstr);
        }
        calloc.free(plen);
        JS_FreeValue(_context, msgVal);
      }

      // Get stack trace
      final stackProp = 'stack'.toNativeUtf8();
      final stackVal = JS_GetPropertyStr(_context, exception, stackProp);
      calloc.free(stackProp);

      if (!stackVal.isUndefined) {
        final plen = calloc<Size>();
        final cstr = JS_ToCStringLen2(_context, plen, stackVal, false);
        if (cstr != nullptr) {
          stack = cstr.toDartString(length: plen.value);
          JS_FreeCString(_context, cstr);
        }
        calloc.free(plen);
        JS_FreeValue(_context, stackVal);
      }
    } finally {
      JS_FreeValue(_context, exception);
    }

    throw JsException(message, stack);
  }
}

/// A JavaScript function that can be called from Dart.
class JsFunction {
  final JsRuntime _runtime;
  final JSValue _value;
  bool _disposed = false;

  JsFunction._(this._runtime, this._value);

  /// Returns true if this function has been disposed.
  bool get isDisposed => _disposed;

  /// Calls this function with the given arguments.
  ///
  /// [args] are the arguments to pass to the function.
  /// [thisArg] is the 'this' value for the function (defaults to undefined).
  ///
  /// Returns the result converted to a Dart value.
  dynamic call([List<dynamic>? args, dynamic thisArg]) {
    if (_disposed) {
      throw JsRuntimeDisposedException();
    }
    return _runtime.call(this, args, thisArg);
  }

  /// Disposes this function and frees resources.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (!_runtime.isDisposed) {
      JS_FreeValue(_runtime._context, _value);
    }
  }
}
