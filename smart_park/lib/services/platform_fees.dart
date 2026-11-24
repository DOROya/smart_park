import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// SmartPark's original platform commission. Sales are now priced at the
/// rate in `settings/platform` (functions/src/commission.js), and each sale
/// saves its rate (`commissionRate`); sales from before that were all 5%,
/// so this stays the fallback for them.
const double kPlatformFeeRate = 0.05;

/// Platform fee for a gross amount, rounded the same way checkout records it.
/// [rate] is the sale's saved commission; older sales were 5%.
int platformFeeCentavosFor(int grossAmountCentavos, {double? rate}) =>
    (grossAmountCentavos * (rate ?? kPlatformFeeRate)).round();

/// The commission a stored sale (ticket, split) was priced at.
double saleCommissionRate(Map<String, dynamic>? sale) {
  final Object? rate = sale?['commissionRate'];
  return rate is num && rate > 0 && rate < 1
      ? rate.toDouble()
      : kPlatformFeeRate;
}

/// "5%" or "7.5%".
String commissionPercent(double rate) {
  final double p = (rate * 1000).round() / 10;
  return '${p == p.roundToDouble() ? p.toInt() : p.toStringAsFixed(1)}%';
}

/// `settings/platform`: the rate now and at most one scheduled change.
class PlatformCommissionSettings {
  const PlatformCommissionSettings({
    required this.currentRate,
    this.pendingRate,
    this.pendingEffectiveAt,
    this.pendingAnnouncementId = '',
  });

  /// The rate in force at [now] (a pending one counts from its date, as the
  /// server prices it), from the document's [data].
  factory PlatformCommissionSettings.of(
    Map<String, dynamic>? data, {
    DateTime? now,
  }) {
    double? valid(Object? v) =>
        v is num && v >= 0.01 && v <= 0.15 ? v.toDouble() : null;
    final double? pending = valid(data?['pendingRate']);
    final Object? at = data?['pendingEffectiveAt'];
    final DateTime? effective = at is Timestamp ? at.toDate() : null;
    final double base = valid(data?['commissionRate']) ?? kPlatformFeeRate;
    final bool inForce =
        pending != null &&
        effective != null &&
        !(now ?? DateTime.now()).isBefore(effective);
    return PlatformCommissionSettings(
      currentRate: inForce ? pending : base,
      pendingRate: inForce ? null : pending,
      pendingEffectiveAt: inForce ? null : effective,
      pendingAnnouncementId: inForce
          ? ''
          : ((data?['pendingAnnouncementId'] as String?) ?? ''),
    );
  }

  final double currentRate;
  final double? pendingRate;
  final DateTime? pendingEffectiveAt;
  final String pendingAnnouncementId;

  bool get hasPending => pendingRate != null && pendingEffectiveAt != null;
}

/// The commission now, kept live once [watchPlatformCommission] starts
/// (after sign-in: the settings are for signed-in users). Starts at 5%.
final ValueNotifier<PlatformCommissionSettings> platformCommission =
    ValueNotifier<PlatformCommissionSettings>(
      const PlatformCommissionSettings(currentRate: kPlatformFeeRate),
    );

StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _commissionSub;

/// Keeps [platformCommission] in step with `settings/platform`. Called on
/// each sign-in; a listener from an earlier session is replaced.
void watchPlatformCommission({FirebaseFirestore? firestore}) {
  unawaited(_commissionSub?.cancel());
  _commissionSub = (firestore ?? FirebaseFirestore.instance)
      .collection('settings')
      .doc('platform')
      .snapshots()
      .listen(
        (DocumentSnapshot<Map<String, dynamic>> snap) =>
            platformCommission.value = PlatformCommissionSettings.of(
              snap.data(),
            ),
        onError: (Object _) {},
      );
}

/// Stops watching, on sign-out.
Future<void> stopWatchingPlatformCommission() async {
  await _commissionSub?.cancel();
  _commissionSub = null;
}

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
