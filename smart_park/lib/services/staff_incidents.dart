import 'package:cloud_firestore/cloud_firestore.dart';

/// Gate staff flag a driver's ticket for their owner (`staff_incidents`);
/// the owner then reports it to SmartPark (see driver_reports.dart) or
/// dismisses it. Staff see what became of their flag; drivers never do.

const String kIncidentOpen = 'open';
const String kIncidentReported = 'reported';
const String kIncidentDismissed = 'dismissed';

String incidentStatus(Map<String, dynamic> data) =>
    ((data['status'] as String?) ?? kIncidentOpen).trim().toLowerCase();

/// Flags the driver of ticket [transactionId] ([ticket] is its
/// `transactions` doc). Security rules check the ticket is the staff
/// member's facility's and belongs to that driver.
Future<void> flagIncident({
  required String staffId,
  required String staffName,
  required String transactionId,
  required Map<String, dynamic> ticket,
  required String reason,
  String details = '',
  FirebaseFirestore? firestore,
}) {
  final FirebaseFirestore db = firestore ?? FirebaseFirestore.instance;
  String text(String key) => ((ticket[key] as String?) ?? '').trim();
  return db.collection('staff_incidents').add(<String, dynamic>{
    'establishmentId': text('establishmentId'),
    'establishmentName': text('establishmentName'),
    'ownerId': text('ownerId'),
    'staffId': staffId,
    'staffName': staffName.trim(),
    'transactionId': transactionId,
    'driverId': text('driverId'),
    'driverName': text('driverName'),
    'vehiclePlate': text('vehiclePlate'),
    'reason': reason,
    'details': details.trim(),
    'status': kIncidentOpen,
    'createdAt': FieldValue.serverTimestamp(),
  });
}

/// The owner closes [incidentId] as reported to SmartPark or dismissed.
Future<void> resolveIncident(
  String incidentId,
  String status, {
  FirebaseFirestore? firestore,
}) {
  final FirebaseFirestore db = firestore ?? FirebaseFirestore.instance;
  return db.collection('staff_incidents').doc(incidentId).update(
    <String, dynamic>{
      'status': status,
      'handledAt': FieldValue.serverTimestamp(),
    },
  );
}

/// The incident as the ticket fields the owner's report form reads.
Map<String, dynamic> incidentAsTicket(Map<String, dynamic> incident) =>
    <String, dynamic>{
      for (final String key in <String>[
        'establishmentId',
        'establishmentName',
        'driverId',
        'driverName',
        'vehiclePlate',
      ])
        key: incident[key],
    };
