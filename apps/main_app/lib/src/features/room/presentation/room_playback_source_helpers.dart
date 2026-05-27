import 'package:flutter/foundation.dart';
import 'package:live_player/live_player.dart';

String summarizePlaybackSource(PlaybackSource? source) {
  final url = source?.url;
  if (url == null) {
    return '-';
  }
  final audio = source?.externalAudio?.url;
  final base = '${url.host}${url.path}';
  if (audio == null) {
    return base;
  }
  return '$base + audio=${audio.host}${audio.path}';
}

bool samePlaybackSource(PlaybackSource? left, PlaybackSource? right) {
  if (left == null || right == null) {
    return left == right;
  }
  return left.url == right.url &&
      mapEquals(left.headers, right.headers) &&
      left.masterPlaylistUrl == right.masterPlaylistUrl &&
      left.masterPlaylistContent == right.masterPlaylistContent &&
      left.bufferProfile == right.bufferProfile &&
      left.hlsBitrate == right.hlsBitrate &&
      samePlaybackExternalMedia(left.externalAudio, right.externalAudio);
}

bool samePlaybackExternalMedia(
  PlaybackExternalMedia? left,
  PlaybackExternalMedia? right,
) {
  if (left == null || right == null) {
    return left == right;
  }
  return left.url == right.url &&
      mapEquals(left.headers, right.headers) &&
      left.label == right.label &&
      left.mimeType == right.mimeType;
}

bool samePlaybackExternalMediaForPreRefresh(
  PlaybackExternalMedia? left,
  PlaybackExternalMedia? right,
) {
  if (left == null || right == null) {
    return left == right;
  }
  return left.url == right.url;
}
