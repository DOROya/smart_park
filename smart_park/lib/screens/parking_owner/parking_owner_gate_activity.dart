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
    final String? staffId = widget.staffFilter;
    if (staffId != null && data['staffId'] != staffId) return false;
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

  Widget _staffPicker(List<(String, String)> options) {
    final String? selected = widget.staffFilter;
    String label = 'All staff';
    for (final (String id, String name) in options) {
      if (id == selected) label = name;
    }
    return PopupMenuButton<String>(
      tooltip: 'Filter by staff',
      initialValue: selected ?? '',
      onSelected: (String value) =>
          widget.onStaffFilterChanged(value.isEmpty ? null : value),
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        const PopupMenuItem<String>(value: '', child: Text('All staff')),
        for (final (String id, String name) in options)
          PopupMenuItem<String>(value: id, child: Text(name)),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected == null ? AppTheme.surface : AppTheme.warningSoft,
          borderRadius: BorderRadius.circular(AppTheme.radius),
          border: Border.all(
            color: selected == null ? spCardBorder : AppTheme.accent,
          ),
        ),
        child: Row(
          children: <Widget>[
            Icon(Icons.badge_outlined, size: 18, color: AppTheme.textMuted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textDark,
                ),
              ),
            ),
            if (selected != null)
              GestureDetector(
                onTap: () => widget.onStaffFilterChanged(null),
                child: Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: AppTheme.textMuted,
                ),
              )
            else
              Icon(Icons.expand_more_rounded, color: AppTheme.textMuted),
          ],
        ),
      ),
    );
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
        final List<Map<String, dynamic>> visible = _filter == 'inside'
            ? insideLogs.where(_matchesFilter).toList()
            : summary.dayLogs.where(_matchesFilter).toList();
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
          onTap: () =>
              showSpActivityDetails(context, log: data, staffNames: staffNames),
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
            _staffPicker(staffOptions),
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
                message: widget.staffFilter == null
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
