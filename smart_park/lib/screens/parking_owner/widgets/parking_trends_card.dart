import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../services/parking_trends.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/smartpark_ui.dart';
import '../../../widgets/sp_loading.dart';

/// The owner's usage trends: vehicles per day over the last 7 or 30 days and
/// the busiest hours of the day, from the facility's gate logs (QR scans and
/// walk-ins alike).
class ParkingTrendsCard extends StatefulWidget {
  const ParkingTrendsCard({
    super.key,
    required this.facilityId,
    this.firestore,
  });

  final String facilityId;

  /// Defaults to [FirebaseFirestore.instance]; tests pass a fake.
  final FirebaseFirestore? firestore;

  @override
  State<ParkingTrendsCard> createState() => _ParkingTrendsCardState();
}

class _ParkingTrendsCardState extends State<ParkingTrendsCard>
    with SpStreamCache<ParkingTrendsCard> {
  int _days = 7;

  static const List<String> _weekdays = <String>[
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  /// Only the selected range is downloaded, not the whole scan history.
  Query<Map<String, dynamic>> _rangeQuery(DateTime firstDay) {
    return (widget.firestore ?? FirebaseFirestore.instance)
        .collection('activity_logs')
        .where('establishmentID', isEqualTo: widget.facilityId)
        .where(
          'timestamp',
          isGreaterThanOrEqualTo: Timestamp.fromDate(firstDay),
        )
        .orderBy('timestamp', descending: true);
  }

  static String _count(int n, String one, [String? many]) =>
      '$n ${n == 1 ? one : (many ?? '${one}s')}';

  static String _shortHour(int hour) {
    if (hour == 0) return '12a';
    if (hour == 12) return '12p';
    return hour < 12 ? '${hour}a' : '${hour - 12}p';
  }

  @override
  Widget build(BuildContext context) {
    final DateTime now = DateTime.now();
    final DateTime firstDay = DateTime(
      now.year,
      now.month,
      now.day - (_days - 1),
    );

    return SpSectionCard(
      icon: Icons.insights_rounded,
      title: 'Parking Trends',
      subtitle: 'Vehicles that entered, including walk-ins.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SpSegmentedControl<int>(
            options: const <(int, String)>[
              (7, 'Last 7 days'),
              (30, 'Last 30 days'),
            ],
            selected: _days,
            onChanged: (int value) => setState(() => _days = value),
          ),
          const SizedBox(height: 14),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            // Keyed by the first day, so a new range or a new day re-queries.
            stream: cachedStream(
              'trends_${widget.facilityId}_${spDayKey(firstDay)}',
              () =>
                  _rangeQuery(firstDay).snapshots(includeMetadataChanges: true),
            ),
            builder: (BuildContext context, snapshot) {
              if (snapshot.hasError) {
                return const SpEmptyState(
                  boxed: false,
                  icon: Icons.error_outline_rounded,
                  message: 'Unable to load trends right now.',
                );
              }
              // A new range first answers from the offline cache, which can
              // be empty; wait for the server before saying "no vehicles".
              if (!snapshot.hasData ||
                  (snapshot.data!.docs.isEmpty &&
                      snapshot.data!.metadata.isFromCache)) {
                return const SpSkeletonList();
              }
              final ParkingTrends trends = ParkingTrends.fromLogs(
                spDocsData(snapshot),
                today: now,
                days: _days,
                now: now,
                timeOf: (Map<String, dynamic> log) =>
                    spParseDateTime(log['timestamp']),
                isEntry: (Map<String, dynamic> log) =>
                    spIsAllowedLog(log) && spLogScanType(log) == 'entry',
              );
              if (trends.isEmpty) {
                return SpEmptyState(
                  boxed: false,
                  icon: Icons.insights_outlined,
                  message:
                      'No vehicles in the last $_days days yet. Trends appear '
                      'once your staff scan entries.',
                );
              }
              return _buildTrends(trends);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTrends(ParkingTrends trends) {
    final DateTime? busiest = trends.busiestDay;
    final int? peakHour = trends.peakHour;
    final double average = trends.dailyAverage;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _TrendStat(
                icon: Icons.directions_car_rounded,
                color: spEntryColor,
                label: 'Vehicles',
                value: '${trends.totalEntries}',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _TrendStat(
                icon: Icons.show_chart_rounded,
                color: spExitColor,
                label: 'Daily average',
                value: average.toStringAsFixed(average % 1 == 0 ? 0 : 1),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _TrendStat(
                icon: Icons.event_available_rounded,
                color: spInsideColor,
                label: 'Busiest day',
                value: busiest == null
                    ? '—'
                    : '${_weekdays[busiest.weekday - 1]}, '
                          '${spFormatDate(busiest).split(',').first}',
                caption: _count(trends.busiestDayEntries, 'vehicle'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _TrendStat(
                icon: Icons.schedule_rounded,
                color: AppTheme.warning,
                label: 'Peak hour',
                value: peakHour == null ? '—' : trendHourRange(peakHour),
                caption: peakHour == null
                    ? null
                    : _count(
                        trends.hourlyEntries[peakHour],
                        'entry',
                        'entries',
                      ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        const _ChartTitle('Vehicles per day'),
        const SizedBox(height: 8),
        SpBarChart(
          values: <double>[
            for (final int count in trends.dailyEntries) count.toDouble(),
          ],
          labels: <String>[
            for (int i = 0; i < trends.days; i++)
              trends.days <= 7
                  ? _weekdays[trends.dayAt(i).weekday - 1]
                  : '${trends.dayAt(i).day}',
          ],
          // 30 bars: label every 5th day so the dates stay readable.
          labelEvery: trends.days <= 7 ? 1 : 5,
          formatValue: (double v) => v.toStringAsFixed(0),
          color: spEntryColor,
        ),
        const SizedBox(height: 18),
        const _ChartTitle('Busiest hours'),
        const SizedBox(height: 8),
        SpBarChart(
          values: <double>[
            for (final int count in trends.hourlyEntries) count.toDouble(),
          ],
          labels: <String>[for (int h = 0; h < 24; h++) _shortHour(h)],
          labelEvery: 3,
          formatValue: (double v) => v.toStringAsFixed(0),
          color: AppTheme.warning,
        ),
        const SizedBox(height: 6),
        Text(
          'Entries by hour of day, across the last ${trends.days} days.',
          style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
        ),
      ],
    );
  }
}

class _ChartTitle extends StatelessWidget {
  const _ChartTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: AppTheme.textDark,
        fontSize: 13,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _TrendStat extends StatelessWidget {
  const _TrendStat({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    this.caption,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppTheme.textDark,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (caption != null)
            Text(
              caption!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
            ),
        ],
      ),
    );
  }
}
