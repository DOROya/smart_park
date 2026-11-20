import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_park/screens/parking_owner/widgets/owner_walk_in_cash_row.dart';
import 'package:smart_park/services/activity_export.dart';
import 'package:smart_park/services/gate_cash.dart';
import 'package:smart_park/services/sales_report.dart';
import 'package:smart_park/services/staff_shifts.dart';

Timestamp at(int day, [int hour = 9]) =>
    Timestamp.fromDate(DateTime(2026, 11, day, hour));

Map<String, dynamic> overtimeExit({
  required String collector,
  double amount = 40,
  String? handover,
  int day = 20,
}) => <String, dynamic>{
  'scanType': 'exit',
  'source': 'ticket',
  'staffId': collector,
  'staffName': 'Ana',
  'overtimeAmount': amount,
  'overtimeStatus': 'collected',
  'overtimeCollectedBy': collector,
  'timestamp': at(day),
  'cashHandoverId': ?handover,
};

Map<String, dynamic> walkInExit({
  required String staff,
  double fee = 50,
  String? handover,
  int day = 20,
}) => <String, dynamic>{
  'scanType': 'exit',
  'source': 'walk_in',
  'staffId': staff,
  'staffName': 'Ben',
  'walkInFee': fee,
  'timestamp': at(day),
  'cashHandoverId': ?handover,
};

