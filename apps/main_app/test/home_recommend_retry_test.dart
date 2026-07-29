import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nolive_app/src/features/home/presentation/home_page.dart';

void main() {
  test('isTransientHomeRecommendError covers timeout wording', () {
    expect(isTransientHomeRecommendError(TimeoutException('x')), isTrue);
    expect(
      isTransientHomeRecommendError(Exception('Twitch browse popular 请求超时')),
      isTrue,
    );
    expect(isTransientHomeRecommendError(Exception('未拿到首页推荐内容')), isTrue);
    expect(isTransientHomeRecommendError(Exception('parse error')), isFalse);
  });
}
