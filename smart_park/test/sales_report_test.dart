import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_park/services/sales_report.dart';
import 'package:smart_park/services/sales_report_pdf.dart';
import 'package:smart_park/widgets/smartpark_ui.dart' show spPeso;
import 'package:smart_park/widgets/sp_sales_report_card.dart';

// Sunday, November 8, 2026.
final DateTime now = DateTime(2026, 11, 8, 15);

final List<SalesEntry> entries = <SalesEntry>[
  SalesEntry(
    at: DateTime(2026, 11, 1, 9),
    grossCentavos: 10000,
    commissionCentavos: 500,
    processingCentavos: 200,
    payoutCentavos: 9300,
  ),
  SalesEntry(
    at: DateTime(2026, 11, 1, 18),
    grossCentavos: 5000,
    commissionCentavos: 250,
    processingCentavos: 100,
    payoutCentavos: 4650,
  ),
  SalesEntry(
    at: DateTime(2026, 11, 7, 12),
    grossCentavos: 20000,
    commissionCentavos: 1000,
    processingCentavos: 400,
    payoutCentavos: 18600,
  ),
  // Overtime cash: money but not a transaction.
  SalesEntry(at: DateTime(2026, 11, 7, 20), count: 0, cashCentavos: 3000),
  SalesEntry(
    at: DateTime(2026, 3, 15),
    count: 2,
    grossCentavos: 7000,
    commissionCentavos: 350,
  ),
  SalesEntry(
    at: DateTime(2025, 12, 31),
    grossCentavos: 99900,
    commissionCentavos: 4995,
  ),
];

FinanceRange rangeOf(FinancePeriod p, DateTime d) =>
    FinanceRange.containing(p, d);

