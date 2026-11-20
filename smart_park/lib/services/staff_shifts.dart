import 'package:cloud_firestore/cloud_firestore.dart';

/// Staff duty log: a staff member clocks in at the start of a shift and out
/// at the end (`staff_shifts`), so the owner knows who was on duty when,
/// not only who scanned. The gate never requires it. An open shift has
/// `endedAt: null`; the owner can end one someone forgot.

CollectionReference<Map<String, dynamic>> _shifts(FirebaseFirestore? db) =>
    (db ?? FirebaseFirestore.instance).collection('staff_shifts');

/// The staff member's open shift(s); normally none or one.
Query<Map<String, dynamic>> openShiftsOf(
  String staffId, {
  FirebaseFirestore? firestore,
}) => _shifts(
  firestore,
).where('staffId', isEqualTo: staffId).where('endedAt', isNull: true);

/// Everyone on duty at [facilityId] now.
Query<Map<String, dynamic>> onDutyAt(
  String facilityId, {
  FirebaseFirestore? firestore,
}) => _shifts(firestore)
    .where('establishmentId', isEqualTo: facilityId)
    .where('endedAt', isNull: true);

/// Shifts at [facilityId] that started on [day] (local), newest first.
Query<Map<String, dynamic>> shiftsOnDay(
  String facilityId,
  DateTime day, {
  FirebaseFirestore? firestore,
}) {
  final DateTime start = DateTime(day.year, day.month, day.day);
  return _shifts(firestore)
      .where('establishmentId', isEqualTo: facilityId)
      .where('startedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
      .where(
        'startedAt',
        isLessThan: Timestamp.fromDate(start.add(const Duration(days: 1))),
      )
      .orderBy('startedAt', descending: true);
}

Future<void> clockIn({
  required String staffId,
  required String staffName,
  required String facilityId,
  String? ownerId,
  FirebaseFirestore? firestore,
}) => _shifts(firestore).add(<String, dynamic>{
  'establishmentId': facilityId,
  'ownerId': ?ownerId,
  'staffId': staffId,
  'staffName': staffName.trim(),
  'startedAt': FieldValue.serverTimestamp(),
  'endedAt': null,
});

/// Ends a shift: the staff member's own, or by the owner ([endedBy]).
Future<void> clockOut(
  String shiftId, {
  String? endedBy,
  FirebaseFirestore? firestore,
}) => _shifts(firestore).doc(shiftId).update(<String, dynamic>{
  'endedAt': FieldValue.serverTimestamp(),
  'endedBy': ?endedBy,
});

/// "8h 05m" for a shift; still running when [end] is null.
String shiftLength(DateTime start, DateTime? end, {DateTime? now}) {
  final Duration d = (end ?? now ?? DateTime.now()).difference(start);
  final int minutes = d.isNegative ? 0 : d.inMinutes;
  return '${minutes ~/ 60}h ${(minutes % 60).toString().padLeft(2, '0')}m';
}
