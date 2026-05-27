import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_player/src/mpv_player.dart';

void main() {
  group('media_kit debug cleanup helpers', () {
    test('matches native reference holder files by basename', () {
      expect(
        isMediaKitNativeReferenceHolderPath(
          '/tmp/com.alexmercerind.media_kit.NativeReferenceHolder.1234',
        ),
        isTrue,
      );
      expect(
        isMediaKitNativeReferenceHolderPath(
          '/tmp/not-media-kit-reference-holder',
        ),
        isFalse,
      );
    });

    test('deletes only native reference holder files in a directory', () async {
      final directory =
          await Directory.systemTemp.createTemp('nolive-mpv-cleanup-test-');
      addTearDown(() async {
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      });

      final holderFile = File(
        '${directory.path}${Platform.pathSeparator}'
        'com.alexmercerind.media_kit.NativeReferenceHolder.111',
      );
      final otherFile = File(
        '${directory.path}${Platform.pathSeparator}keep-me.txt',
      );
      await holderFile.writeAsString('stale');
      await otherFile.writeAsString('keep');

      final deleted =
          await deleteMediaKitNativeReferenceHolderFilesInDirectory(directory);

      expect(deleted, 1);
      expect(await holderFile.exists(), isFalse);
      expect(await otherFile.exists(), isTrue);
    });
  });
}
