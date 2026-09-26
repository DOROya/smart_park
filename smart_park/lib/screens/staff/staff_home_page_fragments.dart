// ignore_for_file: invalid_use_of_protected_member

part of 'staff_home_page.dart';

DateTime? _parseDateTime(dynamic value) {
  if (value == null) return null;
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  return null;
}

extension _StaffHomePageFragments on _StaffHomePageState {
  Widget _buildDashboardTab(Map<String, dynamic> userData) {
    if (_assignedFacilityId == null || _assignedFacilityId!.isEmpty) {
      return Center(
        child: Text(
          'No facility assignment found yet.',
          style: TextStyle(color: AppTheme.textMuted),
        ),
      );
    }

    final String roleLabel =
        ((userData['staffRole'] as String?) ??
                (userData['role'] as String?) ??
                'Staff')
            .trim();
    final String firstName = ((userData['firstName'] as String?) ?? '').trim();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: cachedStream(
        'activity_$_assignedFacilityId',
        () => FirebaseFirestore.instance
            .collection('activity_logs')
            .where('establishmentID', isEqualTo: _assignedFacilityId)
            .snapshots(),
      ),
      builder:
          (
            BuildContext context,
            AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> activitySnapshot,
          ) {
            return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: cachedStream(
                'establishment_$_assignedFacilityId',
                () => FirebaseFirestore.instance
                    .collection('establishments')
                    .doc(_assignedFacilityId)
                    .snapshots(),
              ),
              builder:
                  (
                    BuildContext context,
                    AsyncSnapshot<DocumentSnapshot<Map<String, dynamic>>>
                    facilitySnapshot,
                  ) {
                    return StreamBuilder<
                      DocumentSnapshot<Map<String, dynamic>>
                    >(
                      stream: cachedStream(
                        'details_$_assignedFacilityId',
                        () => FirebaseFirestore.instance
                            .collection('establishment_details')
                            .doc(_assignedFacilityId)
                            .snapshots(),
                      ),
                      builder:
                          (
                            BuildContext context,
                            AsyncSnapshot<
                              DocumentSnapshot<Map<String, dynamic>>
                            >
                            detailsSnapshot,
                          ) {
                            final DateTime now = DateTime.now();
                            final SpActivitySummary summary =
                                SpActivitySummary.fromLogs(
                                  (activitySnapshot.data?.docs ??
                                          <
                                            QueryDocumentSnapshot<
                                              Map<String, dynamic>
                                            >
                                          >[])
                                      .map(
                                        (
                                          QueryDocumentSnapshot<
                                            Map<String, dynamic>
                                          >
                                          doc,
                                        ) => doc.data(),
                                      ),
                                  now,
                                );

                            final Map<String, dynamic> facility =
                                facilitySnapshot.data?.data() ??
                                <String, dynamic>{};
                            final Map<String, dynamic> details =
                                detailsSnapshot.data?.data() ??
                                <String, dynamic>{};
                            final String facilityName =
                                ((facility['name'] as String?) ?? '').trim();
                            final Map<dynamic, dynamic> slotCounts =
                                (details['slotCounts']
                                    as Map<dynamic, dynamic>?) ??
                                <dynamic, dynamic>{};
                            final int carSlots =
                                ((slotCounts['car'] as num?) ?? 0).toInt();
                            final int motorcycleSlots =
                                ((slotCounts['motorcycle'] as num?) ?? 0)
                                    .toInt();
                            final int slotSum = carSlots + motorcycleSlots;
                            final int totalSlots = slotSum > 0
                                ? slotSum
                                : ((facility['availability'] as num?) ?? 0)
                                      .toInt();

                            return ListView(
                              padding: const EdgeInsets.all(16),
                              children: [
                                SpHeroBanner(
                                  title: firstName.isEmpty
                                      ? spGreeting(now)
                                      : '${spGreeting(now)}, $firstName',
                                  badge: roleLabel,
                                  details: <(IconData, String)>[
                                    (
                                      Icons.storefront_rounded,
                                      facilityName.isEmpty
                                          ? 'Assigned facility'
                                          : facilityName,
                                    ),
                                    (
                                      Icons.calendar_today_rounded,
                                      spFormatDate(now),
                                    ),
                                  ],
                                  action: SpHeroButton(
                                    icon: Icons.qr_code_scanner_rounded,
                                    label: 'Open Gate Scanner',
                                    onPressed: () {
                                      setState(() {
                                        _selectedNavIndex = 1;
                                      });
                                    },
                                  ),
                                ),
                                const SizedBox(height: 16),
                                const SpSectionLabel("Today's Activity"),
                                const SizedBox(height: 10),
                                SpDailyActivityTiles(summary: summary),
                                const SizedBox(height: 16),
                                SpLiveSlotsCard(
                                  establishmentId: _assignedFacilityId ?? '',
                                  totalSlots: totalSlots,
                                  fallbackOccupied: summary.insideNow,
                                  carSlots: carSlots,
                                  motorcycleSlots: motorcycleSlots,
                                ),
                                const SizedBox(height: 16),
                                SpSectionLabel(
                                  'Recent Scans',
                                  trailing: summary.dayLogs.isEmpty
                                      ? null
                                      : TextButton(
                                          onPressed: () {
                                            setState(() {
                                              _selectedHistoryDate =
                                                  DateTime.now();
                                              _selectedNavIndex = 2;
                                            });
                                          },
                                          child: const Text('View all'),
                                        ),
                                ),
                                const SizedBox(height: 6),
                                if (summary.dayLogs.isEmpty)
                                  const SpEmptyState(
                                    message: 'No scans yet today.',
                                  )
                                else
                                  for (final Map<String, dynamic> data
                                      in summary.dayLogs.take(3))
                                    SpActivityCard(data: data),
                              ],
                            );
                          },
                    );
                  },
            );
          },
    );
  }

  Widget _gateModeSelector() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(AppTheme.radius),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _gateModeButton('entry', Icons.login_rounded, 'Entry'),
          ),
          Expanded(
            child: _gateModeButton('exit', Icons.logout_rounded, 'Exit'),
          ),
        ],
      ),
    );
  }

  Widget _gateModeButton(String mode, IconData icon, String label) {
    final bool selected = _gateMode == mode;
    return GestureDetector(
      onTap: () {
        if (_gateMode != mode && mounted) {
          setState(() {
            _gateMode = mode;
          });
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppTheme.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          boxShadow: selected
              ? const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              icon,
              size: 18,
              color: selected ? AppTheme.textDark : AppTheme.textMuted,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: selected ? AppTheme.textDark : AppTheme.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQrTab() {
    final String? facilityId = _assignedFacilityId;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Scan Customer QR Code',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppTheme.textDark,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Set Entry or Exit first, then place the QR code in the frame.',
          style: TextStyle(color: AppTheme.textMuted),
        ),
        const SizedBox(height: 12),
        _gateModeSelector(),
        const SizedBox(height: 8),
        Text(
          _gateMode == 'entry'
              ? 'Entry mode: tickets are verified and checked in.'
              : 'Exit mode: stay time is checked, overtime is billed.',
          style: TextStyle(
            color: AppTheme.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        FutureBuilder<bool>(
          future: _permissionService.ensureCameraPermissionForQr(context),
          builder:
              (BuildContext context, AsyncSnapshot<bool> permissionSnapshot) {
                if (permissionSnapshot.connectionState ==
                    ConnectionState.waiting) {
                  return const SizedBox(
                    height: 280,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                if (permissionSnapshot.data != true) {
                  return SizedBox(
                    height: 280,
                    child: Center(
                      child: Text(
                        'Camera permission is required for scanning.',
                        style: TextStyle(color: AppTheme.textMuted),
                      ),
                    ),
                  );
                }

                return SizedBox(
                  height: 280,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        MobileScanner(
                          controller: _scannerController,
                          onDetect: _onBarcodeDetect,
                        ),
                        Center(
                          child: Container(
                            width: 220,
                            height: 220,
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: AppTheme.accent,
                                width: 4,
                              ),
                              borderRadius: BorderRadius.circular(
                                AppTheme.radiusSmall,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
        ),
        if (_lastScanResult != null) ...[
          const SizedBox(height: 12),
          _GateResultCard(result: _lastScanResult!),
        ],
        const SizedBox(height: 12),
        _ManualPlateLookup(onLookup: _lookupByPlate),
        if (facilityId != null && facilityId.isNotEmpty) ...[
          const SizedBox(height: 12),
          WalkInPanel(facilityId: facilityId, ownerId: _ownerId),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                'Recent Scans',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textDark,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  _selectedNavIndex = 2;
                });
              },
              child: const Text('View All'),
            ),
          ],
        ),
        if (facilityId == null)
          const Text('Assign staff to a facility first.')
        else
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: cachedStream(
              'recent_$facilityId',
              () => FirebaseFirestore.instance
                  .collection('activity_logs')
                  .where('establishmentID', isEqualTo: facilityId)
                  .orderBy('timestamp', descending: true)
                  .limit(5)
                  .snapshots(),
            ),
            builder:
                (
                  BuildContext context,
                  AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snapshot,
                ) {
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return const Text('No scans yet.');
                  }

                  return Column(
                    children: snapshot.data!.docs.map((
                      QueryDocumentSnapshot<Map<String, dynamic>> doc,
                    ) {
                      final Map<String, dynamic> data = doc.data();
                      return SpActivityCard(data: data);
                    }).toList(),
                  );
                },
          ),
      ],
    );
  }

  Widget _buildHistoryTab() {
    final String? facilityId = _assignedFacilityId;
    if (facilityId == null) {
      return const Center(child: Text('No facility assignment found.'));
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: SpPageHeader(
            title: 'History',
            subtitle: 'Gate scans at your facility.',
            trailing: SpDateButton(
              date: _selectedHistoryDate,
              onTap: _pickHistoryDate,
            ),
          ),
        ),
        TabBar(
          controller: _historyTabController,
          labelColor: AppTheme.textDark,
          unselectedLabelColor: AppTheme.textMuted,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700),
          indicatorColor: AppTheme.accent,
          indicatorWeight: 3,
          tabs: const [
            Tab(text: 'All'),
            Tab(text: 'Entries'),
            Tab(text: 'Exits'),
            Tab(text: 'Inside'),
          ],
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: cachedStream(
              'history_$facilityId',
              () => FirebaseFirestore.instance
                  .collection('activity_logs')
                  .where('establishmentID', isEqualTo: facilityId)
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
            ),
            builder:
                (
                  BuildContext context,
                  AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snapshot,
                ) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'Could not load history.\n'
                          '${friendlyError(snapshot.error!, fallback: 'Please try again.')}',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppTheme.textMuted),
                        ),
                      ),
                    );
                  }

                  if (!snapshot.hasData) {
                    return const SpSkeletonList();
                  }

                  final List<Map<String, dynamic>> dayLogs = snapshot.data!.docs
                      .map(
                        (QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
                            doc.data(),
                      )
                      .where((Map<String, dynamic> data) {
                        // Pending server timestamps read as null; treat them as now.
                        final DateTime date =
                            _parseDateTime(data['timestamp']) ?? DateTime.now();
                        return _sameDate(date, _selectedHistoryDate);
                      })
                      .toList();
                  final List<Map<String, dynamic>> filtered = dayLogs
                      .where(_matchesHistoryFilter)
                      .toList();

                  final int entries = dayLogs
                      .where(
                        (Map<String, dynamic> d) =>
                            spIsAllowedLog(d) && spLogScanType(d) == 'entry',
                      )
                      .length;
                  final int exits = dayLogs
                      .where(
                        (Map<String, dynamic> d) =>
                            spIsAllowedLog(d) && spLogScanType(d) == 'exit',
                      )
                      .length;
                  final int denied = dayLogs
                      .where((Map<String, dynamic> d) => !spIsAllowedLog(d))
                      .length;

                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    children: [
                      Row(
                        children: [
                          _historyStat('Entries', entries, AppTheme.success),
                          const SizedBox(width: 8),
                          _historyStat('Exits', exits, AppTheme.info),
                          const SizedBox(width: 8),
                          _historyStat('Denied', denied, AppTheme.danger),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (filtered.isEmpty)
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: 40),
                          child: Column(
                            children: [
                              Icon(
                                Icons.receipt_long_rounded,
                                size: 44,
                                color: AppTheme.borderStrong,
                              ),
                              SizedBox(height: 8),
                              Text(
                                'No scans for this filter and date.',
                                style: TextStyle(color: AppTheme.textMuted),
                              ),
                            ],
                          ),
                        )
                      else
                        for (final Map<String, dynamic> data in filtered)
                          SpActivityCard(data: data),
                    ],
                  );
                },
          ),
        ),
      ],
    );
  }

  Widget _historyStat(String label, int value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.radius),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$value',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppTheme.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(Map<String, dynamic> userData) {
    switch (_selectedNavIndex) {
      case 1:
        return _buildQrTab();
      case 2:
        return _buildHistoryTab();
      case 0:
      default:
        return _buildDashboardTab(userData);
    }
  }

  BottomNavigationBarItem _navItem({
    required IconData icon,
    required String label,
    bool emphasized = false,
  }) {
    return BottomNavigationBarItem(
      icon: emphasized
          ? Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: Color(0x22F2C335),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 28),
            )
          : Icon(icon),
      label: label,
    );
  }
}

