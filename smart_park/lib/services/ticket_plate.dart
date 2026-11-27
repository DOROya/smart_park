import 'package:cloud_firestore/cloud_firestore.dart';

import 'parking_pricing.dart';

/// A driver may move a ticket to another plate, e.g. to lend it to someone
/// with the same vehicle type. The vehicle type never changes; the ticket
/// keeps the plates it was on before (`plateHistory`), and each gate log the
/// plate it was scanned with, so it always shows which vehicles used it.

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

/// Most plate changes one ticket keeps a record of (security rules cap it).
const int kMaxPlateHistory = 30;

/// A plate a ticket was on before, and until when.
typedef PastPlate = ({String plate, DateTime? until});

/// The ticket's earlier plates, oldest first (`plateHistory`).
List<PastPlate> ticketPlateHistory(Map<String, dynamic> ticket) {
  final Object? raw = ticket['plateHistory'];
  if (raw is! List) return const <PastPlate>[];
  return <PastPlate>[
    for (final Object? e in raw)
      if (e is Map && e['plate'] is String && (e['plate'] as String).isNotEmpty)
        (
          plate: e['plate'] as String,
          until: e['until'] is Timestamp
              ? (e['until'] as Timestamp).toDate()
              : null,
        ),
  ];
}

/// "ABC123 (to Nov 18) → NEW 123 (now)": every plate the ticket was on,
/// oldest first; '' when it was never moved.
String plateHistoryLabel(Map<String, dynamic> ticket) {
  final List<PastPlate> past = ticketPlateHistory(ticket);
  if (past.isEmpty) return '';
  const List<String> months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final String current = ((ticket['vehiclePlate'] as String?) ?? '').trim();
  return <String>[
    for (final PastPlate p in past)
      p.until == null
          ? p.plate
          : '${p.plate} (to ${months[p.until!.month - 1]} ${p.until!.day})',
    if (current.isNotEmpty) '$current (now)',
  ].join(' → ');
}

/// Puts ticket [transactionId] on [plate], recording the plate it replaces
/// in `plateHistory`. Rules let only the ticket's own driver do it, and
/// only append to the history.
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
  final DocumentReference<Map<String, dynamic>> ref = db
      .collection('transactions')
      .doc(transactionId);
  return db.runTransaction<void>((Transaction tx) async {
    final Map<String, dynamic> ticket = (await tx.get(ref)).data() ?? {};
    final Object? raw = ticket['plateHistory'];
    final List<Object?> history = raw is List ? List<Object?>.of(raw) : [];
    if (history.length >= kMaxPlateHistory) {
      throw StateError("This ticket's plate was changed too many times.");
    }
    tx.update(ref, <String, dynamic>{
      'vehiclePlate': normalized,
      'updatedAt': FieldValue.serverTimestamp(),
      'plateHistory': <Object?>[
        ...history,
        <String, dynamic>{
          'plate': (ticket['vehiclePlate'] as String?) ?? '',
          'until': Timestamp.now(),
        },
      ],
    });
  });
}

/// The ways one plate may have been typed, for the gate's plate lookup: as
/// typed (older tickets kept their case), upper-cased, without spaces or
/// dashes, and with a space (or dash) between letters and digits.
/// "gaj789" -> gaj789, GAJ789, GAJ 789, GAJ-789. At most 5, so it fits a
/// Firestore `whereIn`.
List<String> plateLookupVariants(String raw) {
  final String typed = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (typed.isEmpty) return const <String>[];
  final String upper = typed.toUpperCase();
  final String bare = upper.replaceAll(RegExp(r'[\s-]'), '');
  final String split = bare.replaceAllMapped(
    RegExp(r'([A-Z])(?=\d)|(\d)(?=[A-Z])'),
    (Match m) => '${m[1] ?? ''}${m[2] ?? ''} ',
  );
  return <String>{
    typed,
    upper,
    bare,
    split,
    split.replaceAll(' ', '-'),
  }.toList();
}
