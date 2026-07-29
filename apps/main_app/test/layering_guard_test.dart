import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the feature layering that the room refactor established.
///
/// `application/` holds use cases, policies and orchestration; `presentation/`
/// holds widgets and the controllers that drive them. Imports may only point
/// presentation -> application. A single reverse edge is enough to make the
/// boundary meaningless again, so this test fails on the first one.
void main() {
  final libRoot = Directory('lib/src');

  List<File> dartFilesUnder(String segment) {
    if (!libRoot.existsSync()) {
      return const <File>[];
    }
    return libRoot
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where((file) => file.path.contains('/$segment/'))
        .toList(growable: false);
  }

  Iterable<String> importsOf(File file) sync* {
    final pattern = RegExp("""^\\s*(?:import|export)\\s+['"]([^'"]+)['"]""");
    for (final line in file.readAsLinesSync()) {
      final match = pattern.firstMatch(line);
      if (match != null) {
        yield match.group(1)!;
      }
    }
  }

  test('lib/src exists so the guard is actually scanning something', () {
    expect(libRoot.existsSync(), isTrue);
    expect(dartFilesUnder('application'), isNotEmpty);
    expect(dartFilesUnder('presentation'), isNotEmpty);
  });

  test('application never imports presentation', () {
    final violations = <String>[];
    for (final file in dartFilesUnder('application')) {
      for (final import in importsOf(file)) {
        final pointsAtPresentation =
            import.contains('/presentation/') ||
            (!import.startsWith('package:') &&
                !import.startsWith('dart:') &&
                import.contains('presentation/'));
        if (pointsAtPresentation) {
          violations.add('${file.path} -> $import');
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'application/ must not depend on presentation/. Move the shared type '
          'into application/ (policies, state, ports) or invert the dependency.',
    );
  });

  test('room application layer stays free of platform plugins', () {
    // Plugin-backed adapters belong in app/platform/. There is no longer an
    // exception for `floating`: RoomPipHostFacade speaks RoomPipStatus and
    // RoomPipAspectRatio, and the switcher widget moved to the platform layer.
    const bannedPlugins = <String>[
      'package:wakelock_plus/',
      'package:window_manager/',
      'package:floating/',
    ];
    final violations = <String>[];
    for (final file in dartFilesUnder('application')) {
      if (!file.path.contains('/room/')) {
        continue;
      }
      for (final import in importsOf(file)) {
        for (final banned in bannedPlugins) {
          if (import.startsWith(banned)) {
            violations.add('${file.path} -> $import');
          }
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'Keep plugin usage in app/platform/ adapters; the room application '
          'layer should only see the abstract ports.',
    );
  });
}
