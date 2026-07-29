import 'package:live_providers/live_providers.dart';
import 'package:live_providers/src/tooling/provider_smoke.dart';

Future<void> main() async {
  final cases = <ProviderSmokeCase>[
    ProviderSmokeCase(
      name: 'twitch',
      provider: TwitchProvider.live(),
      query: '',
    ),
    ProviderSmokeCase(
      name: 'youtube',
      provider: YouTubeProvider.live(),
      query: '',
    ),
    ProviderSmokeCase(
      name: 'chaturbate',
      provider: ChaturbateProvider.live(),
      query: '',
    ),
    ProviderSmokeCase(
      name: 'stripchat',
      provider: StripchatProvider.live(),
      query: '',
    ),
  ];
  for (final c in cases) {
    print('== ${c.name} ==');
    try {
      final r = await runProviderSmokeCase(c);
      print('rooms=${r.rooms.items.length}');
      if (r.selectedRoom != null) {
        print('room=${r.selectedRoom!.roomId} title=${r.selectedRoom!.title}');
      }
      if (r.detail != null) {
        print('detail live=${r.detail!.isLive}');
      }
      print(
        'qualities=${r.qualities.map((e) => e.label).join(",")} count=${r.qualities.length}',
      );
      print('urls=${r.urls.length}');
      if (r.urls.isNotEmpty) {
        final u = r.urls.first.url;
        print(u.length > 140 ? '${u.substring(0, 140)}...' : u);
      }
      final err = validateProviderSmokeResult(r);
      if (err != null) print('validate=$err');
    } catch (e) {
      print('ERR $e');
    }
  }
}
