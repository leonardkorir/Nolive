// Copyright (c) 2024, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    // Only build code assets if requested
    if (!input.config.buildCodeAssets) {
      return;
    }

    final packageName = input.packageName;
    final targetOS = input.config.code.targetOS;
    final targetArch = input.config.code.targetArchitecture;

    // Check if targeting 32-bit ARM
    final isArm32 = targetArch == Architecture.arm;

    // QuickJS source files relative to package root
    const quickjsDir = 'third_party/quickjs-ng';
    final sources = [
      '$quickjsDir/cutils.c',
      '$quickjsDir/dtoa.c',
      '$quickjsDir/libregexp.c',
      '$quickjsDir/libunicode.c',
      '$quickjsDir/quickjs.c',
      '$quickjsDir/quickjs-libc.c',
    ];

    // Platform-specific defines
    final defines = <String, String?>{'_GNU_SOURCE': null};

    // Windows-specific defines
    if (targetOS == OS.windows) {
      defines['WIN32_LEAN_AND_MEAN'] = null;
      defines['_WIN32_WINNT'] = '0x0601';
      // Export symbols on Windows
      defines['JS_EXTERN'] = '__declspec(dllexport)';
    }

    // macOS/iOS framework define
    if (targetOS == OS.macOS || targetOS == OS.iOS) {
      defines['JS_EXTERN'] = '__attribute__((visibility("default")))';
    }

    // Linux/Android shared library
    if (targetOS == OS.linux || targetOS == OS.android) {
      defines['JS_EXTERN'] = '__attribute__((visibility("default")))';
    }

    // Compiler flags
    final flags = <String>[];

    // Libraries to link
    final libraries = <String>[];

    // Add C11 standard and disable warnings for non-Windows platforms
    if (targetOS != OS.windows) {
      flags.addAll([
        '-Wno-implicit-fallthrough',
        '-Wno-sign-compare',
        '-Wno-missing-field-initializers',
        '-Wno-unused-parameter',
        '-Wno-unused-but-set-variable',
      ]);

      // On Linux
      if (targetOS == OS.linux) {
        // Link math library explicitly
        libraries.add('m');
        // Add flags for better compatibility when used as a dependency
        flags.addAll([
          '-fPIC', // Position independent code (required for shared libraries)
          '-fno-strict-aliasing', // Disable strict aliasing optimizations
          '-fno-omit-frame-pointer', // Keep frame pointer for better debugging
          '-fwrapv', // Wrap signed integer overflow (safer behavior)
        ]);
        // Disable computed goto / direct dispatch on Linux
        // This prevents SIGSEGV when the library is loaded by another application
        // The jump table can trigger "Invalid permissions for mapped object" errors
        defines['DIRECT_DISPATCH'] = '0';
      }

      // On Android, explicitly link libm for math functions like scalbn
      if (targetOS == OS.android) {
        libraries.add('m'); // libm - math library
        // Improve compatibility with older Android devices (e.g., Android 9)
        // Disable some optimizations that may cause issues on certain ARM devices
        flags.addAll([
          '-fno-fast-math', // Ensure strict floating-point behavior
          '-fstack-protector-strong', // Stack protection
        ]);

        // Disable computed goto / direct dispatch on Android
        // This uses a jump table that some Android devices flag as "executing non-executable memory"
        defines['DIRECT_DISPATCH'] = '0';

        // Special handling for ARM32 (armeabi-v7a)
        if (isArm32) {
          flags.addAll([
            '-marm', // Generate ARM code, not Thumb (more compatible)
            '-fno-omit-frame-pointer', // Keep frame pointer for debugging
            '-fno-strict-aliasing', // Disable strict aliasing
          ]);
          // Disable NaN boxing on ARM32 to use consistent 16-byte JSValue struct
          // This matches our FFI bindings and avoids pointer packing issues
          defines['JS_NAN_BOXING'] = '0';
        }
      }
    } else {
      // MSVC requires experimental flag for C11 atomics support
      flags.add('/experimental:c11atomics');
    }

    // Build the library
    final builder = CBuilder.library(
      name: packageName,
      assetName: 'src/quickjs_bindings.g.dart',
      sources: sources,
      includes: [quickjsDir],
      defines: defines,
      flags: flags,
      libraries: libraries,
      std: 'c11', // QuickJS-ng requires C11 for stdatomic.h
    );

    await builder.run(
      input: input,
      output: output,
      logger: Logger('')
        ..level = Level.ALL
        ..onRecord.listen((record) => print(record.message)),
    );
  });
}
