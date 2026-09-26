import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_park/services/parking_pricing.dart';
import 'package:smart_park/widgets/sp_overtime.dart';

void main() {
  final DateTime entry = DateTime(2026, 9, 26, 9);
  final Map<String, dynamic> rates = <String, dynamic>{
    'car': <String, dynamic>{'initial': 50, 'succeedingHour': 20},
  };

  SpParkedStay stay(Map<String, dynamic> extra, {Map<String, dynamic>? r}) =>
      SpParkedStay.fromTicket('t1', <String, dynamic>{
        'vehicleType': 'car',
        'vehiclePlate': 'ABC 123',
        'plan': 'base',
        'entryAt': Timestamp.fromDate(entry),
        ...extra,
      }, r ?? rates)!;

  group('SpParkedStay', () {
    test('overtime starts after the paid hours plus grace', () {
      expect(
        overtimeStartsAt(entry, 2),
        entry.add(const Duration(hours: 2, minutes: 5)),
      );
      final SpParkedStay s = stay(<String, dynamic>{});
      expect(s.paidUntil, entry.add(const Duration(hours: 2)));
      expect(
        s.isOverAt(entry.add(const Duration(hours: 2, minutes: 5))),
        isFalse,
      );
      expect(
        s.isOverAt(entry.add(const Duration(hours: 2, minutes: 6))),
        isTrue,
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
      expect(
        s.endsSoonAt(entry.add(const Duration(hours: 2, minutes: 3))),
        isTrue,
      );
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
