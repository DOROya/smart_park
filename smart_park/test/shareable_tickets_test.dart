import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_park/screens/staff/gate_result_card.dart';
import 'package:smart_park/services/driver_reports.dart';
import 'package:smart_park/services/gate_scan_service.dart';
import 'package:smart_park/services/ticket_plate.dart';
import 'package:smart_park/theme/app_theme.dart';
import 'package:smart_park/widgets/smartpark_ui.dart';
import 'package:smart_park/widgets/sp_vehicle_type.dart';

GateScanResult result({
  String decision = 'ALLOWED',
  String scanType = 'entry',
  String? vehicleType = 'motorcycle',
}) => GateScanResult(
  decision: decision,
  vehiclePlate: 'MC 123',
  scanType: scanType,
  timestamp: DateTime(2026, 10, 30, 9),
  transactionId: 't1',
  activityLogId: 'log-1',
  vehicleType: vehicleType,
  reason: 'Paid ticket verified. 3 hours left. Admit.',
);

void main() {
  group('ticket plate', () {
    test('is stored trimmed and upper-cased', () {
      expect(normalizePlate('  abc 1234 '), 'ABC 1234');
    });

    test('can change on a paid ticket with hours left that is not parked', () {
      final Map<String, dynamic> ready = <String, dynamic>{
        'status': 'paid',
        'plan': 'base',
        'entryStatus': 'not_checked_in',
      };
      expect(canChangeTicketPlate(ready), isTrue);
      expect(
        canChangeTicketPlate(<String, dynamic>{
          ...ready,
          'entryStatus': 'checked_out',
          'remainingHours': 5,
        }),
        isTrue,
      );
      expect(
        canChangeTicketPlate(<String, dynamic>{
          ...ready,
          'entryStatus': 'checked_in',
        }),
        isFalse,
      );
      expect(
        canChangeTicketPlate(<String, dynamic>{
          ...ready,
          'entryStatus': 'checked_out',
          'remainingHours': 0,
        }),
        isFalse,
      );
      expect(
        canChangeTicketPlate(<String, dynamic>{...ready, 'status': 'pending'}),
        isFalse,
      );
    });

    test('change writes only the plate and updatedAt', () async {
      final FakeFirebaseFirestore db = FakeFirebaseFirestore();
      await db.collection('transactions').doc('t1').set(<String, dynamic>{
        'vehiclePlate': 'OLD 1',
        'vehicleType': 'motorcycle',
        'status': 'paid',
      });
      await changeTicketPlate(
        transactionId: 't1',
        plate: ' new 22 ',
        firestore: db,
      );
      final Map<String, dynamic> t = (await db
          .collection('transactions')
          .doc('t1')
          .get()).data()!;
      expect(t['vehiclePlate'], 'NEW 22');
      expect(t['vehicleType'], 'motorcycle');
      expect(t['updatedAt'], isNotNull);
      expect(t.keys.toSet(), <String>{
        'vehiclePlate',
        'vehicleType',
        'status',
        'updatedAt',
      });
    });

    test('change refuses an empty or too-long plate', () {
      final FakeFirebaseFirestore db = FakeFirebaseFirestore();
      expect(
        () => changeTicketPlate(transactionId: 't1', plate: '  ', firestore: db),
        throwsArgumentError,
      );
      expect(
        () => changeTicketPlate(
          transactionId: 't1',
          plate: 'A' * (kMaxPlateLength + 1),
          firestore: db,
        ),
        throwsArgumentError,
      );
    });
  });

  group('wording', () {
    test('the sharing rule names the vehicle type', () {
      expect(
        spTicketSharingRule('Motorcycle'),
        'This ticket is for a MOTORCYCLE. It can be shared, but only for the '
        'same vehicle type. The account that bought it is responsible for its '
        'use.',
      );
    });

    test('staff can flag a wrong vehicle type; sharing is not a reason', () {
      expect(kDriverReportReasons, contains(kWrongVehicleTypeReason));
      expect(
        kDriverReportReasons.where((String r) => r.contains('shared')),
        isEmpty,
      );
      expect(kDriverReportReasons.last, 'Other');
    });

    test('vehicle types get their own label and colors', () {
      expect(spVehicleTypeKey(null), 'car');
      expect(spVehicleTypeKey(' Motorcycle '), 'motorcycle');
      expect(spVehicleTypeLabel('motorcycle'), 'Motorcycle');
      expect(
        spVehicleTypeColors('car').$1,
        isNot(spVehicleTypeColors('motorcycle').$1),
      );
    });
  });

  group('GateResultCard', () {
    Future<void> pumpCard(
      WidgetTester tester,
      GateScanResult r, {
      VoidCallback? onWrongVehicle,
    }) {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      return tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.theme,
          home: Scaffold(
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                GateResultCard(
                  result: r,
                  onMarkCollected: () {},
                  onWrongVehicle: onWrongVehicle,
                ),
              ],
            ),
          ),
        ),
      );
    }

    testWidgets('shows the vehicle type large beside the plate', (
      WidgetTester tester,
    ) async {
      await pumpCard(tester, result(), onWrongVehicle: () {});
      expect(tester.takeException(), isNull);
      expect(find.text('MOTORCYCLE'), findsOneWidget);
      expect(find.byIcon(Icons.two_wheeler_rounded), findsOneWidget);
      expect(find.text('MC 123'), findsOneWidget);
      // Larger than the plate: it is what staff check first.
      final double typeSize = tester
          .widget<Text>(find.text('MOTORCYCLE'))
          .style!
          .fontSize!;
      final double plateSize = tester
          .widget<Text>(find.text('MC 123'))
          .style!
          .fontSize!;
      expect(typeSize, greaterThan(plateSize));
    });

    testWidgets('shows CAR in the car color', (WidgetTester tester) async {
      await pumpCard(tester, result(vehicleType: 'car'));
      expect(find.text('CAR'), findsOneWidget);
      expect(find.byIcon(Icons.directions_car_rounded), findsOneWidget);
    });

    testWidgets('admitted entries offer "Wrong vehicle" as a single tap', (
      WidgetTester tester,
    ) async {
      int taps = 0;
      await pumpCard(tester, result(), onWrongVehicle: () => taps++);
      await tester.tap(find.text('Wrong vehicle'));
      expect(taps, 1);
    });

    testWidgets('exits and denials have no "Wrong vehicle"', (
      WidgetTester tester,
    ) async {
      await pumpCard(tester, result(scanType: 'exit'), onWrongVehicle: () {});
      expect(find.text('Wrong vehicle'), findsNothing);
      await pumpCard(tester, result(decision: 'DENIED'), onWrongVehicle: () {});
      expect(find.text('Wrong vehicle'), findsNothing);
      expect(find.text('MOTORCYCLE'), findsOneWidget);
    });

    testWidgets('without a ticket read, keeps the plain plate line', (
      WidgetTester tester,
    ) async {
      await pumpCard(
        tester,
        result(decision: 'DENIED', vehicleType: null),
        onWrongVehicle: () {},
      );
      expect(find.text('Plate MC 123 - ENTRY'), findsOneWidget);
      expect(find.text('Wrong vehicle'), findsNothing);
    });
  });

  group('activity lists', () {
    final DateTime day = DateTime(2026, 10, 30, 12);
    final Map<String, dynamic> refused = <String, dynamic>{
      'timestamp': day,
      'decision': 'DENIED',
      'status': 'DENIED',
      'scanType': 'entry',
      'refusal': kRefusalWrongVehicle,
      'decisionReason': kWrongVehicleReason,
    };

    test('list a wrong-vehicle refusal but not other denials', () {
      final SpActivitySummary summary = SpActivitySummary.fromLogs(
        <Map<String, dynamic>>[
          <String, dynamic>{
            'timestamp': day,
            'decision': 'ALLOWED',
            'scanType': 'entry',
          },
          refused,
          <String, dynamic>{
            'timestamp': day,
            'decision': 'DENIED',
            'scanType': 'entry',
          },
        ],
        day,
      );
      expect(summary.dayLogs, hasLength(2));
      expect(summary.dayLogs, contains(refused));
      // It is not a vehicle that came in.
      expect(summary.entries, 1);
      expect(summary.denied, 2);
      expect(spIsListedLog(refused), isTrue);
      expect(spIsInsideLog(refused), isFalse);
    });

    testWidgets('show the refusal as denied with its reason', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.theme,
          home: Scaffold(body: SpActivityCard(data: refused)),
        ),
      );
      expect(find.text('Denied'), findsOneWidget);
      expect(find.textContaining(kWrongVehicleReason), findsOneWidget);
    });
  });
}
