import 'package:cloud_firestore/cloud_firestore.dart';

import 'driver_reports.dart' show reasonFields;

/// Drivers report a facility to the SmartPark admin from one of their own
/// tickets for it (`facility_reports`). Only admins read them, so the
/// facility is never told who reported it. The admin marks each one
/// resolved (acted on) or dismissed.

const String kFacilityReportOpen = 'open';
const String kFacilityReportResolved = 'resolved';
const String kFacilityReportDismissed = 'dismissed';

/// Reasons a driver picks from; the last one needs details. Kept short so
/// each fits on one chip at phone width.
const List<String> kFacilityReportReasons = <String>[
  'Refused a valid ticket',
  'Charged more than the app shows',
  'Closed during posted hours',
  'Unsafe or poorly kept',
  'Rude or abusive staff',
  'Vehicle damaged or items lost',
  'Other',
];

String facilityReportStatus(Map<String, dynamic> data) =>
    ((data['status'] as String?) ?? kFacilityReportOpen).trim().toLowerCase();

/// Files a report on the facility of ticket [transactionId]. Security rules
/// check that the ticket is [driverId]'s and for this facility.
Future<void> submitFacilityReport({
  required String driverId,
  required String driverName,
  required String establishmentId,
  required String establishmentName,
  required String transactionId,
  required List<String> reasons,
  String details = '',
  FirebaseFirestore? firestore,
}) {
  if (reasons.isEmpty) throw ArgumentError.value(reasons, 'reasons');
  final FirebaseFirestore db = firestore ?? FirebaseFirestore.instance;
  return db.collection('facility_reports').add(<String, dynamic>{
    'driverId': driverId,
    'driverName': driverName,
    'establishmentId': establishmentId,
    'establishmentName': establishmentName,
    'transactionId': transactionId,
    ...reasonFields(reasons),
    'details': details.trim(),
    'status': kFacilityReportOpen,
    'createdAt': FieldValue.serverTimestamp(),
  });
}

/// Admin closes [reportId] as resolved (acted on) or dismissed.
Future<void> closeFacilityReport({
  required String adminId,
  required String reportId,
  required bool resolved,
  String adminNote = '',
  FirebaseFirestore? firestore,
}) {
  final FirebaseFirestore db = firestore ?? FirebaseFirestore.instance;
  return db
      .collection('facility_reports')
      .doc(reportId)
      .update(<String, dynamic>{
        'status': resolved ? kFacilityReportResolved : kFacilityReportDismissed,
        'adminNote': adminNote.trim(),
        'reviewedBy': adminId,
        'reviewedAt': FieldValue.serverTimestamp(),
      });
}
