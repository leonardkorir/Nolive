import 'package:live_core/live_core.dart';
import 'package:live_providers/src/providers/huya/huya_mapper.dart';
import 'package:test/test.dart';

void main() {
  group('HuyaMapper exception and edge case tests', () {
    test('Empty search response (no items found) parses correctly', () {
      final res = HuyaMapper.mapSearchResponse(
        '{"response": {"3": {"docs": [], "numFound": 0}}}',
        page: 1,
      );
      expect(res.items, isEmpty);
      expect(res.hasMore, isFalse);
      expect(res.page, 1);
    });

    test('Non-map search response throws ProviderParseException', () {
      expect(
        () => HuyaMapper.mapSearchResponse('[]', page: 1),
        throwsA(isA<ProviderParseException>()),
      );
    });

    test(
      'Room detail HTML missing TT_ROOM_DATA or stream script throws ProviderParseException',
      () {
        expect(
          () => HuyaMapper.mapRoomDetail(
            '<html><body>No data</body></html>',
            requestedRoomId: 'yy/123',
          ),
          throwsA(isA<ProviderParseException>()),
        );
      },
    );

    test(
      'Room detail HTML with empty gameStreamInfoList throws ProviderParseException',
      () {
        // TT_ROOM_DATA state: ON, stream data is present but gameStreamInfoList is empty
        final html = '''<html>
        <script>var TT_ROOM_DATA = {"state":"ON","isReplay":false};</script>
        <script>stream: {"data":[{"gameLiveInfo":{"introduction":"Intro","gameFullName":"LOL","screenshot":"cover","nick":"Streamer","avatar180":"avatar","totalCount":100,"yyid":123},"gameStreamInfoList":[]}]}</script>
      </html>''';
        expect(
          () => HuyaMapper.mapRoomDetail(html, requestedRoomId: 'yy/123'),
          throwsA(isA<ProviderParseException>()),
        );
      },
    );

    test(
      'offline room (state OFF) maps isLive=false without stream lines',
      () {
        // SlotSun: status from TT_ROOM_DATA only; offline pages often lack streams.
        final html = '''<html>
        <script>var TT_ROOM_DATA = {"state":"OFF","isReplay":false,"nick":"OfflineNick"};</script>
      </html>''';
        final detail = HuyaMapper.mapRoomDetail(
          html,
          requestedRoomId: '998',
        );
        expect(detail.isLive, isFalse);
        expect(detail.roomId, '998');
        expect(detail.streamerName, 'OfflineNick');
        expect(detail.metadata?['lines'], isEmpty);
      },
    );

    test(
      'offline room with empty stream blob still maps offline',
      () {
        final html = '''<html>
        <script>var TT_ROOM_DATA = {"state":"OFF","isReplay":false};</script>
        <script>stream: {"data":[]}</script>
      </html>''';
        final detail = HuyaMapper.mapRoomDetail(
          html,
          requestedRoomId: '660002',
        );
        expect(detail.isLive, isFalse);
      },
    );

    test(
      'Room detail JSON lacking default quality in vMultiStreamInfo sets first mapped quality as default',
      () {
        final html = '''<html>
        <script>var TT_ROOM_DATA = {"state":"ON","isReplay":false};</script>
        <script>stream: {
          "data":[{
            "gameLiveInfo":{"introduction":"Intro","gameFullName":"LOL","screenshot":"cover","nick":"Streamer","avatar180":"avatar","totalCount":100,"yyid":123},
            "gameStreamInfoList":[{"lChannelId":111,"lSubChannelId":222,"sFlvUrl":"https://flv.huya.test/src","sStreamName":"stream","sCdnType":"AL","sFlvAntiCode":"fm=dGVzdF9wcmVmaXg=&fs=1&ctype=huya_pc_exe&t=100&wsTime=65D4D440"}]
          }],
          "vMultiStreamInfo":[{"sDisplayName":"超清","iBitRate":4000},{"sDisplayName":"高清","iBitRate":2000}]
        }</script>
      </html>''';
        final detail = HuyaMapper.mapRoomDetail(
          html,
          requestedRoomId: 'yy/123',
        );
        final qualities = HuyaMapper.mapPlayQualities(detail);

        expect(qualities, hasLength(2));
        // None of the original iBitRate is 0, so qualities don't have default=true initially
        // Assert that the first one in sorted order is made default = true
        final defaultQuality = qualities.where((q) => q.isDefault);
        expect(defaultQuality, hasLength(1));
        expect(defaultQuality.first.id, '4000');
      },
    );
  });
}
