// ignore_for_file: invalid_use_of_protected_member

part of 'staff_home_page.dart';

extension _StaffHomePageFragments on _StaffHomePageState {
  bool get _isTablet => spIsTablet(context);

  /// Two columns need landscape width; a portrait tablet stays single column.
  bool get _useTabletColumns => MediaQuery.sizeOf(context).width >= 1000;

  /// A gate scan that opens its details. [showDate] is for lists that can
  /// span several days.
  Widget _scanCard(Map<String, dynamic> data, {bool showDate = false}) {
    return SpActivityCard(
      data: data,
      showDate: showDate,
      hideStaffId: FirebaseAuth.instance.currentUser?.uid,
      onTap: () => showSpActivityDetails(
        context,
        log: data,
        onMarkOvertimeCollected: _markLogOvertimeCollected,
        flaggingStaffName: _staffName,
      ),
    );
  }

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
    // Staff usually have no users/ profile, so use their staff record name.
    final String profileFirstName = ((userData['firstName'] as String?) ?? '')
        .trim();
    final String firstName = profileFirstName.isNotEmpty
        ? profileFirstName
        : _staffName.split(' ').first;

    return withDayLogs(
      _assignedFacilityId!,
      DateTime.now(),
      builder: (BuildContext context, SpDayLogs today) {
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
                return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
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
                        AsyncSnapshot<DocumentSnapshot<Map<String, dynamic>>>
                        detailsSnapshot,
                      ) {
                        final DateTime now = DateTime.now();
                        final SpActivitySummary summary =
                            SpActivitySummary.fromLogs(
                              today.logs,
                              now,
                              insideLogs: today.insideLogs,
                            );

                        final Map<String, dynamic> facility =
                            facilitySnapshot.data?.data() ??
                            <String, dynamic>{};
                        final Map<String, dynamic> details =
                            detailsSnapshot.data?.data() ?? <String, dynamic>{};
                        final String facilityName =
                            ((facility['name'] as String?) ?? '').trim();
                        final Map<dynamic, dynamic> slotCounts =
                            (details['slotCounts'] as Map<dynamic, dynamic>?) ??
                            <dynamic, dynamic>{};
                        final int carSlots = ((slotCounts['car'] as num?) ?? 0)
                            .toInt();
                        final int motorcycleSlots =
                            ((slotCounts['motorcycle'] as num?) ?? 0).toInt();
                        final int slotSum = carSlots + motorcycleSlots;
                        final int totalSlots = slotSum > 0
                            ? slotSum
                            : ((facility['availability'] as num?) ?? 0).toInt();

                        final Widget hero = SpHeroBanner(
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
                            (Icons.calendar_today_rounded, spFormatDate(now)),
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
                        );
                        final List<Widget> rightNow = <Widget>[
                          const SpSectionLabel('Right Now'),
                          const SizedBox(height: 10),
                          SpDailyActivityTiles(
                            summary: summary,
                            insideOnly: true,
                            entriesAndExitsLabel: 'History',
                            onSeeEntriesAndExits: () => setState(() {
                              _selectedHistoryDate = DateTime.now();
                              _selectedNavIndex = 2;
                            }),
                          ),
                        ];
                        final Widget cashCard = _ShiftCashCard(
                          cash: SpOvertimeCash.from(
                            today.logs.where(
                              (Map<String, dynamic> log) =>
                                  log['staffId'] ==
                                  FirebaseAuth.instance.currentUser?.uid,
                            ),
                          ),
                        );

                        final Widget slotsCard = SpLiveSlotsCard(
                          establishmentId: _assignedFacilityId ?? '',
                          totalSlots: totalSlots,
                          fallbackOccupied: summary.insideNow,
                          carSlots: carSlots,
                          motorcycleSlots: motorcycleSlots,
                        );
                        final List<Widget> recentScans = <Widget>[
                          SpSectionLabel(
                            'Recent Scans',
                            trailing: summary.dayLogs.isEmpty
                                ? null
                                : TextButton(
                                    onPressed: () {
                                      setState(() {
                                        _selectedHistoryDate = DateTime.now();
                                        _selectedNavIndex = 2;
                                      });
                                    },
                                    child: const Text('View all'),
                                  ),
                          ),
                          const SizedBox(height: 6),
                          if (summary.dayLogs.isEmpty)
                            const SpEmptyState(message: 'No scans yet today.')
                          else
                            for (final Map<String, dynamic> data
                                in summary.dayLogs.take(3))
                              _scanCard(data),
                        ];

                        return ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            hero,
                            const SizedBox(height: 16),
                            if (_useTabletColumns)
                              SpTabletColumns(
                                leftFlex: 3,
                                rightFlex: 2,
                                left: <Widget>[
                                  ...rightNow,
                                  const SizedBox(height: 16),
                                  ...recentScans,
                                ],
                                right: <Widget>[
                                  slotsCard,
                                  const SizedBox(height: 16),
                                  cashCard,
                                ],
                              )
                            else ...[
                              ...rightNow,
                              const SizedBox(height: 12),
                              cashCard,
                              const SizedBox(height: 16),
                              slotsCard,
                              const SizedBox(height: 16),
                              ...recentScans,
                            ],
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
    if (facilityId == null || facilityId.isEmpty) {
      return _buildQrTabContent(null, null);
    }
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: cachedStream(
        'details_$facilityId',
        () => FirebaseFirestore.instance
            .collection('establishment_details')
            .doc(facilityId)
            .snapshots(),
      ),
      builder: (BuildContext context, detailsSnapshot) {
        final Map<String, dynamic>? details = detailsSnapshot.data?.data();
        return _buildQrTabContent(
          facilityId,
          isFacilityRestricted(details) ? facilityStatus(details) : null,
        );
      },
    );
  }

