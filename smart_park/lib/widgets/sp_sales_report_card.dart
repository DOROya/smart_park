import 'package:flutter/material.dart';

import '../services/error_reporter.dart';
import '../services/sales_report.dart';
import '../services/sales_report_pdf.dart';
import '../theme/app_theme.dart';
import 'smartpark_ui.dart';

/// Week / Month / Quarter / Year selector with arrows to step through
/// periods. Everything under it on a Finance tab follows the chosen range.
class SpFinancePeriodBar extends StatelessWidget {
  const SpFinancePeriodBar({
    super.key,
    required this.range,
    required this.onChanged,
    this.earliest,
    this.now,
  });

  final FinanceRange range;
  final ValueChanged<FinanceRange> onChanged;

  /// Oldest date with data; the back arrow stops at its period.
  final DateTime? earliest;

  /// Overrides the clock, for tests.
  final DateTime? now;

  /// A calendar for weeks; for months, quarters and years, a sheet of every
  /// period from the first one with data up to now.
  Future<void> _pick(
    BuildContext context,
    DateTime today,
    FinanceRange first,
  ) async {
    if (range.period == FinancePeriod.week) {
      final DateTime? day = await showDatePicker(
        context: context,
        initialDate: range.contains(today) ? today : range.start,
        firstDate: first.start,
        lastDate: today,
        helpText: 'Pick any day of the week',
      );
      if (day != null) {
        onChanged(FinanceRange.containing(FinancePeriod.week, day));
      }
      return;
    }
    final FinanceRange? picked = await showModalBottomSheet<FinanceRange>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      // A phone-width sheet, centered on tablets.
      constraints: BoxConstraints(
        maxWidth: 560,
        maxHeight: MediaQuery.sizeOf(context).height * 0.7,
      ),
      backgroundColor: AppTheme.surface,
      builder: (BuildContext context) =>
          _PeriodPickerSheet(selected: range, first: first, today: today),
    );
    if (picked != null && picked != range) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final DateTime today = now ?? DateTime.now();
    final FinanceRange first = FinanceRange.containing(
      range.period,
      earliest != null && earliest!.isBefore(today) ? earliest! : today,
    );
    final bool canGoBack = range.start.isAfter(first.start);
    final bool canGoForward = !range.end.isAfter(
      DateTime(today.year, today.month, today.day),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SpSegmentedControl<FinancePeriod>(
          options: const <(FinancePeriod, String)>[
            (FinancePeriod.week, 'Week'),
            (FinancePeriod.month, 'Month'),
            (FinancePeriod.quarter, 'Quarter'),
            (FinancePeriod.year, 'Year'),
          ],
          selected: range.period,
          // Land on the latest part of what is showing (today, if it is
          // in view), but never before the first sale.
          onChanged: (FinancePeriod p) {
            DateTime anchor = range.contains(today) ? today : range.lastDay;
            if (earliest != null && anchor.isBefore(earliest!)) {
              anchor = earliest!;
            }
            onChanged(FinanceRange.containing(p, anchor));
          },
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            IconButton(
              tooltip: 'Previous ${range.period.name}',
              onPressed: canGoBack ? () => onChanged(range.step(-1)) : null,
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Expanded(
              // Tap the period to jump straight to another one.
              child: Tooltip(
                message: 'Choose a ${range.period.name}',
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                  onTap: () => _pick(context, today, first),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                range.label,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.textDark,
                                ),
                              ),
                            ),
                            Icon(
                              Icons.arrow_drop_down_rounded,
                              color: AppTheme.textMuted,
                            ),
                          ],
                        ),
                        if (range.months.isNotEmpty)
                          Text(
                            range.months,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textMuted,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Next ${range.period.name}',
              onPressed: canGoForward ? () => onChanged(range.step(1)) : null,
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
      ],
    );
  }
}

/// Every month, quarter or year from [first] to [today], newest year first,
/// as chips. Tapping one closes the sheet with that range.
class _PeriodPickerSheet extends StatelessWidget {
  const _PeriodPickerSheet({
    required this.selected,
    required this.first,
    required this.today,
  });

  final FinanceRange selected;
  final FinanceRange first;
  final DateTime today;

