import 'package:live_providers/src/providers/youtube/youtube_page_parser.dart';
import 'package:test/test.dart';

void main() {
  test('youtube page parser extracts api key and current video id', () {
    const html = '''
<html>
<script>
var ytInitialData = {"contents":{"twoColumnBrowseResultsRenderer":{"tabs":[{"tabRenderer":{"content":{"sectionListRenderer":{"contents":[{"itemSectionRenderer":{"contents":[{"videoRenderer":{"videoId":"abc123XYZ09","title":{"runs":[{"text":"Live now"}]}}}]}}]}}}}]}}};
</script>
<script>
ytcfg.set({
  "INNERTUBE_API_KEY":"AIzaTest",
  "INNERTUBE_CLIENT_NAME":"WEB",
  "INNERTUBE_CONTEXT":{"client":{"clientVersion":"2.20260320.01.00","visitorData":"visitor-token"}},
  "rolloutToken":"rollout-token"
});
</script>
</html>
''';
    final parser = YouTubePageParser();
    final bootstrap = parser.parsePage(
      requestedRoomId: '@demo/live',
      html: html,
    );

    expect(bootstrap.apiKey, 'AIzaTest');
    expect(bootstrap.videoId, 'abc123XYZ09');
    expect(bootstrap.innertubeContext?['client'], isA<Map>());
    expect(
      (bootstrap.innertubeContext?['client'] as Map)['visitorData'],
      'visitor-token',
    );
    expect(bootstrap.rolloutToken, 'rollout-token');
  });

  test('youtube page parser keeps only live search candidates', () {
    const html = '''
<html><script>
var ytInitialData = {
  "contents": {
    "twoColumnSearchResultsRenderer": {
      "primaryContents": {
        "sectionListRenderer": {
          "contents": [{
            "itemSectionRenderer": {
              "contents": [
                {
                  "videoRenderer": {
                    "videoId": "live1234567",
                    "title": {"runs": [{"text": "Live Coding Session"}]},
                    "ownerText": {"runs": [{"text": "Coder", "navigationEndpoint": {"commandMetadata": {"webCommandMetadata": {"url": "/@coder"}}}}]},
                    "thumbnail": {"thumbnails": [{"url": "https://i.ytimg.com/live.jpg"}]},
                    "thumbnailOverlays": [{"thumbnailOverlayTimeStatusRenderer": {"style": "LIVE"}}],
                    "viewCountText": {"simpleText": "1,234 watching"}
                  }
                },
                {
                  "videoRenderer": {
                    "videoId": "vod12345678",
                    "title": {"runs": [{"text": "Old Upload"}]},
                    "ownerText": {"runs": [{"text": "Uploader"}]},
                    "thumbnail": {"thumbnails": [{"url": "https://i.ytimg.com/vod.jpg"}]}
                  }
                }
              ]
            }
          }]
        }
      }
    }
  }
};
</script></html>
''';
    final parser = YouTubePageParser();
    final candidates = parser.parseSearchCandidates(html);

    expect(candidates, hasLength(1));
    expect(candidates.single.videoId, 'live1234567');
    expect(candidates.single.streamerName, 'Coder');
    expect(candidates.single.viewerCount, 1234);
    expect(candidates.single.ownerProfileUrl, '/@coder');
  });

  test('youtube page parser extracts live chat bootstrap from chat page', () {
    const html = '''
<html><script>
ytcfg.set({
  "INNERTUBE_API_KEY":"AIzaChat",
  "INNERTUBE_CLIENT_VERSION":"2.20260320.01.00",
  "INNERTUBE_CONTEXT":{"client":{"visitorData":"visitor-token"}}
});
</script><script>
var bootstrap = {
  "continuationContents": {
    "liveChatContinuation": {
      "continuations": [{
        "invalidationContinuationData": {
          "continuation": "chat-continuation",
          "timeoutMs": 1000
        }
      }]
    }
  }
};
</script></html>
''';
    final parser = YouTubePageParser();
    final bootstrap = parser.tryParseLiveChatBootstrap(
      html: html,
    );

    expect(bootstrap, isNotNull);
    expect(bootstrap!.apiKey, 'AIzaChat');
    expect(bootstrap.clientVersion, '2.20260320.01.00');
    expect(bootstrap.visitorData, 'visitor-token');
    expect(bootstrap.continuation, 'chat-continuation');
  });

  test('youtube page parser extracts room candidate from watch-next page', () {
    const html = '''
<html><script>
var ytInitialData = {
  "contents": {
    "twoColumnWatchNextResults": {
      "results": {
        "results": {
          "contents": [
            {
              "videoPrimaryInfoRenderer": {
                "title": {"runs": [{"text": "Bloomberg Business News Live"}]},
                "viewCount": {
                  "videoViewCountRenderer": {
                    "viewCount": {"runs": [{"text": "4,615"}, {"text": " watching now"}]},
                    "isLive": true,
                    "originalViewCount": "4615"
                  }
                }
              }
            },
            {
              "videoSecondaryInfoRenderer": {
                "owner": {
                  "videoOwnerRenderer": {
                    "thumbnail": {
                      "thumbnails": [
                        {"url": "https://yt3.ggpht.com/demo=s48", "width": 48, "height": 48},
                        {"url": "https://yt3.ggpht.com/demo=s176", "width": 176, "height": 176}
                      ]
                    },
                    "title": {
                      "runs": [{
                        "text": "Bloomberg Television",
                        "navigationEndpoint": {
                          "commandMetadata": {
                            "webCommandMetadata": {"url": "/@markets"}
                          }
                        }
                      }]
                    },
                    "navigationEndpoint": {
                      "commandMetadata": {
                        "webCommandMetadata": {"url": "/@markets"}
                      }
                    }
                  }
                }
              }
            }
          ]
        }
      }
    }
  }
};
</script></html>
''';
    final parser = YouTubePageParser();
    final initialData = parser.tryExtractInitialData(html);
    final candidate = parser.findLiveCandidateByVideoId(
      initialData: initialData,
      videoId: 'iEpJwprxDdk',
    );

    expect(candidate, isNotNull);
    expect(candidate!.title, 'Bloomberg Business News Live');
    expect(candidate.streamerName, 'Bloomberg Television');
    expect(candidate.viewerCount, 4615);
    expect(candidate.ownerProfileUrl, '/@markets');
    expect(candidate.streamerAvatarUrl, 'https://yt3.ggpht.com/demo=s176');
  });
}
