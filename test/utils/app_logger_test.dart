import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peerchat_secure/src/utils/app_logger.dart';

void main() {
  group('AppLogger', () {
    late DebugPrintCallback originalDebugPrint;
    late List<String?> loggedMessages;

    setUp(() {
      originalDebugPrint = debugPrint;
      loggedMessages = <String?>[];
      debugPrint = (String? message, {int? wrapWidth}) {
        loggedMessages.add(message);
      };
    });

    tearDown(() {
      debugPrint = originalDebugPrint;
    });

    test('debug, info, warning, and print alias emit tagged log lines', () {
      AppLogger.d('debug');
      AppLogger.print('alias');
      AppLogger.i('info');
      AppLogger.w('warn');

      expect(loggedMessages, <String?>[
        '[DEBUG] debug',
        '[DEBUG] alias',
        '[INFO] info',
        '[WARNING] warn',
      ]);
    });

    test('error logging includes optional error and stack trace details', () {
      final stack = StackTrace.fromString('trace line');

      AppLogger.e('failure', 'boom', stack);

      expect(loggedMessages, <String?>[
        '[ERROR] failure',
        'Error Details: boom',
        'Stack Trace:\n$stack',
      ]);
    });

    test('error logging without optional values emits only the base message', () {
      AppLogger.e('failure');

      expect(loggedMessages, <String?>['[ERROR] failure']);
    });
  });
}