  static const List<String> _quarterNames = <String>[
    'Q1 · Jan - Mar',
    'Q2 · Apr - Jun',
    'Q3 · Jul - Sep',
    'Q4 · Oct - Dec',
  ];

  Widget _chip(BuildContext context, FinanceRange r, String label) {
    final bool enabled =
        !r.start.isBefore(first.start) && !r.start.isAfter(today);
    return ChoiceChip(
      label: Text(label),
      selected: r == selected,
      onSelected: enabled ? (_) => Navigator.of(context).pop(r) : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final FinancePeriod period = selected.period;
    final List<int> years = <int>[
      for (int y = today.year; y >= first.start.year; y--) y,
    ];
    final String title = switch (period) {
      FinancePeriod.month => 'Choose a month',
      FinancePeriod.quarter => 'Choose a quarter',
      _ => 'Choose a year',
    };

    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 12),
          if (period == FinancePeriod.year)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final int y in years)
                  _chip(
                    context,
                    FinanceRange.containing(period, DateTime(y)),
                    '$y',
                  ),
              ],
            )
          else
            for (final int y in years) ...[
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 8),
                child: Text(
                  '$y',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textMuted,
                  ),
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  if (period == FinancePeriod.quarter)
                    for (int q = 0; q < 4; q++)
                      _chip(
                        context,
                        FinanceRange.containing(period, DateTime(y, q * 3 + 1)),
                        _quarterNames[q],
                      )
                  else
                    for (int m = 1; m <= 12; m++)
                      _chip(
                        context,
                        FinanceRange.containing(period, DateTime(y, m)),
                        kSalesMonthNames[m - 1].substring(0, 3),
                      ),
                ],
              ),
              const SizedBox(height: 12),
            ],
        ],
      ),
    );
  }
}

/// The selected period per day (week, month) or per month (quarter,
/// year), which can be printed or shared as a PDF report.
class SpSalesReportCard extends StatefulWidget {
  const SpSalesReportCard({
    super.key,
    required this.report,
    required this.audience,
    required this.scopeLabel,
    required this.preparedBy,
  });

  final SalesReport report;
  final SalesReportAudience audience;

  /// What the figures cover, e.g. the facility name.
  final String scopeLabel;

  /// Printed as "Prepared by" on the report.
  final String preparedBy;

  @override
  State<SpSalesReportCard> createState() => _SpSalesReportCardState();
}

class _SpSalesReportCardState extends State<SpSalesReportCard> {
  bool _busy = false;

  bool get _owner => widget.audience == SalesReportAudience.owner;

  Future<void> _export({required bool share}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (share) {
        await shareSalesReport(
          report: widget.report,
          audience: widget.audience,
          scopeLabel: widget.scopeLabel,
          preparedBy: widget.preparedBy,
        );
      } else {
        await printSalesReport(
          report: widget.report,
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
    final SalesReport report = widget.report;
    final bool daily = report.breakdown == SalesBreakdown.daily;
    // Newest first. Days without activity are left out; months are all
    // shown, since at most twelve rows stay short.
    final List<SalesRow> rows = <SalesRow>[
      for (final SalesRow row in report.rows.reversed)
        if (!daily || !row.isEmpty) row,
    ];
    final String what = _owner ? 'Sales' : 'Commission';

    return SpSectionCard(
      icon: Icons.summarize_rounded,
      title: daily ? 'Daily $what' : 'Monthly $what',
      subtitle:
          '${daily ? 'Per day' : 'Per month'} for '
          '${salesReportPeriod(report)}. Print it or save it as a PDF.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Divider(height: 1, color: AppTheme.border),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: SpEmptyState(
                boxed: false,
                message: _owner
                    ? 'No sales in ${report.range.label}.'
                    : 'No commission in ${report.range.label}.',
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
                  report.breakdown == SalesBreakdown.daily
                      ? '${report.rowLabel(row)}, ${salesWeekday(row.start)}'
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
                formatSalesPeso(
                  _owner ? row.grossCentavos : row.commissionCentavos,
                ),
                style: TextStyle(fontWeight: FontWeight.w800, color: main),
              ),
              if (_owner)
                Text(
                  'Est. payout ${formatSalesPeso(row.payoutCentavos)}',
                  style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
