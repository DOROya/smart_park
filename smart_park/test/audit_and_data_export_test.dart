import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_park/widgets/sp_audit_log.dart';
import 'package:smart_park/widgets/sp_download_data.dart';

void main() {
  group('audit log', () {
    test('actions group by their prefix', () {
      expect(spAuditCategory('facility.approved'), SpAuditCategory.facility);
      expect(
        spAuditCategory('facility.rates_changed'),
        SpAuditCategory.facility,
      );
      expect(
        spAuditCategory('privacy.documents_deleted'),
        SpAuditCategory.facility,
      );
      expect(spAuditCategory('staff.password_reset'), SpAuditCategory.staff);
      expect(spAuditCategory('refund.approved'), SpAuditCategory.refund);
      expect(spAuditCategory('driver.warned'), SpAuditCategory.report);
      expect(spAuditCategory('report.resolved'), SpAuditCategory.report);
      expect(spAuditCategory('account.data_exported'), SpAuditCategory.account);
      expect(
        spAuditCategory('maintenance.stats_rebuilt'),
        SpAuditCategory.maintenance,
      );
      expect(spAuditCategory('something'), SpAuditCategory.other);
      expect(spAuditCategory(''), SpAuditCategory.other);
    });

    test('admin changes group with accounts', () {
      expect(spAuditCategory('admin.promoted'), SpAuditCategory.account);
      expect(spAuditCategory('admin.level_changed'), SpAuditCategory.account);
    });

    test('a facility\'s own business is kept from the admin', () {
      for (final String action in <String>[
        'cash.received',
        'staff.shift_ended',
        'staff.added',
        'staff.password_reset',
        'gate.overtime_status_changed',
        'gate.missed_exit_recorded',
      ]) {
        expect(spAuditIsFacilityInternal(action), isTrue, reason: action);
      }
      for (final String action in <String>[
        'facility.approved',
        'facility.rates_changed',
        'driver.warned',
        'refund.approved',
        'report.dismissed',
        'account.data_exported',
        'admin.promoted',
        '',
      ]) {
        expect(spAuditIsFacilityInternal(action), isFalse, reason: action);
      }
    });

    test('pages hold 10 entries each', () {
      expect(spAuditPageCount(0, 10), 1);
      expect(spAuditPageCount(1, 10), 1);
      expect(spAuditPageCount(10, 10), 1);
      expect(spAuditPageCount(11, 10), 2);
      expect(spAuditPageCount(43, 10), 5);
    });

    test('actions that take something away are severe', () {
      expect(spAuditIsSevere('facility.suspended'), isTrue);
      expect(spAuditIsSevere('staff.deactivated'), isTrue);
      expect(spAuditIsSevere('facility.approved'), isFalse);
      expect(spAuditIsSevere('refund.approved'), isFalse);
    });

    test('actor label shows the role when known', () {
      expect(
        spAuditActorLabel(<String, dynamic>{
          'actorName': 'Ana Cruz',
          'actorRole': 'admin',
        }),
        'Ana Cruz (Admin)',
      );
      expect(spAuditActorLabel(<String, dynamic>{'actorName': 'Ben'}), 'Ben');
      expect(spAuditActorLabel(<String, dynamic>{}), 'Unknown');
      // Older entries logged a supervisor under their sign-in email.
      expect(
        spAuditActorLabel(<String, dynamic>{
          'actorName': 'e6zfa_boss@staff.smartpark.internal',
          'actorRole': 'supervisor',
        }),
        'e6zfa_boss (Supervisor)',
      );
      // A console or script edit by a project member.
      expect(
        spAuditActorLabel(<String, dynamic>{'actorName': 'dev@gmail.com'}),
        'SmartPark team',
      );
    });

    testWidgets('the card names itself for admins and owners', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: <Widget>[
                SpAuditLogCard(admin: true),
                SpAuditLogCard(admin: false),
              ],
            ),
          ),
        ),
      );
      expect(find.text('Audit Log'), findsOneWidget);
      expect(find.text('Change History'), findsOneWidget);
    });
  });

  group('data export', () {
    test('file name carries the date', () {
      expect(
        spDataExportFileName(DateTime(2026, 3, 7)),
        'smartpark-my-data-2026-03-07.json',
      );
    });

    test('bytes are indented JSON that reads back the same', () {
      final Map<String, dynamic> export = <String, dynamic>{
        'format': 'smartpark-data-export/1',
        'tickets': <Object>[
          <String, Object>{'id': 't1', 'amount': 50},
        ],
        'name': 'Señora Peña',
      };
      final String text = utf8.decode(spDataExportBytes(export));
      expect(text, contains('\n  "format"'));
      expect(jsonDecode(text), export);
    });
  });
}
