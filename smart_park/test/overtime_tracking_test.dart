import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_park/services/parking_pricing.dart';
import 'package:smart_park/widgets/sp_overtime.dart';

void main() {
  final DateTime entry = DateTime(2026, 9, 26, 9);
  final Map<String, dynamic> rates = <String, dynamic>{
    'car': <String, dynamic>{'initial': 50, 'succeedingHour': 20},
  };

  SpParkedStay stay(
    Map<String, dynamic> extra, {
    Map<String, dynamic>? r,
    int grace = kDefaultGraceMinutes,
  }) => SpParkedStay.fromTicket(
    't1',
    <String, dynamic>{
      'vehicleType': 'car',
      'vehiclePlate': 'ABC 123',
      'plan': 'base',
      'entryAt': Timestamp.fromDate(entry),
      ...extra,
    },
    r ?? rates,
    graceMinutes: grace,
  )!;

  group('SpParkedStay', () {
    test('with no grace, overtime starts the first minute past paid', () {
      expect(
        overtimeStartsAt(entry, 2),
        entry.add(const Duration(hours: 2, minutes: 1)),
      );
      final SpParkedStay s = stay(<String, dynamic>{}, grace: 0);
      expect(s.paidUntil, entry.add(const Duration(hours: 2)));
      expect(s.isOverAt(entry.add(const Duration(hours: 2))), isFalse);
      expect(
        s.isOverAt(entry.add(const Duration(hours: 2, minutes: 1))),
        isTrue,
      );
    });

    test('a reused ticket counts only the hours it has left', () {
      final SpParkedStay s = stay(<String, dynamic>{
        'plan': 'daily',
        'remainingHours': 3,
      }, grace: 0);
      expect(s.includedHours, 3);
      expect(s.isOverAt(entry.add(const Duration(hours: 3))), isFalse);
      expect(
        s.isOverAt(entry.add(const Duration(hours: 3, minutes: 1))),
        isTrue,
      );
    });

    test("overtime waits for the facility's grace period", () {
      final SpParkedStay s = stay(<String, dynamic>{});
      expect(s.overtimeFrom, entry.add(const Duration(hours: 2, minutes: 21)));
      expect(
        s.isOverAt(entry.add(const Duration(hours: 2, minutes: 20))),
        isFalse,
      );
      expect(
        s.isOverAt(entry.add(const Duration(hours: 2, minutes: 21))),
        isTrue,
      );
      // Counted from the end of the paid time: 1 hour, not 0.
      expect(
        s.overtimeHoursAt(entry.add(const Duration(hours: 2, minutes: 21))),
        1,
      );
      final SpParkedStay longGrace = stay(<String, dynamic>{}, grace: 30);
      expect(
        longGrace.isOverAt(entry.add(const Duration(hours: 2, minutes: 30))),
        isFalse,
      );
    });

    test('owed matches what the gate would bill', () {
      final SpParkedStay s = stay(<String, dynamic>{});
      // 4h on a 2h base: 1h55m past grace -> 2 hours at 20.
      expect(s.owedAt(entry.add(const Duration(hours: 4))), 40);
      expect(
        stay(
          <String, dynamic>{},
          r: <String, dynamic>{},
        ).owedAt(entry.add(const Duration(hours: 4))),
        isNull,
      );
    });

    test('ends soon in the last 15 minutes and the grace period', () {
      final SpParkedStay s = stay(<String, dynamic>{});
      expect(
        s.endsSoonAt(entry.add(const Duration(hours: 1, minutes: 40))),
        isFalse,
      );
      expect(
        s.endsSoonAt(entry.add(const Duration(hours: 1, minutes: 50))),
        isTrue,
      );
      expect(s.endsSoonAt(entry.add(const Duration(hours: 2))), isTrue);
      expect(s.endsSoonAt(entry.add(const Duration(hours: 3))), isFalse);
    });

    test('extended plans include their extra hours', () {
      final SpParkedStay s = stay(<String, dynamic>{
        'plan': 'extended',
        'duration': 3,
      });
      expect(s.includedHours, 5);
      expect(s.isOverAt(entry.add(const Duration(hours: 4))), isFalse);
    });

    test('skips walk-ins and tickets without an entry time', () {
      expect(
        SpParkedStay.fromTicket('w', <String, dynamic>{
          'source': 'walk_in',
          'entryAt': Timestamp.fromDate(entry),
        }, rates),
        isNull,
      );
      expect(SpParkedStay.fromTicket('t', <String, dynamic>{}, rates), isNull);
    });
  });

  test('SpOvertimeCash splits owed and collected cash', () {
    final SpOvertimeCash cash = SpOvertimeCash.from(<Map<String, dynamic>>[
      <String, dynamic>{'overtimeStatus': 'cash_due', 'overtimeAmount': 40},
      <String, dynamic>{'overtimeStatus': 'collected', 'overtimeAmount': 20},
      <String, dynamic>{'overtimeStatus': 'collected', 'overtimeAmount': 30},
      <String, dynamic>{'overtimeStatus': 'none', 'overtimeAmount': 0},
      <String, dynamic>{'overtimeStatus': 'rate_unresolved'},
    ]);
    expect(cash.dueCount, 1);
    expect(cash.dueAmount, 40);
    expect(cash.collectedCount, 2);
    expect(cash.collectedAmount, 50);
    expect(SpOvertimeCash.from(<Map<String, dynamic>>[]).isEmpty, isTrue);
  });
}
