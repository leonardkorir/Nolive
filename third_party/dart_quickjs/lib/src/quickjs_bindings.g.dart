// Copyright (c) 2024, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// AUTO GENERATED FILE, DO NOT EDIT.
// Generated QuickJS-ng FFI bindings.

// ignore_for_file: non_constant_identifier_names, camel_case_types

@ffi.DefaultAsset('package:dart_quickjs/src/quickjs_bindings.g.dart')
library;

import 'dart:ffi' as ffi;

import 'package:ffi/ffi.dart';

// Opaque types for QuickJS structures
final class JSRuntime extends ffi.Opaque {}

final class JSContext extends ffi.Opaque {}

/// JSValue structure for non-NaN-boxing mode (64-bit systems and ARM32 with JS_NAN_BOXING=0)
/// Layout: 8 bytes union + 8 bytes tag = 16 bytes total
///
/// The union contains:
/// - int32 (4 bytes, for integers)
/// - double (8 bytes, for float64)
/// - ptr (4 or 8 bytes depending on platform)
///
/// We access it as a single 64-bit value and extract what we need.
final class JSValue extends ffi.Struct {
  /// The union value - stores int32, float64, or ptr depending on tag
  /// For int32 values: only lower 32 bits are valid
  /// For float64 values: all 64 bits represent the double
  @ffi.Int64()
  external int u;

  /// The tag indicating the type of value stored
  @ffi.Int64()
  external int tag;
}

// ============================================================
// Runtime functions
// ============================================================

@ffi.Native<ffi.Pointer<JSRuntime> Function()>()
external ffi.Pointer<JSRuntime> JS_NewRuntime();

@ffi.Native<ffi.Void Function(ffi.Pointer<JSRuntime>)>()
external void JS_FreeRuntime(ffi.Pointer<JSRuntime> rt);

@ffi.Native<ffi.Void Function(ffi.Pointer<JSRuntime>, ffi.Size)>()
external void JS_SetMemoryLimit(ffi.Pointer<JSRuntime> rt, int limit);

@ffi.Native<ffi.Void Function(ffi.Pointer<JSRuntime>, ffi.Size)>()
external void JS_SetMaxStackSize(ffi.Pointer<JSRuntime> rt, int stackSize);

@ffi.Native<ffi.Void Function(ffi.Pointer<JSRuntime>)>()
external void JS_RunGC(ffi.Pointer<JSRuntime> rt);

// ============================================================
// Context functions
// ============================================================

@ffi.Native<ffi.Pointer<JSContext> Function(ffi.Pointer<JSRuntime>)>()
external ffi.Pointer<JSContext> JS_NewContext(ffi.Pointer<JSRuntime> rt);

@ffi.Native<ffi.Void Function(ffi.Pointer<JSContext>)>()
external void JS_FreeContext(ffi.Pointer<JSContext> ctx);

@ffi.Native<ffi.Pointer<JSRuntime> Function(ffi.Pointer<JSContext>)>()
external ffi.Pointer<JSRuntime> JS_GetRuntime(ffi.Pointer<JSContext> ctx);

@ffi.Native<JSValue Function(ffi.Pointer<JSContext>)>()
external JSValue JS_GetGlobalObject(ffi.Pointer<JSContext> ctx);

// ============================================================
// Evaluation functions
// ============================================================

@ffi.Native<
  JSValue Function(
    ffi.Pointer<JSContext>,
    ffi.Pointer<Utf8>,
    ffi.Size,
    ffi.Pointer<Utf8>,
    ffi.Int32,
  )
>()
external JSValue JS_Eval(
  ffi.Pointer<JSContext> ctx,
  ffi.Pointer<Utf8> input,
  int inputLen,
  ffi.Pointer<Utf8> filename,
  int evalFlags,
);

// ============================================================
// Value functions
// ============================================================

@ffi.Native<ffi.Void Function(ffi.Pointer<JSContext>, JSValue)>()
external void JS_FreeValue(ffi.Pointer<JSContext> ctx, JSValue val);

@ffi.Native<JSValue Function(ffi.Pointer<JSContext>, JSValue)>()
external JSValue JS_DupValue(ffi.Pointer<JSContext> ctx, JSValue val);

// ============================================================
// Type conversion functions
// ============================================================

@ffi.Native<
  ffi.Pointer<Utf8> Function(
    ffi.Pointer<JSContext>,
    ffi.Pointer<ffi.Size>,
    JSValue,
    ffi.Bool,
  )
>()
external ffi.Pointer<Utf8> JS_ToCStringLen2(
  ffi.Pointer<JSContext> ctx,
  ffi.Pointer<ffi.Size> plen,
  JSValue val,
  bool cesu8,
);

