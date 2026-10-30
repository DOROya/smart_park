import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_park/screens/parking_owner/widgets/facility_review_status_banner.dart';
import 'package:smart_park/services/driver_reports.dart';
import 'package:smart_park/services/facility_status.dart';
import 'package:smart_park/services/staff_incidents.dart';
import 'package:smart_park/theme/app_theme.dart';
import 'package:smart_park/widgets/sp_reason_dropdowns.dart';

const List<String> options = <String>['Late', 'Rude', 'Other'];

/// Hosts the dropdowns with their own state, as the forms do.
class _Host extends StatefulWidget {
  const _Host({this.initial = const <String?>[null]});

  final List<String?> initial;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late List<String?> values = widget.initial;

  @override
  Widget build(BuildContext context) => SpReasonDropdowns(
    options: options,
    values: values,
    onChanged: (List<String?> v) => setState(() => values = v),
  );
}

Future<void> pumpHost(WidgetTester tester, [List<String?>? initial]) =>
    tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.theme,
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: _Host(initial: initial ?? const <String?>[null]),
          ),
        ),
      ),
    );

List<String?> hostValues(WidgetTester tester) =>
    tester.state<_HostState>(find.byType(_Host)).values;

/// The reasons the dropdown at [index] offers.
List<String> offered(WidgetTester tester, int index) => <String>[
  for (final DropdownMenuItem<String> item
      in tester
          .widget<DropdownButton<String>>(
            find.byType(DropdownButton<String>).at(index),
          )
          .items!)
    item.value!,
];