void main() {
  group('gate cash', () {
    test('counts overtime collected and walk-in fees per staff member', () {
      final List<StaffCashDue> due = cashDueByStaff(
        <({String id, Map<String, dynamic> data})>[
          (id: 'a', data: overtimeExit(collector: 's1', amount: 40, day: 18)),
          (id: 'b', data: walkInExit(staff: 's1', fee: 60)),
          (id: 'c', data: walkInExit(staff: 's2', fee: 30)),
          // Already handed over, or not cash: skipped.
          (id: 'd', data: walkInExit(staff: 's2', fee: 99, handover: 'h1')),
          (
            id: 'e',
            data: <String, dynamic>{
              ...overtimeExit(collector: 's2'),
              'overtimeStatus': 'cash_due',
            },
          ),
          // The same log from both queries counts once.
          (id: 'c', data: walkInExit(staff: 's2', fee: 30)),
        ],
      );
      expect(due.map((d) => d.staffId), <String>['s1', 's2']);
      expect(due[0].overtime, 40);
      expect(due[0].walkIn, 60);
      expect(due[0].total, 100);
      expect(due[0].logIds, <String>['a', 'b']);
      expect(due[0].since, DateTime(2026, 11, 18, 9));
      expect(due[1].total, 30);
    });

    test('a walk-in fee only counts on a walk-in exit', () {
      expect(walkInFeeOf(walkInExit(staff: 's1')), 50);
      expect(
        walkInFeeOf(<String, dynamic>{
          ...walkInExit(staff: 's1'),
          'scanType': 'entry',
        }),
        0,
      );
      expect(
        walkInFeeOf(<String, dynamic>{
          ...walkInExit(staff: 's1'),
          'source': 'ticket',
        }),
        0,
      );
    });

    test('a handover is recorded and stamps every log it covers', () async {
      final FakeFirebaseFirestore db = FakeFirebaseFirestore();
      final Map<String, Map<String, dynamic>> logs =
          <String, Map<String, dynamic>>{
            'a': overtimeExit(collector: 's1', amount: 40),
            'b': walkInExit(staff: 's1', fee: 60),
          };
      for (final MapEntry<String, Map<String, dynamic>> e in logs.entries) {
        await db.collection('activity_logs').doc(e.key).set(e.value);
      }
      final StaffCashDue due = cashDueByStaff(
        logs.entries.map((e) => (id: e.key, data: e.value)),
      ).single;
      final String id = await recordCashHandover(
        facilityId: 'f1',
        ownerId: 'o1',
        due: due,
        staffName: 'Ana',
        logsById: logs,
        note: ' short by 5 ',
        firestore: db,
      );
      final Map<String, dynamic> h =
          (await db.collection('cash_handovers').doc(id).get()).data()!;
      expect(h['amount'], 100);
      expect(h['overtimeAmount'], 40);
      expect(h['walkInAmount'], 60);
      expect(h['logCount'], 2);
      expect(h['staffId'], 's1');
      expect(h['receivedBy'], 'o1');
      expect(h['note'], 'short by 5');
      for (final String log in <String>['a', 'b']) {
        final Map<String, dynamic> d =
            (await db.collection('activity_logs').doc(log).get()).data()!;
        expect(d['cashHandoverId'], id);
        expect(awaitsHandover(d), isFalse);
      }
    });
  });

  group('walk-in cash in reports', () {
    test('sums the fees whose exit is in the period', () {
      final FinanceRange nov = FinanceRange.containing(
        FinancePeriod.month,
        DateTime(2026, 11, 5),
      );
      final ({int centavos, int count}) r = walkInCashIn(<Map<String, dynamic>>[
        walkInExit(staff: 's1', fee: 50, day: 3),
        walkInExit(staff: 's1', fee: 25.5, day: 20),
        <String, dynamic>{
          ...walkInExit(staff: 's1', fee: 70),
          'timestamp': Timestamp.fromDate(DateTime(2026, 10, 31, 23)),
        },
      ], nov);
      expect(r.centavos, 7550);
      expect(r.count, 2);
    });
  });

  group('activity export', () {
    test('quotes commas and quotes, and defuses spreadsheet formulas', () {
      expect(csvField('ABC 123'), 'ABC 123');
      expect(csvField('Dela Cruz, Juan'), '"Dela Cruz, Juan"');
      expect(csvField('He said "hi"'), '"He said ""hi"""');
      expect(csvField('=HYPERLINK("x")'), '"\'=HYPERLINK(""x"")"');
      expect(csvField('-5'), "'-5");
      expect(csvField(null), '');
    });

    test('one row per scan with the cash taken', () {
      final List<String> row = activityCsvRow(<String, dynamic>{
        ...overtimeExit(collector: 's1', amount: 40),
        'timestamp': Timestamp.fromDate(DateTime(2026, 11, 20, 7, 5)),
        'decision': 'ALLOWED',
        'vehiclePlate': 'ABC 123',
        'vehicleType': 'car',
        'driverName': 'Juan',
        'transactionId': 't1',
        'elapsedSeconds': 3 * 3600 + 25 * 60,
      }, (_) => 'Ana');
      expect(row.length, kActivityCsvColumns.length);
      expect(row.sublist(0, 4), <String>[
        '2026-11-20',
        '07:05',
        'Exit',
        'Allowed',
      ]);
      expect(row[5], 'ABC 123');
      expect(row[7], 'SmartPark');
      expect(row[10], 'Ana');
      expect(row[11], '3:25');
      expect(row[12], '40.00');
      expect(row[13], 'collected');
      expect(row[15], 'Not yet');

      final List<String> walkIn = activityCsvRow(
        walkInExit(staff: 's2', fee: 50, handover: 'h1'),
        (_) => 'Ben',
      );
      expect(walkIn[7], 'Walk-in');
      expect(walkIn[14], '50.00');
      expect(walkIn[15], 'Yes');
    });

    test('the file starts with a byte order mark and a header row', () {
      final List<int> bytes = buildActivityCsv(<Map<String, dynamic>>[
        walkInExit(staff: 's1'),
      ], (_) => 'Ben');
      // UTF-8 byte order mark, so Excel reads accented names correctly.
      expect(bytes.sublist(0, 3), <int>[0xEF, 0xBB, 0xBF]);
      final String csv = utf8.decode(bytes.sublist(3));
      expect(csv.startsWith('Date,Time,Scan,'), isTrue);
      expect(csv.trim().split('\r\n'), hasLength(2));
      expect(
        activityCsvFileName(DateTime(2026, 11, 1), DateTime(2026, 11, 20)),
        'SmartPark-activity-2026-11-01-to-2026-11-20.csv',
      );
    });
  });

  group('duty log', () {
    test('shift length reads as hours and minutes', () {
      final DateTime start = DateTime(2026, 11, 20, 8, 2);
      expect(shiftLength(start, DateTime(2026, 11, 20, 16, 7)), '8h 05m');
      expect(
        shiftLength(start, null, now: DateTime(2026, 11, 20, 8, 32)),
        '0h 30m',
      );
    });

    test('clock in opens a shift and clock out ends it', () async {
      final FakeFirebaseFirestore db = FakeFirebaseFirestore();
      await clockIn(
        staffId: 's1',
        staffName: 'Ana',
        facilityId: 'f1',
        ownerId: 'o1',
        firestore: db,
      );
      final QuerySnapshot<Map<String, dynamic>> open = await openShiftsOf(
        's1',
        firestore: db,
      ).get();
      expect(open.docs, hasLength(1));
      expect((await onDutyAt('f1', firestore: db).get()).docs, hasLength(1));
      await clockOut(open.docs.single.id, endedBy: 'o1', firestore: db);
      expect((await openShiftsOf('s1', firestore: db).get()).docs, isEmpty);
      final Map<String, dynamic> ended =
          (await db.collection('staff_shifts').doc(open.docs.single.id).get())
              .data()!;
      expect(ended['endedAt'], isNotNull);
      expect(ended['endedBy'], 'o1');
    });
  });
}
