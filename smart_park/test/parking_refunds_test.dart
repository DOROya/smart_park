import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_park/services/parking_refunds.dart';

void main() {
  test('the estimate keeps back the fees, as the server does', () {
    // 7 days for PHP 330 by GCash: 1650 commission and 660 PayMongo fee
    // leave 30690; 96 of 168 hours unused -> floor(30690 * 96 / 168).
    final Map<String, dynamic> weekly = <String, dynamic>{
      'plan': 'weekly',
      'duration': 1,
      'amount': 330,
      'paymentMethod': 'gcash',
      'remainingHours': 96,
    };
    final RefundBreakdown b = RefundBreakdown.of(weekly);
    expect(b.platformFeeCentavos, 1650);
    expect(b.processorFeeCentavos, 660);
    expect(b.refundableCentavos, 30690);
    expect(estimatedRefundCentavos(weekly), 17537);
    expect(
      estimatedRefundCentavos(<String, dynamic>{
        'plan': 'daily',
        'duration': 2,
        'amount': 200,
      }),
      18600,
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
