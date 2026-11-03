import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_park/content/terms_content.dart';
import 'package:smart_park/screens/auth/terms_screen.dart';
import 'package:smart_park/theme/app_theme.dart';
import 'package:smart_park/widgets/auth_widgets.dart';
import 'package:smart_park/widgets/sp_terms_view.dart';

String allText(String role) => termsFor(
  role,
).expand((TermsSection s) => <String>[s.title, ...s.points]).join(' ');

void main() {
  group('terms content', () {
    test('drivers and owners each get every section, numbered in order', () {
      for (final String role in <String>[kDriverRole, kParkingOwnerRole]) {
        final List<TermsSection> sections = termsFor(role);
        expect(sections, hasLength(10));
        for (int i = 0; i < sections.length; i++) {
          expect(sections[i].title, startsWith('${i + 1}. '));
          expect(sections[i].points, isNotEmpty);
        }
      }
      expect(termsFor('admin'), isEmpty);
    });

    test('match what the app does', () {
      final String driver = allText(kDriverRole);
      expect(driver, contains('not a reservation service'));
      expect(driver, contains('only for the same vehicle type'));
      expect(driver, contains('at least 2 hours'));
      expect(driver, contains('20 minutes unless the owner picked another'));
      expect(driver, contains('paid in cash'));
      expect(driver, contains('Republic Act No. 10173'));
      expect(driver, contains('it is not stored'));

      final String owner = allText(kParkingOwnerRole);
      expect(owner, contains('5% platform commission'));
      expect(owner, contains('none, or 10, 15, 20, 25, 30 minutes'));
      expect(owner, contains('Deactivate a staff account'));
      expect(owner, contains('ask for a review'));
      // Each role only reads about its own side.
      expect(driver, isNot(contains('platform commission')));
      expect(owner, isNot(contains('Account Notices')));
    });

    test('name a way to reach SmartPark', () {
      for (final String role in <String>[kDriverRole, kParkingOwnerRole]) {
        expect(allText(role), contains(kSupportEmail));
      }
    });
  });

  group('sign-up terms screen', () {
    Future<void> pumpTerms(WidgetTester tester, String role) {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      return tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.theme,
          home: TermsScreen(
            role: role,
            firstName: 'Ana',
            lastName: 'Reyes',
            email: 'ana@example.com',
            password: 'secret123',
          ),
        ),
      );
    }

    bool createEnabled(WidgetTester tester) => tester
        .widget<PrimaryAuthButton>(find.byType(PrimaryAuthButton))
        .enabled;

    testWidgets('shows the role\'s terms instead of placeholder text', (
      WidgetTester tester,
    ) async {
      await pumpTerms(tester, kDriverRole);
      expect(tester.takeException(), isNull);
      expect(find.textContaining('placeholder'), findsNothing);
      expect(find.text('3. Tickets'), findsOneWidget);
      expect(find.text('8. Privacy Notice'), findsOneWidget);
      expect(find.text('Last updated $kTermsUpdatedLabel'), findsOneWidget);
    });

    testWidgets('owners see the facility sections', (
      WidgetTester tester,
    ) async {
      await pumpTerms(tester, kParkingOwnerRole);
      expect(find.text('3. Registering a Facility'), findsOneWidget);
      expect(find.text('3. Tickets'), findsNothing);
    });

    testWidgets('an account needs the box ticked first', (
      WidgetTester tester,
    ) async {
      await pumpTerms(tester, kDriverRole);
      expect(createEnabled(tester), isFalse);
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      expect(createEnabled(tester), isTrue);
    });
  });

  testWidgets('the Profile card opens the terms again', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.theme,
        home: const Scaffold(body: SpTermsCard(role: kParkingOwnerRole)),
      ),
    );
    await tester.tap(find.text('Read Terms and Conditions'));
    await tester.pumpAndSettle();
    expect(find.byType(SpTermsPage), findsOneWidget);
    expect(find.text('Terms and Conditions'), findsOneWidget);
    expect(find.text('1. About SmartPark'), findsOneWidget);
  });
}
