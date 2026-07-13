import 'package:live_providers/src/providers/chaturbate/chaturbate_room_page_parser.dart';
import 'package:test/test.dart';

void main() {
  test('chaturbate room page parser accepts quoted csrf keys', () {
    const parser = ChaturbateRoomPageParser();

    expect(
      parser.tryExtractCsrfToken('{"csrftoken": "csrf-double"}'),
      'csrf-double',
    );
    expect(
      parser.tryExtractCsrfToken("{'csrftoken': 'csrf-single'}"),
      'csrf-single',
    );
  });

  test('chaturbate room page parser extracts csrf from middleware input', () {
    const parser = ChaturbateRoomPageParser();

    expect(
      parser.tryExtractCsrfToken(
        '<input type="hidden" name="csrfmiddlewaretoken" value="csrf-input">',
      ),
      'csrf-input',
    );
    expect(
      parser.tryExtractCsrfToken(
        '<input value="csrf-input-rev" name="csrfmiddlewaretoken" type="hidden">',
      ),
      'csrf-input-rev',
    );
  });

  test('chaturbate room page parser extracts csrf from cookie string', () {
    expect(
      ChaturbateRoomPageParser.tryExtractCsrfTokenFromCookie(
        'sessionid=abc; csrftoken=cookie%2Dcsrf; other=1',
      ),
      'cookie-csrf',
    );
    expect(
      ChaturbateRoomPageParser.tryExtractCsrfTokenFromCookie('sessionid=abc'),
      isNull,
    );
  });

  test('chaturbate room page parser accepts double quoted push service JSON', () {
    const parser = ChaturbateRoomPageParser();
    final raw = parser.tryExtractPushServicesRawValue(
      r'''push_services: JSON.parse("[{\"backend\":\"a\",\"host\":\"realtime.pa.highwebmedia.com\"}]")''',
    );

    final decoded = parser.decodePushServices(raw!);

    expect(decoded, hasLength(1));
    expect(decoded.single['backend'], 'a');
    expect(decoded.single['host'], 'realtime.pa.highwebmedia.com');
  });

  test('chaturbate room page parser accepts HAR-style escaped push services', () {
    const parser = ChaturbateRoomPageParser();
    final raw = parser.tryExtractPushServicesRawValue(
      r'''window["tsInstance"] = new TS(extend({ push_services: JSON.parse('[{\u0022backend\u0022:\u0022a\u0022,\u0022host\u0022:\u0022realtime.pa.highwebmedia.com\u0022,\u0022fallback_hosts\u0022:[\u0022b-fallback.pa.highwebmedia.com\u0022]}]'), csrftoken: 'csrf' }, {}));''',
    );

    final decoded = parser.decodePushServices(raw!);

    expect(decoded, hasLength(1));
    expect(decoded.single['backend'], 'a');
    expect(decoded.single['host'], 'realtime.pa.highwebmedia.com');
    expect(decoded.single['fallback_hosts'], [
      'b-fallback.pa.highwebmedia.com',
    ]);
  });

  test('chaturbate room page parser accepts direct push service arrays', () {
    const parser = ChaturbateRoomPageParser();
    final raw = parser.tryExtractPushServicesRawValue('''
window.ts = {
  push_services: [{"backend":"a","rest_host":"realtime.pa.highwebmedia.com"}],
  csrftoken: "csrf"
};
''');

    final decoded = parser.decodePushServices(raw!);

    expect(decoded, hasLength(1));
    expect(decoded.single['rest_host'], 'realtime.pa.highwebmedia.com');
  });
}
