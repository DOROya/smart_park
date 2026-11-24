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
    test('every role gets its sections, numbered in order', () {
      expect(termsFor(kDriverRole), hasLength(12));
      expect(termsFor(kParkingOwnerRole), hasLength(12));
      expect(termsFor(kStaffRole), hasLength(8));
      for (final String role in <String>[
        kDriverRole,
        kParkingOwnerRole,
        kStaffRole,
      ]) {
        final List<TermsSection> sections = termsFor(role);
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
      expect(owner, contains('platform commission'));
      // The rate in force, and the notice before a higher one.
      expect(owner, contains('and is 5%'));
      expect(owner, contains('at least 30 days before a higher rate'));
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

    test('cover who runs SmartPark, age, liability and disputes', () {
      for (final String role in <String>[
        kDriverRole,
        kParkingOwnerRole,
        kStaffRole,
      ]) {
        final String text = allText(role);
        expect(text, contains(kOperatorName));
        expect(text, contains('Responsibility and Liability'));
        expect(text, contains('laws of the Republic of the Philippines'));
        expect(text, contains('National Privacy Commission'));
        expect(text, contains('asks you to accept it before you continue'));
      }
      final String driver = allText(kDriverRole);
      expect(driver, contains('leave within 10 minutes of entering'));
      expect(driver, contains('Overtime does not run while the facility is'));
      expect(driver, contains('not charged overtime for the wait'));
      expect(driver, contains('within 3 days is approved automatically'));
      expect(driver, contains('within 72 hours'));
      expect(
        allText(kParkingOwnerRole),
        contains('written notice in the app and 7 days to fix it'),
      );
      expect(driver, contains('at least 18 years old'));
      expect(driver, contains('but not your email address'));
      expect(driver, contains('keeps the old one'));
      expect(driver, contains('contest it there'));
      expect(driver, contains('report a facility'));
      final String owner = allText(kParkingOwnerRole);
      expect(owner, contains('You are the seller of the parking'));
      expect(owner, contains('dispute it from the refund'));
      expect(owner, contains('due within 15 days'));
      expect(owner, contains('which are not refunded'));
      expect(driver, contains('never the full price'));
      expect(owner, contains('Post a notice at your gate'));
    });

    test('the Privacy Notice covers the audit log, data download and '
        'document deletion', () {
      final String driver = allText(kDriverRole);
      final String owner = allText(kParkingOwnerRole);
      final String staff = allText(kStaffRole);
      for (final String text in <String>[driver, owner, staff]) {
        expect(text, contains('audit log'));
      }
      expect(driver, contains('Download My Data'));
      expect(owner, contains('Download My Data'));
      // Staff have no Profile screen to download from.
      expect(staff, isNot(contains('Download My Data')));
      expect(owner, contains('deleted 90 days later'));
      expect(driver, isNot(contains('deleted 90 days later')));
    });

    test('the version is the date the terms were last changed', () {
      expect(kTermsVersion, startsWith('2026-11-23'));
      expect(kTermsUpdatedLabel, 'November 23, 2026');
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
