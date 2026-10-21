import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_park/services/driver_reports.dart';

void main() {
  late FakeFirebaseFirestore db;

  setUp(() => db = FakeFirebaseFirestore());

  Future<String> report() async {
    await submitDriverReport(
      ownerId: 'owner-1',
      establishmentId: 'fac-1',
      establishmentName: 'Mall Parking',
      transactionId: 'tx-1',
      driverId: 'driver-1',
      driverName: 'Ana Reyes',
      reason: 'Refused to pay overtime cash',
      details: '  Left without paying.  ',
      firestore: db,
    );
    return (await db.collection('driver_reports').get()).docs.single.id;
  }

  test('a new report is open and carries the driver and ticket', () async {
    final String id = await report();
    final Map<String, dynamic> data =
        (await db.collection('driver_reports').doc(id).get()).data()!;
    expect(reportStatus(data), kReportOpen);
    expect(data['driverName'], 'Ana Reyes');
    expect(data['transactionId'], 'tx-1');
    expect(data['details'], 'Left without paying.');
  });

  test('warning the driver closes the report and writes the warning', () async {
    final String id = await report();
    final Map<String, dynamic> data =
        (await db.collection('driver_reports').doc(id).get()).data()!;
    await warnDriverForReport(
      adminId: 'admin-1',
      reportId: id,
      report: data,
      message: 'Please pay overtime at the gate.',
      adminNote: 'Warned.',
      firestore: db,
    );
    final Map<String, dynamic> closed =
        (await db.collection('driver_reports').doc(id).get()).data()!;
    final QueryDocumentSnapshot<Map<String, dynamic>> warning =
        (await db.collection('driver_warnings').get()).docs.single;
    expect(reportStatus(closed), kReportWarned);
    expect(closed['warningId'], warning.id);
    expect(warning['driverId'], 'driver-1');
    expect(warning['message'], 'Please pay overtime at the gate.');
    expect(warning['acknowledgedAt'], isNull);

    await acknowledgeDriverWarning(warning.id, firestore: db);
    expect(
      (await db.collection('driver_warnings').doc(warning.id).get())
          .data()!['acknowledgedAt'],
      isNotNull,
    );
  });

  test('a warning over "Other" carries no reason label', () async {
    await submitDriverReport(
      ownerId: 'owner-1',
      establishmentId: 'fac-1',
      establishmentName: 'Mall Parking',
      transactionId: 'tx-2',
      driverId: 'driver-1',
      driverName: 'Ana Reyes',
      reason: 'Other',
      details: 'Blocked the exit lane.',
      firestore: db,
    );
    final QueryDocumentSnapshot<Map<String, dynamic>> doc =
        (await db.collection('driver_reports').get()).docs.single;
    await warnDriverForReport(
      adminId: 'admin-1',
      reportId: doc.id,
      report: doc.data(),
      message: 'Please keep the exit lane clear.',
      firestore: db,
    );
    expect(
      (await db.collection('driver_warnings').get()).docs.single['reason'],
      '',
    );
  });

  test('dismissing sends the driver nothing', () async {
    final String id = await report();
    await dismissDriverReport(adminId: 'admin-1', reportId: id, firestore: db);
    expect(
      reportStatus(
        (await db.collection('driver_reports').doc(id).get()).data()!,
      ),
      kReportDismissed,
    );
    expect((await db.collection('driver_warnings').get()).docs, isEmpty);
  });
}
