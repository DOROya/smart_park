import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../services/error_reporter.dart';
import '../../theme/app_theme.dart';
import '../../utils/friendly_error.dart';
import '../../widgets/smartpark_ui.dart';
import '../../widgets/sp_dialog.dart';

/// One day on the payment health chart.
class PaymentHealthDay {
  const PaymentHealthDay({
    required this.date,
    required this.confirmedInApp,
    required this.rescued,
    required this.unfinished,
  });

  final String date;
  final int confirmedInApp;
  final int rescued;
  final int unfinished;

  int get paid => confirmedInApp + rescued;
}

/// A payment the 15-minute check finished, as an example for the card.
class RescuedPayment {
  const RescuedPayment({
    required this.establishmentName,
    required this.amount,
    required this.kind,
    required this.paidAt,
  });

  final String establishmentName;
  final double amount;

  /// "gate", "add_hours" or "app".
  final String kind;
  final DateTime? paidAt;
}

/// The getPaymentHealth function's reply.
class PaymentHealth {
  const PaymentHealth({
    required this.periodDays,
    required this.ok,
    required this.problems,
    required this.paid,
    required this.confirmedInApp,
    required this.rescued,
    required this.rescuedPercent,
    required this.gateTimedOut,
    required this.gateCancelled,
    required this.gateFailedToStart,
    required this.checkoutsAbandoned,
    required this.inProgress,
    required this.stuck,
    required this.refundsInFlight,
    required this.refundsFailed,
    required this.refundsSlow,
    required this.lastRunMinutesAgo,
    required this.jobOverdue,
    required this.series,
    required this.rescuedRecent,
  });

  final int periodDays;
  final bool ok;
  final List<String> problems;
  final int paid;
  final int confirmedInApp;
  final int rescued;
  final double rescuedPercent;
  final int gateTimedOut;
  final int gateCancelled;
  final int gateFailedToStart;
  final int checkoutsAbandoned;
  final int inProgress;
  final int stuck;
  final int refundsInFlight;
  final int refundsFailed;
  final int refundsSlow;
  final int? lastRunMinutesAgo;
  final bool jobOverdue;
  final List<PaymentHealthDay> series;
  final List<RescuedPayment> rescuedRecent;

  int get unfinished =>
      gateTimedOut + gateCancelled + gateFailedToStart + checkoutsAbandoned;

  static int _int(Object? v) => v is num ? v.toInt() : 0;

  static Map<String, dynamic> _map(Object? v) => v is Map
      ? v.map((Object? k, Object? val) => MapEntry('$k', val))
      : <String, dynamic>{};

  factory PaymentHealth.fromMap(Map<String, dynamic> m) {
    final Map<String, dynamic> unfinished = _map(m['unfinished']);
    final Map<String, dynamic> refunds = _map(m['refunds']);
    final Map<String, dynamic> reconcile = _map(m['reconcile']);
    return PaymentHealth(
      periodDays: _int(m['periodDays']),
      ok: m['status'] == 'ok',
      problems: ((m['problems'] as List<Object?>?) ?? <Object?>[])
          .whereType<String>()
          .toList(),
      paid: _int(m['paid']),
      confirmedInApp: _int(m['confirmedInApp']),
      rescued: _int(m['rescued']),
      rescuedPercent: (m['rescuedPercent'] as num?)?.toDouble() ?? 0,
      gateTimedOut: _int(unfinished['gateTimedOut']),
      gateCancelled: _int(unfinished['gateCancelled']),
      gateFailedToStart: _int(unfinished['gateFailedToStart']),
      checkoutsAbandoned: _int(unfinished['checkoutsAbandoned']),
      inProgress: _int(m['inProgress']),
      stuck: _int(m['stuck']),
      refundsInFlight: _int(refunds['inFlight']),
      refundsFailed: _int(refunds['failed']),
      refundsSlow: _int(refunds['slow']),
      lastRunMinutesAgo: (reconcile['lastRunMinutesAgo'] as num?)?.toInt(),
      jobOverdue: reconcile['overdue'] == true,
      series: <PaymentHealthDay>[
        for (final Object? d in (m['series'] as List<Object?>?) ?? <Object?>[])
          PaymentHealthDay(
            date: '${_map(d)['date'] ?? ''}',
            confirmedInApp: _int(_map(d)['confirmedInApp']),
            rescued: _int(_map(d)['rescued']),
            unfinished: _int(_map(d)['unfinished']),
          ),
      ],
      rescuedRecent: <RescuedPayment>[
        for (final Object? r
            in (m['rescuedRecent'] as List<Object?>?) ?? <Object?>[])
          RescuedPayment(
            establishmentName: '${_map(r)['establishmentName'] ?? ''}',
            amount: (_map(r)['amount'] as num?)?.toDouble() ?? 0,
            kind: '${_map(r)['kind'] ?? 'app'}',
            paidAt: DateTime.tryParse('${_map(r)['paidAt'] ?? ''}')?.toLocal(),
          ),
      ],
    );
  }
}

