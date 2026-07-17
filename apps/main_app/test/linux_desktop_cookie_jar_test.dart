import 'package:flutter_test/flutter_test.dart';
import 'package:nolive_app/src/app/runtime_bridges/linux_desktop_webview_adapter.dart';

void main() {
  test('LinuxDesktopCookieJar set/get filters by domain and path', () async {
    final jar = LinuxDesktopCookieJar();
    await jar.setCookie(
      url: 'https://www.twitch.tv/',
      name: 'auth-token',
      value: 'abc',
      domain: '.twitch.tv',
      path: '/',
    );
    await jar.setCookie(
      url: 'https://chaturbate.com/',
      name: 'sessionid',
      value: 'xyz',
      domain: 'chaturbate.com',
      path: '/',
    );

    final twitch = await jar.getCookies(url: 'https://www.twitch.tv/room');
    expect(twitch.map((c) => c.name), contains('auth-token'));
    expect(twitch.map((c) => c.value), contains('abc'));
    expect(twitch.any((c) => c.name == 'sessionid'), isFalse);

    final cb = await jar.getCookies(url: 'https://chaturbate.com/b/foo');
    expect(cb.single.name, 'sessionid');

    final header = jar.exportCookieHeader(
      allowedHostSuffixes: const ['twitch.tv'],
    );
    expect(header, contains('auth-token=abc'));
    expect(header, isNot(contains('sessionid')));
  });

  test('documentCookieAssignments emits injectable statements', () async {
    final jar = LinuxDesktopCookieJar();
    await jar.setCookie(
      url: 'https://example.com/',
      name: 'a',
      value: '1',
      domain: 'example.com',
      path: '/',
    );
    final scripts = jar.documentCookieAssignments();
    expect(scripts, isNotEmpty);
    expect(scripts.first, contains('document.cookie='));
    expect(scripts.first, contains('a=1'));
  });
}
