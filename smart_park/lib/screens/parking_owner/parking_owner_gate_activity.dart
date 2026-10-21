part of 'package:smart_park/screens/parking_owner/parking_owner_home_screen.dart';

/// Staff uid-to-name map, deactivated staff included (and marked). Older
/// records use a random doc id, so the uid comes from `userId` when present.
Map<String, String> _staffNameMap(
  Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
) {
  final Map<String, String> names = <String, String>{};
  for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in docs) {
    final Map<String, dynamic> data = doc.data();
    final String uid = ((data['userId'] as String?) ?? '').trim();
    final String name = ((data['name'] as String?) ?? '').trim();
    names[uid.isEmpty ? doc.id : uid] = isStaffRecordActive(data)
        ? name
        : '${name.isEmpty ? 'Unnamed staff' : name} (deactivated)';
  }
  return names;
}

/// Owner changes an exit's overtime status from the scan details sheet.
/// Shows the error and rethrows so the sheet keeps the old status.
Future<void> _ownerSetOvertimeStatus(
  BuildContext context,
  Map<String, dynamic> log,
  String status,
) async {
  final String ownerId = FirebaseAuth.instance.currentUser?.uid ?? '';
  final String transactionId = ((log['transactionId'] as String?) ?? '').trim();
  try {
    await setOvertimeStatusAsOwner(
      ownerId: ownerId,
      transactionId: transactionId,
      status: status,
    );
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlyError(error, fallback: 'Could not update overtime.'),
          ),
        ),
      );
    }
    rethrow;
  }
}

class _GateActivityContent extends StatefulWidget {
  const _GateActivityContent({
    required this.facilityId,
    required this.ownerId,
    required this.staffFilter,
    required this.onStaffFilterChanged,
  });

  final String facilityId;
  final String ownerId;

  /// Staff uid to show scans for; null shows everyone's.
  final String? staffFilter;
  final ValueChanged<String?> onStaffFilterChanged;

  @override
  State<_GateActivityContent> createState() => _GateActivityContentState();
}

