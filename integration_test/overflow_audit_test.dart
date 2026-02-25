import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:peerchat_secure/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('no RenderFlex overflow across main app pages',
      (WidgetTester tester) async {
    FlutterErrorDetails? overflowError;
    final originalOnError = FlutterError.onError;

    FlutterError.onError = (FlutterErrorDetails details) {
      final msg = details.exceptionAsString();
      if (msg.contains('RenderFlex overflowed') ||
          msg.contains('A RenderFlex overflowed')) {
        overflowError = details;
      }
      originalOnError?.call(details);
    };

    Future<void> assertNoTestExceptions() async {
      final e = tester.takeException();
      expect(e, isNull, reason: 'Unexpected framework exception: $e');
      expect(
        overflowError,
        isNull,
        reason:
            'Render overflow detected: ${overflowError?.exceptionAsString()}',
      );
    }

    Future<void> openTab(String label) async {
      final tab = find.text(label);
      expect(tab, findsWidgets, reason: 'Tab "$label" should be visible');
      await tester.tap(tab.first);
      await tester.pump(const Duration(milliseconds: 900));
      await assertNoTestExceptions();
    }

    Future<void> maybeScrollOnce() async {
      final scrollables = find.byType(Scrollable);
      if (scrollables.evaluate().isEmpty) return;
      await tester.drag(scrollables.first, const Offset(0, -500));
      await tester.pump(const Duration(milliseconds: 700));
      await assertNoTestExceptions();
    }

    app.main();

    // App has periodic timers/background work; avoid pumpAndSettle.
    await tester.pump(const Duration(seconds: 6));
    await assertNoTestExceptions();

    // Main tabs
    await openTab('Home');
    await maybeScrollOnce();

    await openTab('Messages');
    await maybeScrollOnce();

    await openTab('Peers');
    await maybeScrollOnce();

    await openTab('Emergency');
    await maybeScrollOnce();

    await openTab('Debug');
    await maybeScrollOnce();

    // Debug sub-tabs
    final routesTab = find.text('Routes');
    if (routesTab.evaluate().isNotEmpty) {
      await tester.tap(routesTab.first);
      await tester.pump(const Duration(milliseconds: 700));
      await assertNoTestExceptions();
    }
    final queueTab = find.text('Queue');
    if (queueTab.evaluate().isNotEmpty) {
      await tester.tap(queueTab.first);
      await tester.pump(const Duration(milliseconds: 700));
      await assertNoTestExceptions();
    }
    final networkTab = find.text('Network');
    if (networkTab.evaluate().isNotEmpty) {
      await tester.tap(networkTab.first);
      await tester.pump(const Duration(milliseconds: 700));
      await assertNoTestExceptions();
      await maybeScrollOnce();
    }

    await assertNoTestExceptions();

    FlutterError.onError = originalOnError;
  });
}

