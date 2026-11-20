import 'package:flutter_test/flutter_test.dart';
import 'package:smart_park/screens/staff/gate_pass_panel.dart';

void main() {
  test('staff see whether the driver still has to confirm', () {
    expect(
      gatePaymentStageText('confirm', 'gcash'),
      'Driver notified. Waiting for them to tap Confirm on their phone',
    );
    expect(
      gatePaymentStageText('approve', 'gcash'),
      'Driver is approving the payment in GCash',
    );
    expect(
      gatePaymentStageText('approve', 'card'),
      'Driver is approving the payment (their bank may send an OTP)',
    );
    expect(
      gatePaymentStageText('approve', 'qrph'),
      'Driver is approving the payment',
    );
    // An older server without stages.
    expect(
      gatePaymentStageText('', 'gcash'),
      'Waiting for the driver to pay on their phone',
    );
  });
}
