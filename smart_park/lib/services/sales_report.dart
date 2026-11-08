/// Finance figures for one week, month, quarter or year: the totals on the
/// Finance tabs, their day-by-day or month-by-month breakdown, and the
/// printed report. Amounts are kept in centavos so totals add up exactly.
library;

/// The period the Finance tabs show.
enum FinancePeriod { week, month, quarter, year }

/// How a report's rows are cut: per day (week, month) or per month
/// (quarter, year).
enum SalesBreakdown { daily, monthly }

const List<String> kSalesMonthNames = <String>[
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

const List<String> kSalesWeekdays = <String>[
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
];

String _shortMonth(int month) => kSalesMonthNames[month - 1].substring(0, 3);

/// One calendar week (Monday to Sunday), month, quarter or year.
class FinanceRange {
  const FinanceRange._(this.period, this.start);

  /// The [period] that contains [day].
  factory FinanceRange.containing(FinancePeriod period, DateTime day) {
    final DateTime d = DateTime(day.year, day.month, day.day);
    return switch (period) {
      FinancePeriod.week => FinanceRange._(
        period,
        DateTime(d.year, d.month, d.day - (d.weekday - 1)),
      ),
      FinancePeriod.month => FinanceRange._(period, DateTime(d.year, d.month)),
      FinancePeriod.quarter => FinanceRange._(
        period,
        DateTime(d.year, ((d.month - 1) ~/ 3) * 3 + 1),
      ),
      FinancePeriod.year => FinanceRange._(period, DateTime(d.year)),
    };
  }

  final FinancePeriod period;

  /// First day of the range (midnight, local time).
  final DateTime start;

  /// First day after the range.
  DateTime get end => switch (period) {
    FinancePeriod.week => DateTime(start.year, start.month, start.day + 7),
    FinancePeriod.month => DateTime(start.year, start.month + 1),
    FinancePeriod.quarter => DateTime(start.year, start.month + 3),
    FinancePeriod.year => DateTime(start.year + 1),
  };

  /// Last day of the range.
  DateTime get lastDay => DateTime(end.year, end.month, end.day - 1);

  bool contains(DateTime t) => !t.isBefore(start) && t.isBefore(end);

  SalesBreakdown get breakdown =>
      period == FinancePeriod.week || period == FinancePeriod.month
      ? SalesBreakdown.daily
      : SalesBreakdown.monthly;

  /// The same kind of range [delta] steps later (or earlier, if negative).
  FinanceRange step(int delta) => switch (period) {
    FinancePeriod.week => FinanceRange._(
      period,
      DateTime(start.year, start.month, start.day + 7 * delta),
    ),
    FinancePeriod.month => FinanceRange._(
      period,
      DateTime(start.year, start.month + delta),
    ),
    FinancePeriod.quarter => FinanceRange._(
      period,
      DateTime(start.year, start.month + 3 * delta),
    ),
    FinancePeriod.year => FinanceRange._(period, DateTime(start.year + delta)),
  };

  /// e.g. "Nov 2 - 8, 2026", "November 2026", "Q4 2026", "2026".
  String get label {
    switch (period) {
      case FinancePeriod.week:
        final DateTime last = lastDay;
        if (start.year != last.year) {
          return '${_shortMonth(start.month)} ${start.day}, ${start.year} - '
              '${_shortMonth(last.month)} ${last.day}, ${last.year}';
        }
        if (start.month != last.month) {
          return '${_shortMonth(start.month)} ${start.day} - '
              '${_shortMonth(last.month)} ${last.day}, ${last.year}';
        }
        return '${_shortMonth(start.month)} ${start.day} - ${last.day}, '
            '${start.year}';
      case FinancePeriod.month:
        return '${kSalesMonthNames[start.month - 1]} ${start.year}';
      case FinancePeriod.quarter:
        return 'Q${(start.month - 1) ~/ 3 + 1} ${start.year}';
      case FinancePeriod.year:
        return '${start.year}';
    }
  }

  /// e.g. "Oct - Dec" for a quarter; empty for other periods.
  String get months => period == FinancePeriod.quarter
      ? '${_shortMonth(start.month)} - ${_shortMonth(lastDay.month)}'
      : '';

  /// "Weekly", "Monthly", "Quarterly" or "Annual".
  String get adjective => switch (period) {
    FinancePeriod.week => 'Weekly',
    FinancePeriod.month => 'Monthly',
    FinancePeriod.quarter => 'Quarterly',
    FinancePeriod.year => 'Annual',
  };

  /// Short slug for file names, e.g. "2026-11", "2026-Q4", "2026-11-02".
  String get slug {
    String two(int n) => n.toString().padLeft(2, '0');
    return switch (period) {
      FinancePeriod.week =>
        '${start.year}-${two(start.month)}-${two(start.day)}',
      FinancePeriod.month => '${start.year}-${two(start.month)}',
      FinancePeriod.quarter => '${start.year}-Q${(start.month - 1) ~/ 3 + 1}',
      FinancePeriod.year => '${start.year}',
    };
  }

  @override
  bool operator ==(Object other) =>
      other is FinanceRange && other.period == period && other.start == start;

  @override
  int get hashCode => Object.hash(period, start);
}

/// One sale (or one day's pre-summed sales) dated [at].
///
/// An owner sees one entry per paid ticket, plus one per overtime cash
/// collection ([count] 0, only [cashCentavos]). The admin sees one entry per
/// `stats_daily` doc, which already sums that day's payments.
class SalesEntry {
  const SalesEntry({
    required this.at,
    this.count = 1,
    this.grossCentavos = 0,
    this.commissionCentavos = 0,
    this.processingCentavos = 0,
    this.payoutCentavos = 0,
    this.cashCentavos = 0,
  });

  final DateTime at;

  /// Paid transactions this entry stands for.
  final int count;

  /// What drivers paid in the app.
  final int grossCentavos;

  /// SmartPark's commission on [grossCentavos].
  final int commissionCentavos;

  /// PayMongo's (estimated) processing fee.
  final int processingCentavos;

  /// What reaches the owner after commission and processing.
  final int payoutCentavos;

  /// Overtime paid in cash at the gate, outside the app.
  final int cashCentavos;
}

/// Totals for one day, one month, or a whole report.
class SalesRow {
  SalesRow(this.start);

  /// First moment of the day or month the row covers.
  final DateTime start;

  int count = 0;
  int grossCentavos = 0;
  int commissionCentavos = 0;
  int processingCentavos = 0;
  int payoutCentavos = 0;
  int cashCentavos = 0;

  bool get isEmpty =>
      count == 0 &&
      grossCentavos == 0 &&
      commissionCentavos == 0 &&
      cashCentavos == 0;

  void add(SalesEntry e) {
    count += e.count;
    grossCentavos += e.grossCentavos;
    commissionCentavos += e.commissionCentavos;
    processingCentavos += e.processingCentavos;
    payoutCentavos += e.payoutCentavos;
    cashCentavos += e.cashCentavos;
  }

  void addRow(SalesRow r) {
    count += r.count;
    grossCentavos += r.grossCentavos;
    commissionCentavos += r.commissionCentavos;
    processingCentavos += r.processingCentavos;
    payoutCentavos += r.payoutCentavos;
    cashCentavos += r.cashCentavos;
  }
}

/// Sales in one [FinanceRange], broken down per day (week, month) or per
/// month (quarter, year). Rows stop at today: no empty future days.
class SalesReport {
  SalesReport._(this.range, this.rows) : totals = SalesRow(range.start) {
    for (final SalesRow row in rows) {
      totals.addRow(row);
    }
  }

  factory SalesReport.forRange(
    Iterable<SalesEntry> entries,
    FinanceRange range, {
    DateTime? now,
  }) {
    final DateTime current = now ?? DateTime.now();
    final DateTime today = DateTime(current.year, current.month, current.day);
    final bool daily = range.breakdown == SalesBreakdown.daily;
    final List<SalesRow> rows = <SalesRow>[];
    for (
      DateTime t = range.start;
      t.isBefore(range.end) && !t.isAfter(today);
      t = daily
          ? DateTime(t.year, t.month, t.day + 1)
          : DateTime(t.year, t.month + 1)
    ) {
      rows.add(SalesRow(t));
    }
    for (final SalesEntry e in entries) {
      if (!range.contains(e.at)) continue;
      final int index = daily
          ? DateTime(
              e.at.year,
              e.at.month,
              e.at.day,
            ).difference(range.start).inDays
          : (e.at.year - range.start.year) * 12 +
                e.at.month -
                range.start.month;
      if (index >= 0 && index < rows.length) rows[index].add(e);
    }
    return SalesReport._(range, rows);
  }

  final FinanceRange range;

  /// Oldest first.
  final List<SalesRow> rows;
  final SalesRow totals;

  SalesBreakdown get breakdown => range.breakdown;

  /// Label for one row: "Nov 8" for a day, "November" for a month.
  String rowLabel(SalesRow row) => breakdown == SalesBreakdown.daily
      ? '${_shortMonth(row.start.month)} ${row.start.day}'
      : kSalesMonthNames[row.start.month - 1];

  /// The row with the largest [amount], or null when every row is zero.
  SalesRow? bestBy(int Function(SalesRow) amount) {
    SalesRow? best;
    for (final SalesRow row in rows) {
      if (amount(row) > 0 && (best == null || amount(row) > amount(best))) {
        best = row;
      }
    }
    return best;
  }
}

String salesWeekday(DateTime d) => kSalesWeekdays[d.weekday - 1];

/// "PHP 1,234.50" from centavos.
String formatSalesPeso(int centavos) {
  final bool negative = centavos < 0;
  final int abs = centavos.abs();
  final String whole = (abs ~/ 100).toString();
  final String cents = (abs % 100).toString().padLeft(2, '0');
  final StringBuffer grouped = StringBuffer();
  for (int i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) grouped.write(',');
    grouped.write(whole[i]);
  }
  return '${negative ? '-' : ''}PHP $grouped.$cents';
}
