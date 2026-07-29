// Resolve live play URLs (with headers) and prove host MPV can demux/decode.
// Usage (from packages/live_providers): dart run tool/linux_paint_mpv_probe.dart
import 'dart:io';

import 'package:live_core/live_core.dart';
import 'package:live_providers/live_providers.dart';

Future<int> mpvDecode(LivePlayUrl play, {int frames = 20}) async {
  final args = <String>[
    '--vo=null',
    '--ao=null',
    '--frames=$frames',
    '--quiet',
    '--no-config',
    '--demuxer-readahead-secs=3',
    '--network-timeout=15',
  ];
  for (final e in play.headers.entries) {
    // mpv accepts repeated --http-header-fields
    args.add('--http-header-fields=${e.key}: ${e.value}');
  }
  args.add(play.url);
  final r = await Process.run('mpv', args, environment: Platform.environment);
  final err = r.stderr.toString();
  final out = r.stdout.toString();
  final ok =
      r.exitCode == 0 ||
      err.contains('Exiting... (End of file)') ||
      out.contains('VO:') ||
      err.contains('VO:');
  stdout.writeln(
    'mpv_exit=${r.exitCode} ok=$ok headers=${play.headers.length}',
  );
  for (final line
      in '$err\n$out'.split('\n').where((l) => l.trim().isNotEmpty).take(12)) {
    stdout.writeln('  $line');
  }
  return ok ? 0 : r.exitCode;
}

Future<void> probeTwitch() async {
  stdout.writeln('=== twitch ===');
  final tw = TwitchProvider.live();
  final rooms = await tw.fetchRecommendRooms(page: 1);
  if (rooms.items.isEmpty) {
    stdout.writeln('FAIL no rooms');
    return;
  }
  final detail = await tw.fetchRoomDetail(rooms.items.first.roomId);
  stdout.writeln('room=${detail.roomId} live=${detail.isLive}');
  final q = await tw.fetchPlayQualities(detail);
  final urls = await tw.fetchPlayUrls(detail: detail, quality: q.first);
  final u = urls.first;
  stdout.writeln('url=${u.url.substring(0, u.url.length.clamp(0, 100))}...');
  stdout.writeln('headers_keys=${u.headers.keys.toList()}');
  final code = await mpvDecode(u);
  stdout.writeln(code == 0 ? 'TW_MPV_OK' : 'TW_MPV_FAIL');
}

Future<void> probeChaturbate() async {
  stdout.writeln('=== chaturbate ===');
  final cb = ChaturbateProvider.live();
  final rooms = await cb.fetchRecommendRooms(page: 1);
  if (rooms.items.isEmpty) {
    stdout.writeln('FAIL no rooms');
    return;
  }
  final detail = await cb.fetchRoomDetail(rooms.items.first.roomId);
  stdout.writeln('room=${detail.roomId} live=${detail.isLive}');
  final q = await cb.fetchPlayQualities(detail);
  final urls = await cb.fetchPlayUrls(detail: detail, quality: q.first);
  final u = urls.first;
  stdout.writeln('url=${u.url.substring(0, u.url.length.clamp(0, 100))}...');
  stdout.writeln('headers_keys=${u.headers.keys.toList()}');
  final code = await mpvDecode(u);
  stdout.writeln(code == 0 ? 'CB_MPV_OK' : 'CB_MPV_FAIL');
}

Future<void> probeYoutube() async {
  stdout.writeln('=== youtube ===');
  final yt = YouTubeProvider.live();
  var rooms = await yt.searchRooms('live');
  if (rooms.items.isEmpty) {
    rooms = await yt.fetchRecommendRooms(page: 1);
  }
  if (rooms.items.isEmpty) {
    stdout.writeln('FAIL no rooms');
    return;
  }
  final detail = await yt.fetchRoomDetail(rooms.items.first.roomId);
  stdout.writeln('room=${detail.roomId} live=${detail.isLive}');
  final q = await yt.fetchPlayQualities(detail);
  if (q.isEmpty) {
    stdout.writeln('FAIL no qualities');
    return;
  }
  final urls = await yt.fetchPlayUrls(detail: detail, quality: q.first);
  if (urls.isEmpty) {
    stdout.writeln('FAIL no urls');
    return;
  }
  final u = urls.first;
  stdout.writeln('url=${u.url.substring(0, u.url.length.clamp(0, 100))}...');
  stdout.writeln('headers_keys=${u.headers.keys.toList()}');
  final code = await mpvDecode(u);
  stdout.writeln(code == 0 ? 'YT_MPV_OK' : 'YT_MPV_FAIL');
}

Future<void> probeOneDomestic(String name, dynamic provider) async {
  stdout.writeln('=== $name ===');
  final rooms = await provider.fetchRecommendRooms(page: 1);
  final detail = await provider.fetchRoomDetail(rooms.items.first.roomId);
  final q = await provider.fetchPlayQualities(detail);
  final urls = await provider.fetchPlayUrls(detail: detail, quality: q.first);
  final u = urls.first as LivePlayUrl;
  stdout.writeln('room=${detail.roomId} live=${detail.isLive}');
  final code = await mpvDecode(u, frames: 15);
  stdout.writeln(
    code == 0
        ? '${name.toUpperCase()}_MPV_OK'
        : '${name.toUpperCase()}_MPV_FAIL',
  );
}

Future<void> probeDouyuHuya() async {
  await probeOneDomestic('douyu', DouyuProvider.live());
  await probeOneDomestic('huya', HuyaProvider.live());
}

Future<void> probeStripchat() async {
  stdout.writeln('=== stripchat ===');
  final sc = StripchatProvider.live();
  final rooms = await sc.fetchRecommendRooms(page: 1);
  if (rooms.items.isEmpty) {
    stdout.writeln('FAIL no rooms');
    return;
  }
  final detail = await sc.fetchRoomDetail(rooms.items.first.roomId);
  stdout.writeln('room=${detail.roomId} live=${detail.isLive}');
  final q = await sc.fetchPlayQualities(detail);
  final urls = await sc.fetchPlayUrls(detail: detail, quality: q.first);
  final u = urls.first;
  stdout.writeln('url=${u.url.substring(0, u.url.length.clamp(0, 100))}...');
  stdout.writeln('headers_keys=${u.headers.keys.toList()}');
  final code = await mpvDecode(u);
  stdout.writeln(code == 0 ? 'SC_MPV_OK' : 'SC_MPV_FAIL');
}

Future<void> main(List<String> args) async {
  final only = args.isEmpty ? 'all' : args.first;
  if (only == 'all' || only == 'domestic') await probeDouyuHuya();
  if (only == 'all' || only == 'twitch') await probeTwitch();
  if (only == 'all' || only == 'chaturbate') await probeChaturbate();
  if (only == 'all' || only == 'youtube') await probeYoutube();
  if (only == 'all' || only == 'stripchat') await probeStripchat();
}
