import 'package:flutter/material.dart';

import '../services/error_reporter.dart';
import '../services/sales_report.dart';
import '../services/sales_report_pdf.dart';
import '../theme/app_theme.dart';
import 'smartpark_ui.dart';

/// Finance card with daily (one month) and monthly (one year) sales, which
/// can be printed or shared as a PDF report.
class SpSalesReportCard extends StatefulWidget {
  const SpSalesReportCard({
    super.key,
    required this.entries,
    required this.audience,
    required this.scopeLabel,
    required this.preparedBy,
    this.now,
  });

  final List<SalesEntry> entries;
  final SalesReportAudience audience;

  /// What the figures cover, e.g. the facility name.
  final String scopeLabel;

  /// Printed as "Prepared by" on the report.
  final String preparedBy;

  /// Overrides the clock, for tests.
  final DateTime? now;

  @override
  State<SpSalesReportCard> createState() => _SpSalesReportCardState();
}

class _SpSalesReportCardState extends State<SpSalesReportCard> {
  SalesPeriod _period = SalesPeriod.daily;
  late DateTime _month;
  late int _year;
  bool _busy = false;

  DateTime get _now => widget.now ?? DateTime.now();

  bool get _owner => widget.audience == SalesReportAudience.owner;

  @override
  void initState() {
    super.initState();
    _month = DateTime(_now.year, _now.month);
    _year = _now.year;
  }

  /// Oldest month with any sales, so the back arrow stops there.
  DateTime get _earliest {
    DateTime earliest = DateTime(_now.year, _now.month);
    for (final SalesEntry e in widget.entries) {
      final DateTime m = DateTime(e.at.year, e.at.month);
      if (m.isBefore(earliest)) earliest = m;
    }
    return earliest;
  }

  SalesReport get _report => _period == SalesPeriod.daily
      ? SalesReport.daily(widget.entries, _month, now: _now)
      : SalesReport.monthly(widget.entries, _year, now: _now);

  bool get _canGoBack => _period == SalesPeriod.daily
      ? _month.isAfter(_earliest)
      : _year > _earliest.year;

  bool get _canGoForward => _period == SalesPeriod.daily
      ? _month.isBefore(DateTime(_now.year, _now.month))
      : _year < _now.year;

  void _step(int delta) => setState(() {
    if (_period == SalesPeriod.daily) {
      _month = DateTime(_month.year, _month.month + delta);
    } else {
      _year += delta;
    }
  });

  Future<void> _export({required bool share}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final SalesReport report = _report;
      if (share) {
        await shareSalesReport(
          report: report,
          audience: widget.audience,
          scopeLabel: widget.scopeLabel,
          preparedBy: widget.preparedBy,
        );
      } else {
        await printSalesReport(
          report: report,
          audience: widget.audience,
          scopeLabel: widget.scopeLabel,
          preparedBy: widget.preparedBy,
        );
      }
    } catch (error, stack) {
      reportError(error, stack, reason: 'sales report export');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not create the report. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final SalesReport report = _report;
    final bool daily = _period == SalesPeriod.daily;
    // Newest first on screen. Days without sales are left out; months are
    // all shown, since twelve rows stay short.
    final List<SalesRow> rows = <SalesRow>[
      for (final SalesRow row in report.rows.reversed)
        if (!daily || !row.isEmpty) row,
    ];

    return SpSectionCard(
      icon: Icons.summarize_rounded,
      title: 'Sales Report',
      subtitle: daily
          ? 'Sales per day for the month. Print it or save it as a PDF.'
          : 'Sales per month for the year. Print it or save it as a PDF.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SpSegmentedControl<SalesPeriod>(
            options: const <(SalesPeriod, String)>[
              (SalesPeriod.daily, 'Daily'),
              (SalesPeriod.monthly, 'Monthly'),
            ],
            selected: _period,
            onChanged: (SalesPeriod p) => setState(() => _period = p),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton(
                tooltip: daily ? 'Previous month' : 'Previous year',
                onPressed: _canGoBack ? () => _step(-1) : null,
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Expanded(
                child: Text(
                  report.periodLabel,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textDark,
                  ),
                ),
              ),
              IconButton(
                tooltip: daily ? 'Next month' : 'Next year',
                onPressed: _canGoForward ? () => _step(1) : null,
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              _figure(
                'Gross sales',
                formatSalesPeso(report.totals.grossCentavos),
              ),
              _figure('Transactions', '${report.totals.count}'),
              _owner
                  ? _figure(
                      'Your payout',
                      formatSalesPeso(report.totals.payoutCentavos),
                    )
                  : _figure(
                      'Commission',
                      formatSalesPeso(report.totals.commissionCentavos),
                    ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: AppTheme.border),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: SpEmptyState(
                boxed: false,
                message: 'No sales in ${report.periodLabel}.',
              ),
            )
          else
            for (final SalesRow row in rows) _row(report, row),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: SpPrimaryButton(
                  icon: Icons.print_rounded,
                  label: 'Print report',
                  busy: _busy,
                  onPressed: () => _export(share: false),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : () => _export(share: true),
                  icon: const Icon(Icons.ios_share_rounded, size: 18),
                  label: const Text('PDF'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.textDark,
                    side: BorderSide(color: AppTheme.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radius),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _figure(String label, String value) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppTheme.textDark,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _row(SalesReport report, SalesRow row) {
    final bool empty = row.isEmpty;
    final Color main = empty ? AppTheme.textMuted : AppTheme.textDark;
    final List<String> details = <String>[
      '${row.count} txn${row.count == 1 ? '' : 's'}',
      if (_owner && row.cashCentavos > 0)
        '+ ${formatSalesPeso(row.cashCentavos)} cash',
    ];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  report.period == SalesPeriod.daily
                      ? '${report.rowLabel(row)}, ${_weekday(row.start)}'
                      : report.rowLabel(row),
                  style: TextStyle(fontWeight: FontWeight.w700, color: main),
                ),
                Text(
                  details.join(' · '),
                  style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatSalesPeso(row.grossCentavos),
                style: TextStyle(fontWeight: FontWeight.w800, color: main),
              ),
              Text(
                _owner
                    ? 'Payout ${formatSalesPeso(row.payoutCentavos)}'
                    : 'Commission ${formatSalesPeso(row.commissionCentavos)}',
                style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _weekday(DateTime d) => const <String>[
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ][d.weekday - 1];
}
