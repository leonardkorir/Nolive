import 'package:live_providers/live_providers.dart';

void walk(Object? v, void Function(String) onUrl) {
  if (v is String) {
    if (v.contains('videoplayback')) onUrl(v);
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
  // ignore: avoid_print
  print('videoplayback count=${urls.length}');
  for (final u in urls.take(3)) {
    final uri = Uri.parse(u);
    // ignore: avoid_print
    print('keys=${uri.queryParameters.keys.toList()}');
    // ignore: avoid_print
    print('n=${uri.queryParameters['n']} s=${uri.queryParameters['s']}');
    // ignore: avoid_print
    print('url=${u.substring(0, u.length.clamp(0, 180))}');
  }
}
