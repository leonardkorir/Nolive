import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('feature presentation code does not consume AppBootstrap directly', () {
    final root = _featureSourceRoot();
    final offenders = <String>[];

    for (final file in _dartFiles(root)) {
      final path = file.path;
      if (!path.contains('/presentation/')) {
        continue;
      }
      final content = file.readAsStringSync();
      if (_consumesAppBootstrap(content)) {
        offenders.add(path);
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Feature pages must receive feature-scoped dependencies instead of AppBootstrap.',
    );
  });

  test('feature AppBootstrap references stay in dependency factory files', () {
    final root = _featureSourceRoot();
    final offenders = <String>[];

    for (final file in _dartFiles(root)) {
      final path = file.path;
      final content = file.readAsStringSync();
      if (!_consumesAppBootstrap(content)) {
        continue;
      }
      if (_isDependencyFactoryFile(path)) {
        continue;
      }
      offenders.add(path);
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Feature-level AppBootstrap references are allowed only at explicit dependency factory boundaries.',
    );
  });
}

Directory _featureSourceRoot() {
  for (final path in const <String>[
    'lib/src/features',
    'apps/main_app/lib/src/features',
  ]) {
    final directory = Directory(path);
    if (directory.existsSync()) {
      return directory;
    }
  }
  fail(
    'Could not find the main app feature source root from '
    '${Directory.current.path}.',
  );
}

Iterable<File> _dartFiles(Directory root) sync* {
  final files =
      root
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .toList()
        ..sort((left, right) => left.path.compareTo(right.path));

  yield* files;
}

bool _consumesAppBootstrap(String content) {
  return content.contains('AppBootstrap') ||
      content.contains("src/app/bootstrap/bootstrap.dart") ||
      content.contains('src/app/bootstrap/bootstrap.dart');
}

bool _isDependencyFactoryFile(String path) {
  final normalized = path.replaceAll('\\', '/');
  return normalized.contains('/application/') &&
      normalized.endsWith('_dependencies.dart');
}
