import 'package:cloud_functions/cloud_functions.dart';

/// A PayMongo checkout opened by the `createParkingCheckout` Cloud Function.
class ParkingCheckout {
  const ParkingCheckout({
    required this.checkoutId,
    required this.checkoutUrl,
    required this.amount,
    required this.establishmentName,
  });

  final String checkoutId;
  final String checkoutUrl;
  final double amount;
  final String establishmentName;
}

/// Result of asking the server whether a checkout has been paid.
class ParkingCheckoutStatus {
  const ParkingCheckoutStatus({
    required this.status,
    required this.transactionId,
    this.qrCode,
    required this.amount,
    required this.establishmentName,
  });

  /// `pending`, `paid` or `expired`.
  final String status;
  final String transactionId;

  /// Ticket QR payload; set once [isPaid].
  final String? qrCode;
  final double amount;
  final String establishmentName;

  bool get isPaid => status == 'paid';
}

/// Talks to the checkout Cloud Functions. The PayMongo secret key and the
/// price calculation live on the server; the app only picks what to buy.
class ParkingCheckoutService {
  ParkingCheckoutService({FirebaseFunctions? functions})
    : _functions =
          functions ?? FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  final FirebaseFunctions _functions;

  Future<ParkingCheckout> createCheckout({
    required String establishmentId,
    required String vehicleType,
    required String plateNumber,
    required String plan,
    required int duration,
    required String paymentMethod,
  }) async {
    final HttpsCallableResult<dynamic> result = await _functions
        .httpsCallable('createParkingCheckout')
        .call(<String, dynamic>{
          'establishmentId': establishmentId,
          'vehicleType': vehicleType,
          'plateNumber': plateNumber,
          'plan': plan,
          'duration': duration,
          'paymentMethod': paymentMethod,
        });
    final Map<String, dynamic> data = _asMap(result.data);
    return ParkingCheckout(
      checkoutId: data['checkoutId'] as String,
      checkoutUrl: data['checkoutUrl'] as String,
      amount: (data['amount'] as num).toDouble(),
      establishmentName: (data['establishmentName'] as String?) ?? '',
    );
  }

  /// Asks the server to check PayMongo; the server records the ticket and
  /// payment when it is paid.
  Future<ParkingCheckoutStatus> confirmCheckout(String checkoutId) async {
    final HttpsCallableResult<dynamic> result = await _functions
        .httpsCallable('confirmParkingCheckout')
        .call(<String, dynamic>{'checkoutId': checkoutId});
    final Map<String, dynamic> data = _asMap(result.data);
    return ParkingCheckoutStatus(
      status: (data['status'] as String?) ?? 'pending',
      transactionId: (data['transactionId'] as String?) ?? '',
      qrCode: data['qrCode'] as String?,
      amount: ((data['amount'] as num?) ?? 0).toDouble(),
      establishmentName: (data['establishmentName'] as String?) ?? '',
    );
  }

  /// Polls [confirmCheckout] until paid or [maxAttempts] run out.
  Future<ParkingCheckoutStatus> pollUntilPaid(
    String checkoutId, {
    Duration interval = const Duration(milliseconds: 1500),
    int maxAttempts = 6,
  }) async {
    ParkingCheckoutStatus status = await confirmCheckout(checkoutId);
    for (int i = 0; i < maxAttempts && !status.isPaid; i++) {
      await Future<void>.delayed(interval);
      try {
        status = await confirmCheckout(checkoutId);
      } on FirebaseFunctionsException {
        // Transient; keep polling.
      }
    }
    return status;
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map) {
      return value.map<String, dynamic>(
        (dynamic k, dynamic v) => MapEntry<String, dynamic>(k.toString(), v),
      );
    }
    return <String, dynamic>{};
  }
}
