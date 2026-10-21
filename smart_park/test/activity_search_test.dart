import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_park/widgets/sp_activity_search.dart';

void main() {
  final List<Map<String, dynamic>> logs = <Map<String, dynamic>>[
    <String, dynamic>{
      'vehiclePlate': 'ABC 123',
      'staffId': 's1',
      'transactionId': 'tx9QZ',
    },
    <String, dynamic>{'vehiclePlate': 'abc 123', 'staffId': 's1'},
    <String, dynamic>{'vehiclePlate': 'XYZ 789', 'staffId': 's2'},
  ];
  const List<(String, String)> staff = <(String, String)>[
    ('s1', 'Juan Dela Cruz'),
    ('s2', 'Maria Santos'),
  ];

  group('spActivityMatchesQuery', () {
    test('matches plates ignoring case, spaces and dashes', () {
      expect(spActivityMatchesQuery(logs[0], 'abc-12'), isTrue);
      expect(spActivityMatchesQuery(logs[2], 'abc'), isFalse);
    });

    test('matches staff names and ticket numbers', () {
      expect(
        spActivityMatchesQuery(logs[2], 'maria', <String, String>{
          's2': 'Maria Santos',
        }),
        isTrue,
      );
      expect(spActivityMatchesQuery(logs[0], 'TX9'), isTrue);
      expect(spActivityMatchesQuery(logs[0], ''), isTrue);
    });
  });

  testWidgets('suggests matching plates and staff, and filters on a pick', (
    WidgetTester tester,
  ) async {
    String query = '';
    String? staffFilter;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) => SizedBox(
              width: 360,
              child: SpActivitySearch(
                logs: logs,
                staff: staff,
                query: query,
                onQueryChanged: (String v) => setState(() => query = v),
                staffFilter: staffFilter,
                onStaffFilterChanged: (String? v) =>
                    setState(() => staffFilter = v),
              ),
            ),
          ),
        ),
      ),
    );

    // Empty box: the dropdown lists staff with their scan counts.
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(find.text('STAFF'), findsOneWidget);
    expect(find.text('Juan Dela Cruz'), findsOneWidget);
    expect(find.text('2 scans'), findsOneWidget);

    // Typing narrows it to the plate, both spellings counted together.
    await tester.enterText(find.byType(TextField), 'abc');
    await tester.pumpAndSettle();
    expect(query, 'abc');
    expect(find.text('PLATES'), findsOneWidget);
    expect(find.text('ABC 123'), findsOneWidget);
    expect(find.text('Maria Santos'), findsNothing);

    // Picking a staff member filters to them and clears the text.
    await tester.enterText(find.byType(TextField), 'mar');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Maria Santos'));
    await tester.pumpAndSettle();
    expect(staffFilter, 's2');
    expect(query, '');
    expect(find.text('Scanned by Maria Santos'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
