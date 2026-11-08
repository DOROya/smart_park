/// Daily and monthly sales figures for the Finance tabs and the printed
/// sales report. Amounts are kept in centavos so totals add up exactly.
library;

enum SalesPeriod { daily, monthly }

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

/// Totals for one day or one month.
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

  bool get isEmpty => count == 0 && grossCentavos == 0 && cashCentavos == 0;

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

/// Sales for one month broken down by day ([SalesPeriod.daily]), or for one
/// year broken down by month ([SalesPeriod.monthly]).
class SalesReport {
  SalesReport._(this.period, this.anchor, this.rows)
    : totals = SalesRow(anchor) {
    for (final SalesRow row in rows) {
      totals.addRow(row);
    }
  }

  /// Every day of [month] up to [now] (the whole month if it is over).
  factory SalesReport.daily(
    Iterable<SalesEntry> entries,
    DateTime month, {
    DateTime? now,
  }) {
    final DateTime today = _dayOf(now ?? DateTime.now());
    final DateTime first = DateTime(month.year, month.month);
    final int daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final List<SalesRow> rows = <SalesRow>[
      for (int d = 1; d <= daysInMonth; d++)
        if (!DateTime(month.year, month.month, d).isAfter(today))
          SalesRow(DateTime(month.year, month.month, d)),
    ];
    for (final SalesEntry e in entries) {
      if (e.at.year != first.year || e.at.month != first.month) continue;
      final int index = e.at.day - 1;
      if (index < rows.length) rows[index].add(e);
    }
    return SalesReport._(SalesPeriod.daily, first, rows);
  }

  /// Every month of [year] up to [now] (all twelve if the year is over).
  factory SalesReport.monthly(
    Iterable<SalesEntry> entries,
    int year, {
    DateTime? now,
  }) {
    final DateTime current = now ?? DateTime.now();
    final int lastMonth = year < current.year
        ? 12
        : year == current.year
        ? current.month
        : 0;
    final List<SalesRow> rows = <SalesRow>[
      for (int m = 1; m <= lastMonth; m++) SalesRow(DateTime(year, m)),
    ];
    for (final SalesEntry e in entries) {
      if (e.at.year != year) continue;
      final int index = e.at.month - 1;
      if (index < rows.length) rows[index].add(e);
    }
    return SalesReport._(SalesPeriod.monthly, DateTime(year), rows);
  }

  final SalesPeriod period;

  /// The month (daily report) or year (monthly report) covered.
  final DateTime anchor;

  /// Oldest first.
  final List<SalesRow> rows;
  final SalesRow totals;

  /// e.g. "November 2026" or "2026".
  String get periodLabel => period == SalesPeriod.daily
      ? '${kSalesMonthNames[anchor.month - 1]} ${anchor.year}'
      : '${anchor.year}';

  /// e.g. "Daily Sales Report".
  String get title => period == SalesPeriod.daily
      ? 'Daily Sales Report'
      : 'Monthly Sales Report';

  /// Label for one row: "Nov 8" for a day, "November" for a month.
  String rowLabel(SalesRow row) => period == SalesPeriod.daily
      ? '${kSalesMonthNames[row.start.month - 1].substring(0, 3)} ${row.start.day}'
      : kSalesMonthNames[row.start.month - 1];

  /// Best row by gross sales, or null when nothing sold.
  SalesRow? get bestRow {
    SalesRow? best;
    for (final SalesRow row in rows) {
      if (row.grossCentavos > 0 &&
          (best == null || row.grossCentavos > best.grossCentavos)) {
        best = row;
      }
    }
    return best;
  }

  /// Average gross per row that had sales.
  int get averageGrossCentavos {
    final int active = rows.where((SalesRow r) => r.grossCentavos > 0).length;
    return active == 0 ? 0 : (totals.grossCentavos / active).round();
  }

  /// File name for the PDF, e.g. "SmartPark-Daily-Sales-2026-11.pdf".
  String get fileName {
    final String y = '${anchor.year}';
    return period == SalesPeriod.daily
        ? 'SmartPark-Daily-Sales-$y-${anchor.month.toString().padLeft(2, '0')}.pdf'
        : 'SmartPark-Monthly-Sales-$y.pdf';
  }

  static DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);
}

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
