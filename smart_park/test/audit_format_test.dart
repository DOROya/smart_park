import 'package:flutter_test/flutter_test.dart';
import 'package:smart_park/widgets/sp_audit_format.dart';

void main() {
  group('audit field labels', () {
    test('known fields use the form names', () {
      expect(spAuditFieldLabel('gracePeriodMinutes'), 'Grace period');
      expect(spAuditFieldLabel('contactNumber'), 'Contact number');
      expect(spAuditFieldLabel('photoUrls'), 'Photos');
    });

    test('rate and slot paths name the vehicle', () {
      expect(spAuditFieldLabel('rates.car.initial'), 'Car base rate');
      expect(
        spAuditFieldLabel('ratesByType.motorcycle.succeedingHour'),
        'Motorcycle rate per extra hour',
      );
      expect(spAuditFieldLabel('slotCounts.mini_bus'), 'Mini Bus slots');
    });

    test('unknown fields are split into words', () {
      expect(spAuditFieldLabel('plateNumber'), 'Plate number');
      expect(spAuditFieldLabel('complianceNotice.dueAt'), 'Notice due by');
    });

    test('labels the server already made readable stay', () {
      expect(spAuditFieldLabel('Car daily rate'), 'Car daily rate');
    });
  });

  group('audit values', () {
    test('JSON text becomes words', () {
      expect(
        spAuditValueText('{"car":20,"motorcycle":10}', field: 'slotCounts'),
        'Car: 20, Motorcycle: 10',
      );
      expect(
        spAuditValueText(
          '{"car":{"initial":"40","succeedingHour":"20"}}',
          field: 'rates',
        ),
        'Car (Base rate: PHP 40, Rate per extra hour: PHP 20)',
      );
      expect(
        spAuditValueText('["Blocked exits","No permit"]', field: 'reasons'),
        'Blocked exits, No permit',
      );
    });

    test('photo lists are counted, not printed', () {
      expect(
        spAuditValueText(
          '["https://a.example/1.jpg","https://a.example/2.jpg"]',
          field: 'photoUrls',
        ),
        '2 photos',
      );
    });

    test('plain values', () {
      expect(spAuditValueText(null), 'none');
      expect(spAuditValueText(''), 'none');
      expect(spAuditValueText(true), 'Yes');
      expect(spAuditValueText(15, field: 'gracePeriodMinutes'), '15 minutes');
      expect(spAuditValueText('08:00', field: 'openTime'), '8:00 AM');
      expect(spAuditValueText('approved', field: 'status'), 'Approved');
      expect(spAuditValueText(12550, field: 'amountCentavos'), 'PHP 125.50');
      expect(spAuditValueText('PHP 250'), 'PHP 250');
    });

    test('JSON cut short by the server is still readable', () {
      expect(
        spAuditValueText('{"car":{"initial":"40","succ...', field: 'rates'),
        isNot(contains('"')),
      );
    });

    test('a change reads from -> to', () {
      expect(
        spAuditChangeText('gracePeriodMinutes', <String, dynamic>{
          'from': 10,
          'to': 15,
        }),
        '10 minutes  →  15 minutes',
      );
    });
  });

  group('audit changes shown', () {
    test('ids, bookkeeping and repeats are hidden', () {
      final List<String> shown = spAuditVisibleChanges(<String, dynamic>{
        'establishmentID': <String, dynamic>{'from': null, 'to': 'x'},
        'latitude': <String, dynamic>{'from': 1, 'to': 2},
        'location': <String, dynamic>{'from': '1, 2', 'to': '3, 4'},
        'openTime': <String, dynamic>{'from': '08:00', 'to': '09:00'},
        'operatingHours': <String, dynamic>{'from': 'a', 'to': 'b'},
        'name': <String, dynamic>{'from': 'A', 'to': 'B'},
      }).map((MapEntry<String, Object?> e) => e.key).toList();
      expect(shown, <String>['name', 'location', 'operatingHours']);
    });
  });

  group('audit summaries', () {
    test('a trailing field list is put in words', () {
      expect(
        spAuditSummaryText(
          'facility.details_updated',
          'Edited facility details (slotCounts, gracePeriodMinutes)',
        ),
        'Edited facility details: slots and grace period',
      );
      expect(
        spAuditSummaryText(
          'facility.updated',
          'Edited the facility listing (closeTime, openTime, operatingHours, '
              'latitude, location)',
        ),
        'Edited the facility listing: operating hours and map pin',
      );
    });

    test('other summaries are left alone', () {
      expect(
        spAuditSummaryText(
          'facility.closed_temporarily',
          'Closed the facility until Nov 24, 10:00 PM (Typhoon)',
        ),
        'Closed the facility until Nov 24, 10:00 PM (Typhoon)',
      );
      expect(
        spAuditSummaryText('facility.approved', 'Approved the facility'),
        'Approved the facility',
      );
    });
  });

  group('created, cleared and id-only changes', () {
    test('a new record shows only its value', () {
      expect(
        spAuditChangeText('walkInAmount', <String, dynamic>{
          'from': null,
          'to': 30,
        }),
        'PHP 30.00',
      );
      expect(
        spAuditChangeText('staffName', <String, dynamic>{
          'from': null,
          'to': 'Juan Dela Cruz',
        }),
        'Juan Dela Cruz',
      );
    });

    test('a cleared value says removed', () {
      expect(
        spAuditChangeText('closedReason', <String, dynamic>{
          'from': 'Typhoon',
          'to': null,
        }),
        'Typhoon  →  removed',
      );
    });

    test('ids, staff sign-in addresses and empty changes are hidden', () {
      final List<String> shown = spAuditVisibleChanges(<String, dynamic>{
        'amount': <String, dynamic>{'from': null, 'to': 30},
        'receivedBy': <String, dynamic>{
          'from': null,
          'to': '3028hHByKZbq6nbw3wnO0tD7f253',
        },
        'ownerId': <String, dynamic>{'from': null, 'to': 'abc'},
        'staffId': <String, dynamic>{'from': null, 'to': 'abc'},
        'userId': <String, dynamic>{'from': null, 'to': 'abc'},
        'closedBy': <String, dynamic>{'from': 'abc', 'to': null},
        'receivedAt': <String, dynamic>{
          'from': null,
          'to': '2026-11-24T12:36:43.912Z',
        },
        'email': <String, dynamic>{
          'from': null,
          'to': 'e6zfa_juan@staff.smartpark.internal',
        },
        'closedReason': <String, dynamic>{'from': '', 'to': null},
        'staffName': <String, dynamic>{'from': null, 'to': 'Juan Dela Cruz'},
      }).map((MapEntry<String, Object?> e) => e.key).toList();
      expect(shown, <String>['staffName', 'amount']);
    });

    test('cash handover fields read in words', () {
      expect(spAuditFieldLabel('walkInAmount'), 'Walk-in cash');
      expect(spAuditFieldLabel('logCount'), 'Gate records');
      expect(spAuditValueText(0, field: 'overtimeAmount'), 'PHP 0.00');
    });

    test('roles read as the app names them', () {
      expect(spAuditValueText('supervisor', field: 'role'), 'Supervisor');
      expect(spAuditValueText('super', field: 'adminLevel'), 'Super admin');
    });

    test('old summaries get the right article', () {
      expect(
        spAuditSummaryText('admin.promoted', 'Made Isaiah Calamba a admin'),
        'Made Isaiah Calamba an admin',
      );
      expect(
        spAuditSummaryText('admin.promoted', 'Made Vince a super admin'),
        'Made Vince a super admin',
      );
    });
  });

  group('detail lines', () {
    final DateTime at = DateTime.utc(2026, 11, 25, 8, 3, 28);

    test('lines that repeat the headline or the time are dropped', () {
      final List<SpAuditLine> lines = spAuditLines(
        <String, dynamic>{
          'active': <String, dynamic>{'from': null, 'to': false},
          'deactivatedAt': <String, dynamic>{
            'from': null,
            'to': '2026-11-25T08:03:28.234Z',
          },
        },
        action: 'staff.deactivated',
        at: at,
      );
      expect(lines, isEmpty);
    });

    test('cleared, created and changed values are told apart', () {
      final List<SpAuditLine> lines = spAuditLines(<String, dynamic>{
        'closedReason': <String, dynamic>{'from': 'Typhoon', 'to': null},
        'closedAt': <String, dynamic>{
          'from': '2026-11-25T07:38:50Z',
          'to': null,
        },
        'name': <String, dynamic>{'from': null, 'to': 'Juliville Parking'},
        'status': <String, dynamic>{'from': 'open', 'to': 'dismissed'},
      }, at: at);
      expect(lines.map((SpAuditLine l) => l.label), <String>[
        'Name',
        'Status',
        'Reason for closing',
      ]);
      expect(lines[0].before, isNull);
      expect(lines[1].before, 'Open');
      expect(lines[1].value, 'Dismissed');
      expect(lines[2].cleared, isTrue);
      expect(lines[2].value, 'Typhoon');
    });
  });
}
