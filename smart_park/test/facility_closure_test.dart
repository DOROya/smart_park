import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_park/services/facility_closure.dart';
import 'package:smart_park/services/operating_hours.dart';
import 'package:smart_park/services/parking_pricing.dart';

void main() {
  final DateTime now = DateTime(2026, 11, 23, 12);

  test('a closure reads from the details until it ends', () {
    final Map<String, dynamic> details = <String, dynamic>{
      'closedUntil': Timestamp.fromDate(now.add(const Duration(hours: 5))),
      'closedAt': Timestamp.fromDate(now.subtract(const Duration(hours: 1))),
      'closedReason': 'Holiday',
    };
    final TemporaryClosure? c = TemporaryClosure.of(details, now: now);
    expect(c, isNotNull);
    expect(c!.reason, 'Holiday');
    expect(c.isActiveAt(now), isTrue);
    // Over once closedUntil passes: the facility reopens by itself.
    expect(
      TemporaryClosure.of(details, now: now.add(const Duration(hours: 6))),
      isNull,
    );
    expect(TemporaryClosure.of(<String, dynamic>{'closedUntil': null}), isNull);
  });

  test('a facility open all day is closed during a closure', () {
    final OperatingHours hours = const OperatingHours.allDay().withClosure(
      now,
      now.add(const Duration(hours: 2)),
    );
    expect(hours.isOpenAt(now.add(const Duration(minutes: 30))), isFalse);
    expect(hours.isOpenAt(now.add(const Duration(hours: 3))), isTrue);
    expect(hours.isOpenAt(now.subtract(const Duration(minutes: 1))), isTrue);
  });

  test('overtime leaves out the closed time, counted once', () {
    // Open 6 AM - 10 PM; closed temporarily 8 PM until 8 AM next day.
    const OperatingHours weekly = OperatingHours(
      openMinutes: 6 * 60,
      closeMinutes: 22 * 60,
    );
    final DateTime from = DateTime(2026, 11, 23, 20);
    final DateTime to = DateTime(2026, 11, 24, 9);
    final OperatingHours hours = weekly.withClosure(
      from,
      DateTime(2026, 11, 24, 8),
    );
    // 8 PM - 8 AM closed (12 h); 8 - 9 AM open.
    expect(closedTimeBetween(from, to, hours), const Duration(hours: 12));
    // Without the closure only the night (10 PM - 6 AM) counts.
    expect(closedTimeBetween(from, to, weekly), const Duration(hours: 8));
  });

  test('a closure ends in the future, within 30 days', () {
    expect(
      closureDenial(now.add(const Duration(days: 1)), '', now: now),
      isNull,
    );
    expect(
      closureDenial(now.subtract(const Duration(minutes: 1)), '', now: now),
      isNotNull,
    );
    expect(
      closureDenial(now.add(const Duration(days: 31)), '', now: now),
      contains('30 days'),
    );
    expect(
      closureDenial(now.add(const Duration(days: 1)), 'x' * 121, now: now),
      isNotNull,
    );
  });
}
