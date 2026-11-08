part of 'admin_home_page.dart';

/// Dashboard and Finance chart series built from `stats_daily`. The admin
/// sees SmartPark's commission only, never what drivers paid the lots.
extension _AdminFinanceSeries on _AdminHomePageState {
  double _paymentCommission(_DayStat day) => day.commission;

  double _sumCommission(List<_DayStat> days) =>
      days.fold<double>(0, (double sum, _DayStat d) => sum + d.commission);

  static const List<String> _monthNames = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  /// Commission per day for the last [days] days (oldest first).
  _RevenueSeries _dailyRevenue(
    List<_DayStat> payments,
    int days, {
    double Function(_DayStat)? amountOf,
  }) {
    final double Function(_DayStat) amount = amountOf ?? _paymentCommission;
    final DateTime now = DateTime.now();
    final DateTime start = DateTime(now.year, now.month, now.day - (days - 1));
    final List<double> values = List<double>.filled(days, 0);
    for (final _DayStat doc in payments) {
      final int index = doc.day.difference(start).inDays;
      if (index >= 0 && index < days) values[index] += amount(doc);
    }
    final List<String> labels = List<String>.generate(days, (int i) {
      final DateTime day = DateTime(start.year, start.month, start.day + i);
      if (days <= 7) {
        return i == days - 1 ? 'Today' : kSalesWeekdays[day.weekday - 1];
      }
      return '${_monthNames[day.month - 1]} ${day.day}';
    });
    return _RevenueSeries(
      values: values,
      labels: labels,
      labelEvery: days <= 7 ? 1 : 7,
      bucketLabel: 'day',
    );
  }

  /// Commission per row of the Finance tab's report: per day for a week or
  /// month, per month for a quarter or year.
  _RevenueSeries _commissionSeries(SalesReport report) {
    final bool daily = report.breakdown == SalesBreakdown.daily;
    final bool week = report.range.period == FinancePeriod.week;
    return _RevenueSeries(
      values: <double>[
        for (final SalesRow row in report.rows) row.commissionCentavos / 100,
      ],
      labels: <String>[
        for (final SalesRow row in report.rows)
          week
              ? kSalesWeekdays[row.start.weekday - 1]
              : daily
              ? '${_monthNames[row.start.month - 1]} ${row.start.day}'
              : _monthNames[row.start.month - 1],
      ],
      labelEvery: daily && !week ? 7 : 1,
      bucketLabel: daily ? 'day' : 'month',
    );
  }
}

/// One `stats_daily/{YYYY-MM-DD}` doc: SmartPark's commission and the
/// number of payments for a Manila calendar day.
class _DayStat {
  const _DayStat({
    required this.day,
    required this.commission,
    required this.paymentCount,
  });

  final DateTime day;
  final double commission;
  final int paymentCount;

  static _DayStat? fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final Map<String, dynamic> data = doc.data();
    final DateTime? day = DateTime.tryParse(
      (data['date'] as String?) ?? doc.id,
    );
    if (day == null) return null;
    return _DayStat(
      day: DateTime(day.year, day.month, day.day),
      commission: ((data['commissionCentavos'] as num?) ?? 0) / 100,
      paymentCount: ((data['paymentCount'] as num?) ?? 0).toInt(),
    );
  }
}

class _RevenueSeries {
  const _RevenueSeries({
    required this.values,
    required this.labels,
    required this.labelEvery,
    required this.bucketLabel,
  });

  final List<double> values;
  final List<String> labels;
  final int labelEvery;

  /// What one bar covers: "day", "week" or "month".
  final String bucketLabel;

  double get total => values.fold<double>(0, (double a, double b) => a + b);
}
