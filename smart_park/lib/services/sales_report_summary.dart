/// What the PDF and Excel sales reports share: who the report is for, its
/// title and file name, and the figures compared with the period before.
library;

import 'sales_report.dart';

/// Who the report is for, which decides its columns.
enum SalesReportAudience {
  /// A parking owner: their facility's gross, fees, payout and cash.
  owner,

  /// The admin: SmartPark's commission across all facilities. Gross sales
  /// are the owners' business, so the admin's report leaves them out.
  platform,
}

/// e.g. "Monthly Sales Report" or "Quarterly Commission Report".
String salesReportTitle(SalesReport report, SalesReportAudience audience) =>
    '${report.range.adjective} '
    '${audience == SalesReportAudience.owner ? 'Sales' : 'Commission'} Report';

/// e.g. "November 2026", or "Q4 2026 (Oct - Dec)" for a quarter.
String salesReportPeriod(SalesReport report) => report.range.months.isEmpty
    ? report.range.label
    : '${report.range.label} (${report.range.months})';

/// e.g. "SmartPark-Sales-2026-11.pdf" or "...-2026-11.xlsx".
String salesReportFileName(
  SalesReport report,
  SalesReportAudience audience, {
  String extension = 'pdf',
}) =>
    'SmartPark-'
    '${audience == SalesReportAudience.owner ? 'Sales' : 'Commission'}-'
    '${report.range.slug}.$extension';

/// The figure a report ranks rows by: sales for owners, commission for the
/// admin.
int salesHeadline(SalesRow row, SalesReportAudience audience) =>
    audience == SalesReportAudience.owner
    ? row.grossCentavos
    : row.commissionCentavos;

/// "Gross sales" or "Commission".
String salesHeadlineName(SalesReportAudience audience) =>
    audience == SalesReportAudience.owner ? 'Gross sales' : 'Commission';

/// Days with activity ("days") or months ("months"), for wording.
String salesRowNoun(SalesReport report, {bool plural = true}) =>
    report.breakdown == SalesBreakdown.daily
    ? (plural ? 'days' : 'day')
    : (plural ? 'months' : 'month');

/// Rows with any activity.
int salesActiveRows(SalesReport report) =>
    report.rows.where((SalesRow r) => !r.isEmpty).length;

/// How a [SalesMetric] is written.
enum SalesUnit { money, count }

/// One line of the period comparison.
class SalesMetric {
  const SalesMetric(
    this.label,
    this.current,
    this.previous, {
    this.unit = SalesUnit.money,
    this.neutral = false,
  });

  final String label;
  final int current;

  /// The same figure for the period before; null when there is none.
  final int? previous;
  final SalesUnit unit;

  /// A cost or derived figure, where up is not simply good: its change is
  /// shown without green or red.
  final bool neutral;

  int? get change => previous == null ? null : current - previous!;

  /// Relative change, e.g. 0.125 for +12.5%; null without a base.
  double? get ratio => salesChange(current, previous);
}

/// Relative change from [previous] to [current]; null when [previous] is
/// missing or zero.
double? salesChange(int current, int? previous) =>
    previous == null || previous == 0 ? null : (current - previous) / previous;

/// "+12.5%", "-3.0%", "0.0%", or "n/a" without a base.
String formatSalesChange(double? ratio) {
  if (ratio == null) return 'n/a';
  final String pct = (ratio.abs() * 100).toStringAsFixed(1);
  if (pct == '0.0') return '0.0%';
  return '${ratio < 0 ? '-' : '+'}$pct%';
}

/// [value] written for its [unit].
String formatSalesValue(int value, SalesUnit unit) =>
    unit == SalesUnit.money ? formatSalesPeso(value) : '$value';

int _average(int total, int count) => count == 0 ? 0 : (total / count).round();

