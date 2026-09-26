// ignore_for_file: invalid_use_of_protected_member

part of 'admin_home_page.dart';

/// Facility tab: metrics, review panels, table and cards.
extension _AdminFacilityReview on _AdminHomePageState {
  Widget _buildFacilityMetricsRow({
    required int establishmentCount,
    required int pendingCount,
  }) {
    return SpStatRow(
      left: SpStatTile(
        icon: Icons.apartment_rounded,
        color: spEntryColor,
        label: 'Total Facilities',
        caption: 'Registered on SmartPark',
        value: '$establishmentCount',
      ),
      right: SpStatTile(
        icon: Icons.pending_actions_rounded,
        color: spInsideColor,
        label: 'Pending Review',
        caption: 'Waiting for approval',
        value: '$pendingCount',
      ),
    );
  }

  Widget _buildFacilityReviewWorkflow(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> establishments,
  ) {
    return StatefulBuilder(
      builder: (BuildContext context, StateSetter setFacilityState) {
        final List<QueryDocumentSnapshot<Map<String, dynamic>>> filteredAll =
            _filteredEstablishments(establishments);
        final List<QueryDocumentSnapshot<Map<String, dynamic>>>
        filteredPending = _pendingEstablishments(filteredAll);
        final List<QueryDocumentSnapshot<Map<String, dynamic>>>
        filteredApproved = _approvedEstablishments(filteredAll);
        final List<QueryDocumentSnapshot<Map<String, dynamic>>>
        filteredRejected = filteredAll.where((doc) {
          final String status =
              ((_mergedEstablishmentData(doc)['status'] as String?) ??
                      'pending')
                  .toLowerCase();
          return status == 'rejected';
        }).toList();

        return SpSectionCard(
          icon: Icons.fact_check_outlined,
          title: 'Establishment Review',
          subtitle: 'Search, sort and open a facility to approve or reject.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _facilitySearchController,
                      onChanged: (String value) {
                        setFacilityState(() {
                          _facilitySearchQuery = value;
                        });
                      },
                      decoration: InputDecoration(
                        hintText: 'Search facility, owner, address...',
                        prefixIcon: const Icon(Icons.search_rounded, size: 20),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
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
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceAlt,
                      borderRadius: BorderRadius.circular(AppTheme.radius),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.sort_rounded,
                          color: AppTheme.textMuted,
                          size: 20,
                        ),
                        const SizedBox(width: 4),
                        DropdownButtonHideUnderline(
                          child: DropdownButton<_FacilitySortOption>(
                            value: _facilitySort,
                            isDense: true,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textDark,
                            ),
                            onChanged: (_FacilitySortOption? value) {
                              if (value == null) return;
                              setFacilityState(() {
                                _facilitySort = value;
                              });
                            },
                            items: const [
                              DropdownMenuItem(
                                value: _FacilitySortOption.pendingFirst,
                                child: Text('Pending First'),
                              ),
                              DropdownMenuItem(
                                value: _FacilitySortOption.newest,
                                child: Text('Newest'),
                              ),
                              DropdownMenuItem(
                                value: _FacilitySortOption.oldest,
                                child: Text('Oldest'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _buildCollapsibleFacilityPanel(
                title: 'Pending Facilities',
                facilities: filteredPending,
                emptyText: 'No facilities pending review.',
                accentColor: AppTheme.warning,
                icon: Icons.pending_actions_rounded,
                initExpanded: true,
              ),
              _buildCollapsibleFacilityPanel(
                title: 'Approved Facilities',
                facilities: filteredApproved,
                emptyText: 'No approved facilities found.',
                accentColor: AppTheme.success,
                icon: Icons.check_circle_outline_rounded,
                initExpanded: false,
              ),
              _buildCollapsibleFacilityPanel(
                title: 'Rejected Facilities',
                facilities: filteredRejected,
                emptyText: 'No rejected facilities found.',
                accentColor: AppTheme.danger,
                icon: Icons.cancel_outlined,
                initExpanded: false,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCollapsibleFacilityPanel({
    required String title,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> facilities,
    required String emptyText,
    required Color accentColor,
    required IconData icon,
    required bool initExpanded,
  }) {
    final int count = facilities.length;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppTheme.surfaceAlt,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
          side: BorderSide(color: AppTheme.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: initExpanded,
            tilePadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 4,
            ),
            leading: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              ),
              child: Icon(icon, color: accentColor, size: 20),
            ),
            title: Row(
              children: [
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textDark,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: accentColor,
                    ),
                  ),
                ),
              ],
            ),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: facilities.isEmpty
                    ? Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusSmall,
                          ),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Text(
                          emptyText,
                          style: TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 13,
                          ),
                        ),
                      )
                    : _buildFacilityPanelList(title, facilities),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// A page of [facilities] (a compact table on tablets, cards on phones)
  /// with a "Show more" control so long lists don't flood the screen.
  Widget _buildFacilityPanelList(
    String panelKey,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> facilities,
  ) {
    final bool isTablet = _isTablet;
    final int pageSize = isTablet ? 10 : 5;
    final int limit = _facilityPanelLimits[panelKey] ?? pageSize;
    final List<QueryDocumentSnapshot<Map<String, dynamic>>> visible = facilities
        .take(limit)
        .toList();
    final int remaining = facilities.length - visible.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isTablet)
          _buildFacilityTable(visible)
        else
          _buildFacilityList(visible),
        if (remaining > 0 || limit > pageSize)
          Padding(
            padding: EdgeInsets.only(top: isTablet ? 8 : 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (remaining > 0)
                  TextButton.icon(
                    onPressed: () => setState(
                      () => _facilityPanelLimits[panelKey] = limit + pageSize,
                    ),
                    icon: const Icon(Icons.expand_more_rounded, size: 18),
                    label: Text(
                      'Show ${remaining < pageSize ? remaining : pageSize} more '
                      '($remaining left)',
                    ),
                  ),
                if (limit > pageSize)
                  TextButton.icon(
                    onPressed: () =>
                        setState(() => _facilityPanelLimits.remove(panelKey)),
                    icon: const Icon(Icons.expand_less_rounded, size: 18),
                    label: const Text('Show less'),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  static final TextStyle _facilityTableHeaderStyle = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.4,
    color: AppTheme.textMuted,
  );

  /// Tablet facility list: one dense row per facility; tap to review.
  Widget _buildFacilityTable(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> facilities,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppTheme.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(
              children: [
                Expanded(
                  flex: 4,
                  child: Text('FACILITY', style: _facilityTableHeaderStyle),
                ),
                Expanded(
                  flex: 3,
                  child: Text('OWNER', style: _facilityTableHeaderStyle),
                ),
                Expanded(
                  flex: 2,
                  child: Text('SLOTS', style: _facilityTableHeaderStyle),
                ),
                Expanded(
                  flex: 2,
                  child: Text('SUBMITTED', style: _facilityTableHeaderStyle),
                ),
                SizedBox(width: 28),
              ],
            ),
          ),
          for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
              in facilities) ...[
            Divider(height: 1, thickness: 1, color: AppTheme.surfaceAlt),
            _buildFacilityTableRow(doc),
          ],
        ],
      ),
    );
  }

  Widget _buildFacilityTableRow(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final Map<String, dynamic> data = _mergedEstablishmentData(doc);
    final String name = ((data['name'] as String?) ?? '').trim();
    final String address = ((data['address'] as String?) ?? '').trim();
    final String ownerName =
        '${(data['ownerFirstName'] as String?) ?? ''} ${(data['ownerLastName'] as String?) ?? ''}'
            .trim();
    final String ownerEmail = ((data['ownerEmail'] as String?) ?? '').trim();
    final int cars = (((data['slotCounts'] as Map?)?['car'] as num?) ?? 0)
        .toInt();
    final int motorcycles =
        (((data['slotCounts'] as Map?)?['motorcycle'] as num?) ?? 0).toInt();
    final bool resubmitted =
        ((data['status'] as String?) ?? 'pending').toLowerCase() == 'pending' &&
        data['resubmittedAt'] != null;
    final DateTime? submittedAt =
        _parseDateTime(data['resubmittedAt']) ??
        _parseDateTime(data['createdAt']) ??
        _parseDateTime(data['createdAtClient']);

    Widget twoLines(String top, String bottom, {bool strong = false}) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            top,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: strong ? 14 : 13,
              fontWeight: strong ? FontWeight.w700 : FontWeight.w600,
              color: AppTheme.textDark,
            ),
          ),
          if (bottom.isNotEmpty)
            Text(
              bottom,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
            ),
        ],
      );
    }

    Widget slot(IconData icon, Color color, int count) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.textDark,
            ),
          ),
        ],
      );
    }

    return InkWell(
      onTap: () => _showEstablishmentReviewDialog(doc),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            Expanded(
              flex: 4,
              child: twoLines(
                name.isEmpty ? 'Unnamed Establishment' : name,
                address.isEmpty ? 'No address' : address,
                strong: true,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 3,
              child: twoLines(
                ownerName.isEmpty ? 'Unknown Owner' : ownerName,
                ownerEmail,
              ),
            ),
            Expanded(
              flex: 2,
              child: Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  slot(Icons.directions_car_outlined, AppTheme.info, cars),
                  slot(
                    Icons.two_wheeler_outlined,
                    AppTheme.success,
                    motorcycles,
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    submittedAt == null ? '—' : _relativeTime(submittedAt),
                    style: TextStyle(fontSize: 13, color: AppTheme.textDark),
                  ),
                  if (resubmitted) ...[
                    const SizedBox(height: 2),
                    SpChip(label: 'Resubmitted', color: AppTheme.warning),
                  ],
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
          ],
        ),
      ),
    );
  }

  /// Phone facility list: the tablet table's facts in one compact row per
  /// facility (name, owner, slots, submitted); tap to review.
  Widget _buildFacilityList(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> facilities,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppTheme.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (int i = 0; i < facilities.length; i++) ...[
            if (i > 0)
              Divider(height: 1, thickness: 1, color: AppTheme.surfaceAlt),
            _buildFacilityListRow(facilities[i]),
          ],
        ],
      ),
    );
  }

  Widget _buildFacilityListRow(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final Map<String, dynamic> data = _mergedEstablishmentData(doc);
    final String name = ((data['name'] as String?) ?? '').trim();
    final String ownerName =
        '${(data['ownerFirstName'] as String?) ?? ''} ${(data['ownerLastName'] as String?) ?? ''}'
            .trim();
    final int cars = (((data['slotCounts'] as Map?)?['car'] as num?) ?? 0)
        .toInt();
    final int motorcycles =
        (((data['slotCounts'] as Map?)?['motorcycle'] as num?) ?? 0).toInt();
    final bool resubmitted =
        ((data['status'] as String?) ?? 'pending').toLowerCase() == 'pending' &&
        data['resubmittedAt'] != null;
    final DateTime? submittedAt =
        _parseDateTime(data['resubmittedAt']) ??
        _parseDateTime(data['createdAt']) ??
        _parseDateTime(data['createdAtClient']);

    final TextStyle meta = TextStyle(fontSize: 12, color: AppTheme.textMuted);

    return InkWell(
      onTap: () => _showEstablishmentReviewDialog(doc),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          name.isEmpty ? 'Unnamed Establishment' : name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textDark,
                          ),
                        ),
                      ),
                      if (resubmitted) ...[
                        const SizedBox(width: 6),
                        SpChip(label: 'Resubmitted', color: AppTheme.warning),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    ownerName.isEmpty ? 'Unknown Owner' : ownerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: meta,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.directions_car_outlined,
                        size: 14,
                        color: AppTheme.info,
                      ),
                      const SizedBox(width: 3),
                      Text('$cars', style: meta),
                      const SizedBox(width: 10),
                      Icon(
                        Icons.two_wheeler_outlined,
                        size: 14,
                        color: AppTheme.success,
                      ),
                      const SizedBox(width: 3),
                      Text('$motorcycles', style: meta),
                      if (submittedAt != null) ...[
                        Text('  ·  ', style: meta),
                        Flexible(
                          child: Text(
                            _relativeTime(submittedAt),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: meta,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
          ],
        ),
      ),
    );
  }
}
