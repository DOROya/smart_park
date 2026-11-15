import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'parking_pricing.dart';

/// Days a facility can stay suspended before its tickets are refunded
/// automatically (matches SUSPENSION_REFUND_DAYS in functions/src/refunds.js).
const int kSuspensionRefundDays = 14;

/// Restriction reasons that mean SmartPark approved bad documents, so
/// SmartPark covers the refunds (matches ADMIN_FAULT_REASONS on the server).
const List<String> kAdminFaultReasons = <String>[
  'Invalid business permit',
  'Incomplete or false documents',
];

/// A refund for a ticket at a facility SmartPark pulled
/// (`refunds/{ticketId}`, written only by the server).
class ParkingRefund {
  const ParkingRefund({
    required this.ticketId,
    required this.status,
    required this.cause,
    required this.paidBy,
    required this.amountCentavos,
    required this.unusedHours,
    required this.establishmentName,
    required this.vehiclePlate,
    this.driverId = '',
    this.ownerId = '',
    this.failureReason = '',
    this.decisionNote = '',
    this.ownerOwedCentavos,
    this.disputeStatus = '',
    this.disputeMessage = '',
    this.disputeNote = '',
    this.reasons = const <String>[],
    this.createdAt,
    this.refundedAt,
  });

  factory ParkingRefund.fromMap(String id, Map<String, dynamic> m) {
    String text(String key) => ((m[key] as String?) ?? '').trim();
    DateTime? date(String key) {
      final Object? v = m[key];
      return v is Timestamp ? v.toDate() : null;
    }

    final Object? rawDispute = m['dispute'];
    String dispute(String key) =>
        rawDispute is Map ? ((rawDispute[key] as String?) ?? '').trim() : '';

    return ParkingRefund(
      ticketId: id,
      status: text('status'),
      cause: text('cause'),
      paidBy: text('paidBy'),
      amountCentavos: ((m['amountCentavos'] as num?) ?? 0).toInt(),
      unusedHours: ((m['unusedHours'] as num?) ?? 0).toInt(),
      establishmentName: text('establishmentName'),
      vehiclePlate: text('vehiclePlate'),
      driverId: text('driverId'),
      ownerId: text('ownerId'),
      failureReason: text('failureReason'),
      decisionNote: text('decisionNote'),
      ownerOwedCentavos: (m['ownerOwedCentavos'] as num?)?.toInt(),
      disputeStatus: dispute('status'),
      disputeMessage: dispute('message'),
      disputeNote: dispute('note'),
      reasons: ((m['restrictionReasons'] as List<dynamic>?) ?? <dynamic>[])
          .whereType<String>()
          .toList(),
      createdAt: date('createdAt'),
      refundedAt: date('refundedAt'),
    );
  }

  final String ticketId;

  /// requested, approved, processing, awaiting_exit, refunded, failed or
  /// rejected.
  final String status;

  /// deactivated, suspended_14_days or driver_request.
  final String cause;

  /// platform (SmartPark) or owner.
  final String paidBy;
  final int amountCentavos;
  final int unusedHours;
  final String establishmentName;
  final String vehiclePlate;
  final String driverId;
  final String ownerId;
  final String failureReason;
  final String decisionNote;

  /// What the owner repays for this refund once sent: the refund less
  /// SmartPark's commission on it. Null on refunds from before that was
  /// recorded, where the owner repaid the whole amount.
  final int? ownerOwedCentavos;

  /// The owner's dispute of the charge: '' (none), open, upheld or rejected.
  final String disputeStatus;
  final String disputeMessage;

  /// The admin's reason when a dispute was turned down.
  final String disputeNote;
  final List<String> reasons;
  final DateTime? createdAt;
  final DateTime? refundedAt;

  bool get isRefunded => status == 'refunded';
  bool get isPendingApproval => status == 'requested';
  bool get isFailed => status == 'failed';
  bool get isRejected => status == 'rejected';
  bool get paidByOwner => paidBy == 'owner';
  bool get hasOpenDispute => disputeStatus == 'open';

  /// An owner may dispute a refund charged to them, once.
  bool get canDispute => paidByOwner && disputeStatus.isEmpty;

