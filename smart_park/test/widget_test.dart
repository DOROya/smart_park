import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_park/screens/auth/welcome_screen.dart';
import 'package:smart_park/theme/app_theme.dart';

void main() {
  testWidgets('Welcome screen renders', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.lightTheme, home: const WelcomeScreen()),
    );

    expect(
      find.text('Welcome to SmartPark.', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.text('Find, pay for, and manage parking in one app.'),
      findsOneWidget,
    );
    expect(find.text('Login'), findsOneWidget);
    expect(find.text('Create an Account'), findsOneWidget);
  });
}
