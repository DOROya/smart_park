import 'package:flutter_test/flutter_test.dart';
import 'package:smart_park/content/terms_content.dart';
import 'package:smart_park/screens/auth/terms_update_gate.dart';
import 'package:smart_park/services/driver_reports.dart';
import 'package:smart_park/services/facility_reports.dart';
import 'package:smart_park/services/facility_status.dart';
import 'package:smart_park/services/parking_pricing.dart';
import 'package:smart_park/services/parking_refunds.dart';

void main() {
  test('only the current terms version counts as accepted', () {
    expect(hasAcceptedCurrentTerms(null), isFalse);
    expect(hasAcceptedCurrentTerms(<String, dynamic>{}), isFalse);
    expect(
      hasAcceptedCurrentTerms(<String, dynamic>{'termsVersion': '2026-11-03'}),
      isFalse,
    );
    expect(
      hasAcceptedCurrentTerms(<String, dynamic>{'termsVersion': kTermsVersion}),
      isTrue,
    );
  });

  test('a ticket keeps the overtime rate posted when its price was fixed', () {
    final Map<String, dynamic> rates = <String, dynamic>{
      'car': <String, dynamic>{'initial': '40', 'succeedingHour': '30'},
    };
    expect(
      ticketOvertimeRate(
        <String, dynamic>{'purchaseOvertimeRate': 20},
        rates,
        'car',
      ),
      20,
    );
    // Older tickets and walk-ins have none kept: the current rate applies.
    expect(ticketOvertimeRate(<String, dynamic>{}, rates, 'car'), 30);
    expect(
      ticketOvertimeRate(
        <String, dynamic>{'purchaseOvertimeRate': 0},
        rates,
        'car',
      ),
      30,
    );
  });

  test('an owner repays a refund less the commission SmartPark gives back', () {
    final ParkingRefund charged = ParkingRefund.fromMap('t1', <String, dynamic>{
      'status': 'refunded',
      'paidBy': 'owner',
      'amountCentavos': 10000,
      'ownerOwedCentavos': 9500,
    });
    expect(charged.ownerShareCentavos, 9500);
    expect(charged.canDispute, isTrue);

    // Refunds from before the share was recorded count in full.
    final ParkingRefund old = ParkingRefund.fromMap('t2', <String, dynamic>{
      'paidBy': 'owner',
      'amountCentavos': 10000,
    });
    expect(old.ownerShareCentavos, 10000);

    final ParkingRefund platform = ParkingRefund.fromMap(
      't3',
      <String, dynamic>{'paidBy': 'platform', 'amountCentavos': 10000},
    );
    expect(platform.ownerShareCentavos, 0);
    expect(platform.canDispute, isFalse);
  });

  test('a refund charge can be disputed once', () {
    ParkingRefund withDispute(String status) =>
        ParkingRefund.fromMap('t1', <String, dynamic>{
          'paidBy': 'owner',
          'dispute': <String, dynamic>{
            'status': status,
            'message': 'The permit was valid.',
            'note': 'Checked the documents.',
          },
        });
    expect(withDispute('open').hasOpenDispute, isTrue);
    expect(withDispute('open').canDispute, isFalse);
    expect(withDispute('rejected').canDispute, isFalse);
    expect(withDispute('rejected').disputeNote, 'Checked the documents.');
    expect(withDispute('open').disputeMessage, 'The permit was valid.');
  });

  test('a lapsed permit is its own reason, charged to the owner', () {
    expect(kRestrictionReasons, contains(kPermitExpiredReason));
    expect(kAdminFaultReasons, isNot(contains(kPermitExpiredReason)));
    expect(kAdminFaultReasons, contains('Invalid business permit'));
  });

  test('a warning is contested, then kept or withdrawn', () {
    expect(warningContestStatus(<String, dynamic>{'message': 'x'}), '');
    expect(
      warningContestStatus(<String, dynamic>{'contestMessage': 'I paid.'}),
      'open',
    );
    expect(
      warningContestStatus(<String, dynamic>{
        'contestMessage': 'I paid.',
        'contestStatus': 'rejected',
      }),
      'rejected',
    );
  });

  test('facility reports start open and offer reasons with Other last', () {
    expect(facilityReportStatus(<String, dynamic>{}), kFacilityReportOpen);
    expect(
      facilityReportStatus(<String, dynamic>{'status': 'Resolved'}),
      kFacilityReportResolved,
    );
    expect(kFacilityReportReasons.last, 'Other');
    expect(kFacilityReportReasons, contains('Refused a valid ticket'));
  });
}
