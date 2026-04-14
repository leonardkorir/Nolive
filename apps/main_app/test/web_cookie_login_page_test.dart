import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nolive_app/src/features/settings/presentation/chaturbate_web_login_page.dart';

void main() {
  test('web login load failure only reports main-frame request errors', () {
    expect(
      shouldReportWebLoginLoadFailure(
        WebResourceRequest(
          url: WebUri('https://chaturbate.com/'),
          isForMainFrame: true,
        ),
      ),
      isTrue,
    );

    expect(
      shouldReportWebLoginLoadFailure(
        WebResourceRequest(
          url: WebUri('https://static.example.com/app.js'),
          isForMainFrame: false,
        ),
      ),
      isFalse,
    );
  });
}
