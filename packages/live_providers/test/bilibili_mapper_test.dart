import 'package:live_providers/src/providers/bilibili/bilibili_mapper.dart';
import 'package:test/test.dart';

void main() {
  test('bilibili mapper skips search rooms with missing room ids', () {
    final response = {
      'data': {
        'pageinfo': {
          'live_room': {'numPages': 1},
        },
        'result': {
          'live_room': [
            {
              'roomid': null,
              'title': 'invalid room',
              'uname': 'nobody',
            },
            {
              'roomid': 32558935,
              'title': 'valid room',
              'uname': '主播',
              'live_status': 1,
            },
          ],
        },
      },
    };

    final page = BilibiliMapper.mapSearchResponse(response, page: 1);

    expect(page.items, hasLength(1));
    expect(page.items.single.roomId, '32558935');
  });
}
