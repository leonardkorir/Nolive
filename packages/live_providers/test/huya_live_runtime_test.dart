import 'package:live_providers/live_providers.dart';
import 'package:live_providers/src/providers/huya/huya_live_data_source.dart';
import 'package:live_providers/src/providers/huya/huya_sign_service.dart';
import 'package:live_providers/src/providers/huya/huya_transport.dart';
import 'package:test/test.dart';

void main() {
  test('live huya runtime maps search/detail/play flow', () async {
    final transport = _FakeHuyaTransport();
    final signService = HttpHuyaSignService();
    final provider = HuyaProvider(
      dataSource: HuyaLiveDataSource(
        transport: transport,
        signService: signService,
      ),
    );

    final rooms = await provider.searchRooms('测试');
    expect(rooms.items, hasLength(1));
    expect(rooms.items.single.areaName, '英雄联盟');

    final detail = await provider.fetchRoomDetail(rooms.items.single.roomId);
    expect(detail.roomId, 'yy/123456');
    expect(detail.areaName, '英雄联盟');
    expect(detail.isLive, isTrue);

    final qualities = await provider.fetchPlayQualities(detail);
    expect(qualities, isNotEmpty);
    expect(qualities.first.label, '原画');
    expect(qualities.first.isDefault, isTrue);

    final urls = await provider.fetchPlayUrls(
      detail: detail,
      quality: qualities.firstWhere((item) => item.isDefault),
    );
    expect(urls, isNotEmpty);
    expect(urls.first.url, contains('sStreamName123'));
  });

  test('live huya runtime normalizes malformed display text', () async {
    final transport = _MalformedTextHuyaTransport();
    final signService = HttpHuyaSignService();
    final provider = HuyaProvider(
      dataSource: HuyaLiveDataSource(
        transport: transport,
        signService: signService,
      ),
    );

    final rooms = await provider.searchRooms('测试');
    final detail = await provider.fetchRoomDetail(rooms.items.single.roomId);

    expect(rooms.items.single.title, '虎牙游戏厅');
    expect(rooms.items.single.streamerName, '虎牙热门主播');
    expect(rooms.items.single.areaName, '热门游戏');
    expect(detail.title, '虎牙游戏厅');
    expect(detail.streamerName, '虎牙热门主播');
    expect(detail.areaName, '热门游戏');
    expect(detail.description, '虎牙游戏厅');
  });
}

class _FakeHuyaTransport extends HuyaTransport {
  @override
  Future<String> getText(
    String url, {
    Map<String, String> queryParameters = const {},
    Map<String, String> headers = const {},
  }) async {
    final uri = Uri.parse(url).replace(
      queryParameters: queryParameters.isEmpty ? null : queryParameters,
    );
    if (uri.toString().startsWith('https://search.cdn.huya.com/')) {
      return '{"response":{"3":{"docs":[{"yyid":"123456","game_roomName":"虎牙测试房间","game_screenshot":"https://huyaimg.msstatic.com/cover.jpg","gameName":"英雄联盟","game_nick":"虎牙主播","game_imgUrl":"https://huyaimg.msstatic.com/avatar.jpg","game_total_count":"98765"}],"numFound":1}}}';
    }
    if (uri.toString().startsWith('https://www.huya.com/yy/123456')) {
      return '''<html><script>var TT_ROOM_DATA = {"state":"ON","isReplay":false};</script><script>stream: {"data":[{"gameLiveInfo":{"introduction":"虎牙测试房间","gameFullName":"英雄联盟","screenshot":"https://huyaimg.msstatic.com/cover.jpg","nick":"虎牙主播","avatar180":"https://huyaimg.msstatic.com/avatar.jpg","totalCount":12345,"yyid":123456},"gameStreamInfoList":[{"lChannelId":111,"lSubChannelId":222,"sFlvUrl":"https://flv.huya.test/src","sHlsUrl":"https://hls.huya.test/src","sFlvAntiCode":"fm=dGVzdF9wcmVmaXg=&fs=1&ctype=huya_pc_exe&t=100&wsTime=65D4D440","sHlsAntiCode":"fm=dGVzdF9wcmVmaXg=&fs=1&ctype=huya_pc_exe&t=100&wsTime=65D4D440","sStreamName":"sStreamName123","sCdnType":"AL"}]}],"vMultiStreamInfo":[{"sDisplayName":"原画","iBitRate":0},{"sDisplayName":"高清","iBitRate":2000}]}</script></html>''';
    }
    fail('Unexpected huya request: $uri');
  }
}

class _MalformedTextHuyaTransport extends _FakeHuyaTransport {
  static final String _badTitle =
      '虎牙游${String.fromCharCode(0xD800)}戏${String.fromCharCode(0xDC00)}厅';
  static final String _badName = '虎牙熱${String.fromCharCode(0xD800)}門主播';
  static final String _badArea = '熱門遊${String.fromCharCode(0xDC00)}戲';

  @override
  Future<String> getText(
    String url, {
    Map<String, String> queryParameters = const {},
    Map<String, String> headers = const {},
  }) async {
    final uri = Uri.parse(url).replace(
      queryParameters: queryParameters.isEmpty ? null : queryParameters,
    );
    if (uri.toString().startsWith('https://search.cdn.huya.com/')) {
      return '{"response":{"3":{"docs":[{"yyid":"123456","game_roomName":"$_badTitle","game_screenshot":"https://huyaimg.msstatic.com/cover.jpg","gameName":"$_badArea","game_nick":"$_badName","game_imgUrl":"https://huyaimg.msstatic.com/avatar.jpg","game_total_count":"98765"}],"numFound":1}}}';
    }
    if (uri.toString().startsWith('https://www.huya.com/yy/123456')) {
      return '''<html><script>var TT_ROOM_DATA = {"state":"ON","isReplay":false};</script><script>stream: {"data":[{"gameLiveInfo":{"introduction":"$_badTitle","gameFullName":"$_badArea","screenshot":"https://huyaimg.msstatic.com/cover.jpg","nick":"$_badName","avatar180":"https://huyaimg.msstatic.com/avatar.jpg","totalCount":12345,"yyid":123456},"gameStreamInfoList":[{"lChannelId":111,"lSubChannelId":222,"sFlvUrl":"https://flv.huya.test/src","sHlsUrl":"https://hls.huya.test/src","sFlvAntiCode":"fm=dGVzdF9wcmVmaXg=&fs=1&ctype=huya_pc_exe&t=100&wsTime=65D4D440","sHlsAntiCode":"fm=dGVzdF9wcmVmaXg=&fs=1&ctype=huya_pc_exe&t=100&wsTime=65D4D440","sStreamName":"sStreamName123","sCdnType":"AL"}]}],"vMultiStreamInfo":[{"sDisplayName":"原画","iBitRate":0}]}</script></html>''';
    }
    fail('Unexpected huya request: $uri');
  }
}
