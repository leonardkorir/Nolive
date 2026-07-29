import 'dart:io';

import 'package:live_providers/live_providers.dart';

Future<void> main() async {
  final yt = YouTubeProvider.live();
  var rooms = await yt.searchRooms('live news');
  if (rooms.items.isEmpty) {
    rooms = await yt.fetchRecommendRooms(page: 1);
  }
  stdout.writeln('rooms=${rooms.items.length}');
  final detail = await yt.fetchRoomDetail(rooms.items.first.roomId);
  stdout.writeln('room=${detail.roomId} live=${detail.isLive}');
  stdout.writeln('metaKeys=${detail.metadata?.keys.toList()}');
  stdout.writeln('playerJsUrl=${detail.metadata?['playerJsUrl']}');
  final q = await yt.fetchPlayQualities(detail);
  final urls = await yt.fetchPlayUrls(detail: detail, quality: q.first);
  for (final u in urls.take(5)) {
    final uri = Uri.tryParse(u.url);
    final n = uri?.queryParameters['n'];
    final pathN = <String>[];
    final segs = uri?.pathSegments ?? const [];
    for (var i = 0; i < segs.length - 1; i++) {
      if (segs[i] == 'n') pathN.add(segs[i + 1]);
    }
    stdout.writeln(
      'url nQuery=$n pathN=$pathN headers=${u.headers.keys.toList()}',
    );
    stdout.writeln('  ${u.url.substring(0, u.url.length.clamp(0, 120))}');
  }
}
