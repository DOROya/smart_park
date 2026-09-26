// ignore_for_file: invalid_use_of_protected_member

part of 'package:smart_park/screens/parking_owner/parking_owner_home_screen.dart';

extension _ParkingOwnerHomeFragments on _ParkingOwnerHomePageState {
  InputDecoration _ownerFieldDecoration({
    required String label,
    String? hint,
    IconData? icon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: icon == null ? null : Icon(icon, size: 20),
      filled: true,
      fillColor: AppTheme.surfaceAlt,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTheme.radius),
        borderSide: BorderSide(color: AppTheme.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTheme.radius),
        borderSide: BorderSide(color: AppTheme.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTheme.radius),
        borderSide: const BorderSide(color: AppTheme.accent, width: 1.4),
      ),
      labelStyle: TextStyle(
        color: AppTheme.textMuted,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
      hintStyle: TextStyle(color: AppTheme.textMuted, fontSize: 12),
    );
  }

  String _formatShortDate(DateTime dateTime) => spFormatDate(dateTime);

  Widget _buildBody({
    required String ownerId,
    required Map<String, dynamic> ownerData,
    required String role,
  }) {
    switch (_selectedIndex) {
      case 1:
        return _buildStaffTab(ownerId: ownerId, ownerData: ownerData);
      case 2:
        return _buildGateActivityTab(ownerId: ownerId, ownerData: ownerData);
      case 3:
        return _buildCommissionsTab(ownerId: ownerId, ownerData: ownerData);
      case 4:
        return _buildProfileTab();
      case 0:
      default:
        return _buildFacilityTab(ownerId: ownerId, ownerData: ownerData);
    }
  }

  /// Resolves the owner's facility id, falling back to a lookup by ownerId
  /// for accounts whose user doc does not store it.
  Widget _withFacilityId({
    required String ownerId,
    required Map<String, dynamic> ownerData,
    required Widget Function(String facilityId, bool resolving) builder,
  }) {
    final String initialFacilityId = _resolveFacilityId(ownerData);
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: initialFacilityId.isEmpty
          ? cachedStream(
              'owner_facility_$ownerId',
              () => FirebaseFirestore.instance
                  .collection('establishments')
                  .where('ownerId', isEqualTo: ownerId)
                  .limit(1)
                  .snapshots(),
            )
          : null,
      builder:
          (
            BuildContext context,
            AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> estSnapshot,
          ) {
            String facilityId = initialFacilityId;
            if (facilityId.isEmpty &&
                estSnapshot.hasData &&
                estSnapshot.data!.docs.isNotEmpty) {
              facilityId = estSnapshot.data!.docs.first.id;
            }
            final bool resolving =
                initialFacilityId.isEmpty &&
                estSnapshot.connectionState == ConnectionState.waiting;
            return builder(facilityId, resolving);
          },
    );
  }

  Widget _buildFacilityTab({
    required String ownerId,
    required Map<String, dynamic> ownerData,
  }) {
    final String firstName = ((ownerData['firstName'] as String?) ?? '').trim();

    return _withFacilityId(
      ownerId: ownerId,
      ownerData: ownerData,
      builder: (String establishmentId, bool resolving) {
        final bool hasFacility = establishmentId.isNotEmpty;
        final DateTime now = DateTime.now();
        final Widget heroButton = SpHeroButton(
          icon: hasFacility ? Icons.edit_rounded : Icons.add_business_rounded,
          label: hasFacility ? 'Update Facility' : 'Register Facility',
          onPressed: () =>
              _openFacilityDialog(ownerId: ownerId, ownerData: ownerData),
        );
        // A full-width button reads as a stray bar across a tablet banner.
        final Widget facilityButton = _isTablet
            ? Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 280),
                  child: heroButton,
                ),
              )
            : heroButton;
        final String greeting = firstName.isEmpty
            ? spGreeting(now)
            : '${spGreeting(now)}, $firstName';

        if (!hasFacility) {
          return ListView(
            padding: const EdgeInsets.only(top: 8),
            children: [
              SpHeroBanner(
                title: greeting,
                badge: 'Owner',
                details: <(IconData, String)>[
                  (Icons.storefront_rounded, 'No facility registered yet'),
                  (Icons.calendar_today_rounded, spFormatDate(now)),
                ],
                action: facilityButton,
              ),
              const SizedBox(height: 16),
              if (resolving)
                const SpSkeletonList()
              else
                const SpEmptyState(
                  icon: Icons.add_business_rounded,
                  message:
                      'Register your facility to start onboarding staff and '
                      'accepting drivers. An admin reviews it before it goes '
                      'live.',
                ),
            ],
          );
        }

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: cachedStream(
            'establishment_$establishmentId',
            () => FirebaseFirestore.instance
                .collection('establishments')
                .doc(establishmentId)
                .snapshots(),
          ),
          builder: (context, facilitySnapshot) {
            return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: cachedStream(
                'details_$establishmentId',
                () => FirebaseFirestore.instance
                    .collection('establishment_details')
                    .doc(establishmentId)
                    .snapshots(),
              ),
              builder: (context, detailsSnapshot) {
                return withDayLogs(
                  establishmentId,
                  now,
                  builder: (BuildContext context, SpDayLogs today) {
                    final List<Map<String, dynamic>> logs = today.logs;
                    final List<Map<String, dynamic>> insideLogs =
                        today.insideLogs;
                    final Map<String, dynamic> facility =
                        facilitySnapshot.data?.data() ?? <String, dynamic>{};
                    final Map<String, dynamic>? details = detailsSnapshot.data
                        ?.data();
                    final SpActivitySummary summary =
                        SpActivitySummary.fromLogs(
                          logs,
                          now,
                          insideLogs: insideLogs,
                        );
                    final String facilityName =
                        ((facility['name'] as String?) ?? '').trim();
                    final Map<dynamic, dynamic> slotCounts =
                        (details?['slotCounts'] as Map<dynamic, dynamic>?) ??
                        <dynamic, dynamic>{};
                    final int carSlots = ((slotCounts['car'] as num?) ?? 0)
                        .toInt();
                    final int motorcycleSlots =
                        ((slotCounts['motorcycle'] as num?) ?? 0).toInt();
                    final int slotSum = carSlots + motorcycleSlots;
                    final int totalSlots = slotSum > 0
                        ? slotSum
                        : ((facility['availability'] as num?) ?? 0).toInt();
                    final Widget overstayCard = SpOverstayCard(
                      facilityId: establishmentId,
                      rates: _ratesOf(details),
                    );
                    final SpOvertimeCash overtimeCash = SpOvertimeCash.from(
                      summary.dayLogs,
                    );

                    if (_isTablet) {
                      return _buildTabletFacilityDashboard(
                        greeting: greeting,
                        facilityName: facilityName,
                        facilityButton: facilityButton,
                        now: now,
                        details: details,
                        summary: summary,
                        overstayCard: overstayCard,
                        overtimeCash: overtimeCash,
                        slotsCard: SpLiveSlotsCard(
                          establishmentId: establishmentId,
                          totalSlots: totalSlots,
                          fallbackOccupied: summary.insideNow,
                          carSlots: carSlots,
                          motorcycleSlots: motorcycleSlots,
                        ),
                        detailsCard: _buildFacilityDetailsCard(
                          establishmentId: establishmentId,
                          facility: facility,
                          details: details ?? <String, dynamic>{},
                        ),
                      );
                    }

                    return ListView(
                      padding: const EdgeInsets.only(top: 8),
                      children: [
                        SpHeroBanner(
                          title: greeting,
                          badge: 'Owner',
                          details: <(IconData, String)>[
                            (
                              Icons.storefront_rounded,
                              facilityName.isEmpty
                                  ? 'Your facility'
                                  : facilityName,
                            ),
                            (Icons.calendar_today_rounded, spFormatDate(now)),
                          ],
                          action: facilityButton,
                        ),
                        if (details != null) ...[
                          const SizedBox(height: 12),
                          FacilityReviewStatusBanner(
                            status: details['status'] as String?,
                            rejectionReason:
                                details['rejectionReason'] as String?,
                          ),
                        ],
                        const SizedBox(height: 16),
                        const SpSectionLabel("Today's Activity"),
                        const SizedBox(height: 10),
                        SpDailyActivityTiles(summary: summary),
                        const SizedBox(height: 16),
                        overstayCard,
                        if (!overtimeCash.isEmpty) ...[
                          const SizedBox(height: 12),
                          SpOvertimeCashBanner(cash: overtimeCash),
                        ],
                        const SizedBox(height: 16),
                        SpLiveSlotsCard(
                          establishmentId: establishmentId,
                          totalSlots: totalSlots,
                          fallbackOccupied: summary.insideNow,
                          carSlots: carSlots,
                          motorcycleSlots: motorcycleSlots,
                        ),
                        const SizedBox(height: 16),
                        _buildFacilityDetailsCard(
                          establishmentId: establishmentId,
                          facility: facility,
                          details: details ?? <String, dynamic>{},
                        ),
                        const SizedBox(height: 16),
                        SpSectionLabel(
                          'Recent Scans',
                          trailing: summary.dayLogs.isEmpty
                              ? null
                              : TextButton(
                                  onPressed: () =>
                                      setState(() => _selectedIndex = 2),
                                  child: const Text('View all'),
                                ),
                        ),
                        const SizedBox(height: 6),
                        if (summary.dayLogs.isEmpty)
                          const SpEmptyState(message: 'No scans yet today.')
                        else
                          for (final Map<String, dynamic> data
                              in summary.dayLogs.take(3))
                            _recentScanCard(data),
                      ],
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  /// Tablet facility dashboard: live activity on the left, capacity and
  /// facility details on the right.
  Widget _buildTabletFacilityDashboard({
    required String greeting,
    required String facilityName,
    required Widget facilityButton,
    required DateTime now,
    required Map<String, dynamic>? details,
    required SpActivitySummary summary,
    required Widget overstayCard,
    required SpOvertimeCash overtimeCash,
    required Widget slotsCard,
    required Widget detailsCard,
  }) {
    return ListView(
      padding: const EdgeInsets.only(top: 8),
      children: [
        SpHeroBanner(
          title: greeting,
          badge: 'Owner',
          details: <(IconData, String)>[
            (
              Icons.storefront_rounded,
              facilityName.isEmpty ? 'Your facility' : facilityName,
            ),
            (Icons.calendar_today_rounded, spFormatDate(now)),
          ],
          action: facilityButton,
        ),
        if (details != null) ...[
          const SizedBox(height: 12),
          FacilityReviewStatusBanner(
            status: details['status'] as String?,
            rejectionReason: details['rejectionReason'] as String?,
          ),
        ],
        const SizedBox(height: 20),
        const SpSectionLabel("Today's Activity"),
        const SizedBox(height: 10),
        SpDailyActivityTiles(summary: summary, singleRow: true),
        const SizedBox(height: 20),
        _ownerTabletColumns(
          leftFlex: 3,
          rightFlex: 2,
          left: [
            overstayCard,
            if (!overtimeCash.isEmpty) ...[
              const SizedBox(height: 12),
              SpOvertimeCashBanner(cash: overtimeCash),
            ],
            const SizedBox(height: 20),
            SpSectionLabel(
              'Recent Scans',
              trailing: summary.dayLogs.isEmpty
                  ? null
                  : TextButton(
                      onPressed: () => setState(() => _selectedIndex = 2),
                      child: const Text('View all'),
                    ),
            ),
            const SizedBox(height: 6),
            if (summary.dayLogs.isEmpty)
              const SpEmptyState(message: 'No scans yet today.')
            else
              for (final Map<String, dynamic> data in summary.dayLogs.take(6))
                _recentScanCard(data),
          ],
          right: [slotsCard, const SizedBox(height: 16), detailsCard],
        ),
      ],
    );
  }

  bool get _isTablet => spIsTablet(context);

  /// The facility's rates, as the gate reads them for overtime.
  Map<String, dynamic>? _ratesOf(Map<String, dynamic>? details) {
    final dynamic raw = details?['rates'] ?? details?['ratesByType'];
    if (raw is! Map) return null;
    return raw.map<String, dynamic>(
      (dynamic k, dynamic v) => MapEntry<String, dynamic>(k.toString(), v),
    );
  }

  Widget _recentScanCard(Map<String, dynamic> data) {
    return SpActivityCard(
      data: data,
      onTap: () => showSpActivityDetails(
        context,
        log: data,
        onSetOvertimeStatus: (Map<String, dynamic> log, String status) =>
            _ownerSetOvertimeStatus(context, log, status),
      ),
    );
  }

  /// Two top-aligned columns for tablet layouts.
  Widget _ownerTabletColumns({
    required List<Widget> left,
    required List<Widget> right,
    int leftFlex = 1,
    int rightFlex = 1,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: leftFlex,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: left,
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          flex: rightFlex,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: right,
          ),
        ),
      ],
    );
  }

  String _formatRateLine(dynamic value) {
    if (value is Map) {
      final String initial = (value['initial'] ?? value['hourly'] ?? '')
          .toString()
          .trim();
      final String perHour = (value['succeedingHour'] ?? '').toString().trim();
      final String perDay = (value['succeedingDaily'] ?? value['daily'] ?? '')
          .toString()
          .trim();
      if (initial.isEmpty) {
        return 'Not set';
      }
      final List<String> parts = <String>[
        'PHP $initial first $spBaseStayLabel',
      ];
      if (perHour.isNotEmpty) parts.add('+PHP $perHour/hr');
      if (perDay.isNotEmpty) parts.add('PHP $perDay/day');
      return parts.join(' · ');
    }
    final String text = (value ?? '').toString().trim();
    return text.isEmpty ? 'Not set' : text;
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppTheme.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textMuted,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textDark,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFacilityDetailsCard({
    required String establishmentId,
    required Map<String, dynamic> facility,
    required Map<String, dynamic> details,
  }) {
    final Map<dynamic, dynamic> rates =
        ((details['rates'] ?? details['ratesByType'])
            as Map<dynamic, dynamic>?) ??
        <dynamic, dynamic>{};
    String read(dynamic value) {
      final String text = ((value as String?) ?? '').trim();
      return text.isEmpty ? 'Not provided' : text;
    }

    return SpSectionCard(
      icon: Icons.storefront_outlined,
      title: 'Facility Details',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDetailRow(
            Icons.location_on_outlined,
            'Address',
            read(facility['address']),
          ),
          _buildDetailRow(
            Icons.schedule_rounded,
            'Operating Hours',
            read(facility['operatingHours']),
          ),
          _buildDetailRow(
            Icons.directions_car_outlined,
            'Car Rate',
            _formatRateLine(rates['car']),
          ),
          _buildDetailRow(
            Icons.two_wheeler_outlined,
            'Motorcycle Rate',
            _formatRateLine(rates['motorcycle']),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
            decoration: BoxDecoration(
              color: AppTheme.surfaceAlt,
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            ),
            child: Row(
              children: [
                Icon(Icons.tag_rounded, size: 16, color: AppTheme.textMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    establishmentId,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Copy facility ID',
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: establishmentId),
                    );
                    _showSnackBar('Facility ID copied.');
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGateActivityTab({
    required String ownerId,
    required Map<String, dynamic> ownerData,
  }) {
    return _withFacilityId(
      ownerId: ownerId,
      ownerData: ownerData,
      builder: (String facilityId, bool resolving) {
        if (facilityId.isEmpty) {
          return ListView(
            padding: const EdgeInsets.only(top: 8),
            children: [
              const SpPageHeader(
                title: 'Activity',
                subtitle: 'Gate scans recorded by your staff.',
              ),
              const SizedBox(height: 16),
              if (resolving)
                const SpSkeletonList()
              else
                const SpEmptyState(
                  icon: Icons.storefront_outlined,
                  message: 'Register a facility to see gate activity.',
                ),
            ],
          );
        }
        return _GateActivityContent(
          facilityId: facilityId,
          ownerId: ownerId,
          staffFilter: _activityStaffId,
          onStaffFilterChanged: (String? staffId) =>
              setState(() => _activityStaffId = staffId),
        );
      },
    );
  }

  String _initials(String name) {
    final List<String> parts = name
        .split(RegExp(r'\s+'))
        .where((String part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  Widget _buildStaffTab({
    required String ownerId,
    required Map<String, dynamic> ownerData,
  }) {
    return _withFacilityId(
      ownerId: ownerId,
      ownerData: ownerData,
      builder: (String facilityId, bool resolving) {
        final bool hasFacilityId = facilityId.isNotEmpty;

        final Widget addStaffCard = SpSectionCard(
          icon: Icons.person_add_alt_1_rounded,
          title: 'Add Staff Member',
          subtitle: hasFacilityId
              ? 'Enter a name. A login username and password are '
                    'generated automatically.'
              : 'Register your facility first to enable staff onboarding.',
          child: Form(
            key: _staffFormKey,
            child: Column(
              children: [
                TextFormField(
                  controller: _staffNameController,
                  enabled: hasFacilityId,
                  decoration: _ownerFieldDecoration(
                    label: 'Staff Name',
                    hint: 'Juan Dela Cruz',
                    icon: Icons.person_outline_rounded,
                  ),
                  validator: (value) {
                    final String text = value?.trim() ?? '';
                    if (text.isEmpty) {
                      return 'Enter name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                SpPrimaryButton(
                  icon: Icons.person_add_alt_1_rounded,
                  label: _addingStaff ? 'Adding Staff...' : 'Add Staff',
                  busy: _addingStaff,
                  onPressed: hasFacilityId
                      ? () =>
                            _addStaff(ownerId: ownerId, facilityId: facilityId)
                      : null,
                ),
              ],
            ),
          ),
        );
        final Widget
        staffListCard = StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: cachedStream(
            'staff_$ownerId',
            () => FirebaseFirestore.instance
                .collection('staff_accounts')
                .where('ownerId', isEqualTo: ownerId)
                .snapshots(),
          ),
          builder:
              (
                BuildContext context,
                AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snapshot,
              ) {
                final List<QueryDocumentSnapshot<Map<String, dynamic>>>
                allStaffDocs =
                    snapshot.data?.docs ??
                    <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                final List<QueryDocumentSnapshot<Map<String, dynamic>>>
                staffDocs = allStaffDocs
                    .where((doc) => isStaffRecordActive(doc.data()))
                    .toList();
                final List<QueryDocumentSnapshot<Map<String, dynamic>>>
                deactivatedDocs = allStaffDocs
                    .where((doc) => !isStaffRecordActive(doc.data()))
                    .toList();

                Widget content;
                if (snapshot.hasError) {
                  content = const SpEmptyState(
                    boxed: false,
                    icon: Icons.error_outline_rounded,
                    message: 'Unable to load staff records right now.',
                  );
                } else if (snapshot.connectionState ==
                    ConnectionState.waiting) {
                  content = const SpSkeletonList();
                } else if (staffDocs.isEmpty) {
                  content = SpEmptyState(
                    boxed: false,
                    icon: Icons.groups_outlined,
                    message: deactivatedDocs.isEmpty
                        ? 'No staff accounts yet. Add your first staff '
                              'member above.'
                        : 'No active staff. Add someone above or '
                              'reactivate a staff member below.',
                  );
                } else if (!hasFacilityId) {
                  content = Column(
                    children: [
                      for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
                          in staffDocs)
                        _buildStaffRow(doc, null, statsLoaded: false),
                    ],
                  );
                } else {
                  content = withDayLogs(
                    facilityId,
                    DateTime.now(),
                    builder: (BuildContext context, SpDayLogs today) {
                      final Map<String, _StaffDayStats> stats =
                          _StaffDayStats.today(today.logs);
                      return Column(
                        children: [
                          for (final QueryDocumentSnapshot<Map<String, dynamic>>
                              doc
                              in staffDocs)
                            _buildStaffRow(
                              doc,
                              stats[_staffUid(doc)],
                              statsLoaded: today.loaded,
                            ),
                        ],
                      );
                    },
                  );
                }
                if (deactivatedDocs.isNotEmpty) {
                  content = Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      content,
                      _buildDeactivatedStaff(deactivatedDocs),
                    ],
                  );
                }

                return SpSectionCard(
                  icon: Icons.groups_rounded,
                  title: 'Active Staff',
                  subtitle: staffDocs.isEmpty
                      ? null
                      : 'Tap a staff member to see the scans they recorded.',
                  trailing: staffDocs.isEmpty
                      ? null
                      : SpChip(
                          label: '${staffDocs.length}',
                          color: spExitColor,
                        ),
                  child: content,
                );
              },
        );

        const Widget header = SpPageHeader(
          title: 'Staff',
          subtitle: 'Create and manage staff accounts for your facility.',
        );

        if (_isTablet) {
          return ListView(
            padding: const EdgeInsets.only(top: 8),
            children: [
              header,
              const SizedBox(height: 20),
              _ownerTabletColumns(
                leftFlex: 2,
                rightFlex: 3,
                left: [addStaffCard],
                right: [staffListCard],
              ),
            ],
          );
        }

        return ListView(
          padding: const EdgeInsets.only(top: 8),
          children: [
            header,
            const SizedBox(height: 16),
            addStaffCard,
            const SizedBox(height: 12),
            staffListCard,
          ],
        );
      },
    );
  }

  String _staffUid(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final String uid = ((doc.data()['userId'] as String?) ?? '').trim();
    return uid.isEmpty ? doc.id : uid;
  }

  /// Deactivated staff, collapsed below the active list. Their records are
  /// kept so past scans still show their names.
  Widget _buildDeactivatedStaff(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    return Theme(
      // ExpansionTile draws divider lines by default.
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 4),
        childrenPadding: EdgeInsets.zero,
        title: Text(
          'Deactivated (${docs.length})',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppTheme.textMuted,
          ),
        ),
        children: [
          for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in docs)
            _buildStaffRow(doc, null, statsLoaded: false, deactivated: true),
        ],
      ),
    );
  }

  Widget _buildStaffRow(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    _StaffDayStats? stats, {
    required bool statsLoaded,
    bool deactivated = false,
  }) {
    final Map<String, dynamic> data = doc.data();
    final String rawName = (data['name'] as String?)?.trim() ?? '';
    final String name = rawName.isEmpty ? 'Unnamed Staff' : rawName;
    final String username = (data['username'] as String?)?.trim() ?? '';
    final DateTime? deactivatedAt = spParseDateTime(data['deactivatedAt']);
    final String activityLine = deactivated
        ? (deactivatedAt == null
              ? 'Deactivated'
              : 'Deactivated ${spFormatDate(deactivatedAt)}')
        : !statsLoaded
        ? ''
        : stats == null
        ? 'No scans today'
        : '${stats.scans} scan${stats.scans == 1 ? '' : 's'} today'
              '${stats.denied > 0 ? ' · ${stats.denied} denied' : ''}'
              '${stats.last == null ? '' : ' · last ${spFormatClockTime(stats.last!)}'}';
    final String cashLine =
        deactivated ||
            stats == null ||
            (stats.overtimeCollected <= 0 && stats.overtimeOwed <= 0)
        ? ''
        : <String>[
            if (stats.overtimeCollected > 0)
              '${spPeso(stats.overtimeCollected)} overtime cash to hand over',
            if (stats.overtimeOwed > 0)
              '${spPeso(stats.overtimeOwed)} not confirmed',
          ].join(' · ');
    final bool cashOwed = (stats?.overtimeOwed ?? 0) > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(color: AppTheme.border),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
          // Jump to this staff member's scans in the Activity tab.
          onTap: () => setState(() {
            _activityStaffId = _staffUid(doc);
            _selectedIndex = 2;
          }),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
            child: _staffRowContent(
              doc: doc,
              name: name,
              username: username,
              activityLine: activityLine,
              cashLine: cashLine,
              cashOwed: cashOwed,
              deactivated: deactivated,
            ),
          ),
        ),
      ),
    );
  }

  Widget _staffRowContent({
    required QueryDocumentSnapshot<Map<String, dynamic>> doc,
    required String name,
    required String username,
    required String activityLine,
    String cashLine = '',
    bool cashOwed = false,
    required bool deactivated,
  }) {
    return Row(
      children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: deactivated
              ? AppTheme.border
              : AppTheme.accent.withValues(alpha: 0.3),
          child: Text(
            _initials(name),
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: AppTheme.textDark,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppTheme.textDark,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Icon(
                    Icons.alternate_email_rounded,
                    size: 13,
                    color: AppTheme.textMuted,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      username.isEmpty ? 'No username' : username,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                    ),
                  ),
                ],
              ),
              if (activityLine.isNotEmpty) ...[
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(
                      deactivated
                          ? Icons.person_off_outlined
                          : Icons.qr_code_scanner_rounded,
                      size: 13,
                      color: AppTheme.textMuted,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        activityLine,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (cashLine.isNotEmpty) ...[
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(
                      Icons.payments_outlined,
                      size: 13,
                      color: cashOwed ? spInsideColor : spEntryColor,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        cashLine,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: cashOwed ? spInsideColor : spEntryColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        if (deactivated)
          TextButton(
            onPressed: () => _setStaffActive(doc.id, name, active: true),
            child: const Text('Reactivate'),
          )
        else
          IconButton(
            onPressed: () => _setStaffActive(doc.id, name, active: false),
            icon: Icon(Icons.person_off_outlined, color: spDeniedColor),
            tooltip: 'Deactivate staff',
          ),
      ],
    );
  }

  Widget _buildCommissionsTab({
    required String ownerId,
    required Map<String, dynamic> ownerData,
  }) {
    return _withFacilityId(
      ownerId: ownerId,
      ownerData: ownerData,
      builder: (String facilityId, bool resolving) {
        return ListView(
          padding: const EdgeInsets.only(top: 8),
          children: [
            const SpPageHeader(
              title: 'Finance',
              subtitle: 'Your earnings, SmartPark commission and transactions.',
            ),
            const SizedBox(height: 16),
            if (resolving)
              const SpSkeletonList()
            else if (facilityId.isEmpty)
              const SpEmptyState(
                icon: Icons.storefront_outlined,
                message:
                    'Register your facility first so transactions can be '
                    'tracked here.',
              )
            else
              _CommissionsListContent(
                facilityId: facilityId,
                ownerId: ownerId,
                formatShortDate: _formatShortDate,
              ),
          ],
        );
      },
    );
  }

  Widget _buildProfileTab() {
    return SpProfileView(
      roleLabel: 'Parking Owner',
      firstNameController: _profileFirstNameController,
      lastNameController: _profileLastNameController,
      email: _profileEmailController.text.isNotEmpty
          ? _profileEmailController.text
          : FirebaseAuth.instance.currentUser?.email ?? '',
      onSignOut: _signOut,
      padding: const EdgeInsets.only(top: 8),
      wide: _isTablet,
    );
  }
}

