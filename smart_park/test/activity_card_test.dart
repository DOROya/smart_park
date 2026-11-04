import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_park/widgets/smartpark_ui.dart';

void main() {
  Map<String, dynamic> scan([Map<String, dynamic> extra = const {}]) =>
      <String, dynamic>{
        'vehiclePlate': 'ABC 123',
        'status': 'ALLOWED',
        'scanType': 'entry',
        'driverName': 'Maria Santos',
        'staffId': 'guard-1',
        'staffName': 'Juan Dela Cruz',
        'transactionId': 'ticket-abcdefgh',
        'timestamp': DateTime(2026, 11, 3, 9, 5),
        ...extra,
      };

  Future<void> pump(WidgetTester tester, Widget card) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: SizedBox(width: 340, child: card)),
    ),
  );

  testWidgets('type, time and driver share one line', (
    WidgetTester tester,
  ) async {
    await pump(tester, SpActivityCard(data: scan()));

    expect(find.textContaining('Entry · '), findsOneWidget);
    expect(find.textContaining('Maria Santos'), findsOneWidget);
    expect(find.text('Entry · 9:05 AM · Maria Santos'), findsOneWidget);
  });

  testWidgets('the ticket number is left to the details sheet', (
    WidgetTester tester,
  ) async {
    await pump(tester, SpActivityCard(data: scan()));

    expect(find.textContaining('Ticket #'), findsNothing);
  });

  testWidgets('hides the staff name only on that staff member\'s scans', (
    WidgetTester tester,
  ) async {
    await pump(tester, SpActivityCard(data: scan(), hideStaffId: 'guard-1'));
    expect(find.textContaining('By Juan'), findsNothing);

    await pump(tester, SpActivityCard(data: scan(), hideStaffId: 'guard-2'));
    expect(find.textContaining('By Juan'), findsOneWidget);
  });

  testWidgets('a scan with no staff id keeps its staff name', (
    WidgetTester tester,
  ) async {
    await pump(
      tester,
      SpActivityCard(data: scan(<String, dynamic>{'staffId': ''})),
    );
    expect(find.textContaining('By Juan'), findsOneWidget);
  });

  testWidgets('an exit keeps its stay and billing on one details line', (
    WidgetTester tester,
  ) async {
    await pump(
      tester,
      SpActivityCard(
        data: scan(<String, dynamic>{
          'scanType': 'exit',
          'elapsedSeconds': 7200,
          'billableHours': 2,
        }),
        hideStaffId: 'guard-1',
      ),
    );

    expect(find.textContaining('Stayed'), findsOneWidget);
    expect(find.textContaining('Billed 2h'), findsOneWidget);
  });

  testWidgets('showDate adds the date for lists spanning days', (
    WidgetTester tester,
  ) async {
    await pump(tester, SpActivityCard(data: scan(), showDate: true));

    expect(find.textContaining('Nov 3, 2026, 9:05 AM'), findsOneWidget);
  });

  testWidgets('a denied scan keeps its reason', (WidgetTester tester) async {
    await pump(
      tester,
      SpActivityCard(
        data: scan(<String, dynamic>{
          'status': 'DENIED',
          'decisionReason': 'Vehicle type does not match ticket.',
        }),
      ),
    );

    expect(find.text('Denied'), findsOneWidget);
    expect(find.text('Vehicle type does not match ticket.'), findsOneWidget);
  });

  testWidgets('a long driver name does not overflow', (
    WidgetTester tester,
  ) async {
    await pump(
      tester,
      SpActivityCard(
        data: scan(<String, dynamic>{
          'driverName': 'Maria Clara Dela Cruz Santos Villanueva Reyes Jr.',
        }),
        showDate: true,
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
