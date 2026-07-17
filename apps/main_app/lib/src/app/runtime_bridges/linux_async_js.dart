import 'dart:convert';

import 'package:live_hls_proxy/live_hls_proxy.dart';

/// Pure helpers for Linux WebView `callAsyncJavaScript` polyfill.
///
/// WebKitGTK `evaluate_javascript` does **not** await JavaScript Promises —
/// `jsc_value_to_json` on a Promise yields an empty/unusable value. The shipped
/// path therefore:
/// 1. Starts an async job that writes `{done, ok, value, error}` on
///    `window.__noliveAsyncJobs[jobId]`
/// 2. Polls that slot until `done == true` (or timeout)
///
/// These builders/parsers are pure so unit tests can prove we never treat a
/// pending Promise as a completed result.
class LinuxAsyncJsJobCodec {
  LinuxAsyncJsJobCodec._();

  /// Script that starts the async job and returns the string `"started"`.
  ///
  /// The script body must **not** return the Promise itself to the evaluator.
  static String buildStartScript({
    required String jobId,
    required String functionBody,
    required Map<String, dynamic> arguments,
  }) {
    final jobIdJson = jsonEncode(jobId);
    final argsJson = jsonEncode(arguments);
    return '''
(function() {
  if (!window.__noliveAsyncJobs) {
    window.__noliveAsyncJobs = {};
  }
  window.__noliveAsyncJobs[$jobIdJson] = {
    done: false,
    ok: null,
    value: null,
    error: null
  };
  (async function() {
    const args = $argsJson;
    try {
      const __noliveAsync = async function() {
        $functionBody
      };
      const value = await __noliveAsync.apply(null, Object.values(args));
      window.__noliveAsyncJobs[$jobIdJson] = {
        done: true,
        ok: true,
        value: value,
        error: null
      };
    } catch (e) {
      window.__noliveAsyncJobs[$jobIdJson] = {
        done: true,
        ok: false,
        value: null,
        error: String(e)
      };
    }
  })();
  return "started";
})()
''';
  }

  /// Script that JSON-stringifies the job slot (or a pending stub).
  static String buildPollScript(String jobId) {
    final jobIdJson = jsonEncode(jobId);
    return '''
(function() {
  var job = window.__noliveAsyncJobs && window.__noliveAsyncJobs[$jobIdJson];
  if (!job) {
    return JSON.stringify({ done: false, missing: true });
  }
  try {
    return JSON.stringify(job);
  } catch (e) {
    return JSON.stringify({
      done: true,
      ok: false,
      value: null,
      error: "serialize failed: " + String(e)
    });
  }
})()
''';
  }

  /// Parses a poll payload. Returns `null` while the job is still pending.
  ///
  /// A non-null return means the async work finished (ok or error).
  static HlsJavaScriptResult? parsePollPayload(Object? raw) {
    if (raw == null) return null;
    final text = raw.toString().trim();
    if (text.isEmpty || text == 'null' || text == 'undefined') {
      return null;
    }
    // Strip optional surrounding quotes from jsc_value_to_json string results.
    var payload = text;
    if (payload.length >= 2 &&
        payload.startsWith('"') &&
        payload.endsWith('"')) {
      try {
        payload = jsonDecode(payload) as String;
      } catch (_) {
        // keep raw
      }
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(payload);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;
    final map = Map<String, dynamic>.from(decoded);
    final done = map['done'] == true;
    if (!done) {
      // Critical: pending jobs must not surface a value.
      return null;
    }
    if (map['ok'] == true) {
      return HlsJavaScriptResult(value: map['value']);
    }
    return HlsJavaScriptResult(
      error: map['error']?.toString() ?? 'async javascript failed',
    );
  }

  /// Resolve from an ordered poll sequence (test / harness helper).
  ///
  /// Returns the first completed result; throws if the sequence ends while
  /// still pending (caller would timeout in production).
  static HlsJavaScriptResult resolveFromPollSequence(
    List<Object?> pollPayloads,
  ) {
    for (final payload in pollPayloads) {
      final result = parsePollPayload(payload);
      if (result != null) {
        return result;
      }
    }
    throw StateError(
      'async javascript job never completed within poll sequence',
    );
  }
}
