import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_park/screens/parking_owner/widgets/parking_trends_card.dart';

void main() {
  late FakeFirebaseFirestore db;
  final DateTime now = DateTime.now();
  final DateTime today = DateTime(now.year, now.month, now.day);

  Future<void> addLog(
    DateTime at, {
    String facility = 'fac-1',
    String scanType = 'entry',
    String status = 'ALLOWED',
  }) {
    return db.collection('activity_logs').add(<String, dynamic>{
      'establishmentID': facility,
      'scanType': scanType,
      'status': status,
      'timestamp': Timestamp.fromDate(at),
    });
  }

  Future<void> pumpCard(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 3600);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ParkingTrendsCard(facilityId: 'fac-1', firestore: db),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() => db = FakeFirebaseFirestore());

  testWidgets('shows totals, busiest day and peak hour from gate logs', (
    WidgetTester tester,
  ) async {
    final DateTime yesterday = today.subtract(const Duration(days: 1));
    await addLog(yesterday.add(const Duration(hours: 9, minutes: 5)));
    await addLog(yesterday.add(const Duration(hours: 9, minutes: 40)));
    await addLog(today.subtract(const Duration(days: 3, hours: -17)));
    // Not counted: an exit, a denied scan, another facility, too old.
    await addLog(yesterday.add(const Duration(hours: 10)), scanType: 'exit');
    await addLog(yesterday.add(const Duration(hours: 11)), status: 'DENIED');
    await addLog(yesterday.add(const Duration(hours: 9)), facility: 'fac-2');
    await addLog(today.subtract(const Duration(days: 20)));

    await pumpCard(tester);

    expect(find.text('Parking Trends'), findsOneWidget);
    expect(find.text('Vehicles'), findsOneWidget);
    expect(find.text('3'), findsWidgets);
    expect(find.text('2 vehicles'), findsOneWidget); // busiest day caption
    expect(find.text('9–10 AM'), findsOneWidget); // peak hour
    expect(find.text('2 entries'), findsOneWidget);
    expect(find.text('Vehicles per day'), findsOneWidget);
    expect(find.text('Busiest hours'), findsOneWidget);

    // 30 days also picks up the 20-day-old entry.
    await tester.tap(find.text('Last 30 days'));
    await tester.pumpAndSettle();
    expect(find.text('4'), findsWidgets);
    expect(
      find.text('Entries by hour of day, across the last 30 days.'),
      findsOneWidget,
    );
  });

  testWidgets('explains an empty range instead of empty charts', (
    WidgetTester tester,
  ) async {
    await addLog(today.subtract(const Duration(days: 1)), scanType: 'exit');
    await pumpCard(tester);
    expect(
      find.textContaining('No vehicles in the last 7 days yet'),
      findsOneWidget,
    );
    expect(find.text('Vehicles per day'), findsNothing);
  });
}
