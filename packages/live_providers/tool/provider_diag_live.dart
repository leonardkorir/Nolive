import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_providers/live_providers.dart';

Future<void> main() async {
  await inspectYouTube();
  await inspectTwitch();
}

Future<void> inspectYouTube() async {
  final provider = YouTubeProvider.live();
  print('=== YouTube ===');
  final recommend = await provider.fetchRecommendRooms();
  print('recommend count: ${recommend.items.length}');
  for (final room in recommend.items.take(5)) {
    print(
      'room ${room.roomId} | ${room.streamerName} | live=${room.isLive} | viewers=${room.viewerCount}',
    );
  }

  for (final target in recommend.items.take(5)) {
    try {
      print('detail target: ${target.roomId}');
      final detail = await provider.fetchRoomDetail(target.roomId);
      print('detail roomId: ${detail.roomId}');
      print('detail sourceUrl: ${detail.sourceUrl}');
      print('detail isLive: ${detail.isLive}');
      print('detail title: ${detail.title}');
      print('detail reason: ${detail.metadata?['playbackUnavailableReason']}');
      print('detail status: ${detail.metadata?['playabilityStatus']}');
      print('detail hls: ${detail.metadata?['hlsManifestUrl']}');
      print('detail danmaku: ${detail.danmakuToken != null}');

      final qualities = await provider.fetchPlayQualities(detail);
      print('qualities count: ${qualities.length}');
      for (final quality in qualities.take(3)) {
        print(
          'quality ${quality.id} | ${quality.label} | meta=${jsonEncode(quality.metadata)}',
        );
      }

      if (qualities.isNotEmpty) {
        final urls = await provider.fetchPlayUrls(
          detail: detail,
          quality: qualities.first,
        );
        print('urls count: ${urls.length}');
        for (final url in urls.take(2)) {
          print('url ${url.lineLabel ?? '-'} | ${url.url}');
          print('headers ${jsonEncode(url.headers)}');
        }
      }
    } catch (error) {
      print('detail failed for ${target.roomId}: $error');
    }
  }
}

Future<void> inspectTwitch() async {
  final provider = TwitchProvider.live();
  print('=== Twitch ===');
  final recommend = await provider.fetchRecommendRooms();
  print('recommend count: ${recommend.items.length}');
  for (final room in recommend.items.take(10)) {
    print(
      'room ${room.roomId} | ${room.streamerName} | live=${room.isLive} | viewers=${room.viewerCount}',
    );
  }

  final target = recommend.items.cast<LiveRoom?>().firstWhere(
        (item) => item != null && item.roomId.trim().isNotEmpty,
        orElse: () => null,
      );
  if (target == null) {
    print('no target room');
    return;
  }

  print('detail target: ${target.roomId}');
  final detail = await provider.fetchRoomDetail(target.roomId);
  print('detail roomId: ${detail.roomId}');
  print('detail sourceUrl: ${detail.sourceUrl}');
  print('detail isLive: ${detail.isLive}');
  print('detail title: ${detail.title}');
  print('detail area: ${detail.areaName}');
  print('detail metadata: ${jsonEncode(detail.metadata)}');

  final qualities = await provider.fetchPlayQualities(detail);
  print('qualities count: ${qualities.length}');
  for (final quality in qualities.take(5)) {
    print(
      'quality ${quality.id} | ${quality.label} | meta=${jsonEncode(quality.metadata)}',
    );
  }

  if (qualities.length > 1) {
    final urls = await provider.fetchPlayUrls(
      detail: detail,
      quality: qualities[1],
    );
    print('urls count: ${urls.length}');
    for (final url in urls.take(5)) {
      print(
        'url ${url.lineLabel ?? '-'} | ${url.url} | meta=${jsonEncode(url.metadata)}',
      );
      print('headers ${jsonEncode(url.headers)}');
    }
  }
}
