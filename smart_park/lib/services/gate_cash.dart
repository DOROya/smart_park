import 'package:cloud_firestore/cloud_firestore.dart';

import 'gate_scan_service.dart' show kOvertimeCollected, overtimeStatusOf;

/// Cash staff take at the gate and hand to the owner: overtime marked
/// collected on an exit, and walk-in parking fees (`walkInFee` on a walk-in
/// exit log). When the owner receives it, a `cash_handovers` record is
/// made and every gate log it covers is stamped with its id, once, so no
/// peso is counted twice. Security rules enforce both.

/// Most gate logs one handover covers (a Firestore batch is at most 500
/// writes); anything beyond waits for the next handover.
const int kMaxHandoverLogs = 400;

/// Highest walk-in fee staff can record, in pesos (rules allow the same).
const double kMaxWalkInFee = 100000;

/// Overtime cash on [log] that its collector holds.
double overtimeCashOf(Map<String, dynamic> log) =>
    overtimeStatusOf(log) == kOvertimeCollected
    ? ((log['overtimeAmount'] as num?) ?? 0).toDouble()
    : 0;

/// The walk-in fee taken at this exit.
double walkInFeeOf(Map<String, dynamic> log) =>
    log['source'] == 'walk_in' && log['scanType'] == 'exit'
    ? ((log['walkInFee'] as num?) ?? 0).toDouble()
    : 0;

/// Who holds [log]'s cash: whoever marked the overtime collected, or the
/// staff member who let the walk-in out.
String cashHolderOf(Map<String, dynamic> log) {
  if (overtimeCashOf(log) > 0) {
    return ((log['overtimeCollectedBy'] as String?) ??
            (log['staffId'] as String?) ??
            '')
        .trim();
  }
  return ((log['staffId'] as String?) ?? '').trim();
}

/// Gate cash not handed to the owner yet.
bool awaitsHandover(Map<String, dynamic> log) =>
    (overtimeCashOf(log) > 0 || walkInFeeOf(log) > 0) &&
    ((log['cashHandoverId'] as String?) ?? '').isEmpty;

/// One staff member's cash still to hand over.
class StaffCashDue {
  StaffCashDue(this.staffId);

  final String staffId;
  double overtime = 0;
  double walkIn = 0;
  final List<String> logIds = <String>[];

  /// The staff member's name, from the newest log that carried one.
  String staffName = '';

  /// When they first took cash that is still with them.
  DateTime? since;

  double get total => overtime + walkIn;
}

/// The cash each staff member still holds, from the facility's gate logs
/// (any logs; the ones already handed over are skipped). Biggest first.
List<StaffCashDue> cashDueByStaff(
  Iterable<({String id, Map<String, dynamic> data})> logs,
) {
  final Map<String, StaffCashDue> byStaff = <String, StaffCashDue>{};
  final Set<String> seen = <String>{};
  for (final ({String id, Map<String, dynamic> data}) log in logs) {
    if (!seen.add(log.id) || !awaitsHandover(log.data)) continue;
    final String holder = cashHolderOf(log.data);
    if (holder.isEmpty) continue;
    final StaffCashDue due = byStaff.putIfAbsent(
      holder,
      () => StaffCashDue(holder),
    );
    due.overtime += overtimeCashOf(log.data);
    due.walkIn += walkInFeeOf(log.data);
    due.logIds.add(log.id);
    final String name = ((log.data['staffName'] as String?) ?? '').trim();
    if (due.staffName.isEmpty && holder == log.data['staffId']) {
      due.staffName = name;
    }
    final Object? at = log.data['timestamp'];
    if (at is Timestamp) {
      final DateTime t = at.toDate();
      if (due.since == null || t.isBefore(due.since!)) due.since = t;
    }
  }
  return byStaff.values.toList()
    ..sort((StaffCashDue a, StaffCashDue b) => b.total.compareTo(a.total));
}

/// Gate logs that may hold cash at [facilityId]: overtime collected, and
/// walk-in exits with a fee. Filter with [awaitsHandover].
List<Query<Map<String, dynamic>>> gateCashQueries(
  String facilityId, {
  FirebaseFirestore? firestore,
}) {
  final CollectionReference<Map<String, dynamic>> logs =
      (firestore ?? FirebaseFirestore.instance).collection('activity_logs');
  return <Query<Map<String, dynamic>>>[
    logs
        .where('establishmentID', isEqualTo: facilityId)
        .where('overtimeStatus', isEqualTo: kOvertimeCollected),
    logs
        .where('establishmentID', isEqualTo: facilityId)
        .where('walkInFee', isGreaterThan: 0),
  ];
}

/// The owner (or a supervisor, [receivedBy]) received [due] from a staff
/// member: records the handover and stamps the gate logs it covers (up to
/// [kMaxHandoverLogs]). Returns the handover's id.
Future<String> recordCashHandover({
  required String facilityId,
  required String ownerId,
  String? receivedBy,
  required StaffCashDue due,
  required String staffName,
  required Map<String, Map<String, dynamic>> logsById,
  String note = '',
  FirebaseFirestore? firestore,
}) async {
  final FirebaseFirestore db = firestore ?? FirebaseFirestore.instance;
  final List<String> ids = due.logIds.take(kMaxHandoverLogs).toList();
  double overtime = 0;
  double walkIn = 0;
  for (final String id in ids) {
    final Map<String, dynamic> log = logsById[id] ?? const <String, dynamic>{};
    overtime += overtimeCashOf(log);
    walkIn += walkInFeeOf(log);
  }
  final DocumentReference<Map<String, dynamic>> ref = db
      .collection('cash_handovers')
      .doc();
  final WriteBatch batch = db.batch();
  batch.set(ref, <String, dynamic>{
    'establishmentId': facilityId,
    'ownerId': ownerId,
    'staffId': due.staffId,
    'staffName': staffName.trim(),
    'amount': overtime + walkIn,
    'overtimeAmount': overtime,
    'walkInAmount': walkIn,
    'logCount': ids.length,
    'receivedAt': FieldValue.serverTimestamp(),
    // Who took the cash; the rules require the signed-in user.
    'receivedBy': receivedBy ?? ownerId,
    if (note.trim().isNotEmpty) 'note': note.trim(),
  });
  for (final String id in ids) {
    batch.update(db.collection('activity_logs').doc(id), <String, dynamic>{
      'cashHandoverId': ref.id,
    });
  }
  await batch.commit();
  return ref.id;
}
