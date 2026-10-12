/// Usage trends for one facility, counted from its gate logs: vehicles per
/// day over a recent range and which hours of the day are busiest. A vehicle
/// is one allowed entry (QR scan or walk-in); exits and denied scans don't
/// count.
class ParkingTrends {
  ParkingTrends._({
    required this.firstDay,
    required this.dailyEntries,
    required this.hourlyEntries,
  });

  /// Counts [logs] into the [days] calendar days ending with [today]
  /// (inclusive). [timeOf] reads a log's time (null for a pending server
  /// timestamp, which counts as [now]); [isEntry] says whether a log is an
  /// allowed entry.
  factory ParkingTrends.fromLogs(
    Iterable<Map<String, dynamic>> logs, {
    required DateTime today,
    required int days,
    required DateTime? Function(Map<String, dynamic> log) timeOf,
    required bool Function(Map<String, dynamic> log) isEntry,
    DateTime? now,
  }) {
    final DateTime firstDay = DateTime(
      today.year,
      today.month,
      today.day - (days - 1),
    );
    final List<int> daily = List<int>.filled(days, 0);
    final List<int> hourly = List<int>.filled(24, 0);
    final DateTime fallback = now ?? DateTime.now();
    for (final Map<String, dynamic> log in logs) {
      if (!isEntry(log)) continue;
      final DateTime time = timeOf(log) ?? fallback;
      final int index = _daysBetween(firstDay, time);
      if (index < 0 || index >= days) continue;
      daily[index]++;
      hourly[time.hour]++;
    }
    return ParkingTrends._(
      firstDay: firstDay,
      dailyEntries: daily,
      hourlyEntries: hourly,
    );
  }

  /// The first day of the range; [dailyEntries][i] is `firstDay + i days`.
  final DateTime firstDay;
  final List<int> dailyEntries;

  /// Entries by hour of day (0 = midnight to 1 AM) across the whole range.
  final List<int> hourlyEntries;

  int get days => dailyEntries.length;
  int get totalEntries => dailyEntries.fold<int>(0, (int a, int b) => a + b);
  double get dailyAverage => days == 0 ? 0 : totalEntries / days;
  bool get isEmpty => totalEntries == 0;

  DateTime dayAt(int index) =>
      DateTime(firstDay.year, firstDay.month, firstDay.day + index);

  /// The day with the most entries (the earliest on a tie, the same bar the
  /// chart highlights), or null when nothing was recorded.
  DateTime? get busiestDay {
    final int index = _peakIndex(dailyEntries, preferLatest: false);
    return index < 0 ? null : dayAt(index);
  }

  int get busiestDayEntries {
    final int index = _peakIndex(dailyEntries, preferLatest: false);
    return index < 0 ? 0 : dailyEntries[index];
  }

  /// Hour of day (0-23) with the most entries (the earliest on a tie), or
  /// null when nothing was recorded.
  int? get peakHour {
    final int index = _peakIndex(hourlyEntries, preferLatest: false);
    return index < 0 ? null : index;
  }

  static int _peakIndex(List<int> values, {required bool preferLatest}) {
    int best = -1;
    for (int i = 0; i < values.length; i++) {
      if (values[i] <= 0) continue;
      if (best < 0 ||
          values[i] > values[best] ||
          (preferLatest && values[i] == values[best])) {
        best = i;
      }
    }
    return best;
  }

  /// Whole calendar days from [from] to [to]'s date (DST-safe: compares
  /// dates, not durations).
  static int _daysBetween(DateTime from, DateTime to) => DateTime.utc(
    to.year,
    to.month,
    to.day,
  ).difference(DateTime.utc(from.year, from.month, from.day)).inDays;
}

/// "5 PM", "12 AM": an hour of day on the 12-hour clock.
String trendHourLabel(int hour) {
  final int h = hour % 12 == 0 ? 12 : hour % 12;
  return '$h ${hour < 12 ? 'AM' : 'PM'}';
}

/// "5–6 PM", "11 AM–12 PM": the one-hour window starting at [hour].
String trendHourRange(int hour) {
  final int next = (hour + 1) % 24;
  final String start = trendHourLabel(hour);
  final String end = trendHourLabel(next);
  final bool sameHalf = (hour < 12) == (next < 12) && next != 0;
  return sameHalf ? '${start.split(' ').first}–$end' : '$start–$end';
}
