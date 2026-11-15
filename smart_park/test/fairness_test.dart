import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_park/services/facility_status.dart';
import 'package:smart_park/services/operating_hours.dart';
import 'package:smart_park/services/parking_pricing.dart';
import 'package:smart_park/services/parking_refunds.dart';

void main() {
  // Open 6:00 AM to 10:00 PM.
  const OperatingHours hours = OperatingHours(
    openMinutes: 6 * 60,
    closeMinutes: 22 * 60,
  );

  group('a short visit', () {
    test('uses no hours within 10 minutes of entering', () {
      expect(kTurnaroundMinutes, 10);
      expect(hoursDeducted(const Duration(minutes: 4), 24), 0);
      expect(hoursDeducted(const Duration(minutes: 10), 2), 0);
    });

    test('past that, still uses at least the base stay', () {
      expect(hoursDeducted(const Duration(minutes: 11), 24), 2);
      expect(hoursDeducted(const Duration(hours: 1), 24), 2);
    });
  });

  group('overtime while the facility is closed', () {
    final DateTime entry = DateTime(2026, 11, 15, 19);

    test('closed time is counted by the minute', () {
      expect(
        closedTimeBetween(
          DateTime(2026, 11, 15, 21),
          DateTime(2026, 11, 16, 7),
          hours,
        ),
        const Duration(hours: 8),
      );
      expect(
        closedTimeBetween(
          DateTime(2026, 11, 15, 21),
          DateTime(2026, 11, 16, 7),
          const OperatingHours.allDay(),
        ),
        Duration.zero,
      );
      // No hours set: nothing is known to be closed.
      expect(
        closedTimeBetween(
          DateTime(2026, 11, 15, 21),
          DateTime(2026, 11, 16, 7),
          const OperatingHours(),
        ),
        Duration.zero,
      );
    });

    test('a car locked in overnight is not charged for the night', () {
      // In at 7 pm with 2 hours: paid until 9 pm. Out at 7 am.
      final DateTime exit = DateTime(2026, 11, 16, 7);
      final Duration clock = overtimeClock(entry, exit, 2, hours);
      // 12 hours parked, 8 of them closed.
      expect(clock, const Duration(hours: 4));
      expect(overtimeHours(clock, 2, graceMinutes: 20), 2);
      // Before this, the whole night counted.
      expect(overtimeHours(exit.difference(entry), 2, graceMinutes: 20), 10);
    });

    test('closed time inside the paid hours changes nothing', () {
      // A 24-hour ticket covers the night; leaving at 6 pm is within it.
      final DateTime exit = DateTime(2026, 11, 16, 18);
      final Duration clock = overtimeClock(entry, exit, 24, hours);
      expect(clock, exit.difference(entry));
      expect(overtimeHours(clock, 24), 0);
    });

    test('the grace period also waits for the facility to reopen', () {
      // Paid until 9:50 pm: 10 open minutes, then closed until 6 am.
      final DateTime late = DateTime(2026, 11, 15, 19, 50);
      Duration at(DateTime exit) => overtimeClock(late, exit, 2, hours);
      expect(
        overtimeHours(at(DateTime(2026, 11, 16, 6, 5)), 2, graceMinutes: 20),
        0,
      );
      expect(
        overtimeHours(at(DateTime(2026, 11, 16, 6, 15)), 2, graceMinutes: 20),
        1,
      );
    });
  });

  group('notice before a suspension', () {
    test('fixable reasons need notice; serious ones do not', () {
      expect(needsNoticeFirst(<String>['Rates differ from the listing']), true);
      expect(needsNoticeFirst(<String>[kPermitExpiredReason]), true);
      expect(needsNoticeFirst(<String>['Other']), true);
      expect(needsNoticeFirst(<String>['Safety or security concerns']), false);
      expect(
        needsNoticeFirst(<String>[
          'Rates differ from the listing',
          'Incomplete or false documents',
        ]),
        false,
      );
      expect(needsNoticeFirst(<String>[]), false);
      for (final String reason in kImmediateRestrictionReasons) {
        expect(kRestrictionReasons, contains(reason));
      }
    });

    test('a notice lapses on its due date', () {
      final DateTime issued = DateTime(2026, 11, 15, 9);
      final ComplianceNotice? notice = ComplianceNotice.of(<String, dynamic>{
        'complianceNotice': <String, dynamic>{
          'reasons': <String>['Rates differ from the listing'],
          'message': 'Weekly rate posted at the gate is higher.',
          'issuedAt': Timestamp.fromDate(issued),
          'dueAt': Timestamp.fromDate(
            issued.add(const Duration(days: kComplianceNoticeDays)),
          ),
        },
      });
      expect(notice, isNotNull);
      expect(notice!.reasons, <String>['Rates differ from the listing']);
      expect(notice.lapsedAt(DateTime(2026, 11, 21)), isFalse);
      expect(notice.lapsedAt(DateTime(2026, 11, 22, 9)), isTrue);
      expect(ComplianceNotice.of(<String, dynamic>{}), isNull);
      expect(
        ComplianceNotice.of(<String, dynamic>{'complianceNotice': null}),
        isNull,
      );
    });
  });

  test('a sent refund counts as paid out but not yet refunded', () {
    final ParkingRefund sent = ParkingRefund.fromMap('t1', <String, dynamic>{
      'status': 'sent',
      'paidBy': 'owner',
      'amountCentavos': 10000,
    });
    expect(sent.isPaidOut, isTrue);
    expect(sent.isRefunded, isFalse);
    expect(sent.statusLabel, 'Sent');
    expect(kRefundRequestAutoApproveDays, 3);
  });
}
