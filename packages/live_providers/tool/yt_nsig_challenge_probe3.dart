import 'package:live_providers/live_providers.dart';

void walk(Object? v, void Function(String) onUrl) {
  if (v is String) {
    if (v.contains('videoplayback') || v.contains('googlevideo')) {
      onUrl(v);
    }
  } else if (v is Map) {
    for (final e in v.values) {
      walk(e, onUrl);
    }
  } else if (v is List) {
    for (final e in v) {
      walk(e, onUrl);
    }
  }
}

Future<void> main() async {
  final yt = YouTubeProvider.live();
  final rooms = await yt.searchRooms('live news');
  final detail = await yt.fetchRoomDetail(rooms.items.first.roomId);
  final urls = <String>{};
  walk(detail.metadata, urls.add);
  var found = 0;
  for (final u in urls) {
    final uri = Uri.tryParse(u);
    if (uri == null) continue;
    final n = uri.queryParameters['n'];
    if (n != null && n.isNotEmpty) {
      found += 1;
      // ignore: avoid_print
      print('HAS_N n=$n len=${n.length}');
    }
  }
  // ignore: avoid_print
  print('done urls=${urls.length} withN=$found player=${detail.metadata?['playerJsUrl']}');
}
