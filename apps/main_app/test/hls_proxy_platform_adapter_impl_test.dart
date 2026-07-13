import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nolive_app/src/app/runtime_bridges/hls_proxy_platform_adapter_impl.dart';

void main() {
  test('headless webview settings minimize background rendering pressure', () {
    final settings = buildHlsHeadlessWebViewSettingsForTesting(
      userAgent: 'test-agent',
      interceptRequests: true,
    );

    expect(settings.userAgent, 'test-agent');
    expect(settings.useShouldInterceptRequest, isTrue);
    expect(settings.loadsImagesAutomatically, isFalse);
    expect(settings.blockNetworkImage, isTrue);
    expect(settings.javaScriptCanOpenWindowsAutomatically, isFalse);
    expect(settings.supportMultipleWindows, isFalse);
    expect(settings.supportZoom, isFalse);
    expect(settings.builtInZoomControls, isFalse);
    expect(settings.loadWithOverviewMode, isFalse);
    expect(settings.databaseEnabled, isFalse);
    expect(settings.disableHorizontalScroll, isTrue);
    expect(settings.disableVerticalScroll, isTrue);
    expect(settings.useShouldInterceptAjaxRequest, isFalse);
    expect(settings.useShouldInterceptFetchRequest, isFalse);
    expect(settings.useHybridComposition, isTrue);
    expect(settings.preferredContentMode, UserPreferredContentMode.RECOMMENDED);
  });

  test('headless webview settings keep desktop mode explicit', () {
    final settings = buildHlsHeadlessWebViewSettingsForTesting(
      userAgent: 'test-agent',
      desktopMode: true,
    );

    expect(settings.useShouldInterceptRequest, isFalse);
    expect(settings.preferredContentMode, UserPreferredContentMode.DESKTOP);
  });
}
