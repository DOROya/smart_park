import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_park/services/gate_cash.dart';
import 'package:smart_park/services/sales_report.dart';
import 'package:smart_park/services/sales_report_excel.dart';
import 'package:smart_park/services/sales_report_summary.dart';

void main() {
  final FinanceRange november = FinanceRange.containing(
    FinancePeriod.month,
    DateTime(2026, 11, 15),
  );

  final List<SalesEntry> entries = <SalesEntry>[
    // One app sale: PHP 100 gross, PHP 85 to the owner.
    SalesEntry(
      at: DateTime(2026, 11, 3, 9),
      grossCentavos: 10000,
      commissionCentavos: 1000,
      processingCentavos: 500,
      payoutCentavos: 8500,
    ),
    ...gateCashSalesEntries(
      <Map<String, dynamic>>[
        // Two walk-in exits with a fee, one entry scan (no fee).
        <String, dynamic>{
          'source': 'walk_in',
          'scanType': 'exit',
          'walkInFee': 40,
          'timestamp': Timestamp.fromDate(DateTime(2026, 11, 3, 18)),
        },
        <String, dynamic>{
          'source': 'walk_in',
          'scanType': 'exit',
          'walkInFee': 60.5,
          'timestamp': Timestamp.fromDate(DateTime(2026, 11, 4, 8)),
        },
        <String, dynamic>{
          'source': 'walk_in',
          'scanType': 'entry',
          'walkInFee': 99,
          'timestamp': Timestamp.fromDate(DateTime(2026, 11, 4, 9)),
        },
      ],
      <Map<String, dynamic>>[
        <String, dynamic>{
          'amount': 100.5,
          'receivedAt': Timestamp.fromDate(DateTime(2026, 11, 4, 20)),
        },
      ],
    ),
  ];

  test('walk-in exits and handovers land in the sales report', () {
    final SalesReport report = SalesReport.forRange(
      entries,
      november,
      now: DateTime(2026, 11, 30),
    );
    final SalesRow t = report.totals;
    expect(t.count, 1, reason: 'walk-ins are not app transactions');
    expect(t.walkInCount, 2);
    expect(t.walkInCentavos, 10050);
    expect(t.handoverCentavos, 10050);
    expect(t.takingsCentavos, 10000 + 10050);
    expect(t.takeHomeCentavos, 8500 + 10050);
    expect(report.rows[2].walkInCount, 1); // Nov 3
    expect(report.rows[3].walkInCentavos, 6050); // Nov 4
    expect(report.rows[3].handoverCentavos, 10050);
  });

  test('the summary names walk-ins and handovers', () {
    final SalesReport report = SalesReport.forRange(
      entries,
      november,
      now: DateTime(2026, 11, 30),
    );
    final List<String> labels = salesMetrics(
      report,
      null,
      SalesReportAudience.owner,
    ).map((SalesMetric m) => m.label).toList();
    expect(labels, contains('Walk-in cash'));
    expect(labels, contains('Gate cash handed over by staff'));
  });

  test('the Excel file still builds with the new columns', () {
    final SalesReport report = SalesReport.forRange(
      entries,
      november,
      now: DateTime(2026, 11, 30),
    );
    expect(
      buildSalesReportXlsx(
        report: report,
        audience: SalesReportAudience.owner,
        scopeLabel: 'Test facility',
        preparedBy: 'Tester',
      ),
      isNotEmpty,
    );
  });
}