class _GateActivityContentState extends State<_GateActivityContent>
    with SpStreamCache<_GateActivityContent> {
  DateTime _date = DateTime.now();
  String _filter = 'all';

  /// Text in the search box: part of a plate, a staff name or a ticket #.
  String _query = '';

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

  bool _matchesFilter(
    Map<String, dynamic> data,
    Map<String, String>? staffNames,
  ) {
    final String? staffId = widget.staffFilter;
    if (staffId != null && data['staffId'] != staffId) return false;
    if (!spActivityMatchesQuery(data, _query, staffNames)) return false;
    return switch (_filter) {
      'entry' => spLogScanType(data) == 'entry',
      'exit' => spLogScanType(data) == 'exit',
      'inside' => spIsInsideLog(data),
      _ => true,
    };
  }

  /// Everyone who appears in the staff list or in the logs, so removed staff
  /// can still be filtered on.
  List<(String, String)> _staffOptions(
    Map<String, String> staffNames,
    List<Map<String, dynamic>> logs,
  ) {
    final Map<String, String> options = <String, String>{
      for (final MapEntry<String, String> e in staffNames.entries)
        e.key: e.value.isEmpty ? 'Unnamed staff' : e.value,
    };
    for (final Map<String, dynamic> data in logs) {
      final String staffId = ((data['staffId'] as String?) ?? '').trim();
      if (staffId.isEmpty || options.containsKey(staffId)) continue;
      options[staffId] = '${spLogStaffName(data) ?? 'Unknown staff'} (removed)';
    }
    final List<(String, String)> sorted = <(String, String)>[
      for (final MapEntry<String, String> e in options.entries)
        (e.key, e.value),
    ];
    sorted.sort(
      ((String, String) a, (String, String) b) =>
          a.$2.toLowerCase().compareTo(b.$2.toLowerCase()),
    );
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: cachedStream(
        'staff_${widget.ownerId}',
        () => FirebaseFirestore.instance
            .collection('staff_accounts')
            .where('ownerId', isEqualTo: widget.ownerId)
            .snapshots(),
      ),
      builder: (context, staffSnapshot) {
        // Null until loaded, so nobody is flagged as removed too early.
        final Map<String, String>? staffNames = staffSnapshot.hasData
            ? _staffNameMap(staffSnapshot.data!.docs)
            : null;
        return _buildActivity(staffNames);
      },
    );
  }

  Widget _buildActivity(Map<String, String>? staffNames) {
    // Only the picked day is loaded, not the facility's whole history.
    return withDayLogs(
      widget.facilityId,
      _date,
      builder: (BuildContext context, SpDayLogs day) {
        final List<Map<String, dynamic>> logs = day.logs;
        final List<Map<String, dynamic>> insideLogs = day.insideLogs;
        final SpActivitySummary summary = SpActivitySummary.fromLogs(
          logs,
          _date,
          insideLogs: insideLogs,
        );
        bool matches(Map<String, dynamic> d) => _matchesFilter(d, staffNames);
        final List<Map<String, dynamic>> visible = _filter == 'inside'
            ? insideLogs.where(matches).toList()
            : summary.dayLogs.where(matches).toList();
        final List<(String, String)> staffOptions = _staffOptions(
          staffNames ?? const <String, String>{},
          <Map<String, dynamic>>[...logs, ...insideLogs],
        );

        final bool isTablet = spIsTablet(context);

        final String? staffId = widget.staffFilter;
        final SpOvertimeCash overtimeCash = SpOvertimeCash.from(
          summary.dayLogs.where(
            (Map<String, dynamic> d) =>
                staffId == null || d['staffId'] == staffId,
          ),
        );

        Widget card(Map<String, dynamic> data) => SpActivityCard(
          data: data,
          showDate: _filter == 'inside',
          staffNames: staffNames,
          onTap: () => showSpActivityDetails(
            context,
            canReportDriver: true,
            log: data,
            staffNames: staffNames,
            onSetOvertimeStatus: (Map<String, dynamic> log, String status) =>
                _ownerSetOvertimeStatus(context, log, status),
          ),
        );

        return ListView(
          padding: const EdgeInsets.only(top: 8),
          children: [
            SpPageHeader(
              title: 'Activity',
              subtitle: 'Gate scans recorded by your staff.',
              trailing: SpDateButton(date: _date, onTap: _pickDate),
            ),
            const SizedBox(height: 16),
            if (!overtimeCash.isEmpty) ...[
              SpOvertimeCashBanner(
                cash: overtimeCash,
                period: spSameDate(_date, DateTime.now())
                    ? 'today'
                    : 'on this day',
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
            const SizedBox(height: 8),
            SpActivitySearch(
              logs: _filter == 'inside' ? insideLogs : summary.dayLogs,
              staff: staffOptions,
              query: _query,
              onQueryChanged: (String value) => setState(() => _query = value),
              staffFilter: widget.staffFilter,
              onStaffFilterChanged: widget.onStaffFilterChanged,
            ),
            const SizedBox(height: 12),
            if (day.error != null)
              const SpEmptyState(
                icon: Icons.error_outline_rounded,
                message: 'Unable to load activity.',
              )
            else if (!day.loaded)
              const SpSkeletonList()
            else if (visible.isEmpty)
              SpEmptyState(
                icon: _query.trim().isEmpty
                    ? Icons.receipt_long_rounded
                    : Icons.search_off_rounded,
                message: _query.trim().isNotEmpty
                    ? 'No scans match "${_query.trim()}" for this filter '
                          'and date.'
                    : widget.staffFilter == null
                    ? 'No scans for this filter and date.'
                    : 'No scans by this staff member for this filter '
                          'and date.',
              )
            else if (isTablet)
              SpGrid(
                children: [
                  for (final Map<String, dynamic> data in visible) card(data),
                ],
              )
            else
              for (final Map<String, dynamic> data in visible) card(data),
          ],
        );
      },
    );
  }
}
