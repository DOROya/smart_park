// ignore_for_file: invalid_use_of_protected_member

part of '../staff_home_page.dart';

DateTime? _parseDateTime(dynamic value) {
  if (value == null) return null;
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  return null;
}

extension _StaffHomePageFragments on _StaffHomePageState {
  Widget _buildSummaryTile(String title, String value) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE3E5EA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppTheme.textMuted,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              color: AppTheme.textDark,
              fontWeight: FontWeight.w800,
              fontSize: 20,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardTab(Map<String, dynamic> userData) {
    if (_assignedFacilityId == null || _assignedFacilityId!.isEmpty) {
      return const Center(
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

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('activity_logs')
          .where('establishmentID', isEqualTo: _assignedFacilityId)
          .snapshots(),
      builder: (
        BuildContext context,
        AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> activitySnapshot,
      ) {
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('establishments')
              .where(FieldPath.documentId, isEqualTo: _assignedFacilityId)
              .limit(1)
              .snapshots(),
          builder: (
            BuildContext context,
            AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> facilitySnapshot,
          ) {
            final List<QueryDocumentSnapshot<Map<String, dynamic>>> activityDocs =
                activitySnapshot.data?.docs ??
                <QueryDocumentSnapshot<Map<String, dynamic>>>[];
            final DateTime startOfDay = DateTime(
              DateTime.now().year,
              DateTime.now().month,
              DateTime.now().day,
            );

            int totalEntriesToday = 0;
            int validEntriesToday = 0;
            int exitsToday = 0;
            int activeNow = 0;

            for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
                in activityDocs) {
              final Map<String, dynamic> data = doc.data();
              final DateTime? timestamp = _parseDateTime(data['timestamp']);
              final String scanType =
                  ((data['scanType'] as String?) ?? '').toLowerCase();
              final String status =
                  ((data['status'] as String?) ?? '').toUpperCase();
              final bool isActive = (data['isActive'] as bool?) ?? false;

              if (isActive) {
                activeNow++;
              }

              if (timestamp == null || timestamp.isBefore(startOfDay)) {
                continue;
              }
              if (scanType == 'entry') {
                totalEntriesToday++;
                if (status == 'VALID') {
                  validEntriesToday++;
                }
              }
              if (scanType == 'exit') {
                exitsToday++;
              }
            }

            int totalSlots = 0;
            if ((facilitySnapshot.data?.docs ??
                    <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                .isNotEmpty) {
              totalSlots =
                  ((facilitySnapshot.data!.docs.first.data()['availability']
                              as num?) ??
                          0)
                      .toInt();
            }

            final int occupied = activeNow;
            final int available = (totalSlots - occupied).clamp(0, totalSlots);
            final double occupancy =
                totalSlots == 0 ? 0 : (occupied / totalSlots).clamp(0, 1);

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE3E5EA)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Staff Dashboard',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textDark,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        roleLabel,
                        style: const TextStyle(
                          color: AppTheme.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _buildSummaryTile(
                        'Total Entries',
                        totalEntriesToday.toString(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildSummaryTile(
                        'Valid Entries',
                        validEntriesToday.toString(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _buildSummaryTile('Active Now', activeNow.toString()),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildSummaryTile('Exits', exitsToday.toString()),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE3E5EA)),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 90,
                        height: 90,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            CircularProgressIndicator(
                              value: occupancy,
                              strokeWidth: 9,
                              backgroundColor: const Color(0xFFE8EBF2),
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                Color(0xFF1E88E5),
                              ),
                            ),
                            Text(
                              '${(occupancy * 100).toStringAsFixed(0)}%',
                              style: const TextStyle(
                                color: AppTheme.textDark,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Total Slots: $totalSlots'),
                            Text('Occupied: $occupied'),
                            Text('Available: $available'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
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
        color: const Color(0xFFF1F3F8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          Expanded(child: _gateModeButton('entry', Icons.login_rounded, 'Entry')),
          Expanded(child: _gateModeButton('exit', Icons.logout_rounded, 'Exit')),
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
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
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
        const Text(
          'Scan Customer QR Code',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppTheme.textDark,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
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
          style: const TextStyle(
            color: AppTheme.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        FutureBuilder<bool>(
          future: _permissionService.ensureCameraPermissionForQr(context),
          builder: (
            BuildContext context,
            AsyncSnapshot<bool> permissionSnapshot,
          ) {
            if (permissionSnapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                height: 280,
                child: Center(child: CircularProgressIndicator()),
              );
            }

            if (permissionSnapshot.data != true) {
              return const SizedBox(
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
                borderRadius: BorderRadius.circular(14),
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
                          borderRadius: BorderRadius.circular(10),
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
        const SizedBox(height: 12),
        Row(
          children: [
            const Expanded(
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
            stream: FirebaseFirestore.instance
                .collection('activity_logs')
                .where('establishmentID', isEqualTo: facilityId)
                .orderBy('timestamp', descending: true)
                .limit(5)
                .snapshots(),
            builder: (
              BuildContext context,
              AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snapshot,
            ) {
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return const Text('No scans yet.');
              }

              return Column(
                children: snapshot.data!.docs
                    .map((QueryDocumentSnapshot<Map<String, dynamic>> doc) {
                  final Map<String, dynamic> data = doc.data();
                  return _ActivityRow(data: data);
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
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'History',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textDark,
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _pickHistoryDate,
                icon: const Icon(Icons.calendar_today_rounded, size: 16),
                label: Text(
                  '${_selectedHistoryDate.year}-${_selectedHistoryDate.month.toString().padLeft(2, '0')}-${_selectedHistoryDate.day.toString().padLeft(2, '0')}',
                ),
              ),
            ],
          ),
        ),
        TabBar(
          controller: _historyTabController,
          isScrollable: true,
          labelColor: AppTheme.textDark,
          unselectedLabelColor: AppTheme.textMuted,
          indicatorColor: AppTheme.accent,
          tabs: const [
            Tab(text: 'All'),
            Tab(text: 'Entries'),
            Tab(text: 'Exits'),
            Tab(text: 'Active'),
          ],
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('activity_logs')
                .where('establishmentID', isEqualTo: facilityId)
                .orderBy('timestamp', descending: true)
                .snapshots(),
            builder: (
              BuildContext context,
              AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snapshot,
            ) {
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Could not load history.\n${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppTheme.textMuted),
                    ),
                  ),
                );
              }

              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final List<Map<String, dynamic>> filtered = snapshot.data!.docs
                  .map((QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
                      doc.data())
                  .where((Map<String, dynamic> data) {
                final DateTime date = _parseDateTime(data['timestamp']) ?? DateTime.now();
                return _sameDate(date, _selectedHistoryDate) &&
                    _matchesHistoryFilter(data);
              }).toList();

              if (filtered.isEmpty) {
                return const Center(
                  child: Text('No records for selected filter/date.'),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: filtered.length,
                itemBuilder: (BuildContext context, int index) {
                  final Map<String, dynamic> data = filtered[index];
                  return _ActivityRow(data: data);
                },
              );
            },
          ),
        ),
      ],
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

  final _GateScanResult result;

  @override
  Widget build(BuildContext context) {
    final bool allowed = result.isAllowed;
    final Color accent =
        allowed ? const Color(0xFF1F7A4A) : const Color(0xFFB3261E);
    final Color bg =
        allowed ? const Color(0xFFE8F6EF) : const Color(0xFFFDECEA);
    final String title = allowed
        ? (result.scanType == 'exit' ? 'Exit allowed' : 'Entry allowed')
        : (result.decision == 'ERROR' ? 'Scan error' : 'Scan denied');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white,
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
                color: const Color(0xFFFFF3D9),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE8B93E)),
              ),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.payments_rounded,
                      color: Color(0xFF946200)),
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
              style: const TextStyle(fontSize: 11, color: Color(0xFF737A88)),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE3E5EA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Camera cannot read the QR?',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          const Text(
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
                      borderRadius: BorderRadius.circular(10),
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

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final String plate = (data['vehiclePlate'] as String?) ?? 'N/A';
    final String scanType =
        ((data['scanType'] as String?) ?? 'entry').toLowerCase();
    final String status =
        ((data['status'] as String?) ?? (data['decision'] as String?) ?? '?')
            .toUpperCase();
    final String reason = (data['decisionReason'] as String?) ?? '';
    final int overtimeHours = ((data['overtimeHours'] as num?) ?? 0).toInt();
    final double overtimeAmount =
        ((data['overtimeAmount'] as num?) ?? 0).toDouble();
    final Color statusColor = status == 'ALLOWED'
        ? const Color(0xFF1F7A4A)
        : status == 'DENIED'
            ? const Color(0xFFB3261E)
            : const Color(0xFF946200);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE3E5EA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  plate,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${scanType.toUpperCase()} overtime ${overtimeHours}h / PHP ${overtimeAmount.toStringAsFixed(2)}',
            style: const TextStyle(
              color: AppTheme.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (reason.isNotEmpty) ...<Widget>[
            const SizedBox(height: 2),
            Text(reason, style: const TextStyle(fontSize: 12)),
          ],
        ],
      ),
    );
  }
}
