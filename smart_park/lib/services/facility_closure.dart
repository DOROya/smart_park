import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../widgets/smartpark_ui.dart' show spFormatDate, spFormatClockTime;
import 'operating_hours.dart';

/// Longest a facility may close temporarily at once (the rules allow the
/// same).
const int kMaxClosureDays = 30;

/// Longest closure reason, in characters.
const int kMaxClosureReasonLength = 120;

/// A facility closed for a while on top of its weekly hours, from
/// `establishment_details`: `closedAt` (when it was set), `closedUntil` and
/// an optional `closedReason`. Tickets and temporary QRs stay valid; the
/// gate admits no one until it reopens, by itself, at [until].
class TemporaryClosure {
  const TemporaryClosure({required this.until, this.from, this.reason = ''});

  final DateTime? from;
  final DateTime until;
  final String reason;

  /// The closure on [details] that hasn't ended by [now], or null.
  static TemporaryClosure? of(Map<String, dynamic>? details, {DateTime? now}) {
    final Object? until = details?['closedUntil'];
    if (until is! Timestamp) return null;
    final DateTime end = until.toDate();
    if (!end.isAfter(now ?? DateTime.now())) return null;
    final Object? from = details?['closedAt'];
    return TemporaryClosure(
      until: end,
      from: from is Timestamp ? from.toDate() : null,
      reason: ((details?['closedReason'] as String?) ?? '').trim(),
    );
  }

  /// Closed right now (it may be set to start later only by its [from]).
  bool isActiveAt(DateTime now) =>
      now.isBefore(until) && (from == null || !now.isBefore(from!));
}

/// "Nov 25, 3:00 PM", for the gate and the driver's screens.
String temporaryClosureUntilLabel(TemporaryClosure closure) =>
    '${spFormatDate(closure.until)}, ${spFormatClockTime(closure.until)}';

/// [hours] with the closure on [details], if any, so overtime and the
/// open-now check leave the closed time out.
OperatingHours hoursWithClosure(
  OperatingHours hours,
  Map<String, dynamic>? details,
) {
  final Object? until = details?['closedUntil'];
  if (until is! Timestamp) return hours;
  final Object? from = details?['closedAt'];
  return hours.withClosure(
    from is Timestamp ? from.toDate() : null,
    until.toDate(),
  );
}

/// Why a closure can't be set, or null: it must end in the future and
/// within [kMaxClosureDays].
String? closureDenial(DateTime until, String reason, {DateTime? now}) {
  final DateTime at = now ?? DateTime.now();
  if (!until.isAfter(at)) return 'Pick a time in the future.';
  if (until.isAfter(at.add(const Duration(days: kMaxClosureDays)))) {
    return 'A temporary closure can last at most $kMaxClosureDays days.';
  }
  if (reason.trim().length > kMaxClosureReasonLength) {
    return 'Keep the reason under $kMaxClosureReasonLength characters.';
  }
  return null;
}

/// Closes [facilityId] until [until] (the owner or its supervisor).
Future<void> setTemporaryClosure(
  String facilityId, {
  required DateTime until,
  String reason = '',
  FirebaseFirestore? firestore,
}) {
  final FirebaseFirestore db = firestore ?? FirebaseFirestore.instance;
  return db
      .collection('establishment_details')
      .doc(facilityId)
      .update(<String, dynamic>{
        'closedUntil': Timestamp.fromDate(until),
        'closedReason': reason.trim(),
        'closedAt': FieldValue.serverTimestamp(),
        'closedBy': ?FirebaseAuth.instance.currentUser?.uid,
        'updatedAt': FieldValue.serverTimestamp(),
      });
}

/// Reopens [facilityId] now.
Future<void> clearTemporaryClosure(
  String facilityId, {
  FirebaseFirestore? firestore,
}) {
  final FirebaseFirestore db = firestore ?? FirebaseFirestore.instance;
  return db
      .collection('establishment_details')
      .doc(facilityId)
      .update(<String, dynamic>{
        'closedUntil': null,
        'closedReason': FieldValue.delete(),
        'closedAt': FieldValue.delete(),
        'closedBy': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
}