@ffi.Native<ffi.Void Function(ffi.Pointer<JSContext>, ffi.Pointer<Utf8>)>()
external void JS_FreeCString(ffi.Pointer<JSContext> ctx, ffi.Pointer<Utf8> ptr);

@ffi.Native<ffi.Int32 Function(ffi.Pointer<JSContext>, JSValue)>()
external int JS_ToBool(ffi.Pointer<JSContext> ctx, JSValue val);

@ffi.Native<
  ffi.Int32 Function(ffi.Pointer<JSContext>, ffi.Pointer<ffi.Int32>, JSValue)
>()
external int JS_ToInt32(
  ffi.Pointer<JSContext> ctx,
  ffi.Pointer<ffi.Int32> pres,
  JSValue val,
);

@ffi.Native<
  ffi.Int32 Function(ffi.Pointer<JSContext>, ffi.Pointer<ffi.Int64>, JSValue)
>()
external int JS_ToInt64(
  ffi.Pointer<JSContext> ctx,
  ffi.Pointer<ffi.Int64> pres,
  JSValue val,
);

@ffi.Native<
  ffi.Int32 Function(ffi.Pointer<JSContext>, ffi.Pointer<ffi.Double>, JSValue)
>()
external int JS_ToFloat64(
  ffi.Pointer<JSContext> ctx,
  ffi.Pointer<ffi.Double> pres,
  JSValue val,
);

@ffi.Native<
  ffi.Int32 Function(ffi.Pointer<JSContext>, ffi.Pointer<ffi.Int64>, JSValue)
>()
external int JS_ToBigInt64(
  ffi.Pointer<JSContext> ctx,
  ffi.Pointer<ffi.Int64> pres,
  JSValue val,
);

// ============================================================
// Value creation functions
// ============================================================

@ffi.Native<
  JSValue Function(ffi.Pointer<JSContext>, ffi.Pointer<Utf8>, ffi.Size)
>()
external JSValue JS_NewStringLen(
  ffi.Pointer<JSContext> ctx,
  ffi.Pointer<Utf8> str,
  int len,
);

@ffi.Native<JSValue Function(ffi.Pointer<JSContext>, ffi.Int64)>()
external JSValue JS_NewBigInt64(ffi.Pointer<JSContext> ctx, int val);

@ffi.Native<JSValue Function(ffi.Pointer<JSContext>, JSValue)>()
external JSValue JS_ToString(ffi.Pointer<JSContext> ctx, JSValue val);

// ============================================================
// Object functions
// ============================================================

@ffi.Native<JSValue Function(ffi.Pointer<JSContext>)>()
external JSValue JS_NewObject(ffi.Pointer<JSContext> ctx);

@ffi.Native<JSValue Function(ffi.Pointer<JSContext>)>()
external JSValue JS_NewArray(ffi.Pointer<JSContext> ctx);

@ffi.Native<
  JSValue Function(ffi.Pointer<JSContext>, JSValue, ffi.Pointer<Utf8>)
>()
external JSValue JS_GetPropertyStr(
  ffi.Pointer<JSContext> ctx,
  JSValue thisObj,
  ffi.Pointer<Utf8> prop,
);

@ffi.Native<JSValue Function(ffi.Pointer<JSContext>, JSValue, ffi.Uint32)>()
external JSValue JS_GetPropertyUint32(
  ffi.Pointer<JSContext> ctx,
  JSValue thisObj,
  int idx,
);

@ffi.Native<
  ffi.Int32 Function(
    ffi.Pointer<JSContext>,
    JSValue,
    ffi.Pointer<Utf8>,
    JSValue,
  )
>()
external int JS_SetPropertyStr(
  ffi.Pointer<JSContext> ctx,
  JSValue thisObj,
  ffi.Pointer<Utf8> prop,
  JSValue val,
);

@ffi.Native<
  ffi.Int32 Function(ffi.Pointer<JSContext>, JSValue, ffi.Uint32, JSValue)
>()
external int JS_SetPropertyUint32(
  ffi.Pointer<JSContext> ctx,
  JSValue thisObj,
  int idx,
  JSValue val,
);

@ffi.Native<
  ffi.Int32 Function(ffi.Pointer<JSContext>, JSValue, ffi.Pointer<ffi.Int64>)
>()
external int JS_GetLength(
  ffi.Pointer<JSContext> ctx,
  JSValue obj,
  ffi.Pointer<ffi.Int64> pres,
);

// ============================================================
// Function calling
// ============================================================

@ffi.Native<
  JSValue Function(
    ffi.Pointer<JSContext>,
    JSValue,
    JSValue,
    ffi.Int32,
    ffi.Pointer<JSValue>,
  )
>()
external JSValue JS_Call(
  ffi.Pointer<JSContext> ctx,
  JSValue funcObj,
  JSValue thisObj,
  int argc,
  ffi.Pointer<JSValue> argv,
);

// ============================================================
// Exception handling
// ============================================================

