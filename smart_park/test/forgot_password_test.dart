import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_park/screens/auth/forgot_password_screen.dart';

Future<void> _open(WidgetTester tester, {String email = ''}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.6;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(home: ForgotPasswordScreen(initialEmail: email)),
  );
}

void main() {
  testWidgets('prefills the email typed on the sign-in screen', (
    WidgetTester tester,
  ) async {
    await _open(tester, email: ' saya@example.com ');
    expect(find.text('saya@example.com'), findsOneWidget);
    expect(find.text('Send reset link'), findsOneWidget);
  });

  testWidgets('does not prefill a username', (WidgetTester tester) async {
    await _open(tester, email: 'staff01');
    expect(find.text('staff01'), findsNothing);
  });

  testWidgets('explains an empty email instead of doing nothing', (
    WidgetTester tester,
  ) async {
    await _open(tester);
    await tester.tap(find.text('Send reset link'));
    await tester.pump();
    expect(find.text('Enter the email you signed up with.'), findsOneWidget);
  });

  testWidgets('points username accounts to the parking owner', (
    WidgetTester tester,
  ) async {
    await _open(tester);
    await tester.enterText(find.byType(TextField), 'staff01');
    await tester.tap(find.text('Send reset link'));
    await tester.pump();
    expect(find.textContaining('reset by the parking owner'), findsOneWidget);
  });
}
