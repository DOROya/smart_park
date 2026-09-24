part of '../admin_home_page.dart';

/// Dashboard and Finance chart series built from `stats_daily`.
extension _AdminFinanceSeries on _AdminHomePageState {
  DateTime? _paymentDate(_DayStat day) => day.day;

  double _paymentAmount(_DayStat day) => day.gross;

  double _paymentCommission(_DayStat day) => day.commission;

  double _sumGross(List<_DayStat> days) =>
      days.fold<double>(0, (double sum, _DayStat d) => sum + d.gross);

  double _sumCommission(List<_DayStat> days) =>
      days.fold<double>(0, (double sum, _DayStat d) => sum + d.commission);

  int _sumPayments(List<_DayStat> days) =>
      days.fold<int>(0, (int sum, _DayStat d) => sum + d.paymentCount);

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

  /// Gross payment amount per day for the last [days] days (oldest first).
  /// Pass [amountOf] to sum something other than the gross amount.
  _RevenueSeries _dailyRevenue(
    List<_DayStat> payments,
    int days, {
    double Function(_DayStat)? amountOf,
  }) {
    final double Function(_DayStat) amount = amountOf ?? _paymentAmount;
    const List<String> weekdays = <String>[
      'Mon',
      'Tue',
      'Wed',
      'Thu',
      'Fri',
      'Sat',
      'Sun',
    ];
    final DateTime now = DateTime.now();
    final DateTime start = DateTime(now.year, now.month, now.day - (days - 1));
    final List<double> values = List<double>.filled(days, 0);
    for (final _DayStat doc in payments) {
      final DateTime? date = _paymentDate(doc);
      if (date == null) continue;
      final int index = DateTime(
        date.year,
        date.month,
        date.day,
      ).difference(start).inDays;
      if (index >= 0 && index < days) values[index] += amount(doc);
    }
    final List<String> labels = List<String>.generate(days, (int i) {
      final DateTime day = DateTime(start.year, start.month, start.day + i);
      if (days <= 7) {
        return i == days - 1 ? 'Today' : weekdays[day.weekday - 1];
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

  /// Gross payment amount per 7-day bucket, ending today.
  _RevenueSeries _weeklyRevenue(List<_DayStat> payments, int weeks) {
    final DateTime now = DateTime.now();
    final DateTime start = DateTime(
      now.year,
      now.month,
      now.day - (weeks * 7 - 1),
    );
    final List<double> values = List<double>.filled(weeks, 0);
    for (final _DayStat doc in payments) {
      final DateTime? date = _paymentDate(doc);
      if (date == null) continue;
      final int days = DateTime(
        date.year,
        date.month,
        date.day,
      ).difference(start).inDays;
      if (days >= 0 && days < weeks * 7) {
        values[days ~/ 7] += _paymentAmount(doc);
      }
    }
    return _RevenueSeries(
      values: values,
      labels: List<String>.generate(weeks, (int i) {
        final DateTime day = DateTime(
          start.year,
          start.month,
          start.day + i * 7,
        );
        return '${_monthNames[day.month - 1]} ${day.day}';
      }),
      labelEvery: 3,
      bucketLabel: 'week',
    );
  }

  /// Gross payment amount per calendar month for the last [months] months.
  _RevenueSeries _monthlyRevenue(List<_DayStat> payments, int months) {
    final DateTime now = DateTime.now();
    final DateTime start = DateTime(now.year, now.month - (months - 1));
    final List<double> values = List<double>.filled(months, 0);
    for (final _DayStat doc in payments) {
      final DateTime? date = _paymentDate(doc);
      if (date == null) continue;
      final int index =
          (date.year - start.year) * 12 + date.month - start.month;
      if (index >= 0 && index < months) values[index] += _paymentAmount(doc);
    }
    return _RevenueSeries(
      values: values,
      labels: List<String>.generate(months, (int i) {
        final DateTime month = DateTime(start.year, start.month + i);
        final String name = _monthNames[month.month - 1];
        return months > 12
            ? "$name '${(month.year % 100).toString().padLeft(2, '0')}"
            : name;
      }),
      labelEvery: months > 12 ? (months / 6).ceil() : 1,
      bucketLabel: 'month',
    );
  }

  /// Chart series matching the selected finance range.
  _RevenueSeries _financeRevenueSeries(List<_DayStat> payments) {
    switch (_financeRange) {
      case _FinanceRangeFilter.month:
        return _dailyRevenue(payments, 30);
      case _FinanceRangeFilter.quarter:
        return _weeklyRevenue(payments, 13);
      case _FinanceRangeFilter.year:
        return _monthlyRevenue(payments, 12);
      case _FinanceRangeFilter.all:
        final DateTime now = DateTime.now();
        DateTime? earliest;
        for (final _DayStat doc in payments) {
          final DateTime? date = _paymentDate(doc);
          if (date != null && (earliest == null || date.isBefore(earliest))) {
            earliest = date;
          }
        }
        final int span = earliest == null
            ? 6
            : (now.year - earliest.year) * 12 + now.month - earliest.month + 1;
        return _monthlyRevenue(payments, span.clamp(6, 36));
    }
  }
}

/// One `stats_daily/{YYYY-MM-DD}` doc: paid totals for a Manila calendar day.
class _DayStat {
  const _DayStat({
    required this.day,
    required this.gross,
    required this.commission,
    required this.paymentCount,
  });

  final DateTime day;
  final double gross;
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
      gross: ((data['grossCentavos'] as num?) ?? 0) / 100,
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
