import 'package:live_core/live_core.dart';
import 'package:live_providers/src/providers/douyu/douyu_mapper.dart';
import 'package:test/test.dart';

void main() {
  test('sortedDouyuCdnsFromApi prefers re-weight and deprioritizes scdn/hw3', () {
    final ordered = DouyuMapper.sortedDouyuCdnsFromApi([
      {'cdn': 'scdn', 're-weight': 99999},
      {'cdn': 'hw-h5', 're-weight': 100},
      {'cdn': 'ws-h5', 're-weight': 100},
      {'cdn': 'hw3-h5', 're-weight': 50000},
    ]);

    expect(ordered.first, 'ws-h5');
    expect(ordered.contains('hw-h5'), isTrue);
    expect(ordered.last, 'scdn');
    // hw3 family should not be first when a better peer exists.
    expect(ordered.indexOf('ws-h5'), lessThan(ordered.indexOf('hw3-h5')));
  });

  test('preferReliableDouyuPlayUrls puts hw1a before hw3', () {
    final sorted = DouyuMapper.preferReliableDouyuPlayUrls([
      const LivePlayUrl(
        url: 'https://hw3.douyucdn2.cn/live/a.flv',
        lineLabel: 'hw-h5',
      ),
      const LivePlayUrl(
        url: 'https://hw1a.douyucdn2.cn/live/b.flv',
        lineLabel: 'tct-h5',
      ),
      const LivePlayUrl(
        url: 'https://hw3a.douyucdn2.cn/live/c.flv',
        lineLabel: 'hw-h5',
      ),
    ]);

    expect(sorted.first.url, contains('hw1a'));
    expect(sorted.map((e) => Uri.parse(e.url).host).toList(), [
      'hw1a.douyucdn2.cn',
      'hw3.douyucdn2.cn',
      'hw3a.douyucdn2.cn',
    ]);
  });

  test('preferReliableDouyuPlayUrls keeps one alternate per host', () {
    final sorted = DouyuMapper.preferReliableDouyuPlayUrls([
      const LivePlayUrl(
        url: 'https://hw3.douyucdn2.cn/live/a.flv?token=1',
        lineLabel: 'hw-h5',
      ),
      const LivePlayUrl(
        url: 'https://ws3.douyucdn.cn/live/b.flv?token=2',
        lineLabel: 'ws-h5',
      ),
      const LivePlayUrl(
        url: 'https://hw3.douyucdn2.cn/live/a.flv?token=3',
        lineLabel: 'hw-h5',
      ),
      const LivePlayUrl(
        url: 'https://hw3.douyucdn2.cn/live/a.flv?token=4',
        lineLabel: 'hw-h5',
      ),
    ]);

    // Preferred ws3 + up to 2 hw3 tokens (maxPlayUrlsPerHost).
    expect(sorted, hasLength(3));
    expect(sorted.first.url, contains('ws3'));
    final hw3 = sorted.where((e) => e.url.contains('hw3')).toList();
    expect(hw3, hasLength(2));
    expect(hw3.map((e) => e.url).toSet(), {
      'https://hw3.douyucdn2.cn/live/a.flv?token=1',
      'https://hw3.douyucdn2.cn/live/a.flv?token=3',
    });
  });

  test('mapPlayQualities stores CDN order from weighted sort', () {
    final qualities = DouyuMapper.mapPlayQualities({
      'data': {
        'rate': 0,
        'cdnsWithName': [
          {'cdn': 'scdn', 're-weight': 1},
          {'cdn': 'ws-h5', 're-weight': 99999},
          {'cdn': 'hw-h5', 're-weight': 100},
        ],
        'multirates': [
          {'rate': 0, 'name': '原画', 'bit': 8000},
        ],
      },
    });

    expect(qualities, isNotEmpty);
    final cdns = (qualities.first.metadata?['cdns'] as List?)?.cast<String>();
    expect(cdns, isNotNull);
    expect(cdns!.first, 'ws-h5');
    expect(cdns.last, 'scdn');
  });
}
