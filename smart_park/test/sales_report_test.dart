import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_park/services/sales_report.dart';
import 'package:smart_park/services/sales_report_pdf.dart';
import 'package:smart_park/widgets/sp_sales_report_card.dart';

void main() {
  final DateTime now = DateTime(2026, 11, 8, 15);

  final List<SalesEntry> entries = <SalesEntry>[
    SalesEntry(
      at: DateTime(2026, 11, 1, 9),
      grossCentavos: 10000,
      commissionCentavos: 1000,
      processingCentavos: 250,
      payoutCentavos: 8750,
    ),
    SalesEntry(
      at: DateTime(2026, 11, 1, 18),
      grossCentavos: 5000,
      commissionCentavos: 500,
      processingCentavos: 125,
      payoutCentavos: 4375,
    ),
    SalesEntry(
      at: DateTime(2026, 11, 7, 12),
      grossCentavos: 20000,
      commissionCentavos: 2000,
      processingCentavos: 500,
      payoutCentavos: 17500,
    ),
    // Overtime cash: money but not a transaction.
    SalesEntry(at: DateTime(2026, 11, 7, 20), count: 0, cashCentavos: 3000),
    SalesEntry(at: DateTime(2026, 3, 15), grossCentavos: 7000, count: 2),
    SalesEntry(at: DateTime(2025, 12, 31), grossCentavos: 99900),
  ];

  group('SalesReport.daily', () {
    test('has one row per day up to today, with sales summed by day', () {
      final SalesReport report = SalesReport.daily(
        entries,
        DateTime(2026, 11),
        now: now,
      );
      expect(report.rows, hasLength(8));
      expect(report.rows.first.grossCentavos, 15000);
      expect(report.rows.first.count, 2);
      expect(report.rows[6].grossCentavos, 20000);
      expect(report.rows[6].cashCentavos, 3000);
      expect(report.rows[6].count, 1);
      expect(report.rows[2].isEmpty, isTrue);
      expect(report.totals.grossCentavos, 35000);
      expect(report.totals.payoutCentavos, 30625);
      expect(report.totals.count, 3);
      expect(report.bestRow!.start, DateTime(2026, 11, 7));
      expect(report.averageGrossCentavos, 17500);
      expect(report.periodLabel, 'November 2026');
      expect(report.fileName, 'SmartPark-Daily-Sales-2026-11.pdf');
    });

    test('covers the whole of a past month', () {
      final SalesReport report = SalesReport.daily(
        entries,
        DateTime(2026, 2),
        now: now,
      );
      expect(report.rows, hasLength(28));
      expect(report.totals.grossCentavos, 0);
      expect(report.bestRow, isNull);
    });

    test('ignores the same day number in another month or year', () {
      final SalesReport report = SalesReport.daily(
        entries,
        DateTime(2025, 12),
        now: now,
      );
      expect(report.rows, hasLength(31));
      expect(report.rows.last.grossCentavos, 99900);
      expect(report.totals.grossCentavos, 99900);
    });
  });

  group('SalesReport.monthly', () {
    test('has one row per month up to this month', () {
      final SalesReport report = SalesReport.monthly(entries, 2026, now: now);
      expect(report.rows, hasLength(11));
      expect(report.rows[2].grossCentavos, 7000);
      expect(report.rows[2].count, 2);
      expect(report.rows[10].grossCentavos, 35000);
      expect(report.totals.grossCentavos, 42000);
      expect(report.rowLabel(report.rows[10]), 'November');
      expect(report.fileName, 'SmartPark-Monthly-Sales-2026.pdf');
    });

    test('shows all twelve months of a past year', () {
      final SalesReport report = SalesReport.monthly(entries, 2025, now: now);
      expect(report.rows, hasLength(12));
      expect(report.totals.grossCentavos, 99900);
    });
  });

  test('formatSalesPeso groups thousands', () {
    expect(formatSalesPeso(0), 'PHP 0.00');
    expect(formatSalesPeso(5), 'PHP 0.05');
    expect(formatSalesPeso(123456789), 'PHP 1,234,567.89');
    expect(formatSalesPeso(100000), 'PHP 1,000.00');
    expect(formatSalesPeso(-25050), '-PHP 250.50');
  });

  test('pdfSafeText keeps Latin-1 and plainifies the rest', () {
    expect(pdfSafeText('Peña’s Lot – Main 🚗'), "Peña's Lot - Main");
    expect(pdfSafeText('Juan|Cruz'), 'Juan|Cruz');
  });

  test('builds a PDF for both audiences', () async {
    for (final SalesReportAudience audience in SalesReportAudience.values) {
      final Uint8List bytes = await buildSalesReportPdf(
        report: SalesReport.daily(entries, DateTime(2026, 11), now: now),
        audience: audience,
        scopeLabel: 'Peña’s Lot 🚗',
        preparedBy: 'Juan dela Cruz',
        generatedAt: now,
      );
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    }
  });

  testWidgets('card switches between daily and monthly and steps periods', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SpSalesReportCard(
              entries: entries,
              audience: SalesReportAudience.owner,
              scopeLabel: 'Test Lot',
              preparedBy: 'Owner',
              now: now,
            ),
          ),
        ),
      ),
    );

    expect(find.text('November 2026'), findsOneWidget);
    // Only days with sales are listed.
    expect(find.text('Nov 7, Sat'), findsOneWidget);
    expect(find.text('Nov 1, Sun'), findsOneWidget);
    expect(find.text('Nov 3, Tue'), findsNothing);
    expect(find.text('1 txn · + PHP 30.00 cash'), findsOneWidget);
    // Can't step into the future.
    final IconButton next = tester.widget(
      find.widgetWithIcon(IconButton, Icons.chevron_right_rounded),
    );
    expect(next.onPressed, isNull);

    await tester.tap(find.byTooltip('Previous month'));
    await tester.pump();
    expect(find.text('October 2026'), findsOneWidget);
    expect(find.text('No sales in October 2026.'), findsOneWidget);

    await tester.tap(find.text('Monthly'));
    await tester.pump();
    expect(find.text('2026'), findsOneWidget);
    expect(find.text('March'), findsOneWidget);
    expect(find.text('PHP 420.00'), findsOneWidget);

    await tester.tap(find.byTooltip('Previous year'));
    await tester.pump();
    expect(find.text('2025'), findsOneWidget);
    // 2025 is the earliest year with sales.
    final IconButton back = tester.widget(
      find.widgetWithIcon(IconButton, Icons.chevron_left_rounded),
    );
    expect(back.onPressed, isNull);
  });
}