  /// [restriction] is "suspended" or "deactivated" when an admin pulled the
  /// facility: entry is closed, exits still work.
  Widget _buildQrTabContent(String? facilityId, String? restriction) {
    final double scannerHeight = _isTablet ? 360 : 280;
    final List<Widget> header = <Widget>[
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
      if (restriction != null) ...[
        const SizedBox(height: 12),
        _EntryClosedBanner(restriction: restriction),
      ],
    ];
    final List<Widget> scanner = <Widget>[
      _gateModeSelector(),
      const SizedBox(height: 8),
      Text(
        _gateMode == 'entry'
            ? restriction == null
                  ? 'Entry mode: tickets are verified and checked in.'
                  : 'Entry mode: every scan is denied while the facility '
                        'is $restriction.'
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
                return SizedBox(
                  height: scannerHeight,
                  child: const Center(child: CircularProgressIndicator()),
                );
              }

              if (permissionSnapshot.data != true) {
                return SizedBox(
                  height: scannerHeight,
                  child: Center(
                    child: Text(
                      'Camera permission is required for scanning.',
                      style: TextStyle(color: AppTheme.textMuted),
                    ),
                  ),
                );
              }

              return SizedBox(
                height: scannerHeight,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      MobileScanner(
                        controller: _scannerController,
                        onDetect: _onBarcodeDetect,
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: ValueListenableBuilder<MobileScannerState>(
                          valueListenable: _scannerController,
                          builder:
                              (
                                BuildContext context,
                                MobileScannerState state,
                                Widget? child,
                              ) {
                                if (state.torchState ==
                                    TorchState.unavailable) {
                                  return const SizedBox.shrink();
                                }
                                final bool on =
                                    state.torchState == TorchState.on;
                                return IconButton.filled(
                                  tooltip: on
                                      ? 'Turn off flashlight'
                                      : 'Turn on flashlight',
                                  style: IconButton.styleFrom(
                                    backgroundColor: on
                                        ? AppTheme.accent
                                        : Colors.black54,
                                    foregroundColor: on
                                        ? AppTheme.onAccent
                                        : Colors.white,
                                  ),
                                  onPressed: _scannerController.toggleTorch,
                                  icon: Icon(
                                    on
                                        ? Icons.flash_on_rounded
                                        : Icons.flash_off_rounded,
                                  ),
                                );
                              },
                        ),
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
    ];
    final Widget? result = _lastScanResult == null
        ? null
        : GateResultCard(
            result: _lastScanResult!,
            marking: _markingOvertime,
            onMarkCollected: _markLastOvertimeCollected,
            refusing: _refusingEntry,
            onWrongVehicle: _refuseLastEntry,
          );
    final List<Widget> lookup = <Widget>[
      _ManualPlateLookup(onLookup: _lookupByPlate),
      if (facilityId != null) ...[
        const SizedBox(height: 12),
        WalkInPanel(
          facilityId: facilityId,
          ownerId: _ownerId,
          staffName: _staffName,
          entryClosed: restriction != null,
        ),
      ],
    ];
    final List<Widget> recent = <Widget>[
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

                // The latest scans can be from earlier days.
                return Column(
                  children: <Widget>[
                    for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
                        in snapshot.data!.docs)
                      _scanCard(doc.data(), showDate: true),
                  ],
                );
              },
        ),
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ...header,
        const SizedBox(height: 12),
        if (_useTabletColumns)
          // The result sits beside the camera so it is never below the fold.
          SpTabletColumns(
            leftFlex: 3,
            rightFlex: 2,
            left: <Widget>[...scanner, const SizedBox(height: 12), ...recent],
            right: <Widget>[
              if (result != null) ...[result, const SizedBox(height: 12)],
              ...lookup,
            ],
          )
        else ...[
          ...scanner,
          if (result != null) ...[const SizedBox(height: 12), result],
          const SizedBox(height: 12),
          ...lookup,
          const SizedBox(height: 12),
          ...recent,
        ],
      ],
    );
  }

  Widget _buildHistoryTab() {
    final String? facilityId = _assignedFacilityId;
    if (facilityId == null) {
      return const Center(child: Text('No facility assignment found.'));
    }

    // Only the picked day is loaded, not the facility's whole history.
    return withDayLogs(
      facilityId,
      _selectedHistoryDate,
      builder: (BuildContext context, SpDayLogs day) {
        final SpActivitySummary summary = SpActivitySummary.fromLogs(
          day.logs,
          _selectedHistoryDate,
          insideLogs: day.insideLogs,
        );
        // Denied scans stay logged but are hidden from the history; staff
        // refusals are listed. Inside lists every vehicle still parked,
        // whatever day it came in, like the owner's Activity tab.
        final bool insideTab = _historyFilter == 'active';
        final Iterable<Map<String, dynamic>> scans = insideTab
            ? day.insideLogs.where(spIsInsideLog)
            : day.logs.where(spIsListedLog).where(_matchesHistoryFilter);
        final List<Widget> cards = <Widget>[
          for (final Map<String, dynamic> data in scans)
            if (spActivityMatchesQuery(data, _historyQuery))
              _scanCard(data, showDate: insideTab),
        ];

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SpPageHeader(
              title: 'History',
              subtitle: 'Gate scans at your facility.',
              trailing: SpDateButton(
                date: _selectedHistoryDate,
                onTap: _pickHistoryDate,
              ),
            ),
            const SizedBox(height: 16),
            SpDailyActivityTiles(
              summary: summary,
              today: spSameDate(_selectedHistoryDate, DateTime.now()),
              singleRow: _isTablet,
            ),
            const SizedBox(height: 16),
            SpSegmentedControl<String>(
              options: const <(String, String)>[
                ('all', 'All'),
                ('entry', 'Entries'),
                ('exit', 'Exits'),
                ('active', 'Inside'),
              ],
              selected: _historyFilter,
              onChanged: (String value) =>
                  setState(() => _historyFilter = value),
            ),
            const SizedBox(height: 8),
            SpActivitySearch(
              logs: insideTab ? day.insideLogs : day.logs,
              staff: const <(String, String)>[],
              query: _historyQuery,
              onQueryChanged: (String value) =>
                  setState(() => _historyQuery = value),
              staffFilter: null,
              onStaffFilterChanged: (_) {},
            ),
            const SizedBox(height: 12),
            if (day.error != null)
              SpEmptyState(
                icon: Icons.error_outline_rounded,
                message:
                    'Could not load history. '
                    '${friendlyError(day.error!, fallback: 'Please try again.')}',
              )
            else if (!day.loaded)
              const SpSkeletonList()
            else if (cards.isEmpty)
              SpEmptyState(
                icon: _historyQuery.trim().isEmpty
                    ? Icons.receipt_long_rounded
                    : Icons.search_off_rounded,
                message: _historyQuery.trim().isEmpty
                    ? 'No scans for this filter and date.'
                    : 'No scans match "${_historyQuery.trim()}" for this '
                          'filter and date.',
              )
            else if (_isTablet)
              SpGrid(children: cards)
            else
              ...cards,
          ],
        );
      },
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