class _GateResultCard extends StatelessWidget {
  const _GateResultCard({required this.result});

  final GateScanResult result;

  @override
  Widget build(BuildContext context) {
    final bool allowed = result.isAllowed;
    final Color accent = allowed ? AppTheme.success : AppTheme.danger;
    final Color bg = allowed ? AppTheme.successSoft : AppTheme.dangerSoft;
    final String title = allowed
        ? (result.scanType == 'exit' ? 'Exit allowed' : 'Entry allowed')
        : (result.decision == 'ERROR' ? 'Scan error' : 'Scan denied');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                allowed ? Icons.check_circle_rounded : Icons.cancel_rounded,
                color: accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: accent,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  result.decision,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Plate ${result.vehiclePlate} - ${result.scanType.toUpperCase()}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          if ((result.reason ?? '').isNotEmpty) ...<Widget>[
            const SizedBox(height: 4),
            Text(result.reason!),
          ],
          if (result.scanType == 'exit' && result.elapsed != null) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              'Stay ${_formatStay(result.elapsed!)} - billed '
              '${result.billableHours ?? 2}h (2h base).',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
          if (result.hasOvertime) ...<Widget>[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.warningSoft,
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                border: Border.all(color: AppTheme.accent),
              ),
              child: Row(
                children: <Widget>[
                  Icon(Icons.payments_rounded, color: AppTheme.accentText),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Collect PHP ${result.overtimeAmount!.toStringAsFixed(2)} '
                      'cash for ${result.overtimeHours!.toStringAsFixed(0)}h '
                      'overtime before releasing.',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (result.transactionId != null &&
              result.transactionId!.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              'Ticket ${result.transactionId}',
              style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

String _formatStay(Duration elapsed) {
  final int hours = elapsed.inHours;
  final int minutes = elapsed.inMinutes.remainder(60);
  if (hours <= 0) {
    return '${minutes}m';
  }
  return '${hours}h ${minutes}m';
}

class _ManualPlateLookup extends StatefulWidget {
  const _ManualPlateLookup({required this.onLookup});

  final Future<void> Function(String plate) onLookup;

  @override
  State<_ManualPlateLookup> createState() => _ManualPlateLookupState();
}

class _ManualPlateLookupState extends State<_ManualPlateLookup> {
  final TextEditingController _controller = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Camera cannot read the QR?',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Type the plate from the ticket to verify it manually.',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _controller,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    hintText: 'ABC 1234',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _busy
                    ? null
                    : () async {
                        setState(() {
                          _busy = true;
                        });
                        try {
                          await widget.onLookup(_controller.text);
                        } finally {
                          if (mounted) {
                            setState(() {
                              _busy = false;
                            });
                          }
                        }
                      },
                child: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Verify'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
