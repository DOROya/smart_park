part of 'package:smart_park/screens/parking_owner/parking_owner_home_screen.dart';

class _GateActivityContent extends StatefulWidget {
  const _GateActivityContent({required this.facilityId});

  final String facilityId;

  @override
  State<_GateActivityContent> createState() => _GateActivityContentState();
}

class _GateActivityContentState extends State<_GateActivityContent>
    with SpStreamCache<_GateActivityContent> {
  DateTime _date = DateTime.now();
  String _filter = 'all';

  Future<void> _pickDate() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 1),
    );
    if (picked != null && mounted) {
      setState(() => _date = picked);
    }
  }

  bool _matchesFilter(Map<String, dynamic> data) {
    return switch (_filter) {
      'entry' => spLogScanType(data) == 'entry',
      'exit' => spLogScanType(data) == 'exit',
      'inside' => spIsInsideLog(data),
      _ => true,
    };
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: cachedStream(
        'activity_${widget.facilityId}',
        () => FirebaseFirestore.instance
            .collection('activity_logs')
            .where('establishmentID', isEqualTo: widget.facilityId)
            .orderBy('timestamp', descending: true)
            .snapshots(),
      ),
      builder:
          (
            BuildContext context,
            AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snapshot,
          ) {
            final List<Map<String, dynamic>> logs =
                (snapshot.data?.docs ??
                        <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                    .map(
                      (QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
                          doc.data(),
                    )
                    .toList();
            final SpActivitySummary summary = SpActivitySummary.fromLogs(
              logs,
              _date,
            );
            final List<Map<String, dynamic>> visible = _filter == 'inside'
                ? logs.where(spIsInsideLog).toList()
                : summary.dayLogs.where(_matchesFilter).toList();

            final bool isTablet = spIsTablet(context);

            int cashDueCount = 0;
            double cashDueTotal = 0;
            for (final Map<String, dynamic> data in logs) {
              if (((data['overtimeStatus'] as String?) ?? '').toLowerCase() ==
                  'cash_due') {
                cashDueCount++;
                cashDueTotal += ((data['overtimeAmount'] as num?) ?? 0)
                    .toDouble();
              }
            }

            return ListView(
              padding: const EdgeInsets.only(top: 8),
              children: [
                SpPageHeader(
                  title: 'Activity',
                  subtitle: 'Gate scans recorded by your staff.',
                  trailing: SpDateButton(date: _date, onTap: _pickDate),
                ),
                const SizedBox(height: 16),
                if (cashDueCount > 0) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.warningSoft,
                      borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
                      border: Border.all(color: AppTheme.accent),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.payments_rounded, color: spInsideColor),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'PHP ${cashDueTotal.toStringAsFixed(2)} overtime cash',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.textDark,
                                ),
                              ),
                              Text(
                                '$cashDueCount exit(s) flagged for cash '
                                'collection at the gate.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.accentText,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                SpDailyActivityTiles(
                  summary: summary,
                  today: spSameDate(_date, DateTime.now()),
                  singleRow: isTablet,
                ),
                const SizedBox(height: 16),
                SpSegmentedControl<String>(
                  options: const <(String, String)>[
                    ('all', 'All'),
                    ('entry', 'Entries'),
                    ('exit', 'Exits'),
                    ('inside', 'Inside'),
                  ],
                  selected: _filter,
                  onChanged: (String value) => setState(() => _filter = value),
                ),
                const SizedBox(height: 12),
                if (snapshot.hasError)
                  const SpEmptyState(
                    icon: Icons.error_outline_rounded,
                    message: 'Unable to load activity.',
                  )
                else if (!snapshot.hasData)
                  const SpSkeletonList()
                else if (visible.isEmpty)
                  const SpEmptyState(
                    message: 'No scans for this filter and date.',
                  )
                else if (isTablet)
                  SpGrid(
                    children: [
                      for (final Map<String, dynamic> data in visible)
                        SpActivityCard(
                          data: data,
                          showDate: _filter == 'inside',
                        ),
                    ],
                  )
                else
                  for (final Map<String, dynamic> data in visible)
                    SpActivityCard(data: data, showDate: _filter == 'inside'),
              ],
            );
          },
    );
  }
}
