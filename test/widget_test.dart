import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders app title text in a simple widget', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('PeerChat Secure'))),
    );

    expect(find.text('PeerChat Secure'), findsOneWidget);
  });
}