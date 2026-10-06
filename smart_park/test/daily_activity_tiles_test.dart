import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_park/theme/app_theme.dart';
import 'package:smart_park/widgets/smartpark_ui.dart';

void main() {
  final DateTime day = DateTime(2026, 10, 6, 12);
  final SpActivitySummary summary = SpActivitySummary.fromLogs(
    <Map<String, dynamic>>[
      <String, dynamic>{
        'timestamp': day,
        'decision': 'ALLOWED',
        'scanType': 'entry',
      },
      <String, dynamic>{
        'timestamp': day,
        'decision': 'DENIED',
        'scanType': 'entry',
      },
    ],
    day,
  );

  Future<void> pumpTiles(WidgetTester tester, {bool singleRow = false}) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    return tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.theme,
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: SpDailyActivityTiles(summary: summary, singleRow: singleRow),
          ),
        ),
      ),
    );
  }

  double tileWidth(WidgetTester tester, String label) => tester
      .getSize(
        find.ancestor(of: find.text(label), matching: find.byType(SpStatTile)),
      )
      .width;

  testWidgets('phone layout: no denied tile, Inside Now spans the row', (
    WidgetTester tester,
  ) async {
    await pumpTiles(tester);

    expect(find.textContaining('Denied'), findsNothing);
    expect(find.byType(SpStatTile), findsNWidgets(3));
    // Denied scans are not counted as entries either.
    expect(summary.entries, 1);
    expect(summary.dayLogs, hasLength(1));

    final double entries = tileWidth(tester, 'Daily Entries');
    final double exits = tileWidth(tester, 'Daily Exits');
    final double inside = tileWidth(tester, 'Inside Now');
    expect(inside, closeTo(entries + 10 + exits, 0.01));
    expect(inside, closeTo(390 - 32, 0.01));
  });

  testWidgets('single-row layout shows three equal tiles', (
    WidgetTester tester,
  ) async {
    await pumpTiles(tester, singleRow: true);

    expect(find.byType(SpStatTile), findsNWidgets(3));
    final double entries = tileWidth(tester, 'Daily Entries');
    expect(tileWidth(tester, 'Inside Now'), closeTo(entries, 0.01));
  });
}
