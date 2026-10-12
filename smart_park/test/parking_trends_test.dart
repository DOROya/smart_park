import 'package:flutter_test/flutter_test.dart';
import 'package:smart_park/services/parking_trends.dart';

void main() {
  // Monday, Oct 12 2026, 6 PM.
  final DateTime today = DateTime(2026, 10, 12, 18);

  Map<String, dynamic> log(
    DateTime? at, {
    String scanType = 'entry',
    String status = 'ALLOWED',
  }) => <String, dynamic>{'at': at, 'scanType': scanType, 'status': status};

  ParkingTrends trends(List<Map<String, dynamic>> logs, {int days = 7}) =>
      ParkingTrends.fromLogs(
        logs,
        today: today,
        days: days,
        now: today,
        timeOf: (Map<String, dynamic> l) => l['at'] as DateTime?,
        isEntry: (Map<String, dynamic> l) =>
            l['status'] == 'ALLOWED' && l['scanType'] == 'entry',
      );

  test('counts allowed entries per day and per hour', () {
    final ParkingTrends t = trends(<Map<String, dynamic>>[
      log(DateTime(2026, 10, 12, 9, 5)),
      log(DateTime(2026, 10, 12, 9, 50)),
      log(DateTime(2026, 10, 11, 17, 30)),
      log(DateTime(2026, 10, 6, 8)), // first day of the 7-day range
    ]);
    expect(t.days, 7);
    expect(t.firstDay, DateTime(2026, 10, 6));
    expect(t.dailyEntries, <int>[1, 0, 0, 0, 0, 1, 2]);
    expect(t.totalEntries, 4);
    expect(t.dailyAverage, closeTo(4 / 7, 1e-9));
    expect(t.hourlyEntries[9], 2);
    expect(t.hourlyEntries[17], 1);
    expect(t.hourlyEntries[8], 1);
    expect(t.peakHour, 9);
    expect(t.busiestDay, DateTime(2026, 10, 12));
    expect(t.busiestDayEntries, 2);
  });

  test('exits, denied scans and days outside the range are ignored', () {
    final ParkingTrends t = trends(<Map<String, dynamic>>[
      log(DateTime(2026, 10, 12, 10), scanType: 'exit'),
      log(DateTime(2026, 10, 12, 10), status: 'DENIED'),
      log(DateTime(2026, 10, 5, 23, 59)), // day before the range
      log(DateTime(2026, 10, 13, 0, 1)), // tomorrow
    ]);
    expect(t.isEmpty, isTrue);
    expect(t.peakHour, isNull);
    expect(t.busiestDay, isNull);
  });

  test('a pending server timestamp counts as now', () {
    final ParkingTrends t = trends(<Map<String, dynamic>>[log(null)]);
    expect(t.dailyEntries.last, 1);
    expect(t.peakHour, 18);
  });

  test('30-day range spans the month boundary', () {
    final ParkingTrends t = trends(<Map<String, dynamic>>[
      log(DateTime(2026, 9, 13, 12)), // first day of 30
      log(DateTime(2026, 9, 30, 12)),
      log(DateTime(2026, 10, 1, 12)),
    ], days: 30);
    expect(t.firstDay, DateTime(2026, 9, 13));
    expect(t.dailyEntries.first, 1);
    expect(t.dailyEntries[17], 1); // Sep 30
    expect(t.dailyEntries[18], 1); // Oct 1
    expect(t.totalEntries, 3);
  });

  test('ties pick the earliest day and hour, like the chart highlight', () {
    final ParkingTrends t = trends(<Map<String, dynamic>>[
      log(DateTime(2026, 10, 7, 15)),
      log(DateTime(2026, 10, 9, 8)),
    ]);
    expect(t.busiestDay, DateTime(2026, 10, 7));
    expect(t.peakHour, 8);
  });

  test('hour labels read naturally on the 12-hour clock', () {
    expect(trendHourLabel(0), '12 AM');
    expect(trendHourLabel(12), '12 PM');
    expect(trendHourRange(0), '12–1 AM');
    expect(trendHourRange(9), '9–10 AM');
    expect(trendHourRange(11), '11 AM–12 PM');
    expect(trendHourRange(17), '5–6 PM');
    expect(trendHourRange(23), '11 PM–12 AM');
  });
}
