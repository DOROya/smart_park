import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;
import 'package:smart_park/models/facility_registration_data.dart';
import 'package:smart_park/services/gate_cash.dart';
import 'package:smart_park/services/operating_hours.dart';

void main() {
  test('cash supervisors hold, grouped, until the owner receives it', () {
    final List<SupervisorCashHeld> held = cashHeldBySupervisors(
      <({String id, Map<String, dynamic> data})>[
        (id: 'a', data: <String, dynamic>{'receivedBy': 'sup1', 'amount': 40}),
        (id: 'b', data: <String, dynamic>{'receivedBy': 'sup1', 'amount': 10}),
        (id: 'c', data: <String, dynamic>{'receivedBy': 'sup2', 'amount': 90}),
        // The owner's own, and one the owner already has.
        (id: 'd', data: <String, dynamic>{'receivedBy': 'own', 'amount': 5}),
        (
          id: 'e',
          data: <String, dynamic>{
            'receivedBy': 'sup1',
            'amount': 7,
            'ownerReceivedAt': DateTime(2026),
          },
        ),
        // Old receipts without receivedBy were the owner's.
        (id: 'f', data: <String, dynamic>{'amount': 3}),
      ],
      'own',
    );
    expect(held.map((h) => h.supervisorId), <String>['sup2', 'sup1']);
    expect(held[1].handoverIds, <String>['a', 'b']);
    expect(held[1].total, 50);
  });

  group('a new permit expiry date counts as a document change', () {
    FacilityRegistrationData form(DateTime? was, DateTime? now) =>
        FacilityRegistrationData(
          name: 'Lot',
          address: 'Davao',
          hours: const OperatingHours.allDay(),
          policies: '',
          rates: const <String, dynamic>{},
          slots: const <String, int>{'car': 1, 'motorcycle': 1},
          location: const LatLng(7, 125),
          permitExpiresAt: now,
          previousPermitExpiresAt: was,
        );

    test('moved date flags a check on an approved facility', () {
      final FacilityRegistrationData f = form(
        DateTime(2026, 12, 31),
        DateTime(2027, 12, 31),
      );
      expect(f.documentsChanged, isTrue);
      expect(f.flagsDocumentCheck(previousStatus: 'approved'), isTrue);
    });

    test('same day, or no date, is no change', () {
      expect(
        form(
          DateTime(2026, 12, 31),
          DateTime(2026, 12, 31, 8),
        ).documentsChanged,
        isFalse,
      );
      expect(form(DateTime(2026, 12, 31), null).documentsChanged, isFalse);
    });

    test('setting a date for the first time is a change', () {
      expect(form(null, DateTime(2027)).documentsChanged, isTrue);
    });
  });
}