  /// The owner's part of this refund; the rest is SmartPark's.
  int get ownerShareCentavos =>
      paidByOwner ? (ownerOwedCentavos ?? amountCentavos) : 0;

  String get statusLabel => switch (status) {
    'requested' => 'Awaiting approval',
    'approved' || 'processing' => 'Processing',
    'awaiting_exit' => 'After you exit',
    'refunded' => 'Refunded',
    'failed' => 'Failed',
    'rejected' => 'Rejected',
    _ => status,
  };

  String get causeLabel => switch (cause) {
    'deactivated' => 'Facility deactivated',
    'suspended_14_days' => 'Suspended $kSuspensionRefundDays days',
    'driver_request' => 'Requested by driver',
    _ => cause,
  };

  String get paidByLabel => paidByOwner ? 'Owner' : 'SmartPark';
}

/// The unused share of what a ticket cost, in centavos; mirrors
/// refundCentavos in functions/src/refunds.js.
int estimatedRefundCentavos(Map<String, dynamic> ticket) {
  final int total = includedStayHours(
    plan: ((ticket['plan'] as String?) ?? 'base').trim().toLowerCase(),
    duration: ticketDuration(ticket),
  );
  final int paid = (((ticket['amount'] as num?) ?? 0) * 100).round();
  final int unused = ticketHoursLeft(ticket);
  if (total <= 0 || unused <= 0 || paid <= 0) return 0;
  return (paid * (unused < total ? unused : total)) ~/ total;
}

/// When a suspension started at [suspendedAt] refunds automatically.
DateTime? suspensionRefundDate(Object? suspendedAt) => suspendedAt is Timestamp
    ? suspendedAt.toDate().add(const Duration(days: kSuspensionRefundDays))
    : null;

/// Refunds keyed by ticket id from a query snapshot.
Map<String, ParkingRefund> refundsByTicket(
  QuerySnapshot<Map<String, dynamic>>? snap,
) => <String, ParkingRefund>{
  for (final QueryDocumentSnapshot<Map<String, dynamic>> d
      in snap?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[])
    d.id: ParkingRefund.fromMap(d.id, d.data()),
};

/// Talks to the refund Cloud Functions.
class ParkingRefundService {
  ParkingRefundService({FirebaseFunctions? functions})
    : _functions =
          functions ?? FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  final FirebaseFunctions _functions;

  /// Driver: asks for a refund while the facility is suspended.
  Future<void> request(String ticketId) async {
    await _functions.httpsCallable('requestRefund').call(<String, dynamic>{
      'ticketId': ticketId,
    });
  }

  /// Admin: approves (and sends) or rejects a request; also retries a failed
  /// refund when approving. Returns the refund's new status.
  Future<String> decide(
    String ticketId, {
    required bool approve,
    String note = '',
  }) async {
    final HttpsCallableResult<dynamic> result = await _functions
        .httpsCallable('decideRefund')
        .call(<String, dynamic>{
          'ticketId': ticketId,
          'approve': approve,
          'note': note,
        });
    final Object? data = result.data;
    return data is Map ? ((data['status'] as String?) ?? '') : '';
  }

  /// Owner: says a refund should not be charged to them, and why.
  Future<void> dispute(String ticketId, String message) async {
    await _functions.httpsCallable('disputeRefundCharge').call(
      <String, dynamic>{'ticketId': ticketId, 'message': message},
    );
  }

  /// Admin: upholds a dispute (SmartPark takes over the charge) or turns it
  /// down with a [note] the owner sees.
  Future<void> resolveDispute(
    String ticketId, {
    required bool uphold,
    String note = '',
  }) async {
    await _functions.httpsCallable('resolveRefundDispute').call(
      <String, dynamic>{'ticketId': ticketId, 'uphold': uphold, 'note': note},
    );
  }

  /// Admin: records money an owner paid SmartPark directly toward their
  /// refund balance.
  Future<void> recordRepayment(String ownerId, int amountCentavos) async {
    await _functions.httpsCallable('recordOwnerRepayment').call(
      <String, dynamic>{'ownerId': ownerId, 'amountCentavos': amountCentavos},
    );
  }
}
