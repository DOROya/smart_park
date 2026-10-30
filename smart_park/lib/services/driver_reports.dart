import 'package:cloud_firestore/cloud_firestore.dart';

/// Owners report a driver to the SmartPark admin from one of the driver's
/// tickets at their facility (`driver_reports`). The admin reviews it and
/// either warns the driver (`driver_warnings`, which the driver sees) or
/// dismisses it. Drivers never see the report itself.

const String kReportOpen = 'open';
const String kReportWarned = 'warned';
const String kReportDismissed = 'dismissed';

/// A ticket may be shared, but only for the vehicle type it was bought for;
/// staff refusing a different type at the gate flag it with this reason.
const String kWrongVehicleTypeReason = 'Wrong vehicle type for ticket';

/// Reasons an owner picks from; the last one needs details. Kept short so
/// each fits on one chip at phone width. Sharing a ticket is allowed, so
/// only a fake one is a reason.
const List<String> kDriverReportReasons = <String>[
  'Refused to pay overtime cash',
  'Disputed the overtime charge',
  'Damaged property or a vehicle',
  'Rude or abusive to staff',
  'Parked outside the allowed area',
  kWrongVehicleTypeReason,
  'Used a fake ticket',
  'Other',
];

String reportStatus(Map<String, dynamic> data) =>
    ((data['status'] as String?) ?? kReportOpen).trim().toLowerCase();

/// The reasons on a report, flag or warning (`reasons`), in the order they
/// were picked. Ones from before several could be picked have a single
/// `reason`.
List<String> reportReasons(Map<String, dynamic> data) {
  final Object? list = data['reasons'];
  if (list is List && list.isNotEmpty) {
    return <String>[
      for (final Object? reason in list)
        if (reason is String && reason.trim().isNotEmpty) reason.trim(),
    ];
  }
  final String reason = ((data['reason'] as String?) ?? '').trim();
  return reason.isEmpty ? const <String>[] : <String>[reason];
}

/// [reasons] as stored: the list, plus `reason` with them on one line for
/// the screens (and older app versions) that show a single reason.
Map<String, dynamic> reasonFields(List<String> reasons) => <String, dynamic>{
  'reasons': reasons,
  'reason': reasons.join(', '),
};

/// Files a report on the driver of ticket [transactionId] for one or more
/// [reasons]. Security rules check that the ticket is this facility's and
/// belongs to [driverId].
Future<void> submitDriverReport({
  required String ownerId,
  required String establishmentId,
  required String establishmentName,
  required String transactionId,
  required String driverId,
  required String driverName,
  required List<String> reasons,
  String details = '',
  FirebaseFirestore? firestore,
}) {
  if (reasons.isEmpty) throw ArgumentError.value(reasons, 'reasons');
  final FirebaseFirestore db = firestore ?? FirebaseFirestore.instance;
  return db.collection('driver_reports').add(<String, dynamic>{
    'reporterId': ownerId,
    'establishmentId': establishmentId,
    'establishmentName': establishmentName,
    'transactionId': transactionId,
    'driverId': driverId,
    'driverName': driverName,
    ...reasonFields(reasons),
    'details': details.trim(),
    'status': kReportOpen,
    'createdAt': FieldValue.serverTimestamp(),
  });
}

/// The report's reasons as the driver is told them: all but "Other", which
/// the admin explains in the warning's message instead.
List<String> warningReasons(Map<String, dynamic> report) =>
    reportReasons(report).where((String r) => r != 'Other').toList();

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
    // Drivers see the reasons as labels; "Other" would tell them nothing.
    ...reasonFields(warningReasons(report)),
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
