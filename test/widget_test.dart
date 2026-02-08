// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:just_flutter/main.dart';
import 'package:just_flutter/theme_provider.dart';

void main() {
  testWidgets('App launches smoke test', (WidgetTester tester) async {
    final themeProvider = ThemeProvider();
    await tester.pumpWidget(BUddyApp(themeProvider: themeProvider));
    // Verify the app renders.
    expect(find.text('BUddy Student Helper'), findsOneWidget);
  });
}
