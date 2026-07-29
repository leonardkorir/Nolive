import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nolive_app/src/shared/application/app_log.dart';

/// Guards diagnostic field names against AppLog's persistence redactor.
///
/// `_sensitiveHeaderAssignmentPattern` replaces everything after a bare
/// `cookie=` through end of line, so a log line that reports a *decision* with
/// a field literally named `cookie` loses that field and every field after it.
/// That happened on device (session-2026-07-26-201606): the Chaturbate failure
/// diagnostics persisted as `... source=anonymous cookie=<redacted>` and the
/// challenge / retry / advice fields vanished.
///
/// Asserting on hand-written sample strings only covers the samples. This scans
/// the actual call sites, which is what the first version of the guard missed.
void main() {
  /// `cookie=` immediately followed by an interpolation or a bare word, inside
  /// a string literal — i.e. a diagnostic field, not a real header being built.
  final suspicious = RegExp(r'''\bcookie\s*=\s*\$''');

  List<File> dartSourcesUnder(String path) {
    final dir = Directory(path);
    if (!dir.existsSync()) {
      return const <File>[];
    }
    return dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .toList(growable: false);
  }

  test('the redactor still swallows a bare cookie= field', () {
    // If this ever stops holding, the guard below is pointless and the rule it
    // enforces should be revisited rather than silently kept.
    final sanitized = AppLog.sanitizeMessageForPersistence(
      'diag source=anonymous cookie=false challenge=true',
    );

    expect(sanitized, isNot(contains('challenge=true')));
  });

  test('no diagnostic interpolates a value into a cookie= field', () {
    final roots = <String>[
      'lib',
      '../../packages/live_providers/lib',
      '../../packages/live_core/lib',
      '../../packages/live_player/lib',
      '../../packages/live_danmaku/lib',
      '../../packages/live_hls_proxy/lib',
    ];

    // Real cookie headers being assembled for a request are not diagnostics and
    // are supposed to be redacted if they ever reach a log.
    const allowed = <String>['linux_desktop_webview_adapter.dart'];

    final violations = <String>[];
    for (final root in roots) {
      for (final file in dartSourcesUnder(root)) {
        if (allowed.any(file.path.endsWith)) {
          continue;
        }
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i += 1) {
          if (suspicious.hasMatch(lines[i])) {
            violations.add('${file.path}:${i + 1}  ${lines[i].trim()}');
          }
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'Name decision fields hasCookie= (or similar). A field named cookie= '
          'is truncated by AppLog.sanitizeMessageForPersistence together with '
          'everything after it on the same line.',
    );
  });
}
