import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_park/widgets/sp_overtime.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: 300, child: child),
          ),
        ),
      ),
    );
  }

  testWidgets('explains how an exit log\'s overtime was worked out', (
    WidgetTester tester,
  ) async {
    await pump(
      tester,
      SpOvertimeBreakdown.fromRecord(<String, dynamic>{
        'elapsedSeconds': const Duration(hours: 5, minutes: 10).inSeconds,
        'overtimeHours': 3,
        'overtimeRate': 20,
        'overtimeAmount': 60,
        'overtimeStatus': 'cash_due',
      }),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('5h 10m'), findsOneWidget);
    expect(find.text('counts as 6 hours'), findsOneWidget);
    expect(find.text('Covered by ticket'), findsOneWidget);
    expect(find.text('3 hours'), findsNWidgets(2));
    expect(find.text('× PHP 20.00 per hour'), findsOneWidget);
    expect(find.text('PHP 60.00'), findsOneWidget);
    expect(find.text('Cash not yet confirmed as collected.'), findsOneWidget);
  });

  testWidgets('tells the driver what to do, from a ticket record', (
    WidgetTester tester,
  ) async {
    await pump(
      tester,
      SpOvertimeBreakdown.fromRecord(<String, dynamic>{
        'staySeconds': const Duration(hours: 26).inSeconds,
        'overtimeHours': 2,
        'overtimeAmount': 50,
        'overtimeStatus': 'waived',
      }, forDriver: true),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('counts as 1 day, 2 hours'), findsOneWidget);
    expect(find.text('1 day'), findsOneWidget); // covered by the ticket
    // No stored rate: derived from the amount.
    expect(find.text('× PHP 25.00 per hour'), findsOneWidget);
    expect(
      find.text('Waived by the parking owner. Nothing to pay.'),
      findsOneWidget,
    );
  });
}