/// Shown above the scanner while an admin has the facility pulled, so staff
/// know why every entry is refused before the first car is turned away.
/// The overtime cash this staff member took at the gate today, so the
/// end-of-shift handover to the owner can be checked against it.
class _ShiftCashCard extends StatelessWidget {
  const _ShiftCashCard({required this.cash});

  final SpOvertimeCash cash;

  @override
  Widget build(BuildContext context) {
    final bool owed = cash.dueCount > 0;
    return SpSectionCard(
      icon: Icons.payments_rounded,
      title: 'Your Overtime Cash Today',
      subtitle: 'Hand this to the owner at the end of your shift.',
      trailing: owed
          ? SpChip(label: '${cash.dueCount} to confirm', color: spInsideColor)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            spPeso(cash.collectedAmount),
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            cash.collectedCount == 0
                ? 'No overtime cash collected yet today.'
                : 'Collected from ${cash.collectedCount} exit'
                      '${cash.collectedCount == 1 ? '' : 's'}.',
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
          if (owed) ...[
            const SizedBox(height: 8),
            Text(
              '${spPeso(cash.dueAmount)} from ${cash.dueCount} exit'
              '${cash.dueCount == 1 ? '' : 's'} is not confirmed yet. Open '
              'the scan and tap "Cash collected" once you have it.',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: spInsideColor,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EntryClosedBanner extends StatelessWidget {
  const _EntryClosedBanner({required this.restriction});

  /// "suspended" or "deactivated".
  final String restriction;

  @override
  Widget build(BuildContext context) {
    final bool suspended = restriction == 'suspended';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.dangerSoft,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(color: AppTheme.dangerBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            suspended ? Icons.pause_circle_rounded : Icons.block_rounded,
            color: spDeniedColor,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Entry closed: facility $restriction',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'SmartPark has $restriction this facility. Do not admit '
                  'any vehicle; entry scans and walk-ins are refused until '
                  'it is ${suspended ? 'reinstated' : 'reactivated'}. '
                  'Vehicles already inside can still exit.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
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
