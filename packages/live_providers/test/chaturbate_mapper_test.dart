import 'dart:convert';

import 'package:live_core/live_core.dart';
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

        final urls = ChaturbateMapper.mapPlayUrls(detail, qualities.single);
        expect(urls, hasLength(1));
        expect(urls.single.url, contains('playlist.m3u8'));
        expect(urls.single.lineLabel, 'AUS');
        expect(urls.single.headers, isEmpty);
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
        );

        expect(qualities, hasLength(5));
        expect(qualities.first.label, 'Auto');
        expect(
          qualities.skip(1).map((item) => item.label),
          orderedEquals(const ['1080p', '720p', '480p', '240p']),
        );

        final urls = ChaturbateMapper.mapPlayUrls(detail, qualities[1]);
        expect(urls.single.url, contains('chunklist'));
        expect(urls.single.url, contains('b5128000'));
        expect(urls.single.lineLabel, 'CHI');
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
