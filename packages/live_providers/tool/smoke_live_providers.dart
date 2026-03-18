import 'dart:io';

import 'package:live_providers/live_providers.dart';
import 'package:live_providers/src/tooling/provider_smoke.dart';

Future<void> main() async {
  final cases = <ProviderSmokeCase>[
    ProviderSmokeCase(
      name: 'bilibili',
      provider: BilibiliProvider.live(),
      query: '聊天',
    ),
    ProviderSmokeCase(
      name: 'douyu',
      provider: DouyuProvider.live(),
      query: '王者荣耀',
    ),
    ProviderSmokeCase(
      name: 'huya',
      provider: HuyaProvider.live(),
      query: '王者荣耀',
    ),
    ProviderSmokeCase(
      name: 'douyin',
      provider: DouyinProvider.live(),
      query: '',
    ),
  ];
  final failures = <String>[];

  for (final smokeCase in cases) {
    print('== ${smokeCase.name} ==');
    try {
      final result = await runProviderSmokeCase(smokeCase);
      print('rooms=${result.rooms.items.length}');

      final room = result.selectedRoom;
      if (room != null) {
        print(
            'room=${room.roomId} title=${room.title} streamer=${room.streamerName}');
      }

      final detail = result.detail;
      if (detail != null) {
        print(
          'detail=${detail.roomId} live=${detail.isLive} area=${detail.areaName ?? ''}',
        );
      }

      if (result.qualities.isNotEmpty) {
        print(
          'qualities=${result.qualities.map((item) => item.label).join(',')}',
        );
      } else {
        print('qualities=0');
      }

      print('urls=${result.urls.length}');
      if (result.urls.isNotEmpty) {
        print(result.urls.first.url);
      }

      final validationError = validateProviderSmokeResult(result);
      if (validationError != null) {
        failures.add(validationError);
      }
    } catch (error) {
      failures.add('${smokeCase.name}: $error');
    }
  }

  if (failures.isEmpty) {
    return;
  }

  stderr.writeln('Provider smoke failed:');
  for (final failure in failures) {
    stderr.writeln('- $failure');
  }
  exitCode = 1;
}
