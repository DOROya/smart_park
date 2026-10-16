import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_park/screens/driver/driver_vehicle_selection_page.dart';

void main() {
  late FakeFirebaseFirestore db;

  setUp(() => db = FakeFirebaseFirestore());

  Future<void> pumpPicker(
    WidgetTester tester, {
    Stream<DocumentSnapshot<Map<String, dynamic>>>? occupancy,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: DriverVehicleSelectionPage(
          establishmentName: 'Lot 1',
          // The establishment's legacy `slots` field is always 0.
          vehicleOptions: const <DriverVehicleOption>[
            DriverVehicleOption(
              key: 'motorcycle',
              label: 'Motorcycle',
              icon: Icons.two_wheeler_rounded,
              activeCount: 0,
              capacity: 5,
              rate: 'P30 / 2 hrs',
            ),
            DriverVehicleOption(
              key: 'car',
              label: 'Car / SUV',
              icon: Icons.directions_car_rounded,
              activeCount: 0,
              capacity: 10,
              rate: 'P100 / 2 hrs',
            ),
          ],
          ratesByType: const <String, dynamic>{},
          packageRates: const <String, dynamic>{},
          occupancy: occupancy,
          isPayMongoConfigured: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('counts vehicles parked now, like the details page', (
    WidgetTester tester,
  ) async {
    final DocumentReference<Map<String, dynamic>> doc = db
        .collection('establishment_occupancy')
        .doc('est1');
    await doc.set(<String, dynamic>{
      'occupied': <String, dynamic>{'motorcycle': 1, 'car': 3},
    });

    await pumpPicker(tester, occupancy: doc.snapshots());
    expect(find.text('4 slots available'), findsOneWidget); // motorcycle
    expect(find.text('7 slots available'), findsOneWidget); // car

    // A motorcycle exits while the driver is still choosing.
    await doc.set(<String, dynamic>{
      'occupied': <String, dynamic>{'motorcycle': 0, 'car': 3},
    });
    await tester.pumpAndSettle();
    expect(find.text('5 slots available'), findsOneWidget);
  });

  testWidgets('never shows a negative count when over capacity', (
    WidgetTester tester,
  ) async {
    final DocumentReference<Map<String, dynamic>> doc = db
        .collection('establishment_occupancy')
        .doc('est1');
    await doc.set(<String, dynamic>{
      'occupied': <String, dynamic>{'motorcycle': 7, 'car': 0},
    });
    await pumpPicker(tester, occupancy: doc.snapshots());
    expect(find.text('0 slots available'), findsOneWidget);
    expect(find.text('10 slots available'), findsOneWidget);
  });

  testWidgets('without live data it falls back to the given counts', (
    WidgetTester tester,
  ) async {
    await pumpPicker(tester);
    expect(find.text('5 slots available'), findsOneWidget);
    expect(find.text('10 slots available'), findsOneWidget);
  });
}
