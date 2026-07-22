import 'dart:convert';

import 'package:live_providers/src/providers/douyu/douyu_sign_service.dart';
import 'package:live_providers/src/providers/douyu/douyu_transport.dart';

Future<void> main(List<String> args) async {
  final roomId = args.isNotEmpty ? args[0] : '208114';
  final transport = HttpDouyuTransport();
  final sign = HttpDouyuSignService(transport: transport);
  final body = await sign.buildSignedPlayBody(roomId);
  print('body=$body');

  final response = await transport.postJson(
    'https://www.douyu.com/lapi/live/getH5PlayV1/$roomId',
    body: body,
    headers: sign.buildPlayHeaders(roomId),
  );
  print(const JsonEncoder.withIndent('  ').convert(response));
}
