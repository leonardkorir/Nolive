import 'dart:convert';

import 'package:live_providers/src/providers/douyu/douyu_sign_service.dart';
import 'package:live_providers/src/providers/douyu/douyu_transport.dart';

Future<void> main(List<String> args) async {
  final roomId = args.isNotEmpty ? args[0] : '208114';
  final transport = HttpDouyuTransport();
  final sign = HttpDouyuSignService(transport: transport);
  final ctx = await sign.buildPlayContext(roomId);
  print('body=${ctx.body}');

  final response = await transport.postJson(
    'https://www.douyu.com/lapi/live/getH5Play/$roomId',
    body: sign.extendPlayBody(ctx.body, cdn: '', rate: '-1'),
    headers: sign.buildPlayHeaders(roomId, deviceId: ctx.deviceId),
  );
  print(const JsonEncoder.withIndent('  ').convert(response));
}
