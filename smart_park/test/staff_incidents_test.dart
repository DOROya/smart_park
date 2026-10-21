import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_park/services/staff_incidents.dart';

void main() {
  test(
    'a flag copies the ticket and closes as reported or dismissed',
    () async {
      final FakeFirebaseFirestore db = FakeFirebaseFirestore();
      await flagIncident(
        staffId: 'staff-1',
        staffName: 'Juan',
        transactionId: 'tx-1',
        ticket: <String, dynamic>{
          'establishmentId': 'fac-1',
          'establishmentName': 'Mall Parking',
          'driverId': 'driver-1',
          'driverName': 'Ana Reyes',
          'vehiclePlate': 'ABC 123',
        },
        reason: 'Refused to pay overtime cash',
        details: ' Drove off. ',
        firestore: db,
      );
      final doc = (await db.collection('staff_incidents').get()).docs.single;
      expect(incidentStatus(doc.data()), kIncidentOpen);
      expect(doc['driverName'], 'Ana Reyes');
      expect(doc['details'], 'Drove off.');
      expect(incidentAsTicket(doc.data())['vehiclePlate'], 'ABC 123');

      await resolveIncident(doc.id, kIncidentReported, firestore: db);
      expect(
        incidentStatus(
          (await db.collection('staff_incidents').doc(doc.id).get()).data()!,
        ),
        kIncidentReported,
      );
    },
  );
}
