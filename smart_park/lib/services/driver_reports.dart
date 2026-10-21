import 'package:cloud_firestore/cloud_firestore.dart';

/// Owners report a driver to the SmartPark admin from one of the driver's
/// tickets at their facility (`driver_reports`). The admin reviews it and
/// either warns the driver (`driver_warnings`, which the driver sees) or
/// dismisses it. Drivers never see the report itself.

const String kReportOpen = 'open';
const String kReportWarned = 'warned';
const String kReportDismissed = 'dismissed';

/// Reasons an owner picks from; the last one needs details.
const List<String> kDriverReportReasons = <String>[
  'Refused to pay overtime cash',
  'Overstayed and disputed the charge',
  'Damaged property or another vehicle',
  'Rude or abusive to staff',
  'Parked outside the allowed area',
  'Used a shared or fake ticket',
  'Other',
];

String reportStatus(Map<String, dynamic> data) =>
    ((data['status'] as String?) ?? kReportOpen).trim().toLowerCase();

/// Files a report on the driver of ticket [transactionId]. Security rules
/// check that the ticket is this facility's and belongs to [driverId].
Future<void> submitDriverReport({
  required String ownerId,
  required String establishmentId,
  required String establishmentName,
  required String transactionId,
  required String driverId,
  required String driverName,
  required String reason,
  String details = '',
  FirebaseFirestore? firestore,
}) {
  final FirebaseFirestore db = firestore ?? FirebaseFirestore.instance;
  return db.collection('driver_reports').add(<String, dynamic>{
    'reporterId': ownerId,
    'establishmentId': establishmentId,
    'establishmentName': establishmentName,
    'transactionId': transactionId,
    'driverId': driverId,
    'driverName': driverName,
    'reason': reason,
    'details': details.trim(),
    'status': kReportOpen,
    'createdAt': FieldValue.serverTimestamp(),
  });
}

/// Admin warns the driver over [reportId]: writes the warning the driver
/// will see and closes the report as warned, together.
Future<void> warnDriverForReport({
  required String adminId,
  required String reportId,
  required Map<String, dynamic> report,
  required String message,
  String adminNote = '',
  FirebaseFirestore? firestore,
}) async {
  final FirebaseFirestore db = firestore ?? FirebaseFirestore.instance;
  final DocumentReference<Map<String, dynamic>> warningRef = db
      .collection('driver_warnings')
      .doc();
  final WriteBatch batch = db.batch();
  batch.set(warningRef, <String, dynamic>{
    'driverId': report['driverId'],
    'reportId': reportId,
    'reason': report['reason'],
    'message': message.trim(),
    'establishmentName': report['establishmentName'],
    'createdBy': adminId,
    'createdAt': FieldValue.serverTimestamp(),
    'acknowledgedAt': null,
  });
  batch.update(db.collection('driver_reports').doc(reportId), <String, dynamic>{
    'status': kReportWarned,
    'warningId': warningRef.id,
    'adminNote': adminNote.trim(),
    'reviewedBy': adminId,
    'reviewedAt': FieldValue.serverTimestamp(),
  });
  await batch.commit();
}

/// Admin closes [reportId] without warning the driver.
Future<void> dismissDriverReport({
  required String adminId,
  required String reportId,
  String adminNote = '',
  FirebaseFirestore? firestore,
}) {
  final FirebaseFirestore db = firestore ?? FirebaseFirestore.instance;
  return db.collection('driver_reports').doc(reportId).update(<String, dynamic>{
    'status': kReportDismissed,
    'adminNote': adminNote.trim(),
    'reviewedBy': adminId,
    'reviewedAt': FieldValue.serverTimestamp(),
  });
}

/// The driver confirms they read warning [warningId].
Future<void> acknowledgeDriverWarning(
  String warningId, {
  FirebaseFirestore? firestore,
}) {
  final FirebaseFirestore db = firestore ?? FirebaseFirestore.instance;
  return db.collection('driver_warnings').doc(warningId).update(
    <String, dynamic>{'acknowledgedAt': FieldValue.serverTimestamp()},
  );
}
