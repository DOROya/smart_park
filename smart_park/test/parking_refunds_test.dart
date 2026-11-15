import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_park/services/parking_refunds.dart';

void main() {
  test('the estimate is the unused share of the price (as the server)', () {
    // 7 days for PHP 330 with 96 hours left: floor(33000 * 96 / 168).
    expect(
      estimatedRefundCentavos(<String, dynamic>{
        'plan': 'weekly',
        'duration': 1,
        'amount': 330,
        'remainingHours': 96,
      }),
      18857,
    );
    expect(
      estimatedRefundCentavos(<String, dynamic>{
        'plan': 'daily',
        'duration': 2,
        'amount': 200,
      }),
      20000,
    );
    expect(
      estimatedRefundCentavos(<String, dynamic>{
        'plan': 'daily',
        'duration': 1,
        'amount': 100,
        'remainingHours': 0,
      }),
      0,
    );
  });

  test('automatic suspension refunds come 14 days after it started', () {
    final DateTime start = DateTime(2026, 11, 14, 9);
    expect(
      suspensionRefundDate(Timestamp.fromDate(start)),
      DateTime(2026, 11, 28, 9),
    );
    expect(suspensionRefundDate(null), isNull);
  });

  test('a refund reads its status, cause and who covers it', () {
    final ParkingRefund r = ParkingRefund.fromMap('t1', <String, dynamic>{
      'status': 'requested',
      'cause': 'driver_request',
      'paidBy': 'platform',
      'amountCentavos': 5000,
      'restrictionReasons': <String>['Invalid business permit'],
    });
    expect(r.isPendingApproval, isTrue);
    expect(r.statusLabel, 'Awaiting approval');
    expect(r.causeLabel, 'Requested by driver');
    expect(r.paidByLabel, 'SmartPark');
    expect(r.reasons, <String>['Invalid business permit']);
  });
}
