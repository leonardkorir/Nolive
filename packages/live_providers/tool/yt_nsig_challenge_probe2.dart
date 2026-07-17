import 'dart:convert';
import 'dart:io';
import 'package:live_providers/live_providers.dart';

void walk(Object? v, void Function(String) onUrl) {
  if (v is String) {
    if (v.contains('googlevideo') || v.contains('youtube.com')) onUrl(v);
  } else if (v is Map) {
    for (final e in v.values) walk(e, onUrl);
  } else if (v is List) {
    for (final e in v) walk(e, onUrl);
  }
}

Future<void> main() async {
  final yt = YouTubeProvider.live();
  final rooms = await yt.searchRooms('live news');
  final detail = await yt.fetchRoomDetail(rooms.items.first.roomId);
  print('playerJsUrl=${detail.metadata?['playerJsUrl']}');
  final urls = <String>{};
  walk(detail.metadata, urls.add);
  final withN = <String>[];
  for (final u in urls) {
    final uri = Uri.tryParse(u);
    if (uri == null) continue;
    final n = uri.queryParameters['n'];
    final segs = uri.pathSegments;
    var pathN = false;
    for (var i = 0; i < segs.length - 1; i++) {
      if (segs[i] == 'n') pathN = true;
    }
    if ((n != null && n.isNotEmpty) || pathN || u.contains('signature') || u.contains('s=')) {
      withN.add(u.length > 140 ? '${u.substring(0, 140)}...' : u);
    }
  }
  print('metaUrls=${urls.length} interesting=${withN.length}');
  for (final u in withN.take(8)) print('  $u');

  // Also inspect playbackSources raw
  final ps = detail.metadata?['playbackSources'];
  print('playbackSourcesType=${ps.runtimeType}');
  if (ps is List) {
    print('playbackSourcesLen=${ps.length}');
    if (ps.isNotEmpty) print('first=${jsonEncode(ps.first).substring(0, 200)}');
  }
}