/// The figures a report compares with [previous], headline first.
List<SalesMetric> salesMetrics(
  SalesReport report,
  SalesReport? previous,
  SalesReportAudience audience,
) {
  final SalesRow t = report.totals;
  final SalesRow? p = previous?.totals;
  final String active = report.breakdown == SalesBreakdown.daily
      ? 'Days with sales'
      : 'Months with sales';
  if (audience == SalesReportAudience.platform) {
    return <SalesMetric>[
      SalesMetric('Commission', t.commissionCentavos, p?.commissionCentavos),
      SalesMetric('Transactions', t.count, p?.count, unit: SalesUnit.count),
      SalesMetric(
        'Avg. commission per transaction',
        _average(t.commissionCentavos, t.count),
        p == null ? null : _average(p.commissionCentavos, p.count),
        neutral: true,
      ),
      SalesMetric(
        active,
        salesActiveRows(report),
        previous == null ? null : salesActiveRows(previous),
        unit: SalesUnit.count,
      ),
    ];
  }
  return <SalesMetric>[
    SalesMetric('Gross sales', t.grossCentavos, p?.grossCentavos),
    SalesMetric('Transactions', t.count, p?.count, unit: SalesUnit.count),
    SalesMetric(
      'Avg. sale per transaction',
      _average(t.grossCentavos, t.count),
      p == null ? null : _average(p.grossCentavos, p.count),
      neutral: true,
    ),
    SalesMetric(
      'SmartPark commission',
      t.commissionCentavos,
      p?.commissionCentavos,
      neutral: true,
    ),
    SalesMetric(
      'Processing fee (est.)',
      t.processingCentavos,
      p?.processingCentavos,
      neutral: true,
    ),
    SalesMetric('Payout (est.)', t.payoutCentavos, p?.payoutCentavos),
    SalesMetric('Overtime cash', t.cashCentavos, p?.cashCentavos),
    SalesMetric(
      'Take-home (payout + cash)',
      t.payoutCentavos + t.cashCentavos,
      p == null ? null : p.payoutCentavos + p.cashCentavos,
    ),
    SalesMetric(
      active,
      salesActiveRows(report),
      previous == null ? null : salesActiveRows(previous),
      unit: SalesUnit.count,
    ),
  ];
}

/// Headline totals per weekday (Mon first) and how many of each weekday the
/// report covers, for daily reports.
({List<int> totals, List<int> days}) salesByWeekday(
  SalesReport report,
  SalesReportAudience audience,
) {
  final List<int> totals = List<int>.filled(7, 0);
  final List<int> days = List<int>.filled(7, 0);
  for (final SalesRow row in report.rows) {
    totals[row.start.weekday - 1] += salesHeadline(row, audience);
    days[row.start.weekday - 1]++;
  }
  return (totals: totals, days: days);
}

/// A few sentences on the period, for the top of the report.
String salesNarrative(
  SalesReport report,
  SalesReport? previous,
  SalesReportAudience audience,
) {
  final String what = salesHeadlineName(audience);
  final int total = salesHeadline(report.totals, audience);
  final StringBuffer out = StringBuffer();
  if (total == 0 && report.totals.cashCentavos == 0) {
    out.write(
      'No ${what.toLowerCase()} were recorded for '
      '${report.coveredLabel}.',
    );
  } else {
    out.write(
      '$what for ${report.coveredLabel} came to '
      '${formatSalesPeso(total)} from ${report.totals.count} '
      'transaction${report.totals.count == 1 ? '' : 's'}',
    );
    final double? ratio = previous == null
        ? null
        : salesChange(total, salesHeadline(previous.totals, audience));
    if (previous != null && ratio != null) {
      out.write(
        ratio.abs() < 0.0005
            ? ', unchanged from ${previous.coveredLabel}.'
            : ', ${ratio > 0 ? 'up' : 'down'} '
                  '${formatSalesChange(ratio).substring(1)} from '
                  '${formatSalesPeso(salesHeadline(previous.totals, audience))} '
                  'in ${previous.coveredLabel}.',
      );
    } else if (previous != null) {
      out.write('; there were none in ${previous.coveredLabel}.');
    } else {
      out.write('.');
    }
    final SalesRow? best = report.bestBy(
      (SalesRow r) => salesHeadline(r, audience),
    );
    if (best != null && total > 0) {
      final int share = (salesHeadline(best, audience) * 100 / total).round();
      out.write(
        ' The best ${salesRowNoun(report, plural: false)} was '
        '${report.rowLabel(best)}'
        '${report.breakdown == SalesBreakdown.daily ? ' (${salesWeekday(best.start)})' : ''}'
        ' at ${formatSalesPeso(salesHeadline(best, audience))}, '
        '$share% of the total.',
      );
    }
    out.write(
      ' There was activity on ${salesActiveRows(report)} of '
      '${report.rows.length} ${salesRowNoun(report)}.',
    );
  }
  if (report.isPartial && previous != null) {
    out.write(
      ' The period is still running, so the comparison covers the '
      'same number of days.',
    );
  }
  return out.toString();
}