void main() {
  group('SpReasonDropdowns', () {
    testWidgets('starts with one dropdown and no "Add" until one is picked', (
      WidgetTester tester,
    ) async {
      await pumpHost(tester);
      expect(find.byType(DropdownButton<String>), findsOneWidget);
      expect(find.text('Select a reason'), findsOneWidget);
      expect(find.text('Add Another Reason'), findsNothing);

      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rude').last);
      await tester.pumpAndSettle();
      expect(hostValues(tester), <String?>['Rude']);
      expect(find.text('Add Another Reason'), findsOneWidget);
    });

    testWidgets('a new dropdown leaves out reasons already picked', (
      WidgetTester tester,
    ) async {
      await pumpHost(tester, <String?>['Rude']);
      await tester.tap(find.text('Add Another Reason'));
      await tester.pumpAndSettle();
      expect(find.byType(DropdownButton<String>), findsNWidgets(2));
      expect(find.text('Select another reason'), findsOneWidget);
      // No second "Add" while the new one is empty.
      expect(find.text('Add Another Reason'), findsNothing);

      expect(offered(tester, 1), <String>['Late', 'Other']);
      // The first keeps its own pick.
      expect(offered(tester, 0), containsAll(<String>['Rude', 'Late']));
    });

    testWidgets('picking in one dropdown hides it from the others', (
      WidgetTester tester,
    ) async {
      await pumpHost(tester, <String?>['Rude', 'Late']);
      expect(offered(tester, 0), <String>['Rude', 'Other']);
      expect(offered(tester, 1), <String>['Late', 'Other']);
    });

    testWidgets('extra dropdowns can be removed; the first cannot', (
      WidgetTester tester,
    ) async {
      await pumpHost(tester, <String?>['Rude', 'Late']);
      expect(find.byTooltip('Remove this reason'), findsOneWidget);
      await tester.tap(find.byTooltip('Remove this reason'));
      await tester.pumpAndSettle();
      expect(hostValues(tester), <String?>['Rude']);
      expect(find.byTooltip('Remove this reason'), findsNothing);
    });

    testWidgets('offers no "Add" once every reason is picked', (
      WidgetTester tester,
    ) async {
      await pumpHost(tester, <String?>['Rude', 'Late', 'Other']);
      expect(find.text('Add Another Reason'), findsNothing);
      expect(spPickedReasons(hostValues(tester)), <String>[
        'Rude',
        'Late',
        'Other',
      ]);
    });

    test('picked reasons skip empty dropdowns, in order', () {
      expect(spPickedReasons(<String?>['Late', null, 'Other']), <String>[
        'Late',
        'Other',
      ]);
    });
  });

  group('facility restriction reasons', () {
    test('are read as a list, falling back to the single reason', () {
      expect(
        facilityRestrictionReasons(<String, dynamic>{
          'status': 'suspended',
          'restrictionReasons': <String>['A', 'B'],
          'restrictionReason': 'A, B',
        }),
        <String>['A', 'B'],
      );
      expect(
        facilityRestrictionReasons(<String, dynamic>{
          'status': 'deactivated',
          'restrictionReason': 'Facility not operating',
        }),
        <String>['Facility not operating'],
      );
      expect(
        facilityRestrictionReason(<String, dynamic>{
          'status': 'suspended',
          'restrictionReasons': <String>['A', 'B'],
        }),
        'A, B',
      );
    });

    test('are empty when the facility is not pulled', () {
      expect(
        facilityRestrictionReasons(<String, dynamic>{
          'status': 'approved',
          'restrictionReasons': <String>['A'],
        }),
        isEmpty,
      );
      expect(facilityRestrictionReason(null), isNull);
    });
  });

  group('owner banner', () {
    Future<void> pumpBanner(WidgetTester tester, List<String> reasons) =>
        tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.theme,
            home: Scaffold(
              body: FacilityReviewStatusBanner(
                status: 'suspended',
                restrictionReasons: reasons,
              ),
            ),
          ),
        );

    testWidgets('names every picked reason', (WidgetTester tester) async {
      await pumpBanner(tester, <String>['Facility not operating', 'Safety']);
      expect(
        find.text('Reasons: Facility not operating, Safety'),
        findsOneWidget,
      );
    });

    testWidgets('leaves out "Other"', (WidgetTester tester) async {
      await pumpBanner(tester, <String>['Facility not operating', 'Other']);
      expect(find.text('Reason: Facility not operating'), findsOneWidget);
      await pumpBanner(tester, <String>['Other']);
      expect(find.textContaining('Reason'), findsNothing);
    });
  });

  group('report reasons', () {
    late FakeFirebaseFirestore db;
    setUp(() => db = FakeFirebaseFirestore());

    Future<Map<String, dynamic>> report(List<String> reasons) async {
      await submitDriverReport(
        ownerId: 'owner-1',
        establishmentId: 'fac-1',
        establishmentName: 'Mall Parking',
        transactionId: 'tx-1',
        driverId: 'driver-1',
        driverName: 'Ana Reyes',
        reasons: reasons,
        firestore: db,
      );
      return (await db.collection('driver_reports').get()).docs.single.data();
    }

    test('are stored as a list and on one line', () async {
      final Map<String, dynamic> data = await report(<String>[
        'Rude or abusive to staff',
        'Refused to pay overtime cash',
      ]);
      expect(data['reasons'], <String>[
        'Rude or abusive to staff',
        'Refused to pay overtime cash',
      ]);
      expect(
        data['reason'],
        'Rude or abusive to staff, Refused to pay overtime cash',
      );
      expect(reportReasons(data), hasLength(2));
    });

    test('a report needs at least one', () {
      expect(() => report(const <String>[]), throwsArgumentError);
    });

    test('older single-reason reports still read', () {
      expect(reportReasons(<String, dynamic>{'reason': 'Other'}), <String>[
        'Other',
      ]);
      expect(reportReasons(<String, dynamic>{}), isEmpty);
    });

    test('the warning keeps every reason but "Other"', () async {
      final Map<String, dynamic> data = await report(<String>[
        'Rude or abusive to staff',
        'Other',
      ]);
      final String id =
          (await db.collection('driver_reports').get()).docs.single.id;
      await warnDriverForReport(
        adminId: 'admin-1',
        reportId: id,
        report: data,
        message: 'Please be respectful.',
        firestore: db,
      );
      final Map<String, dynamic> warning =
          (await db.collection('driver_warnings').get()).docs.single.data();
      expect(warning['reasons'], <String>['Rude or abusive to staff']);
      expect(warning['reason'], 'Rude or abusive to staff');
    });

    test('flags carry every picked reason', () async {
      await flagIncident(
        staffId: 'staff-1',
        staffName: 'Juan',
        transactionId: 'tx-1',
        ticket: <String, dynamic>{'driverId': 'driver-1'},
        reasons: const <String>['Wrong vehicle type for ticket', 'Other'],
        details: 'Car on a motorcycle ticket.',
        firestore: db,
      );
      final Map<String, dynamic> flag =
          (await db.collection('staff_incidents').get()).docs.single.data();
      expect(reportReasons(flag), <String>[
        'Wrong vehicle type for ticket',
        'Other',
      ]);
    });
  });
}
