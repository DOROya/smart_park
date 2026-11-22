import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_park/content/driver_help_content.dart';
import 'package:smart_park/content/terms_content.dart';
import 'package:smart_park/screens/driver/driver_guide_page.dart';
import 'package:smart_park/screens/driver/driver_help_page.dart';
import 'package:smart_park/screens/driver/services/driver_establishment_service.dart';
import 'package:smart_park/screens/driver/services/driver_favorites.dart';

Map<String, dynamic> facility(
  String id, {
  double lat = 14.6,
  double lng = 121.0,
  Object? rates,
  num? rating,
  int? ratingCount,
  Map<String, int>? slots,
  String name = '',
}) => <String, dynamic>{
  'establishmentID': id,
  'name': name.isEmpty ? 'Lot $id' : name,
  'address': 'Street $id',
  'latitude': lat,
  'longitude': lng,
  'rates': ?rates,
  'rating': ?rating,
  'ratingCount': ?ratingCount,
  'slotCounts': ?slots,
};

Position here() => Position(
  latitude: 14.6,
  longitude: 121.0,
  timestamp: DateTime(2026),
  accuracy: 5,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

List<String> ids(List<Map<String, dynamic>> list) => list
    .map((Map<String, dynamic> e) => e['establishmentID'] as String)
    .toList();

List<Map<String, dynamic>> run(
  List<Map<String, dynamic>> all, {
  DriverSortOption sort = DriverSortOption.none,
  String? vehicleType,
  Set<String>? onlyIds,
}) => DriverEstablishmentService.filterAndSort(
  establishments: all,
  searchQuery: '',
  openNowOnly: false,
  sortOption: sort,
  currentPosition: here(),
  vehicleType: vehicleType,
  onlyIds: onlyIds,
);

void main() {
  group('sorting and filtering parking', () {
    final List<Map<String, dynamic>> all = <Map<String, dynamic>>[
      facility(
        'far',
        lat: 14.65,
        rates: <String, Object>{
          'car': <String, Object>{'initial': '30'},
        },
        rating: 4.8,
        ratingCount: 3,
        slots: <String, int>{'car': 40},
      ),
      facility(
        'near',
        lat: 14.601,
        rates: <String, Object>{
          'car': <String, Object>{'initial': '60'},
          'motorcycle': <String, Object>{'initial': '20'},
        },
        rating: 4.8,
        ratingCount: 10,
        slots: <String, int>{'car': 5, 'motorcycle': 10},
      ),
      facility('mid', lat: 14.62, slots: <String, int>{'truck': 2}),
    ];

    test('cheapest uses the lowest base rate; no rate goes last', () {
      expect(ids(run(all, sort: DriverSortOption.cheapest)), <String>[
        'near',
        'far',
        'mid',
      ]);
    });

    test('top rated breaks ties by number of ratings, unrated last', () {
      expect(ids(run(all, sort: DriverSortOption.topRated)), <String>[
        'near',
        'far',
        'mid',
      ]);
    });

    test('most slots counts every vehicle type', () {
      expect(ids(run(all, sort: DriverSortOption.mostSlots)), <String>[
        'far',
        'near',
        'mid',
      ]);
    });

    test('nearest', () {
      expect(ids(run(all, sort: DriverSortOption.nearest)), <String>[
        'near',
        'mid',
        'far',
      ]);
    });

    test('vehicle type keeps only facilities with slots for it', () {
      expect(ids(run(all, vehicleType: 'motorcycle')), <String>['near']);
      expect(ids(run(all, vehicleType: 'truck')), <String>['mid']);
      expect(run(all, vehicleType: 'bus'), isEmpty);
    });

    test('legacy "motor" slots count as motorcycle', () {
      expect(
        DriverEstablishmentService.takesVehicle(<String, dynamic>{
          'slotCounts': <String, int>{'motor': 3},
        }, 'motorcycle'),
        isTrue,
      );
    });

    test('saved only', () {
      expect(ids(run(all, onlyIds: <String>{'far', 'gone'})), <String>['far']);
      expect(run(all, onlyIds: <String>{}), isEmpty);
    });

    test('starting price reads rate maps, plain values and old text', () {
      expect(
        DriverEstablishmentService.startingPrice(<String, dynamic>{
          'ratesByType': <String, Object>{'car': 45, 'motorcycle': '25'},
        }),
        25,
      );
      expect(
        DriverEstablishmentService.startingPrice(<String, dynamic>{
          'pricing': 'PHP 40 for 2 hours',
        }),
        40,
      );
      expect(
        DriverEstablishmentService.startingPrice(<String, dynamic>{}),
        isNull,
      );
    });

    test('capacity falls back to the registration count', () {
      expect(
        DriverEstablishmentService.capacity(<String, dynamic>{
          'slotCounts': <String, int>{'car': 4, 'motorcycle': 6, 'motor': 6},
        }),
        10,
      );
      expect(
        DriverEstablishmentService.capacity(<String, dynamic>{
          'availability': 12,
        }),
        12,
      );
    });

    test('directions go to the pin, else the address', () {
      expect(
        DriverEstablishmentService.directionsUri(
          facility('a', lat: 14.5, lng: 121.1),
        ).toString(),
        'https://www.google.com/maps/dir/?api=1'
        '&destination=14.5,121.1&travelmode=driving',
      );
      expect(
        DriverEstablishmentService.directionsUri(<String, dynamic>{
          'address': 'Ayala Ave, Makati',
        }).toString(),
        contains('destination=Ayala%20Ave%2C%20Makati'),
      );
      expect(
        DriverEstablishmentService.directionsUri(<String, dynamic>{}),
        isNull,
      );
    });
  });

  group('saved and recent parking', () {
    test('saving and un-saving updates the profile', () async {
      final FakeFirebaseFirestore db = FakeFirebaseFirestore();
      await db.collection('users').doc('d1').set(<String, dynamic>{
        'role': 'Driver',
      });
      await DriverFavorites.setSaved('d1', 'e1', saved: true, firestore: db);
      await DriverFavorites.setSaved('d1', 'e2', saved: true, firestore: db);
      await DriverFavorites.setSaved('d1', 'e1', saved: false, firestore: db);
      final Map<String, dynamic>? profile =
          (await db.collection('users').doc('d1').get()).data();
      expect(DriverFavorites.fromProfile(profile), <String>{'e2'});
      expect(profile!['role'], 'Driver');
      expect(await DriverFavorites.watch('d1', firestore: db).first, <String>{
        'e2',
      });
    });

    test('a profile without saved parking has none', () {
      expect(DriverFavorites.fromProfile(null), isEmpty);
      expect(
        DriverFavorites.fromProfile(<String, dynamic>{
          DriverFavorites.field: <Object>['a', 3, ''],
        }),
        <String>{'a'},
      );
    });

    test('recent facilities: newest visit first, one entry each', () {
      Timestamp t(int day) => Timestamp.fromDate(DateTime(2026, 11, day));
      final List<String> recent = recentFacilityIds(<Map<String, dynamic>>[
        <String, dynamic>{'establishmentId': 'a', 'createdAt': t(1)},
        <String, dynamic>{
          'establishmentId': 'b',
          'createdAt': t(2),
          'exitAt': t(10),
        },
        <String, dynamic>{'establishmentId': 'a', 'createdAt': t(5)},
        <String, dynamic>{
          'establishmentId': 'w',
          'source': 'walk_in',
          'createdAt': t(20),
        },
        <String, dynamic>{'establishmentId': '', 'createdAt': t(21)},
      ]);
      expect(recent, <String>['b', 'a']);
      expect(
        recentFacilityIds(<Map<String, dynamic>>[
          for (int i = 1; i <= 8; i++)
            <String, dynamic>{'establishmentId': 'f$i', 'createdAt': t(i)},
        ]),
        <String>['f8', 'f7', 'f6', 'f5', 'f4'],
      );
    });
  });

  group('first-run guide', () {
    testWidgets('shows once, then never again', (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (BuildContext context) => TextButton(
              onPressed: () => DriverGuide.showIfFirstRun(context),
              child: const Text('go'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.text(kDriverGuideSteps.first.title), findsOneWidget);

      // Walk through every step to the end.
      for (int i = 1; i < kDriverGuideSteps.length; i++) {
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
        expect(find.text(kDriverGuideSteps[i].title), findsOneWidget);
      }
      await tester.tap(find.text('Start parking'));
      await tester.pumpAndSettle();
      expect(find.text('go'), findsOneWidget);
      expect(await DriverGuide.seen(), isTrue);

      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.text(kDriverGuideSteps.first.title), findsNothing);
    });

    testWidgets('two callers at once open only one guide', (
      WidgetTester tester,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (BuildContext context) => TextButton(
              onPressed: () {
                // As when the driver home is built twice on first sign-in.
                DriverGuide.showIfFirstRun(context);
                DriverGuide.showIfFirstRun(context);
              },
              child: const Text('go'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.byType(DriverGuidePage), findsOneWidget);
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      // Closed once and gone: no second copy underneath.
      expect(find.byType(DriverGuidePage), findsNothing);
      expect(find.text('go'), findsOneWidget);
    });

    testWidgets('Skip closes it and counts as seen', (
      WidgetTester tester,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (BuildContext context) => TextButton(
              onPressed: () => DriverGuide.showIfFirstRun(context),
              child: const Text('go'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(find.text('go'), findsOneWidget);
      expect(await DriverGuide.seen(), isTrue);
    });

    testWidgets('fits a small phone without overflowing', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const MaterialApp(home: DriverGuidePage()));
      for (int i = 1; i < kDriverGuideSteps.length; i++) {
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('help & FAQ', () {
    testWidgets('lists every question and the support email', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: DriverHelpPage()));
      for (final DriverFaqGroup group in kDriverFaqGroups) {
        await tester.scrollUntilVisible(find.text(group.title), 200);
        for (final DriverFaq faq in group.items) {
          await tester.scrollUntilVisible(find.text(faq.question), 200);
          expect(find.text(faq.question), findsOneWidget);
        }
      }
      await tester.scrollUntilVisible(find.text('Email $kSupportEmail'), 200);
      expect(find.text('Email $kSupportEmail'), findsOneWidget);
    });

    testWidgets('a question opens to its answer', (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: DriverHelpPage()));
      final DriverFaq faq = kDriverFaqGroups.first.items[1];
      await tester.scrollUntilVisible(find.text(faq.question), 200);
      await tester.tap(find.text(faq.question));
      await tester.pumpAndSettle();
      expect(find.text(faq.answer), findsOneWidget);
    });

    test('the help states the same QR lifetime as the terms', () {
      expect(kTemporaryQrValidDays, 3);
      final String terms = termsFor(
        'Driver',
      ).expand((TermsSection s) => s.points).join(' ');
      expect(terms, contains('valid for $kTemporaryQrValidDays days'));
    });
  });
}