@ffi.Native<JSValue Function(ffi.Pointer<JSContext>)>()
external JSValue JS_GetException(ffi.Pointer<JSContext> ctx);

@ffi.Native<ffi.Bool Function(ffi.Pointer<JSContext>)>()
external bool JS_HasException(ffi.Pointer<JSContext> ctx);

@ffi.Native<ffi.Bool Function(ffi.Pointer<JSContext>, JSValue)>()
external bool JS_IsError(ffi.Pointer<JSContext> ctx, JSValue val);

// ============================================================
// Type checking functions
// ============================================================

@ffi.Native<ffi.Bool Function(ffi.Pointer<JSContext>, JSValue)>()
external bool JS_IsFunction(ffi.Pointer<JSContext> ctx, JSValue val);

@ffi.Native<ffi.Bool Function(JSValue)>()
external bool JS_IsArray(JSValue val);

// ============================================================
// JSON functions
// ============================================================

@ffi.Native<
  JSValue Function(
    ffi.Pointer<JSContext>,
    ffi.Pointer<Utf8>,
    ffi.Size,
    ffi.Pointer<Utf8>,
  )
>()
external JSValue JS_ParseJSON(
  ffi.Pointer<JSContext> ctx,
  ffi.Pointer<Utf8> buf,
  int bufLen,
  ffi.Pointer<Utf8> filename,
);

@ffi.Native<
  JSValue Function(ffi.Pointer<JSContext>, JSValue, JSValue, JSValue)
>()
external JSValue JS_JSONStringify(
  ffi.Pointer<JSContext> ctx,
  JSValue obj,
  JSValue replacer,
  JSValue space,
);

// ============================================================
// Promise/Job functions
// ============================================================

@ffi.Native<ffi.Bool Function(ffi.Pointer<JSRuntime>)>()
external bool JS_IsJobPending(ffi.Pointer<JSRuntime> rt);

@ffi.Native<
  ffi.Int32 Function(
    ffi.Pointer<JSRuntime>,
    ffi.Pointer<ffi.Pointer<JSContext>>,
  )
>()
external int JS_ExecutePendingJob(
  ffi.Pointer<JSRuntime> rt,
  ffi.Pointer<ffi.Pointer<JSContext>> pctx,
);

// ============================================================
// JS Tag constants
// ============================================================

/// JS_TAG values for checking value types
class JsTag {
  // Tags with reference count (negative values)
  static const int bigInt = -9;
  static const int symbol = -8;
  static const int string = -7;
  static const int module = -3;
  static const int functionBytecode = -2;
  static const int object = -1;

  // Tags without reference count (non-negative values)
  static const int int_ = 0;
  static const int bool_ = 1;
  static const int null_ = 2;
  static const int undefined = 3;
  static const int uninitialized = 4;
  static const int catchOffset = 5;
  static const int exception = 6;
  static const int shortBigInt = 7;
  static const int float64 = 8;
}

/// JS_EVAL flags
class JsEvalFlags {
  static const int typeGlobal = 0;
  static const int typeModule = 1;
}

/// Extension methods for JSValue
extension JSValueExtension on JSValue {
  /// Checks if this value is an exception
  bool get isException => tag == JsTag.exception;

  /// Checks if this value is undefined
  bool get isUndefined => tag == JsTag.undefined;

  /// Checks if this value is null
  bool get isNull => tag == JsTag.null_;

  /// Checks if this value is a number
  bool get isNumber => tag == JsTag.int_ || tag == JsTag.float64;

  /// Checks if this value is a string
  bool get isString => tag == JsTag.string;

  /// Checks if this value is a boolean
  bool get isBool => tag == JsTag.bool_;

  /// Checks if this value is an object
  bool get isObject => tag == JsTag.object;

  /// Checks if this value is a BigInt
  bool get isBigInt => tag == JsTag.bigInt;

  /// Checks if this value has reference count (needs to be freed)
  bool get hasRefCount => tag < 0;

  /// Gets the integer value (for int tag)
  /// In non-NaN-boxing mode, int32 is stored in the lower 32 bits of the union
  int get intValue {
    // Extract lower 32 bits as signed int32
    return (u & 0xFFFFFFFF).toSigned(32);
  }

  /// Gets the boolean value (for bool tag)
  bool get boolValue => (u & 0xFFFFFFFF) != 0;

  /// Gets the float value (for float64 tag)
  double get floatValue {
    // The float64 value is stored as bits in u
    final bytes = u.toUnsigned(64);
    final byteData = ffi.sizeOf<ffi.Double>() == 8
        ? (calloc<ffi.Uint64>()..value = bytes)
        : null;
    if (byteData != null) {
      final result = byteData.cast<ffi.Double>().value;
      calloc.free(byteData);
      return result;
    }
    return u.toDouble();
  }
}
