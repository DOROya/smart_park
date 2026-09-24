/// SmartPark's platform commission, taken from the gross of every
/// transaction. The checkout Cloud Function (functions/src/pricing.js), the
/// owner's commission view and admin reporting must all use this rate so
/// their numbers agree.
const double kPlatformFeeRate = 0.05;

/// Platform fee for a gross amount, rounded the same way checkout records it.
int platformFeeCentavosFor(int grossAmountCentavos) =>
    (grossAmountCentavos * kPlatformFeeRate).round();

/// Rough processor-fee estimate per payment method, used only for
/// reconciliation/display - PayMongo's actual settlement report is the
/// source of truth for the real deducted amount.
int estimateProcessorFeeCentavos({
  required int grossAmountCentavos,
  required String paymentMethodApiType,
}) {
  final double rate = switch (paymentMethodApiType) {
    'card' => 0.035, // ~3.5% + fixed fee (fixed fee omitted from estimate)
    'gcash' || 'paymaya' => 0.02, // ~2.0% for e-wallets
    'qrph' => 0.0134, // ~1.34% for QR Ph
    _ => 0.02,
  };
  return (grossAmountCentavos * rate).round();
}
