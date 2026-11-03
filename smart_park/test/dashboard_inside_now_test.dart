import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_park/theme/app_theme.dart';
import 'package:smart_park/widgets/smartpark_ui.dart';

void main() {
  group('dashboard Inside Now', () {
    final DateTime day = DateTime(2026, 11, 3, 12);
    final SpActivitySummary summary = SpActivitySummary.fromLogs(
      <Map<String, dynamic>>[
        <String, dynamic>{
          'timestamp': day,
          'decision': 'ALLOWED',
          'scanType': 'entry',
          'isActive': true,
        },
        <String, dynamic>{
          'timestamp': day,
          'decision': 'ALLOWED',
          'scanType': 'exit',
        },
      ],
      day,
    );

    testWidgets('shows only Inside Now and links to the rest', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      int opened = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.theme,
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: SpDailyActivityTiles(
                summary: summary,
                insideOnly: true,
                entriesAndExitsLabel: 'History',
                onSeeEntriesAndExits: () => opened++,
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(SpStatTile), findsOneWidget);
      expect(find.text('Inside Now'), findsOneWidget);
      expect(find.text('Daily Entries'), findsNothing);
      expect(find.text('Daily Exits'), findsNothing);
      await tester.tap(find.text("Today's entries and exits in History"));
      expect(opened, 1);
    });
  });
}