/// One staff member's gate scans and overtime cash today, for the Staff tab.
class _StaffDayStats {
  int scans = 0;
  int denied = 0;
  DateTime? last;

  /// Overtime cash from this staff member's exits today: flagged but not
  /// confirmed, and confirmed collected (what they should hand over).
  double overtimeOwed = 0;
  double overtimeCollected = 0;

  static Map<String, _StaffDayStats> today(
    Iterable<Map<String, dynamic>> logs,
  ) {
    final DateTime now = DateTime.now();
    final Map<String, _StaffDayStats> byStaff = <String, _StaffDayStats>{};
    for (final Map<String, dynamic> data in logs) {
      final String staffId = ((data['staffId'] as String?) ?? '').trim();
      if (staffId.isEmpty) continue;
      // Pending server timestamps read as null; treat them as now.
      final DateTime time = spParseDateTime(data['timestamp']) ?? now;
      if (!spSameDate(time, now)) continue;
      final _StaffDayStats stats = byStaff.putIfAbsent(
        staffId,
        _StaffDayStats.new,
      );
      stats.scans++;
      if (!spIsAllowedLog(data)) stats.denied++;
      final double overtime = ((data['overtimeAmount'] as num?) ?? 0)
          .toDouble();
      switch (spOvertimeStatus(data)) {
        case kOvertimeCashDue:
          stats.overtimeOwed += overtime;
        case kOvertimeCollected:
          stats.overtimeCollected += overtime;
      }
      if (stats.last == null || time.isAfter(stats.last!)) stats.last = time;
    }
    return byStaff;
  }
}
