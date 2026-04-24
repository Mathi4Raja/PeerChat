import 'package:flutter_test/flutter_test.dart';
import 'package:peerchat_secure/src/utils/file_size_formatter.dart';

void main() {
  test('formatFileSizeBy1024 formats KB/MB/GB boundaries', () {
    expect(formatFileSizeBy1024(1024), '1.00 KB');
    expect(formatFileSizeBy1024(1024 * 1024), '1.00 MB');
    expect(formatFileSizeBy1024(3 * 1024 * 1024 * 1024), '3.00 GB');
  });
}

