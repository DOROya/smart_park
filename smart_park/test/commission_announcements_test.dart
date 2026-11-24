import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_park/services/announcements.dart';
import 'package:smart_park/services/platform_fees.dart';

void main() {
  final DateTime now = DateTime(2026, 11, 23);

  test('the rate in force matches the server: pending only from its date', () {
    final Map<String, dynamic> settings = <String, dynamic>{
      'commissionRate': 0.05,
      'pendingRate': 0.07,
      'pendingEffectiveAt': Timestamp.fromDate(DateTime(2027, 1, 1)),
    };
    final PlatformCommissionSettings before = PlatformCommissionSettings.of(
      settings,
      now: now,
    );
    expect(before.currentRate, 0.05);
    expect(before.hasPending, isTrue);
    final PlatformCommissionSettings after = PlatformCommissionSettings.of(
      settings,
      now: DateTime(2027, 1, 2),
    );
    expect(after.currentRate, 0.07);
    expect(after.hasPending, isFalse);
    expect(PlatformCommissionSettings.of(null).currentRate, kPlatformFeeRate);
  });

  test('a sale keeps its own rate; older sales were 5%', () {
    expect(platformFeeCentavosFor(10000), 500);
    expect(platformFeeCentavosFor(10000, rate: 0.07), 700);
    expect(saleCommissionRate(<String, dynamic>{'commissionRate': 0.07}), 0.07);
    expect(saleCommissionRate(<String, dynamic>{}), kPlatformFeeRate);
    expect(commissionPercent(0.075), '7.5%');
    expect(commissionPercent(0.05), '5%');
  });

  test('announcements pop up once; a rate change until acknowledged', () {
    final Announcement general = Announcement(
      id: 'g',
      title: 'Hi',
      body: '',
      kind: 'general',
      createdAt: DateTime(2026, 11, 1),
    );
    final Announcement change = Announcement(
      id: 'c',
      title: 'Rate',
      body: '',
      kind: 'commission_change',
      createdAt: DateTime(2026, 11, 2),
      effectiveAt: DateTime(2027, 1, 1),
    );
    // Never seen: both, oldest first.
    expect(
      announcementsToShow(
        <Announcement>[change, general],
        {},
        now: now,
      ).map((Announcement a) => a.id),
      <String>['g', 'c'],
    );
    // Seen but not acknowledged: only the rate change comes back.
    final Map<String, Map<String, dynamic>> seen = {
      'g': <String, dynamic>{'seenAt': 1},
      'c': <String, dynamic>{'seenAt': 1},
    };
    expect(
      announcementsToShow(
        <Announcement>[change, general],
        seen,
        now: now,
      ).map((Announcement a) => a.id),
      <String>['c'],
    );
    // Acknowledged, or past its date: neither.
    expect(
      announcementsToShow(
        <Announcement>[change],
        {
          'c': <String, dynamic>{'acknowledged': true},
        },
        now: now,
      ),
      isEmpty,
    );
    expect(
      announcementsToShow(
        <Announcement>[change],
        seen,
        now: DateTime(2027, 2, 1),
      ),
      isEmpty,
    );
    expect(audienceForRole('Parking Owner'), 'owners');
    expect(audienceForRole('supervisor'), 'staff');
  });
}
