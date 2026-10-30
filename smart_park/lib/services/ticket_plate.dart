import 'package:cloud_firestore/cloud_firestore.dart';

import 'parking_pricing.dart';

/// A driver may move a ticket to another plate, e.g. to lend it to someone
/// with the same vehicle type. The vehicle type never changes, and each gate
/// log keeps the plate it was scanned with, so past visits still show which
/// vehicle used the ticket.

const int kMaxPlateLength = 20;

/// The plate as checkout stores it (trimmed, upper-cased), which is what the
/// gate's plate lookup matches.
String normalizePlate(String raw) => raw.trim().toUpperCase();

/// Paid, with hours left, and not parked: security rules refuse a plate
/// change on a ticket that is checked in.
bool canChangeTicketPlate(Map<String, dynamic> ticket) {
  final String status = ((ticket['status'] as String?) ?? '').toLowerCase();
  final String entry = ((ticket['entryStatus'] as String?) ?? '').toLowerCase();
  return status == 'paid' &&
      entry != 'checked_in' &&
      entry != 'inside' &&
      ticketHoursLeft(ticket) > 0;
}

/// Puts ticket [transactionId] on [plate]. Only `vehiclePlate` and
/// `updatedAt` change; rules let only the ticket's own driver do it.
Future<void> changeTicketPlate({
  required String transactionId,
  required String plate,
  FirebaseFirestore? firestore,
}) {
  final String normalized = normalizePlate(plate);
  if (normalized.isEmpty || normalized.length > kMaxPlateLength) {
    throw ArgumentError.value(plate, 'plate', 'Enter a valid plate number.');
  }
  final FirebaseFirestore db = firestore ?? FirebaseFirestore.instance;
  return db.collection('transactions').doc(transactionId).update(
    <String, dynamic>{
      'vehiclePlate': normalized,
      'updatedAt': FieldValue.serverTimestamp(),
    },
  );
}
