import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;
import 'package:smart_park/models/facility_registration_data.dart';
import 'package:smart_park/services/facility_status.dart';
import 'package:smart_park/services/operating_hours.dart';

FacilityRegistrationData _form({List<String> removedDocs = const <String>[]}) =>
    FacilityRegistrationData(
      name: 'Lot',
      address: 'Davao',
      hours: const OperatingHours.allDay(),
      policies: '',
      rates: const <String, dynamic>{},
      slots: const <String, int>{'car': 1, 'motorcycle': 1},
      location: const LatLng(7, 125),
      removedDocumentUrls: removedDocs,
    );

void main() {
  final FacilityRegistrationData newDocs = _form(removedDocs: <String>['a']);
  final FacilityRegistrationData sameDocs = _form();

  group('changing documents', () {
    test('an approved facility stays open and is flagged for a check', () {
      expect(newDocs.requiresReview(previousStatus: 'approved'), isFalse);
      expect(newDocs.flagsDocumentCheck(previousStatus: 'approved'), isTrue);
    });

    test('a suspended or deactivated one keeps its status, flagged', () {
      for (final String status in <String>['suspended', 'deactivated']) {
        expect(newDocs.requiresReview(previousStatus: status), isFalse);
        expect(newDocs.flagsDocumentCheck(previousStatus: status), isTrue);
      }
    });

    test('a rejected one is resubmitted for review', () {
      expect(newDocs.requiresReview(previousStatus: 'rejected'), isTrue);
      expect(sameDocs.requiresReview(previousStatus: 'rejected'), isTrue);
    });

    test('a pending one, or no new documents, flags nothing', () {
      expect(newDocs.flagsDocumentCheck(previousStatus: 'pending'), isFalse);
      expect(sameDocs.flagsDocumentCheck(previousStatus: 'approved'), isFalse);
      expect(sameDocs.requiresReview(previousStatus: 'approved'), isFalse);
    });
  });

  test('documentsAwaitCheck: flagged and not a pending application', () {
    expect(
      documentsAwaitCheck(<String, dynamic>{
        'status': 'approved',
        'documentsUpdatedAt': DateTime(2026),
      }),
      isTrue,
    );
    expect(
      documentsAwaitCheck(<String, dynamic>{'status': 'approved'}),
      isFalse,
    );
    expect(
      documentsAwaitCheck(<String, dynamic>{
        'status': 'pending',
        'documentsUpdatedAt': DateTime(2026),
      }),
      isFalse,
    );
  });
}