void main() {
  group('FinanceRange', () {
    test('a week runs Monday to Sunday', () {
      final FinanceRange week = rangeOf(FinancePeriod.week, now);
      expect(week.start, DateTime(2026, 11, 2));
      expect(week.end, DateTime(2026, 11, 9));
      expect(week.label, 'Nov 2 - 8, 2026');
      expect(week.step(-1).label, 'Oct 26 - Nov 1, 2026');
      expect(
        rangeOf(FinancePeriod.week, DateTime(2027, 1, 1)).label,
        'Dec 28, 2026 - Jan 3, 2027',
      );
      expect(week.breakdown, SalesBreakdown.daily);
    });

    test('months, quarters and years step across year ends', () {
      final FinanceRange month = rangeOf(FinancePeriod.month, now);
      expect(month.label, 'November 2026');
      expect(month.step(2).label, 'January 2027');
      final FinanceRange quarter = rangeOf(FinancePeriod.quarter, now);
      expect(quarter.label, 'Q4 2026');
      expect(quarter.months, 'Oct - Dec');
      expect(quarter.step(-4).label, 'Q4 2025');
      expect(quarter.breakdown, SalesBreakdown.monthly);
      expect(rangeOf(FinancePeriod.year, now).step(-1).label, '2025');
    });

    test('contains covers the whole last day', () {
      final FinanceRange month = rangeOf(FinancePeriod.month, now);
      expect(month.contains(DateTime(2026, 11, 30, 23, 59)), isTrue);
      expect(month.contains(DateTime(2026, 12, 1)), isFalse);
      expect(month.contains(DateTime(2026, 10, 31, 23, 59)), isFalse);
    });
  });

  group('SalesReport.forRange', () {
    test('a month has a row per day up to today', () {
      final SalesReport report = SalesReport.forRange(
        entries,
        rangeOf(FinancePeriod.month, now),
        now: now,
      );
      expect(report.rows, hasLength(8));
      expect(report.rows.first.grossCentavos, 15000);
      expect(report.rows.first.count, 2);
      expect(report.rows[6].cashCentavos, 3000);
      expect(report.rows[6].count, 1);
      expect(report.totals.grossCentavos, 35000);
      expect(report.totals.payoutCentavos, 32550);
      expect(report.totals.count, 3);
      expect(
        report.bestBy((SalesRow r) => r.grossCentavos)!.start,
        DateTime(2026, 11, 7),
      );
    });

    test('a week only counts its own seven days', () {
      final SalesReport report = SalesReport.forRange(
        entries,
        rangeOf(FinancePeriod.week, now),
        now: now,
      );
      expect(report.rows, hasLength(7));
      expect(report.totals.grossCentavos, 20000);
      expect(report.totals.cashCentavos, 3000);
    });

    test('a quarter has a row per month up to this month', () {
      final SalesReport report = SalesReport.forRange(
        entries,
        rangeOf(FinancePeriod.quarter, now),
        now: now,
      );
      expect(report.rows, hasLength(2));
      expect(report.rowLabel(report.rows.last), 'November');
      expect(report.totals.grossCentavos, 35000);
    });

    test('a year has a row per month, all twelve once it is over', () {
      final SalesReport thisYear = SalesReport.forRange(
        entries,
        rangeOf(FinancePeriod.year, now),
        now: now,
      );
      expect(thisYear.rows, hasLength(11));
      expect(thisYear.rows[2].count, 2);
      expect(thisYear.totals.grossCentavos, 42000);

      final SalesReport lastYear = SalesReport.forRange(
        entries,
        rangeOf(FinancePeriod.year, DateTime(2025, 6)),
        now: now,
      );
      expect(lastYear.rows, hasLength(12));
      expect(lastYear.totals.commissionCentavos, 4995);
    });

    test('a past month is complete and can be empty', () {
      final SalesReport report = SalesReport.forRange(
        entries,
        rangeOf(FinancePeriod.month, DateTime(2026, 2)),
        now: now,
      );
      expect(report.rows, hasLength(28));
      expect(report.totals.isEmpty, isTrue);
      expect(report.bestBy((SalesRow r) => r.grossCentavos), isNull);
    });
  });

  test('formatSalesPeso groups thousands', () {
    expect(formatSalesPeso(0), 'PHP 0.00');
    expect(formatSalesPeso(5), 'PHP 0.05');
    expect(formatSalesPeso(123456789), 'PHP 1,234,567.89');
    expect(formatSalesPeso(-25050), '-PHP 250.50');
  });

  test('spPeso matches the report format everywhere in the app', () {
    expect(spPeso(3630), 'PHP 3,630.00');
    expect(spPeso(27.9), 'PHP 27.90');
    expect(spPeso(0.1 + 0.2), 'PHP 0.30');
  });

  test('pdfSafeText keeps Latin-1 and plainifies the rest', () {
    expect(pdfSafeText('Peña’s Lot – Main 🚗'), "Peña's Lot - Main");
  });

  test('report titles and file names follow the period and audience', () {
    final SalesReport quarter = SalesReport.forRange(
      entries,
      rangeOf(FinancePeriod.quarter, now),
      now: now,
    );
    expect(
      salesReportTitle(quarter, SalesReportAudience.owner),
      'Quarterly Sales Report',
    );
    expect(
      salesReportTitle(quarter, SalesReportAudience.platform),
      'Quarterly Commission Report',
    );
    expect(salesReportPeriod(quarter), 'Q4 2026 (Oct - Dec)');
    expect(
      salesReportFileName(quarter, SalesReportAudience.platform),
      'SmartPark-Commission-2026-Q4.pdf',
    );
  });

  test('builds a PDF for every period and both audiences', () async {
    for (final FinancePeriod period in FinancePeriod.values) {
      for (final SalesReportAudience audience in SalesReportAudience.values) {
        final Uint8List bytes = await buildSalesReportPdf(
          report: SalesReport.forRange(entries, rangeOf(period, now), now: now),
          audience: audience,
          scopeLabel: 'Peña’s Lot 🚗',
          preparedBy: 'Juan dela Cruz',
          generatedAt: now,
        );
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      }
    }
  });

  testWidgets('period bar drives the breakdown card', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: _Harness())),
    );

    expect(find.text('November 2026'), findsOneWidget);
    expect(find.text('Daily Sales'), findsOneWidget);
    // Only days with activity are listed.
    expect(find.text('Nov 7, Sat'), findsOneWidget);
    expect(find.text('Nov 3, Tue'), findsNothing);
    expect(find.text('1 txn · + PHP 30.00 cash'), findsOneWidget);
    expect(find.text('Est. payout PHP 186.00'), findsOneWidget);
    // Can't step into the future.
    final IconButton next = tester.widget(
      find.widgetWithIcon(IconButton, Icons.chevron_right_rounded),
    );
    expect(next.onPressed, isNull);

    await tester.tap(find.byTooltip('Previous month'));
    await tester.pump();
    expect(find.text('October 2026'), findsOneWidget);
    expect(find.text('No sales in October 2026.'), findsOneWidget);

    // Switching from a past period lands on its latest part.
    await tester.tap(find.text('Week'));
    await tester.pump();
    expect(find.text('Oct 26 - Nov 1, 2026'), findsOneWidget);
    // That week ends on Nov 1, so its month is November.
    await tester.tap(find.text('Month'));
    await tester.pump();
    expect(find.text('November 2026'), findsOneWidget);

    await tester.tap(find.text('Quarter'));
    await tester.pump();
    expect(find.text('Q4 2026'), findsOneWidget);
    expect(find.text('Oct - Dec'), findsOneWidget);
    expect(find.text('Monthly Sales'), findsOneWidget);

    await tester.tap(find.text('Year'));
    await tester.pump();
    expect(find.text('2026'), findsOneWidget);
    expect(find.text('March'), findsOneWidget);

    await tester.tap(find.byTooltip('Previous year'));
    await tester.pump();
    expect(find.text('2025'), findsOneWidget);
    // 2025 is the earliest year with sales.
    final IconButton back = tester.widget(
      find.widgetWithIcon(IconButton, Icons.chevron_left_rounded),
    );
    expect(back.onPressed, isNull);
  });

  testWidgets('tapping the period opens a picker with Q1 to Q4', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: _Harness())),
    );
    await tester.tap(find.text('Quarter'));
    await tester.pump();
    expect(find.text('Q4 2026'), findsOneWidget);

    await tester.tap(find.text('Q4 2026'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a quarter'), findsOneWidget);
    // Every quarter from the first sale (Dec 2025) up to now.
    expect(find.text('Q1 · Jan - Mar'), findsNWidgets(2));
    final ChoiceChip q3of2025 = tester
        .widgetList<ChoiceChip>(
          find.widgetWithText(ChoiceChip, 'Q3 · Jul - Sep'),
        )
        .last;
    expect(q3of2025.onSelected, isNull);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Q1 · Jan - Mar').first);
    await tester.pumpAndSettle();
    expect(find.text('Q1 2026'), findsOneWidget);
    expect(find.text('Jan - Mar'), findsOneWidget);
    expect(find.text('March'), findsOneWidget);
  });

  testWidgets('switching never lands before the first sale', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: _Harness())),
    );
    await tester.tap(find.text('Year'));
    await tester.pump();
    await tester.tap(find.byTooltip('Previous year'));
    await tester.pump();
    expect(find.text('2025'), findsOneWidget);
    // 2025's only sale is on Dec 31, so its weeks and months start there.
    await tester.tap(find.text('Month'));
    await tester.pump();
    expect(find.text('December 2025'), findsOneWidget);
    await tester.tap(find.text('Week'));
    await tester.pump();
    expect(find.text('Dec 29, 2025 - Jan 4, 2026'), findsOneWidget);
  });

  testWidgets('the month picker skips months still to come', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: _Harness())),
    );
    await tester.tap(find.text('November 2026'));
    await tester.pumpAndSettle();
    final ChoiceChip dec2026 = tester
        .widgetList<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Dec'))
        .first;
    expect(dec2026.onSelected, isNull);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Mar').first);
    await tester.pumpAndSettle();
    expect(find.text('March 2026'), findsOneWidget);
  });

  for (final Size size in const <Size>[Size(1280, 800), Size(800, 1280)]) {
    testWidgets('fits a ${size.width.toInt()}x${size.height.toInt()} tablet', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: _Harness())),
      );
      for (final String p in <String>['Week', 'Month', 'Quarter', 'Year']) {
        await tester.tap(find.text(p));
        await tester.pump();
      }
      await tester.tap(find.text('2026'));
      await tester.pumpAndSettle();
      // The sheet stays phone-width instead of spanning the tablet.
      expect(
        tester
            .getSize(
              find.ancestor(
                of: find.text('Choose a year'),
                matching: find.byType(ListView),
              ),
            )
            .width,
        lessThanOrEqualTo(560),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the admin card shows commission, never gross', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: _Harness(audience: SalesReportAudience.platform)),
      ),
    );
    expect(find.text('Daily Commission'), findsOneWidget);
    // Nov 7: PHP 10.00 commission on PHP 200.00 paid.
    expect(find.text('PHP 10.00'), findsOneWidget);
    expect(find.text('PHP 200.00'), findsNothing);
    expect(find.textContaining('Payout'), findsNothing);
  });
}

/// The period bar and card wired together, as on a Finance tab.
class _Harness extends StatefulWidget {
  const _Harness({this.audience = SalesReportAudience.owner});

  final SalesReportAudience audience;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  FinanceRange range = FinanceRange.containing(FinancePeriod.month, now);

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          SpFinancePeriodBar(
            range: range,
            earliest: DateTime(2025, 12, 31),
            now: now,
            onChanged: (FinanceRange r) => setState(() => range = r),
          ),
          SpSalesReportCard(
            report: SalesReport.forRange(entries, range, now: now),
            audience: widget.audience,
            scopeLabel: 'Test Lot',
            preparedBy: 'Owner',
          ),
        ],
      ),
    );
  }
}
