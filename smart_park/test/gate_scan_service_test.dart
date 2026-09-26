import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_park/services/gate_scan_service.dart';

const String facilityId = 'fac-1';
const GateStaff staff = GateStaff(
  staffId: 'staff-1',
  email: 'gate@example.com',
  facilityId: facilityId,
  ownerId: 'owner-1',
  name: 'Juan Dela Cruz',
);

String qr(String transactionId, [String plate = 'ABC 123']) => jsonEncode(
  <String, dynamic>{'transactionId': transactionId, 'vehiclePlate': plate},
);

void main() {
  late FakeFirebaseFirestore db;
  late DateTime now;
  late GateScanService service;

  Future<void> seedTicket(String id, Map<String, dynamic> fields) {
    return db.collection('transactions').doc(id).set(<String, dynamic>{
      'establishmentId': facilityId,
      'vehiclePlate': 'ABC 123',
      'vehicleType': 'car',
      'status': 'paid',
      'plan': 'base',
      ...fields,
    });
  }

  Future<GateScanResult?> scan(String payload, {String mode = 'entry'}) {
    return service.handleScanPayload(
      staff: staff,
      gateMode: mode,
      rawPayload: payload,
    );
  }

  Future<Map<String, dynamic>> ticket(String id) async =>
      (await db.collection('transactions').doc(id).get()).data()!;

  Future<List<Map<String, dynamic>>> activityLogs() async =>
      (await db.collection('activity_logs').get()).docs
          .map((QueryDocumentSnapshot<Map<String, dynamic>> d) => d.data())
          .toList();

  setUp(() {
    db = FakeFirebaseFirestore();
    now = DateTime(2026, 9, 24, 12);
    service = GateScanService(firestore: db, clock: () => now);
  });

  group('resolveAssignment', () {
    test('prefers the staff record linked to the uid', () async {
      await db.collection('staff_accounts').add(<String, dynamic>{
        'userId': 'u1',
        'establishmentID': 'fac-a',
        'ownerId': 'o1',
      });
      final StaffAssignment a = await service.resolveAssignment(
        uid: 'u1',
        email: 'x@example.com',
      );
      expect(a.facilityId, 'fac-a');
      expect(a.ownerId, 'o1');
    });

    test('carries the staff name from the staff record', () async {
      await db.collection('staff_accounts').add(<String, dynamic>{
        'userId': 'u1',
        'facilityId': 'fac-a',
        'name': ' Maria Santos ',
      });
      final StaffAssignment a = await service.resolveAssignment(
        uid: 'u1',
        email: '',
      );
      expect(a.staffName, 'Maria Santos');
    });

    test('a deactivated record gives no facility and no fallback', () async {
      await db.collection('staff_accounts').add(<String, dynamic>{
        'userId': 'u1',
        'facilityId': 'fac-a',
        'ownerId': 'o1',
        'active': false,
      });
      // A profile that still names the facility must not re-grant it.
      await db.collection('users').doc('u1').set(<String, dynamic>{
        'establishmentID': 'fac-a',
      });
      final StaffAssignment a = await service.resolveAssignment(
        uid: 'u1',
        email: '',
      );
      expect(a.deactivated, isTrue);
      expect(a.facilityId, isNull);
    });

    test('records without the active field are active', () {
      expect(isStaffRecordActive(<String, dynamic>{}), isTrue);
      expect(isStaffRecordActive(<String, dynamic>{'active': true}), isTrue);
      expect(isStaffRecordActive(<String, dynamic>{'active': false}), isFalse);
    });

    test('falls back to the staff email, then the user profile', () async {
      await db.collection('staff_accounts').add(<String, dynamic>{
        'email': 'gate@example.com',
        'facilityId': 'fac-b',
      });
      await db.collection('users').doc('u3').set(<String, dynamic>{
        'establishmentID': 'fac-c',
        'ownerId': 'o3',
      });

      final StaffAssignment byEmail = await service.resolveAssignment(
        uid: 'u2',
        email: '  Gate@Example.com ',
      );
      expect(byEmail.facilityId, 'fac-b');

      final StaffAssignment byProfile = await service.resolveAssignment(
        uid: 'u3',
        email: '',
      );
      expect(byProfile.facilityId, 'fac-c');
      expect(byProfile.ownerId, 'o3');
    });
  });

  group('scan is denied', () {
    test('when staff has no facility, without logging', () async {
      final GateScanResult? r = await service.handleScanPayload(
        staff: const GateStaff(
          staffId: 's',
          email: '',
          facilityId: null,
          ownerId: null,
        ),
        gateMode: 'entry',
        rawPayload: qr('t1'),
      );
      expect(r!.isDenied, isTrue);
      expect(await activityLogs(), isEmpty);
    });

    test('for a QR that is not a SmartPark ticket', () async {
      final GateScanResult? r = await scan('https://example.com');
      expect(r!.isDenied, isTrue);
      expect(r.reason, 'Not a SmartPark ticket QR.');

      final List<Map<String, dynamic>> logs = await activityLogs();
      expect(logs.single['decision'], 'DENIED');
      expect(logs.single['vehiclePlate'], 'unreadable');
      final QuerySnapshot<Map<String, dynamic>> actions = await db
          .collection('StaffActivityLogs')
          .get();
      expect(actions.docs.single.data()['action'], 'scan_entry');
    });

    test('when the payload has no transaction id', () async {
      final GateScanResult? r = await scan(jsonEncode(<String, dynamic>{}));
      expect(r!.reason, 'Ticket is unreadable. Use plate lookup.');
    });

    test('for an unknown ticket', () async {
      final GateScanResult? r = await scan(qr('missing'));
      expect(r!.reason, 'Ticket not found for this facility.');
      expect((await activityLogs()).single['transactionId'], 'missing');
    });

    test('for another facility\'s ticket', () async {
      await seedTicket('t1', <String, dynamic>{'establishmentId': 'other'});
      final GateScanResult? r = await scan(qr('t1'));
      expect(r!.reason, 'Ticket issued for another facility.');
    });

    test('for an unpaid ticket', () async {
      await seedTicket('t1', <String, dynamic>{'status': 'pending'});
      final GateScanResult? r = await scan(qr('t1'));
      expect(r!.reason, 'Payment not confirmed.');
      expect(
        (await activityLogs()).single['decisionReason'],
        'Ticket not paid (pending).',
      );
    });
  });

  group('entry', () {
    test('admits a paid ticket and opens an entry log', () async {
      await seedTicket('t1', <String, dynamic>{});
      final GateScanResult? r = await scan(qr('t1'));

      expect(r!.isAllowed, isTrue);
      expect(r.vehiclePlate, 'ABC 123');
      final Map<String, dynamic> t = await ticket('t1');
      expect(t['entryStatus'], 'checked_in');
      expect(t['entryStaffId'], 'staff-1');
      final Map<String, dynamic> log = (await activityLogs()).single;
      expect(log['isActive'], isTrue);
      expect(log['decision'], 'ALLOWED');
      expect(log['ownerId'], 'owner-1');
      expect(log['staffId'], 'staff-1');
      expect(log['staffName'], 'Juan Dela Cruz');
      expect(t['entryLogId'], isNotNull);
    });

    test('stamps who scanned on denied logs too', () async {
      await seedTicket('t1', <String, dynamic>{'status': 'pending'});
      await scan(qr('t1'));
      final Map<String, dynamic> log = (await activityLogs()).single;
      expect(log['decision'], 'DENIED');
      expect(log['staffName'], 'Juan Dela Cruz');
    });

    test('leaves staffName off when the name is unknown', () async {
      await seedTicket('t1', <String, dynamic>{});
      await service.handleScanPayload(
        staff: const GateStaff(
          staffId: 'staff-1',
          email: 'gate@example.com',
          facilityId: facilityId,
          ownerId: 'owner-1',
        ),
        gateMode: 'entry',
        rawPayload: qr('t1'),
      );
      expect((await activityLogs()).single.containsKey('staffName'), isFalse);
    });

    test('ignores the same ticket again within the cooldown', () async {
      await seedTicket('t1', <String, dynamic>{});
      await scan(qr('t1'));
      now = now.add(const Duration(seconds: 3));
      expect(await scan(qr('t1')), isNull);
    });

    test('refuses a second entry after the cooldown', () async {
      await seedTicket('t1', <String, dynamic>{});
      await scan(qr('t1'));
      now = now.add(GateScanService.rescanCooldown);
      final GateScanResult? r = await scan(qr('t1'));
      expect(r!.reason, 'Already inside. Do not admit twice.');
    });

    test('refuses a ticket that already completed a stay', () async {
      await seedTicket('t1', <String, dynamic>{'entryStatus': 'checked_out'});
      final GateScanResult? r = await scan(qr('t1'));
      expect(r!.reason, 'Ticket already completed a stay.');
    });
  });

  group('exit', () {
    Future<void> seedInside(Duration stayed, Map<String, dynamic> extra) =>
        seedTicket('t1', <String, dynamic>{
          'entryStatus': 'checked_in',
          'entryAt': Timestamp.fromDate(now.subtract(stayed)),
          ...extra,
        });

    test('releases within paid time and closes the entry log', () async {
      await seedInside(const Duration(hours: 1), <String, dynamic>{});
      await db.collection('activity_logs').add(<String, dynamic>{
        'establishmentID': facilityId,
        'transactionId': 't1',
        'scanType': 'entry',
        'isActive': true,
      });

      final GateScanResult? r = await scan(qr('t1'), mode: 'exit');

      expect(r!.isAllowed, isTrue);
      expect(r.hasOvertime, isFalse);
      expect(r.elapsed, const Duration(hours: 1));
      expect(r.billableHours, 2);
      final Map<String, dynamic> t = await ticket('t1');
      expect(t['entryStatus'], 'checked_out');
      expect(t['overtimeStatus'], 'none');
      expect(t['staySeconds'], 3600);
      final List<Map<String, dynamic>> logs = await activityLogs();
      expect(
        logs.where((Map<String, dynamic> l) => l['isActive'] == true),
        isEmpty,
      );
    });

    test('charges overtime past the base stay and grace period', () async {
      // 4h stay on a 2h base with 5 min grace -> 1h55m over -> 2 billable
      // overtime hours at the succeeding-hour rate.
      await db.collection('establishment_details').doc(facilityId).set(
        <String, dynamic>{
          'rates': <String, dynamic>{
            'car': <String, dynamic>{'initial': 50, 'succeedingHour': 20},
          },
        },
      );
      await seedInside(const Duration(hours: 4), <String, dynamic>{});

      final GateScanResult? r = await scan(qr('t1'), mode: 'exit');

      expect(r!.hasOvertime, isTrue);
      expect(r.overtimeHours, 2);
      expect(r.overtimeAmount, 40);
      expect(r.billableHours, 4);
      expect(r.reason, 'Overtime: collect cash first.');
      final Map<String, dynamic> t = await ticket('t1');
      expect(t['overtimeStatus'], 'cash_due');
      expect(t['overtimeAmount'], 40);
    });

    test('flags overtime when the facility has no rate', () async {
      await seedInside(const Duration(hours: 4), <String, dynamic>{});
      final GateScanResult? r = await scan(qr('t1'), mode: 'exit');
      expect(r!.reason, 'Overtime: confirm.');
      expect((await ticket('t1'))['overtimeStatus'], 'rate_unresolved');
    });

    test('marks overtime cash collected on the ticket and exit log', () async {
      await db.collection('establishment_details').doc(facilityId).set(
        <String, dynamic>{
          'rates': <String, dynamic>{
            'car': <String, dynamic>{'initial': 50, 'succeedingHour': 20},
          },
        },
      );
      await seedInside(const Duration(hours: 4), <String, dynamic>{});
      final GateScanResult? r = await scan(qr('t1'), mode: 'exit');
      expect(r!.activityLogId, isNotNull);

      await service.markOvertimeCollected(
        staff: staff,
        transactionId: 't1',
        exitLogId: r.activityLogId,
      );

      final Map<String, dynamic> t = await ticket('t1');
      expect(t['overtimeStatus'], 'collected');
      expect(t['overtimeCollectedBy'], 'staff-1');
      final Map<String, dynamic> exitLog =
          (await db.collection('activity_logs').doc(r.activityLogId).get())
              .data()!;
      expect(exitLog['overtimeStatus'], 'collected');
      expect(exitLog['overtimeCollectedBy'], 'staff-1');
      expect(r.markedCollected().overtimeCollected, isTrue);
    });

    test('finds the exit log from the ticket when marking collected', () async {
      await db.collection('activity_logs').doc('exit-1').set(<String, dynamic>{
        'establishmentID': facilityId,
        'overtimeStatus': 'cash_due',
      });
      await seedTicket('t1', <String, dynamic>{
        'overtimeStatus': 'cash_due',
        'exitLogId': 'exit-1',
      });
      await service.markOvertimeCollected(staff: staff, transactionId: 't1');
      final Map<String, dynamic> exitLog =
          (await db.collection('activity_logs').doc('exit-1').get()).data()!;
      expect(exitLog['overtimeStatus'], 'collected');
    });

    test('will not mark collected when no overtime cash is due', () async {
      await seedTicket('t1', <String, dynamic>{'overtimeStatus': 'none'});
      await expectLater(
        service.markOvertimeCollected(staff: staff, transactionId: 't1'),
        throwsStateError,
      );
      expect((await ticket('t1'))['overtimeStatus'], 'none');
    });

    test('counts extended plans\' paid hours before overtime', () async {
      // Extended with duration 3 -> 2 + 3 = 5 included hours.
      await seedInside(const Duration(hours: 4), <String, dynamic>{
        'plan': 'extended',
        'duration': 3,
      });
      final GateScanResult? r = await scan(qr('t1'), mode: 'exit');
      expect(r!.hasOvertime, isFalse);
      expect(r.billableHours, 5);
    });

    test('refuses a ticket that already exited', () async {
      await seedTicket('t1', <String, dynamic>{'entryStatus': 'checked_out'});
      final GateScanResult? r = await scan(qr('t1'), mode: 'exit');
      expect(r!.reason, 'Already exited.');
    });

    test('refuses a ticket with no entry on record', () async {
      await seedTicket('t1', <String, dynamic>{});
      final GateScanResult? r = await scan(qr('t1'), mode: 'exit');
      expect(r!.reason, 'No entry on record. Verify first.');
    });
  });

  group('lookupByPlate', () {
    Future<GateScanResult?> lookup(String plate) =>
        service.lookupByPlate(staff: staff, gateMode: 'entry', rawPlate: plate);

    test('asks for a plate when empty', () async {
      final GateScanResult? r = await lookup('   ');
      expect(r!.decision, 'ERROR');
    });

    test('finds the paid ticket for a lower-cased plate', () async {
      await seedTicket('unpaid', <String, dynamic>{
        'vehiclePlate': 'ABC123',
        'status': 'pending',
      });
      await seedTicket('paid', <String, dynamic>{'vehiclePlate': 'ABC123'});

      final GateScanResult? r = await lookup('abc123');

      expect(r!.isAllowed, isTrue);
      expect(r.transactionId, 'paid');
      expect((await ticket('paid'))['entryStatus'], 'checked_in');
    });

    test('ignores walk-ins and reports no ticket', () async {
      await seedTicket('w1', <String, dynamic>{
        'vehiclePlate': 'XYZ',
        'source': 'walk_in',
      });
      final GateScanResult? r = await lookup('XYZ');
      expect(r!.reason, 'No ticket for this plate here.');
    });

    test('denies when the only ticket is unpaid', () async {
      await seedTicket('t1', <String, dynamic>{
        'vehiclePlate': 'XYZ',
        'status': 'pending',
      });
      final GateScanResult? r = await lookup('XYZ');
      expect(r!.reason, 'Ticket for plate is unpaid.');
      expect(r.transactionId, 't1');
    });
  });
}
