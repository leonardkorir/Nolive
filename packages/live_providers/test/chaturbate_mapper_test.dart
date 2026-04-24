import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_providers/src/providers/chaturbate/chaturbate_api_client.dart';
import 'package:live_providers/src/providers/chaturbate/chaturbate_hls_master_playlist_parser.dart';
import 'package:live_providers/src/providers/chaturbate/chaturbate_mapper.dart';
import 'package:live_providers/src/providers/chaturbate/chaturbate_room_page_parser.dart';
import 'package:test/test.dart';

import 'support/chaturbate_fixture_loader.dart';

void main() {
  group(
    'fixture-backed chaturbate mapper coverage',
    skip: ChaturbateFixtureLoader.skipReason,
    () {
      test('recommend mapper keeps phase-1 field boundaries from artifacts',
          () {
        final mostPopular =
            ChaturbateFixtureLoader.loadCarousel('most_popular');
        final rooms = (mostPopular['rooms'] as List).cast<Map>();

        final titleFallbackRoom = ChaturbateMapper.mapRecommendRoom(
          rooms.first.cast<String, dynamic>(),
        );
        expect(titleFallbackRoom.roomId, 'kittengirlxo');
        expect(titleFallbackRoom.title, 'kittengirlxo');
        expect(titleFallbackRoom.streamerName, 'kittengirlxo');
        expect(titleFallbackRoom.coverUrl, contains('thumb.live.mmcdn.com'));
        expect(titleFallbackRoom.keyframeUrl, isNull);
        expect(titleFallbackRoom.streamerAvatarUrl, isNull);
        expect(titleFallbackRoom.areaName, 'Female');

        final roomSubjectPreferred =
            ChaturbateMapper.mapRecommendRoom(rooms[1].cast<String, dynamic>());
        expect(roomSubjectPreferred.title, 'Hiya! | /tipmenu | #lovense #lush');
      });

      test('spy_shows payload still maps room rows without crashing', () {
        final spyShows = ChaturbateFixtureLoader.loadCarousel('spy_shows');
        final firstSpyRoom =
            (spyShows['rooms'] as List).first as Map<String, dynamic>;

        final mapped = ChaturbateMapper.mapRecommendRoom(firstSpyRoom);

        expect(mapped.roomId, 'yourlittlesunrise_');
        expect(mapped.title, startsWith('Body reveal in wet shirt'));
        expect(mapped.streamerName, 'yourlittlesunrise_');
      });

      test('room page parser extracts and decodes initialRoomDossier', () {
        const parser = ChaturbateRoomPageParser();
        final roomPage = ChaturbateFixtureLoader.loadRoomPage();

        final rawValue = parser.extractInitialRoomDossierRawValue(roomPage);
        expect(rawValue, contains(r'\u0022room_status\u0022'));

        final dossier = parser.decodeInitialRoomDossier(rawValue);
        expect(dossier['room_status'], 'public');
        expect(dossier['broadcaster_username'], 'kittengirlxo');
        expect(dossier['num_viewers'], 9627);
        expect(dossier['hls_source'], contains('playlist.m3u8'));
      });

      test('room page parser extracts csrf token and push services', () {
        const parser = ChaturbateRoomPageParser();
        final context =
            parser.parsePageContext(ChaturbateFixtureLoader.loadRoomPage());

        expect(context.csrfToken, isNotEmpty);
        expect(context.pushServices, hasLength(1));
        expect(context.primaryPushService['backend'], 'a');
        expect(
          context.primaryPushService['host'],
          'realtime.pa.highwebmedia.com',
        );
      });

      test('room page parser detects realtime bootstrap readiness', () {
        const parser = ChaturbateRoomPageParser();
        final roomPage = ChaturbateFixtureLoader.loadRoomPage();
        final rawValue = parser.extractInitialRoomDossierRawValue(roomPage);

        expect(parser.hasRealtimeBootstrap(roomPage), isTrue);
        expect(
          parser.hasRealtimeBootstrap(
            'window.initialRoomDossier = "$rawValue";',
          ),
          isFalse,
        );
      });

      test('room page parser tolerates missing csrf token and push services',
          () {
        const parser = ChaturbateRoomPageParser();
        final roomPage = ChaturbateFixtureLoader.loadRoomPage();
        final rawValue = parser.extractInitialRoomDossierRawValue(roomPage);

        final context = parser.parsePageContext(
          'window.initialRoomDossier = "$rawValue";',
        );

        expect(context.csrfToken, isEmpty);
        expect(context.pushServices, isEmpty);

        final detail = ChaturbateMapper.mapRoomDetailFromPageContext(context);
        expect(detail.roomId, 'kittengirlxo');
        expect(detail.danmakuToken, isNull);
      });

      test('search mapper uses username as roomId and streamerName', () {
        final payload =
            ChaturbateFixtureLoader.loadSearchResponse(query: 'lucy');
        final rooms = (payload['rooms'] as List).cast<Map>();

        final mapped = ChaturbateMapper.mapSearchRoom(
          rooms.first.cast<String, dynamic>(),
        );

        expect(mapped.roomId, 'lucysalvatore');
        expect(mapped.streamerName, 'lucysalvatore');
        expect(mapped.title, startsWith('GOAL: Twerking'));
        expect(mapped.areaName, 'Female');
        expect(mapped.viewerCount, 31);
      });

      test('detail mapper and play mapper keep phase-2 boundaries', () {
        const parser = ChaturbateRoomPageParser();
        final context =
            parser.parsePageContext(ChaturbateFixtureLoader.loadRoomPage());

        final detail = ChaturbateMapper.mapRoomDetailFromPageContext(context);
        expect(detail.providerId, ProviderId.chaturbate.value);
        expect(detail.roomId, 'kittengirlxo');
        expect(detail.title, "Kittengirlxo's room");
        expect(detail.streamerName, 'kittengirlxo');
        expect(detail.coverUrl, isNull);
        expect(detail.keyframeUrl, isNull);
        expect(detail.streamerAvatarUrl, isNull);
        expect(detail.areaName, 'Female');
        expect(detail.sourceUrl, 'https://chaturbate.com/kittengirlxo/');
        expect(detail.isLive, isTrue);
        expect(detail.viewerCount, 9627);
        expect(detail.danmakuToken, isA<Map>());
        final danmakuToken = detail.danmakuToken as Map;
        expect(danmakuToken['broadcasterUid'], 'P7746ZL');
        expect(danmakuToken['csrfToken'], context.csrfToken);
        expect(danmakuToken['backend'], 'a');

        final qualities = ChaturbateMapper.mapPlayQualities(detail);
        expect(qualities, hasLength(1));
        expect(qualities.single.id, 'auto');
        expect(qualities.single.label, 'Auto');
        expect(qualities.single.isDefault, isTrue);
        expect(
          qualities.single.metadata?['masterPlaylistUrl'],
          detail.metadata?['hlsSource'],
        );
        expect(qualities.single.metadata?['hlsBitrate'], 'max');

        final urls = ChaturbateMapper.mapPlayUrls(detail, qualities.single);
        expect(urls, hasLength(1));
        expect(urls.single.url, contains('playlist.m3u8'));
        expect(urls.single.lineLabel, 'AUS');
        expect(urls.single.headers['referer'], 'https://chaturbate.com/');
        expect(
          urls.single.headers['origin'],
          'https://chaturbate.com',
        );
        expect(
          urls.single.headers['user-agent'],
          HttpChaturbateApiClient.browserUserAgent,
        );
      });

      test('hls master playlist parser derives fixed qualities and urls', () {
        const parser = ChaturbateHlsMasterPlaylistParser();
        final fixture = ChaturbateFixtureLoader.loadHlsMasterPlaylist(
          harName: 'room-page-realcest-auto.har',
        );
        final variants = parser.parse(
          playlistUrl: fixture.url,
          source: fixture.content,
        );
        final detail = LiveRoomDetail(
          providerId: ProviderId.chaturbate.value,
          roomId: 'realcest',
          title: 'realcest room',
          streamerName: 'realcest',
          sourceUrl: 'https://chaturbate.com/realcest/',
          metadata: {
            'edgeRegion': 'CHI',
            'hlsSource': fixture.url,
          },
        );

        final qualities = ChaturbateMapper.mapPlayQualitiesFromVariants(
          variants: variants,
          fallbackPlaylistUrl: fixture.url,
        );

        expect(qualities, hasLength(5));
        expect(qualities.first.label, 'Auto');
        expect(
          qualities.skip(1).map((item) => item.label),
          orderedEquals(const ['1080p', '720p', '480p', '240p']),
        );

        final urls = ChaturbateMapper.mapPlayUrls(detail, qualities[1]);
        expect(
          urls.single.url,
          fixture.url,
        );
        expect(urls.single.metadata?['hlsBitrate'], qualities[1].id);
        expect(
          urls.single.metadata?['resolvedVariantUrl'],
          qualities[1].metadata?['playlistUrl'],
        );
        expect(
          urls.single.metadata?['audioUrl'],
          anyOf(isNull, contains('chunklist')),
        );
        if (urls.single.metadata?['audioUrl'] != null) {
          expect(urls.single.metadata?['audioHeaders'], urls.single.headers);
        }
        expect(urls.single.lineLabel, 'CHI');
        expect(urls.single.headers['referer'], 'https://chaturbate.com/');
      });

      test('ll-hls parser keeps paired audio rendition for each video variant',
          () {
        const parser = ChaturbateHlsMasterPlaylistParser();
        const playlistUrl =
            'https://edge11-lax.live.mmcdn.com/v1/edge/streams/origin.pinkypuppa.01KNFDA17Y6RTSYE3GWA8VYTPT/llhls.m3u8?token=fixture';
        const source = '''
#EXTM3U
#EXT-X-VERSION:6
#EXT-X-INDEPENDENT-SEGMENTS
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio_aac_96",NAME="Audio_1_1_5",DEFAULT=NO,AUTOSELECT=NO,FORCED=NO,CHANNELS="2",URI="/v1/edge/streams/origin.pinkypuppa.01KNFDA17Y6RTSYE3GWA8VYTPT/chunklist_5_audio_3689313794811747259_llhls.m3u8?session=e92ff262-9461-43b8-9ee4-ef180e1ea521"

#EXT-X-STREAM-INF:BANDWIDTH=1296000,RESOLUTION=852x480,FRAME-RATE=30.000,CODECS="avc1.4d401f,mp4a.40.2",AUDIO="audio_aac_96"
/v1/edge/streams/origin.pinkypuppa.01KNFDA17Y6RTSYE3GWA8VYTPT/chunklist_2_video_3689313794811747259_llhls.m3u8?session=e92ff262-9461-43b8-9ee4-ef180e1ea521
#EXT-X-STREAM-INF:BANDWIDTH=3296000,RESOLUTION=1280x720,FRAME-RATE=30.000,CODECS="avc1.4d401f,mp4a.40.2",AUDIO="audio_aac_96"
/v1/edge/streams/origin.pinkypuppa.01KNFDA17Y6RTSYE3GWA8VYTPT/chunklist_4_video_3689313794811747259_llhls.m3u8?session=e92ff262-9461-43b8-9ee4-ef180e1ea521
''';

        final variants = parser.parse(
          playlistUrl: playlistUrl,
          source: source,
        );
        final qualities = ChaturbateMapper.mapPlayQualitiesFromVariants(
          variants: variants,
          fallbackPlaylistUrl: playlistUrl,
        );
        final detail = LiveRoomDetail(
          providerId: ProviderId.chaturbate.value,
          roomId: 'pinkypuppa',
          title: 'pinkypuppa room',
          streamerName: 'pinkypuppa',
          sourceUrl: 'https://chaturbate.com/pinkypuppa/',
          metadata: const {
            'edgeRegion': 'LAX',
            'hlsSource': playlistUrl,
          },
        );

        expect(variants, hasLength(2));
        expect(
          variants.first.audioUrl,
          contains('chunklist_5_audio_3689313794811747259_llhls.m3u8'),
        );
        expect(
          qualities.first.metadata?['masterPlaylistUrl'],
          playlistUrl,
        );
        expect(qualities.first.metadata?['hlsBitrate'], '1296000');

        final autoUrls = ChaturbateMapper.mapPlayUrls(detail, qualities.first);
        expect(
          autoUrls.single.url,
          contains('chunklist_2_video_3689313794811747259_llhls.m3u8'),
        );
        expect(autoUrls.single.metadata?['hlsBitrate'], '1296000');
        expect(
          autoUrls.single.metadata?['masterPlaylistUrl'],
          playlistUrl,
        );
        expect(
          autoUrls.single.metadata?['audioUrl'],
          contains('chunklist_5_audio_3689313794811747259_llhls.m3u8'),
        );

        final fixedUrls = ChaturbateMapper.mapPlayUrls(detail, qualities[1]);
        expect(
          fixedUrls.single.url,
          contains('chunklist_4_video_3689313794811747259_llhls.m3u8'),
        );
        expect(
          fixedUrls.single.metadata?['hlsBitrate'],
          '3296000',
        );
        expect(
          fixedUrls.single.metadata?['masterPlaylistUrl'],
          playlistUrl,
        );
        expect(
          fixedUrls.single.metadata?['audioUrl'],
          contains('chunklist_5_audio_3689313794811747259_llhls.m3u8'),
        );
      });

      test('play mapper ignores request cookie for playback headers', () {
        final detail = LiveRoomDetail(
          providerId: ProviderId.chaturbate.value,
          roomId: 'realcest',
          title: 'realcest room',
          streamerName: 'realcest',
          sourceUrl: 'https://chaturbate.com/realcest/',
          metadata: const {
            'edgeRegion': 'CHI',
            'hlsSource': 'https://edge.example.com/llhls.m3u8?token=test',
            'requestCookie': 'cf_clearance=demo; csrftoken=demo',
          },
        );
        const quality = LivePlayQuality(
          id: '720p',
          label: '720p',
          metadata: {
            'playlistUrl':
                'https://edge.example.com/chunklist_video.m3u8?token=test',
            'audioUrl':
                'https://edge.example.com/chunklist_audio.m3u8?token=test',
            'audioMimeType': 'application/x-mpegURL',
          },
        );

        final urls = ChaturbateMapper.mapPlayUrls(detail, quality);

        expect(urls.single.headers.containsKey('cookie'), isFalse);
        expect(
          urls.single.url,
          'https://edge.example.com/chunklist_video.m3u8?token=test',
        );
        expect(urls.single.metadata?['audioHeaders'], urls.single.headers);
        expect(
          urls.single.metadata?['audioUrl'],
          'https://edge.example.com/chunklist_audio.m3u8?token=test',
        );
        expect(
          (urls.single.metadata?['audioHeaders'] as Map<String, String>)
              .containsKey('cookie'),
          isFalse,
        );
      });

      test(
          'auto quality keeps ll-hls master playback on a safer startup variant',
          () {
        const parser = ChaturbateHlsMasterPlaylistParser();
        final fixture = ChaturbateFixtureLoader.loadHlsMasterPlaylist(
          harName: 'room-page-realcest-auto-0415.har',
        );
        final variants = parser.parse(
          playlistUrl: fixture.url,
          source: fixture.content,
        );
        final qualities = ChaturbateMapper.mapPlayQualitiesFromVariants(
          variants: variants,
          fallbackPlaylistUrl: fixture.url,
        );
        final detail = LiveRoomDetail(
          providerId: ProviderId.chaturbate.value,
          roomId: 'realcest',
          title: 'realcest room',
          streamerName: 'realcest',
          sourceUrl: 'https://chaturbate.com/realcest/',
          metadata: {
            'edgeRegion': 'LAX',
            'hlsSource': fixture.url,
          },
        );

        final autoUrls = ChaturbateMapper.mapPlayUrls(detail, qualities.first);
        final fixedUrls = ChaturbateMapper.mapPlayUrls(detail, qualities[1]);

        expect(variants, isNotEmpty);
        expect(autoUrls.single.url, variants[2].url);
        expect(
          autoUrls.single.metadata?['hlsBitrate'],
          variants[2].bandwidth.toString(),
        );
        expect(
          autoUrls.single.metadata?['masterPlaylistUrl'],
          fixture.url,
        );
        expect(autoUrls.single.metadata?['audioUrl'], isNotNull);
        expect(
          qualities.first.metadata?['masterPlaylistUrl'],
          fixture.url,
        );
        expect(fixedUrls.single.url, variants.first.url);
        expect(
          fixedUrls.single.metadata?['hlsBitrate'],
          variants.first.bandwidth.toString(),
        );
        expect(
          fixedUrls.single.metadata?['masterPlaylistUrl'],
          fixture.url,
        );
        expect(fixedUrls.single.metadata?['audioUrl'], isNotNull);
      });

      test(
          'auto fallback can derive split playback directly from master playlist content',
          () {
        const playlistUrl =
            'https://edge18-sin.live.mmcdn.com/v1/edge/streams/origin.teyyumi.demo/llhls.m3u8?token=fresh';
        const masterPlaylistContent = '''
#EXTM3U
#EXT-X-VERSION:6
#EXT-X-INDEPENDENT-SEGMENTS
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio_aac_96",NAME="Audio",DEFAULT=NO,AUTOSELECT=NO,FORCED=NO,CHANNELS="2",URI="/v1/edge/streams/origin.teyyumi.demo/chunklist_7_audio_llhls.m3u8?session=fresh"
#EXT-X-STREAM-INF:BANDWIDTH=2096000,RESOLUTION=960x540,FRAME-RATE=30.000,CODECS="avc1.4d401f,mp4a.40.2",AUDIO="audio_aac_96"
/v1/edge/streams/origin.teyyumi.demo/chunklist_2_video_llhls.m3u8?session=fresh
#EXT-X-STREAM-INF:BANDWIDTH=5128000,RESOLUTION=1920x1080,FRAME-RATE=30.000,CODECS="avc1.640028,mp4a.40.2",AUDIO="audio_aac_96"
/v1/edge/streams/origin.teyyumi.demo/chunklist_4_video_llhls.m3u8?session=fresh
''';
        final detail = LiveRoomDetail(
          providerId: ProviderId.chaturbate.value,
          roomId: 'teyyumi',
          title: 'teyyumi room',
          streamerName: 'teyyumi',
          sourceUrl: 'https://chaturbate.com/teyyumi/',
          metadata: const {
            'edgeRegion': 'SIN',
            'hlsSource': playlistUrl,
            'hlsMasterPlaylistContent': masterPlaylistContent,
          },
        );

        final urls = ChaturbateMapper.mapPlayUrls(
          detail,
          const LivePlayQuality(
            id: 'auto',
            label: 'Auto',
            isDefault: true,
          ),
        );

        expect(urls, hasLength(1));
        expect(
          urls.single.url,
          contains('chunklist_2_video_llhls.m3u8?session=fresh'),
        );
        expect(
          urls.single.metadata?['masterPlaylistUrl'],
          playlistUrl,
        );
        expect(
          urls.single.metadata?['audioUrl'],
          contains('chunklist_7_audio_llhls.m3u8?session=fresh'),
        );
        expect(urls.single.metadata?['hlsBitrate'], '2096000');
      });

      test('danmaku mapper parses history and realtime payloads from fixtures',
          () {
        final history = ChaturbateFixtureLoader.loadRoomHistory();
        final historyMessage =
            ChaturbateMapper.mapDanmakuPayload(history.first);
        expect(historyMessage, isNotNull);
        expect(historyMessage!.type, LiveMessageType.chat);
        expect(historyMessage.userName, 'nicolasmonzon');
        expect(historyMessage.content, 'Por el culo la cojes?');

        final websocketMessages =
            ChaturbateFixtureLoader.loadWebSocketMessages();
        final realtimeData = websocketMessages
            .where((item) => item['type'] == 'receive')
            .map((item) => item['data']?.toString() ?? '')
            .firstWhere((text) => text.contains('"action":15'));
        final wrapper =
            (jsonDecode(realtimeData) as Map).cast<String, dynamic>();
        final envelope =
            (wrapper['messages'] as List).first as Map<String, dynamic>;
        final event =
            jsonDecode(envelope['data'] as String) as Map<String, dynamic>;
        final realtimeMessage = ChaturbateMapper.mapDanmakuPayload(event);

        expect(realtimeMessage, isNotNull);
        expect(
          realtimeMessage!.type,
          anyOf(LiveMessageType.chat, LiveMessageType.gift),
        );
        expect(realtimeMessage.content, isNotEmpty);
      });
    },
  );
}
