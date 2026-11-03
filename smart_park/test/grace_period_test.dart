import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;
import 'package:smart_park/models/facility_registration_data.dart';
import 'package:smart_park/services/operating_hours.dart';
import 'package:smart_park/services/parking_pricing.dart';

void main() {
  group('grace period', () {
    test(
      'no overtime within it, then every started hour from the paid end',
      () {
        // 2 paid hours, 20 minutes grace.
        Duration stay(int h, int m) => Duration(hours: h, minutes: m);
        expect(overtimeHours(stay(2, 20), 2, graceMinutes: 20), 0);
        expect(overtimeHours(stay(2, 21), 2, graceMinutes: 20), 1);
        expect(overtimeHours(stay(3, 0), 2, graceMinutes: 20), 1);
        expect(overtimeHours(stay(3, 25), 2, graceMinutes: 20), 2);
        // Without one, the first minute over is billed.
        expect(overtimeHours(stay(2, 1), 2), 1);
      },
    );

    test('only covers time past the paid hours', () {
      expect(
        withinGrace(const Duration(hours: 1), 2, graceMinutes: 20),
        isFalse,
      );
      expect(
        withinGrace(const Duration(hours: 2, minutes: 10), 2, graceMinutes: 20),
        isTrue,
      );
      expect(
        withinGrace(const Duration(hours: 2, minutes: 30), 2, graceMinutes: 20),
        isFalse,
      );
      expect(withinGrace(const Duration(hours: 2, minutes: 10), 2), isFalse);
    });

    test('overtime starts the first minute past the grace', () {
      final DateTime entry = DateTime(2026, 11, 3, 9);
      expect(
        overtimeStartsAt(entry, 2, graceMinutes: 20),
        DateTime(2026, 11, 3, 11, 21),
      );
    });

    test('comes from the facility, 20 minutes when none was picked', () {
      expect(facilityGraceMinutes(null), 20);
      expect(facilityGraceMinutes(<String, dynamic>{}), 20);
      expect(
        facilityGraceMinutes(<String, dynamic>{'gracePeriodMinutes': 30}),
        30,
      );
      expect(
        facilityGraceMinutes(<String, dynamic>{'gracePeriodMinutes': 0}),
        0,
      );
      // Out-of-range values are held to 0-60.
      expect(
        facilityGraceMinutes(<String, dynamic>{'gracePeriodMinutes': 500}),
        60,
      );
      expect(kGracePeriodOptions, contains(kDefaultGraceMinutes));
    });

    test('reads in words', () {
      expect(formatGracePeriod(20), '20-minute grace period');
      expect(formatGracePeriod(0), 'no grace period');
      expect(graceOptionLabel(15), '15 minutes');
      expect(graceOptionLabel(0), 'None');
    });

    test('is saved with the facility details', () {
      final FacilityRegistrationData data = FacilityRegistrationData(
        name: 'Lot',
        address: 'Davao',
        hours: const OperatingHours.allDay(),
        policies: '',
        rates: const <String, dynamic>{},
        slots: const <String, int>{'car': 1, 'motorcycle': 1},
        location: const LatLng(7, 125),
        gracePeriodMinutes: 30,
      );
      expect(
        data.toEstablishmentDetailsFirestore(
          establishmentId: 'e1',
        )['gracePeriodMinutes'],
        30,
      );
    });
  });
}
