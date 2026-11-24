import 'parking_receipt.dart';
import 'parking_refunds.dart';
import '../widgets/smartpark_ui.dart' show spParseDateTime;

/// What a line in the driver's Transaction History is.
enum DriverTransactionKind { ticket, extraHours, overtime, refund }

/// One money movement on the driver's account: a payment out, or a refund
/// back in.
class DriverTransaction {
  const DriverTransaction({
    required this.kind,
    required this.facilityName,
    required this.amountCentavos,
    required this.at,
    required this.method,
    required this.detail,
    required this.ticketId,
  });

  final DriverTransactionKind kind;
  final String facilityName;

  /// Always positive; [isRefund] says which way it went.
  final int amountCentavos;
  final DateTime? at;

  /// "GCash", "Card", "Cash"...
  final String method;

  /// e.g. "Daily · ABC 1234", "3 hours added".
  final String detail;
  final String ticketId;

  bool get isRefund => kind == DriverTransactionKind.refund;

  String get title => switch (kind) {
    DriverTransactionKind.ticket => 'Parking ticket',
    DriverTransactionKind.extraHours => 'Extra hours',
    DriverTransactionKind.overtime => 'Overtime',
    DriverTransactionKind.refund => 'Refund',
  };
}

int _centavos(Object? pesos) => pesos is num ? (pesos * 100).round() : 0;

String _plan(Map<String, dynamic> t) {
  final String plan = ((t['plan'] as String?) ?? '').trim();
  return plan.isEmpty ? '' : '${plan[0].toUpperCase()}${plan.substring(1)}';
}

/// The driver's payments and refunds, newest first, from their tickets
/// (`transactions`), extra-hour purchases (`payments` with kind
/// "extra_hours") and refunds. Overtime is the cash paid at the exit of the
/// ticket's latest visit, the one the ticket records.
List<DriverTransaction> driverTransactions({
  required Map<String, Map<String, dynamic>> tickets,
  required Iterable<Map<String, dynamic>> payments,
  required Iterable<ParkingRefund> refunds,
}) {
  final List<DriverTransaction> out = <DriverTransaction>[];
  String facility(String ticketId, [Map<String, dynamic>? fallback]) {
    final String name =
        ((tickets[ticketId]?['establishmentName'] ??
                        fallback?['establishmentName'])
                    as String? ??
                '')
            .trim();
    return name.isEmpty ? 'Parking facility' : name;
  }

  tickets.forEach((String id, Map<String, dynamic> t) {
    if (((t['status'] as String?) ?? '').toLowerCase() != 'paid') return;
    final ParkingReceipt receipt = ParkingReceipt.fromTicket(id, t);
    final bool walkIn = t['source'] == 'walk_in';
    final String plate = ((t['vehiclePlate'] as String?) ?? '').trim();
    final int paid = _centavos(t['amount']);
    if (paid > 0) {
      out.add(
        DriverTransaction(
          kind: DriverTransactionKind.ticket,
          facilityName: facility(id),
          amountCentavos: paid,
          at:
              spParseDateTime(t['createdAt']) ??
              spParseDateTime(t['createdAtClient']),
          method: walkIn ? 'Cash' : receipt.paymentMethodLabel,
          detail: <String>[
            _plan(t),
            plate.toUpperCase(),
          ].where((String s) => s.isNotEmpty).join(' · '),
          ticketId: id,
        ),
      );
    }
    final int overtime = _centavos(t['overtimeAmount']);
    if (t['overtimeStatus'] == 'collected' && overtime > 0) {
      final int hours = ((t['overtimeHours'] as num?) ?? 0).toInt();
      out.add(
        DriverTransaction(
          kind: DriverTransactionKind.overtime,
          facilityName: facility(id),
          amountCentavos: overtime,
          at:
              spParseDateTime(t['overtimeCollectedAt']) ??
              spParseDateTime(t['exitAt']),
          method: 'Cash',
          detail: '$hours hour${hours == 1 ? '' : 's'} over, paid at the exit',
          ticketId: id,
        ),
      );
    }
  });

  for (final Map<String, dynamic> p in payments) {
    if (p['kind'] != 'extra_hours') continue;
    if (((p['status'] as String?) ?? 'paid') != 'paid') continue;
    final String ticketId = ((p['ticketId'] as String?) ?? '').trim();
    final int hours = ((p['hours'] as num?) ?? 0).toInt();
    out.add(
      DriverTransaction(
        kind: DriverTransactionKind.extraHours,
        facilityName: facility(ticketId),
        amountCentavos: _centavos(p['amount']),
        at: spParseDateTime(p['createdAt']),
        method: ParkingReceipt.fromTicket(ticketId, <String, dynamic>{
          'paymentMethod': p['paymentMethod'],
        }).paymentMethodLabel,
        detail: '$hours hour${hours == 1 ? '' : 's'} added to the ticket',
        ticketId: ticketId,
      ),
    );
  }

  for (final ParkingRefund r in refunds) {
    if (!r.isPaidOut || r.amountCentavos <= 0) continue;
    out.add(
      DriverTransaction(
        kind: DriverTransactionKind.refund,
        facilityName: facility(r.ticketId),
        amountCentavos: r.amountCentavos,
        at: r.refundedAt ?? r.createdAt,
        method: 'To the account you paid with',
        detail: r.status == 'sent'
            ? 'Sent, waiting for PayMongo to confirm'
            : 'For unused hours',
        ticketId: r.ticketId,
      ),
    );
  }

  final DateTime epoch = DateTime.fromMillisecondsSinceEpoch(0);
  out.sort(
    (DriverTransaction a, DriverTransaction b) =>
        (b.at ?? epoch).compareTo(a.at ?? epoch),
  );
  return out;
}
