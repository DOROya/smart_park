import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_park/screens/driver/widgets/add_hours_sheet.dart';
import 'package:smart_park/screens/driver/widgets/rate_facility.dart';
import 'package:smart_park/screens/parking_owner/widgets/owner_ratings_card.dart';

void main() {
  group('add hours', () {
    test('starts at the fewest hours that reach the PHP 20 minimum', () {
      expect(minExtraHours(30), 1);
      expect(minExtraHours(20), 1);
      expect(minExtraHours(15), 2);
      expect(minExtraHours(1), kMaxExtraHours);
    });

    test('only a paid SmartPark ticket can get more hours', () {
      expect(canAddTicketHours(<String, dynamic>{'status': 'paid'}), isTrue);
      expect(
        canAddTicketHours(<String, dynamic>{
          'status': 'paid',
          'source': 'walk_in',
        }),
        isFalse,
      );
      expect(
        canAddTicketHours(<String, dynamic>{'status': 'refunded'}),
        isFalse,
      );
    });

    test('says how it will be paid', () {
      expect(extraHoursPaymentNote('gcash'), contains('saved GCash number'));
      expect(extraHoursPaymentNote('card'), contains('PayMongo'));
      // An older ticket with no saved number uses PayMongo's page.
      expect(
        extraHoursPaymentNote('gcash', savedNumber: false),
        contains('PayMongo'),
      );
    });
  });

  group('ratings', () {
    test('a ticket can be rated once it has been used', () {
      final Map<String, dynamic> used = <String, dynamic>{
        'establishmentId': 'f1',
        'exitAt': DateTime(2026, 11, 20),
      };
      expect(canRateTicket(used), isTrue);
      expect(
        canRateTicket(<String, dynamic>{'establishmentId': 'f1'}),
        isFalse,
      );
      expect(
        canRateTicket(<String, dynamic>{...used, 'source': 'walk_in'}),
        isFalse,
      );
    });

    test(
      'rating once, then changing it keeps when it was first given',
      () async {
        final FakeFirebaseFirestore db = FakeFirebaseFirestore();
        await saveFacilityRating(
          ticketId: 't1',
          establishmentId: 'f1',
          driverId: 'd1',
          stars: 3,
          comment: ' ok ',
          exists: false,
          firestore: db,
        );
        final Map<String, dynamic> first =
            (await db.collection('facility_ratings').doc('d1_f1').get())
                .data()!;
        expect(first['stars'], 3);
        expect(first['comment'], 'ok');
        expect(first['driverId'], 'd1');
        await saveFacilityRating(
          ticketId: 't1',
          establishmentId: 'f1',
          driverId: 'd1',
          stars: 5,
          exists: true,
          firestore: db,
        );
        final Map<String, dynamic> second =
            (await db.collection('facility_ratings').doc('d1_f1').get())
                .data()!;
        expect(second['stars'], 5);
        expect(second['createdAt'], first['createdAt']);
        expect(
          () => saveFacilityRating(
            ticketId: 't1',
            establishmentId: 'f1',
            driverId: 'd1',
            stars: 6,
            exists: true,
            firestore: db,
          ),
          throwsArgumentError,
        );
      },
    );

    test('each driver counts once, with their newest rating', () {
      final List<Map<String, dynamic>> kept = latestRatingPerDriver(
        <Map<String, dynamic>>[
          <String, dynamic>{
            'driverId': 'd1',
            'stars': 2,
            'updatedAt': DateTime(2026, 1, 1),
          },
          <String, dynamic>{
            'driverId': 'd1',
            'stars': 5,
            'updatedAt': DateTime(2026, 3, 1),
          },
          <String, dynamic>{
            'driverId': 'd2',
            'stars': 4,
            'updatedAt': DateTime(2026, 2, 1),
          },
        ],
      );
      expect(kept.map((r) => r['stars']).toList()..sort(), <int>[4, 5]);
      expect(facilityRatingId('d1', 'f1'), 'd1_f1');
    });

    test('the owner sees the average of whole stars', () {
      final ({double average, int count}) r = ratingAverage(
        <Map<String, dynamic>>[
          <String, dynamic>{'stars': 5},
          <String, dynamic>{'stars': 4},
          <String, dynamic>{'stars': 4},
          <String, dynamic>{'stars': 9},
        ],
      );
      expect(r.average, 4.3);
      expect(r.count, 3);
      expect(ratingAverage(<Map<String, dynamic>>[]).count, 0);
    });
  });
}
