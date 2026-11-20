import 'package:cloud_functions/cloud_functions.dart';

import 'saved_payment.dart';

export 'saved_payment.dart' show SavedPaymentDetails;

/// A temporary QR made by the `createParkingPass` Cloud Function: the
/// package is picked and priced, but it is paid only at the gate.
class ParkingPass {
  const ParkingPass({
    required this.checkoutId,
    required this.qrCode,
    required this.amount,
    required this.establishmentName,
    required this.expiresAt,
  });

  final String checkoutId;
  final String qrCode;
  final double amount;
  final String establishmentName;
  final DateTime expiresAt;
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

/// Talks to the driver's checkout Cloud Functions. The PayMongo secret key and the
/// price calculation live on the server; the app only picks what to buy.
class ParkingCheckoutService {
  ParkingCheckoutService({FirebaseFunctions? functions})
    : _functions =
          functions ?? FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  final FirebaseFunctions _functions;

  /// Makes a temporary QR. Nothing is charged until the driver confirms at
  /// the gate; [saved] holds the details they confirm with.
  Future<ParkingPass> createPass({
    required String establishmentId,
    required String vehicleType,
    required String plateNumber,
    required String plan,
    required int duration,
    required String paymentMethod,
    SavedPaymentDetails saved = SavedPaymentDetails.none,
  }) async {
    final HttpsCallableResult<dynamic> result = await _functions
        .httpsCallable('createParkingPass')
        .call(<String, dynamic>{
          'establishmentId': establishmentId,
          'vehicleType': vehicleType,
          'plateNumber': plateNumber,
          'plan': plan,
          'duration': duration,
          'paymentMethod': paymentMethod,
          if (saved.phone.isNotEmpty) 'payerPhone': saved.phone,
          if (saved.cardPaymentMethodId.isNotEmpty)
            'cardPaymentMethodId': saved.cardPaymentMethodId,
        });
    final Map<String, dynamic> data = _asMap(result.data);
    return ParkingPass(
      checkoutId: data['checkoutId'] as String,
      qrCode: data['qrCode'] as String,
      amount: (data['amount'] as num).toDouble(),
      establishmentName: (data['establishmentName'] as String?) ?? '',
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        (data['expiresAt'] as num).toInt(),
      ),
    );
  }

  /// The driver's Confirm tap at the gate: pays with the saved details.
  /// The server stores the wallet's (or bank's) approval page on the QR's
  /// `paymongo.checkoutUrl`, which is also returned ('' when paid already or
  /// still processing).
  Future<String> confirmGatePayment(String checkoutId) async {
    final HttpsCallableResult<dynamic> result = await _functions
        .httpsCallable('payGatePass')
        .call(<String, dynamic>{'checkoutId': checkoutId});
    return (_asMap(result.data)['redirectUrl'] as String?) ?? '';
  }

  /// Buys [hours] more on paid ticket [ticketId] and opens the payment.
  /// `redirectUrl` is the wallet's approval page (or PayMongo's checkout
  /// page) to open; '' when it is already paid or still processing.
  Future<({String checkoutId, String status, String redirectUrl})> addHours({
    required String ticketId,
    required int hours,
  }) async {
    final HttpsCallableResult<dynamic> result = await _functions
        .httpsCallable('addTicketHours')
        .call(<String, dynamic>{'ticketId': ticketId, 'hours': hours});
    final Map<String, dynamic> data = _asMap(result.data);
    return (
      checkoutId: (data['checkoutId'] as String?) ?? '',
      status: (data['status'] as String?) ?? '',
      redirectUrl: (data['redirectUrl'] as String?) ?? '',
    );
  }

  /// Cancels a temporary QR that hasn't been paid.
  Future<void> cancelPass(String checkoutId) async {
    await _functions.httpsCallable('cancelParkingPass').call(<String, dynamic>{
      'checkoutId': checkoutId,
    });
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

/// A temporary QR as staff see it at the gate.
class GatePass {
  const GatePass({
    required this.checkoutId,
    required this.status,
    required this.plate,
    required this.vehicleType,
    required this.plan,
    required this.duration,
    required this.amount,
    required this.paymentMethod,
    this.directPay = false,
    this.expiresAt,
  });

  factory GatePass.fromMap(Map<String, dynamic> m) => GatePass(
    directPay: m['directPay'] == true,
    checkoutId: (m['checkoutId'] as String?) ?? '',
    status: (m['status'] as String?) ?? '',
    plate: (m['plate'] as String?) ?? '',
    vehicleType: (m['vehicleType'] as String?) ?? '',
    plan: (m['plan'] as String?) ?? '',
    duration: ((m['duration'] as num?) ?? 0).toInt(),
    amount: ((m['amount'] as num?) ?? 0).toDouble(),
    paymentMethod: (m['paymentMethod'] as String?) ?? '',
    expiresAt: m['expiresAt'] is num
        ? DateTime.fromMillisecondsSinceEpoch((m['expiresAt'] as num).toInt())
        : null,
  );

  final String checkoutId;

  /// `awaiting_gate`, `pending` (paying now), `paid`, `cancelled` or
  /// `expired`.
  final String status;
  final String plate;
  final String vehicleType;
  final String plan;
  final int duration;
  final double amount;
  final String paymentMethod;

  /// The driver saved their payment details, so they only confirm.
  final bool directPay;
  final DateTime? expiresAt;

  /// Staff can take payment on it (or it is already being paid).
  bool get usable => status == 'awaiting_gate' || status == 'pending';
}

/// Staff side of temporary QRs: find one, take payment, stop a payment.
class GatePassService {
  GatePassService({FirebaseFunctions? functions})
    : _functions =
          functions ?? FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  final FirebaseFunctions _functions;

  /// The facility's temporary QR with this id, or the newest usable one for
  /// [plate]; null when there is none.
  Future<GatePass?> find({String? checkoutId, String? plate}) async {
    final HttpsCallableResult<dynamic> result = await _functions
        .httpsCallable('findGatePass')
        .call(<String, dynamic>{'checkoutId': ?checkoutId, 'plate': ?plate});
    final Map<String, dynamic> data = ParkingCheckoutService._asMap(
      result.data,
    );
    return data['found'] == true ? GatePass.fromMap(data) : null;
  }

  /// Opens the payment on the driver's phone.
  Future<void> startPayment(String checkoutId) async {
    await _functions.httpsCallable('startGatePayment').call(<String, dynamic>{
      'checkoutId': checkoutId,
    });
  }

  /// `status`: `pending`, `paid`, `timed_out` or the pass's other status.
  /// While pending, `stage` is `confirm` (the driver hasn't tapped Confirm
  /// yet) or `approve` (the payment is open on their phone).
  Future<({String status, String stage})> checkPayment(
    String checkoutId,
  ) async {
    final HttpsCallableResult<dynamic> result = await _functions
        .httpsCallable('checkGatePayment')
        .call(<String, dynamic>{'checkoutId': checkoutId});
    final Map<String, dynamic> data = ParkingCheckoutService._asMap(
      result.data,
    );
    return (
      status: (data['status'] as String?) ?? '',
      stage: (data['stage'] as String?) ?? '',
    );
  }

  /// Stops an unfinished payment. Returns `paid` if it went through first.
  Future<String> cancelPayment(String checkoutId) =>
      _call('cancelGatePayment', checkoutId);

  Future<String> _call(String name, String checkoutId) async {
    final HttpsCallableResult<dynamic> result = await _functions
        .httpsCallable(name)
        .call(<String, dynamic>{'checkoutId': checkoutId});
    return (ParkingCheckoutService._asMap(result.data)['status'] as String?) ??
        '';
  }
}
