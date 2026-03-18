import 'dart:convert';

import 'package:live_providers/src/providers/douyu/douyu_live_data_source.dart';
import 'package:live_providers/src/providers/douyu/douyu_sign_service.dart';
import 'package:live_providers/src/providers/douyu/douyu_transport.dart';

Future<void> main(List<String> args) async {
  final roomId = args.isNotEmpty ? args[0] : '208114';
  final transport = HttpDouyuTransport();
  final sign = HttpDouyuSignService(transport: transport);
  final ds = DouyuLiveDataSource(transport: transport, signService: sign);

  final detail = await ds.fetchRoomDetail(roomId);
  print('detail room=${detail.roomId} title=${detail.title}');

  final qualities = await ds.fetchPlayQualities(detail);
  print('qualities=${qualities.length}');
  for (final q in qualities) {
    print(
      'Q ${q.id} ${q.label} default=${q.isDefault} meta=${jsonEncode(q.metadata)}',
    );
    final urls = await ds.fetchPlayUrls(detail: detail, quality: q);
    print('  urls=${urls.length}');
    for (final u in urls.take(2)) {
      print('  ${u.lineLabel ?? '-'} -> ${u.url}');
    }
  }
}
