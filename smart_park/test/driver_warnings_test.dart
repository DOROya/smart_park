import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_park/screens/driver/widgets/driver_warning_watcher.dart';
import 'package:smart_park/theme/app_theme.dart';

void main() {
  group('warning popup', () {
    late FakeFirebaseFirestore db;
    late BuildContext hostContext;

    setUp(() async {
      db = FakeFirebaseFirestore();
      await db.collection('driver_warnings').doc('w1').set(<String, dynamic>{
        'driverId': 'driver-1',
        'reasons': <String>['Refused to pay overtime cash'],
        'reason': 'Refused to pay overtime cash',
        'message': 'Please pay overtime at the gate.',
        'establishmentName': 'Mall Parking',
        'createdAt': Timestamp.fromDate(DateTime(2026, 10, 21)),
        'acknowledgedAt': null,
      });
    });

    Future<DriverWarningWatcher> pumpWatcher(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.theme,
          home: Builder(
            builder: (BuildContext context) {
              hostContext = context;
              return const Scaffold(body: SizedBox.expand());
            },
          ),
        ),
      );
      return DriverWarningWatcher(() => hostContext, 'driver-1', firestore: db);
    }

    Future<Map<String, dynamic>> w1() async =>
        (await db.collection('driver_warnings').doc('w1').get()).data()!;

    testWidgets('pops up a new warning once, then never again', (
      WidgetTester tester,
    ) async {
      final DriverWarningWatcher watcher = await pumpWatcher(tester);
      unawaited(watcher.check());
      await tester.pumpAndSettle();
      expect(find.text('Warning from SmartPark'), findsOneWidget);
      expect(find.text('Refused to pay overtime cash'), findsOneWidget);
      expect(find.text('Please pay overtime at the gate.'), findsOneWidget);
      expect(find.textContaining('Mall Parking'), findsOneWidget);
      // Seen as soon as it is shown, before any tap.
      expect((await w1())['acknowledgedAt'], isNotNull);

      await tester.tap(find.text('I understand'));
      await tester.pumpAndSettle();
      expect(find.text('Warning from SmartPark'), findsNothing);

      // Opening the app again shows nothing.
      unawaited(watcher.check());
      await tester.pumpAndSettle();
      expect(find.text('Warning from SmartPark'), findsNothing);
    });

    testWidgets('closing it without "I understand" still counts as seen', (
      WidgetTester tester,
    ) async {
      final DriverWarningWatcher watcher = await pumpWatcher(tester);
      unawaited(watcher.check());
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.text('Warning from SmartPark'), findsNothing);
      unawaited(watcher.check());
      await tester.pumpAndSettle();
      expect(find.text('Warning from SmartPark'), findsNothing);
    });

    testWidgets('shows several new warnings in one popup', (
      WidgetTester tester,
    ) async {
      await db.collection('driver_warnings').doc('w2').set(<String, dynamic>{
        'driverId': 'driver-1',
        'reason': '',
        'message': 'Second warning.',
        'createdAt': Timestamp.fromDate(DateTime(2026, 10, 25)),
        'acknowledgedAt': null,
      });
      final DriverWarningWatcher watcher = await pumpWatcher(tester);
      unawaited(watcher.check());
      await tester.pumpAndSettle();
      expect(find.text('2 warnings from SmartPark'), findsOneWidget);
      expect(find.text('Second warning.'), findsOneWidget);
    });

    testWidgets('ignores other drivers\' and already seen warnings', (
      WidgetTester tester,
    ) async {
      await db.collection('driver_warnings').doc('w1').update(<String, dynamic>{
        'acknowledgedAt': Timestamp.now(),
      });
      await db.collection('driver_warnings').doc('w3').set(<String, dynamic>{
        'driverId': 'driver-2',
        'message': 'Not yours.',
        'acknowledgedAt': null,
      });
      final DriverWarningWatcher watcher = await pumpWatcher(tester);
      unawaited(watcher.check());
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });
  });

  group('Account Notices', () {
    const String longMessage =
        'SmartPark received a report about your parking at Mall Parking: '
        'Refused to pay overtime cash. Please follow each facility\'s rules '
        'and pay any overtime at the gate. Repeated reports may lead to '
        'action on your account.';

    testWidgets('show a short preview and the whole notice on tap', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final FakeFirebaseFirestore db = FakeFirebaseFirestore();
      await db.collection('driver_warnings').add(<String, dynamic>{
        'driverId': 'driver-1',
        'reasons': <String>['Refused to pay overtime cash'],
        'reason': 'Refused to pay overtime cash',
        'message': longMessage,
        'establishmentName': 'Mall Parking',
        'createdAt': Timestamp.fromDate(DateTime(2026, 10, 21)),
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.theme,
          home: Scaffold(
            body: SingleChildScrollView(
              child: DriverNoticesCard(driverId: 'driver-1', firestore: db),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      Text message() => tester.widget<Text>(find.text(longMessage));
      expect(message().maxLines, 2);
      expect(find.text('Tap to read more'), findsOneWidget);
      expect(find.text('Facility: Mall Parking'), findsNothing);
      final double collapsed = tester
          .getSize(find.byType(InkWell).first)
          .height;

      await tester.tap(find.text('Tap to read more'));
      await tester.pumpAndSettle();
      expect(message().maxLines, isNull);
      expect(find.text('Tap to read more'), findsNothing);
      expect(find.text('Facility: Mall Parking'), findsOneWidget);
      expect(
        tester.getSize(find.byType(InkWell).first).height,
        greaterThan(collapsed),
      );

      // Tapping again folds it back.
      await tester.tap(find.text(longMessage));
      await tester.pumpAndSettle();
      expect(message().maxLines, 2);
    });

    testWidgets('older warnings that name "Other" show as a plain Warning', (
      WidgetTester tester,
    ) async {
      final FakeFirebaseFirestore db = FakeFirebaseFirestore();
      await db.collection('driver_warnings').add(<String, dynamic>{
        'driverId': 'driver-1',
        'reason': 'Other',
        'message': 'Please keep the exit lane clear.',
        'createdAt': Timestamp.fromDate(DateTime(2026, 10, 21)),
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.theme,
          home: Scaffold(
            body: SingleChildScrollView(
              child: DriverNoticesCard(driverId: 'driver-1', firestore: db),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Warning'), findsOneWidget);
      expect(find.text('Other'), findsNothing);
    });
  });
}