/// "5 min ago", "2 h ago", "never".
String paymentHealthRunLabel(int? minutesAgo) {
  if (minutesAgo == null) return 'never';
  if (minutesAgo < 1) return 'just now';
  if (minutesAgo < 60) return '$minutesAgo min ago';
  final int hours = minutesAgo ~/ 60;
  if (hours < 48) return '$hours h ago';
  return '${hours ~/ 24} days ago';
}

/// Admin dashboard card: are payments reaching tickets, and is anything
/// stuck? Data from the getPaymentHealth Cloud Function.
class AdminPaymentHealthCard extends StatefulWidget {
  const AdminPaymentHealthCard({super.key, this.load});

  /// Loads the summary for a number of days; the Cloud Function by default.
  /// Tests pass their own.
  final Future<PaymentHealth> Function(int days)? load;

  @override
  State<AdminPaymentHealthCard> createState() => _AdminPaymentHealthCardState();
}

class _AdminPaymentHealthCardState extends State<AdminPaymentHealthCard> {
  static const List<int> _periods = <int>[7, 30];

  int _days = 7;
  PaymentHealth? _health;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  static Future<PaymentHealth> _callFunction(int days) async {
    final HttpsCallableResult<dynamic> result =
        await FirebaseFunctions.instanceFor(region: 'asia-southeast1')
            .httpsCallable('getPaymentHealth')
            .call<dynamic>(<String, dynamic>{'days': days});
    final Object? data = result.data;
    return PaymentHealth.fromMap(
      data is Map
          ? data.map((Object? k, Object? v) => MapEntry('$k', v))
          : <String, dynamic>{},
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final PaymentHealth health = await (widget.load ?? _callFunction)(_days);
      if (!mounted) return;
      setState(() => _health = health);
    } catch (error, stack) {
      reportError(error, stack, reason: 'Payment health');
      if (!mounted) return;
      setState(
        () => _error = friendlyError(
          error,
          fallback: 'Could not load payment health.',
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final PaymentHealth? h = _health;
    return SpSectionCard(
      icon: Icons.monitor_heart_outlined,
      title: 'Payment Health',
      subtitle:
          'Whether every payment a driver made became a ticket. Tap ? to '
          'see what each number means.',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const SpHelpButton(
            title: 'Payment Health',
            points: <SpDialogPoint>[
              SpDialogPoint(
                icon: Icons.payments_outlined,
                text:
                    'Paid: payments that became tickets. Most are confirmed '
                    'right away in the driver\'s app.',
              ),
              SpDialogPoint(
                icon: Icons.healing_rounded,
                text:
                    'Auto-recovered: the driver paid, but their phone lost '
                    'signal or the app closed before the ticket was '
                    'confirmed. Every 15 minutes SmartPark asks PayMongo '
                    'about such payments and finishes them, so the driver '
                    'still gets their ticket. A few are normal; many mean '
                    'drivers are having connection problems.',
                tone: SpDialogTone.success,
              ),
              SpDialogPoint(
                icon: Icons.hourglass_top_rounded,
                text:
                    'In progress now: payments still open. "Stuck" ones '
                    'have been open too long and need a look.',
                tone: SpDialogTone.warning,
              ),
              SpDialogPoint(
                icon: Icons.currency_exchange_rounded,
                text:
                    'Refunds pending: approved refunds PayMongo is still '
                    'sending back to the driver.',
              ),
              SpDialogPoint(
                icon: Icons.block_rounded,
                text:
                    'Ended without payment: the driver or staff stopped '
                    'before paying. No money was taken.',
              ),
            ],
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _refresh,
            icon: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SpSegmentedControl<int>(
            options: <(int, String)>[
              for (final int d in _periods) (d, 'Last $d days'),
            ],
            selected: _days,
            onChanged: (int d) {
              if (d == _days) return;
              setState(() => _days = d);
              unawaited(_refresh());
            },
          ),
          const SizedBox(height: 12),
          if (_error != null && h == null)
            SpEmptyState(icon: Icons.error_outline_rounded, message: _error!)
          else if (h == null)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            _body(h),
        ],
      ),
    );
  }

  Widget _body(PaymentHealth h) {
    final Color statusColor = h.ok ? AppTheme.success : AppTheme.danger;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: h.ok ? AppTheme.successSoft : AppTheme.dangerSoft,
            borderRadius: BorderRadius.circular(AppTheme.radius),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    h.ok
                        ? Icons.check_circle_rounded
                        : Icons.warning_amber_rounded,
                    color: statusColor,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      h.ok ? 'All payments healthy' : 'Needs attention',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '15-minute check last ran '
                '${paymentHealthRunLabel(h.lastRunMinutesAgo)}.',
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
              for (final String problem in h.problems)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '• $problem',
                    style: TextStyle(fontSize: 12.5, color: AppTheme.textDark),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SpGrid(
          columns: 2,
          spacing: 10,
          children: <Widget>[
            _figure(
              'Paid',
              '${h.paid}',
              '${h.confirmedInApp} confirmed in the app',
              AppTheme.info,
            ),
            _figure(
              'Auto-recovered',
              '${h.rescued}',
              h.paid == 0
                  ? 'None needed'
                  : '${_percent(h.rescuedPercent)} of paid',
              AppTheme.accentText,
            ),
            _figure(
              'In progress now',
              '${h.inProgress}',
              h.stuck == 0 ? 'None stuck' : '${h.stuck} stuck',
              h.stuck == 0 ? AppTheme.textDark : AppTheme.danger,
            ),
            _figure(
              'Refunds pending',
              '${h.refundsInFlight}',
              h.refundsFailed == 0
                  ? 'None failed'
                  : '${h.refundsFailed} failed',
              h.refundsFailed == 0 ? AppTheme.textDark : AppTheme.danger,
            ),
          ],
        ),
        if (h.series.isNotEmpty) ...<Widget>[
          const SizedBox(height: 14),
          _chart(h.series),
        ],
        const SizedBox(height: 12),
        Text(
          'Ended without payment: ${h.unfinished}',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppTheme.textDark,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '${h.gateTimedOut} timed out at the gate, ${h.gateCancelled} '
          'stopped by staff, ${h.gateFailedToStart} could not open, '
          '${h.checkoutsAbandoned} left unpaid in the app. No money was taken '
          'for these.',
          style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
        ),
        if (h.rescuedRecent.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          Text(
            'Latest auto-recovered payments',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppTheme.textDark,
            ),
          ),
          for (final RescuedPayment r in h.rescuedRecent)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.healing_rounded,
                    size: 16,
                    color: AppTheme.accentText,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${r.establishmentName.isEmpty ? 'Parking' : r.establishmentName}'
                      ' · ${spPeso(r.amount)}'
                      '${r.kind == 'add_hours' ? ' (added hours)' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppTheme.textDark,
                      ),
                    ),
                  ),
                  if (r.paidAt != null)
                    Text(
                      '${spFormatDate(r.paidAt!)}, ${spFormatClockTime(r.paidAt!)}',
                      style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                    ),
                ],
              ),
            ),
        ],
      ],
    );
  }

  static String _percent(double p) =>
      '${p.toStringAsFixed(p == p.roundToDouble() ? 0 : 1)}%';

  Widget _figure(String label, String value, String caption, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(AppTheme.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          Text(
            caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  /// Paid per day: confirmed in the app, with the auto-recovered part on
  /// top, and the day's total above each bar.
  Widget _chart(List<PaymentHealthDay> series) {
    final int peak = series.fold<int>(
      0,
      (int best, PaymentHealthDay d) => d.paid > best ? d.paid : best,
    );
    final bool many = series.length > 10;
    const double labelSpace = 16;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          height: 110,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              for (final PaymentHealthDay d in series)
                Expanded(
                  child: Tooltip(
                    message:
                        '${d.date}: ${d.confirmedInApp} in app, '
                        '${d.rescued} auto-recovered, ${d.unfinished} '
                        'unfinished',
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: many ? 1 : 4),
                      child: LayoutBuilder(
                        builder: (BuildContext context, BoxConstraints box) {
                          double h(int n) => peak == 0
                              ? 0
                              : (box.maxHeight - labelSpace) * n / peak;
                          return Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: <Widget>[
                              if (d.paid > 0)
                                SizedBox(
                                  height: labelSpace,
                                  child: OverflowBox(
                                    minWidth: 0,
                                    maxWidth: 40,
                                    alignment: Alignment.bottomCenter,
                                    child: Text(
                                      '${d.paid}',
                                      maxLines: 1,
                                      softWrap: false,
                                      style: TextStyle(
                                        fontSize: many ? 8.5 : 11,
                                        fontWeight: d.paid == peak
                                            ? FontWeight.w800
                                            : FontWeight.w600,
                                        color: d.paid == peak
                                            ? AppTheme.info
                                            : AppTheme.textSecondary,
                                      ),
                                    ),
                                  ),
                                ),
                              Container(
                                height: h(d.rescued),
                                color: AppTheme.accent,
                              ),
                              Container(
                                height: h(d.confirmedInApp),
                                decoration: BoxDecoration(
                                  color: AppTheme.info.withValues(alpha: 0.75),
                                  borderRadius: d.rescued == 0
                                      ? const BorderRadius.vertical(
                                          top: Radius.circular(3),
                                        )
                                      : null,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 14,
          children: <Widget>[
            _legend(AppTheme.info.withValues(alpha: 0.75), 'Confirmed in app'),
            _legend(AppTheme.accent, 'Auto-recovered'),
          ],
        ),
      ],
    );
  }

  Widget _legend(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
      ],
    );
  }
}
