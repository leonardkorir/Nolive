import 'dart:io';

import 'package:live_sync/live_sync.dart';
import 'package:test/test.dart';

void main() {
  test('describeLocalSyncError maps timeout and auth failures', () {
    expect(
      describeLocalSyncError(
        const HttpException('Local sync push failed with status 401.'),
      ),
      contains('配对码'),
    );
    expect(
      describeLocalSyncError(
        const HttpException('Local sync request timed out.'),
      ),
      allOf(contains('超时'), isNot(contains('不在同一局域网'))),
    );
    expect(
      describeLocalSyncError(
        const HttpException('Local sync push failed with status 413.'),
      ),
      contains('过大'),
    );
    expect(
      describeLocalSyncError(const FormatException('请先填写局域网同步配对码')),
      contains('配对码'),
    );
  });
}
