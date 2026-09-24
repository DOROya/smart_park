// ignore_for_file: invalid_use_of_protected_member

part of '../admin_home_page.dart';

class _AlertItem {
  _AlertItem({
    required this.title,
    required this.subtitle,
    required this.createdAt,
  });

  final String title;
  final String subtitle;
  final DateTime? createdAt;
}

extension _AdminHomePageFragments on _AdminHomePageState {
  bool get _isTablet => spIsTablet(context);

  /// Bar chart height, shared by the Recent Activity list on phones.
  double get _dashboardChartHeight => 170;

  /// Two top-aligned columns for tablet layouts.
  Widget _adminTabletColumns({
    required Widget left,
    required Widget right,
    int leftFlex = 1,
    int rightFlex = 1,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: leftFlex, child: left),
        const SizedBox(width: 20),
        Expanded(flex: rightFlex, child: right),
      ],
    );
  }

  /// Page title used at the top of every admin tab except the dashboard.
  Widget _buildTabHero({
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    return SpPageHeader(title: title, subtitle: subtitle);
  }

  Widget _buildRevenueChartCard({
    required _RevenueSeries series,
    required String title,
    required String subtitle,
    Color color = spExitColor,
  }) {
    return SpSectionCard(
      icon: Icons.bar_chart_rounded,
      title: title,
      subtitle: subtitle,
      trailing: SpChip(label: spCompactPeso(series.total), color: color),
      child: SpBarChart(
        values: series.values,
        labels: series.labels,
        labelEvery: series.labelEvery,
        formatValue: spCompactPeso,
        color: color,
        height: _dashboardChartHeight,
      ),
    );
  }

  String _relativeTime(DateTime? date) {
    if (date == null) return '';
    final Duration diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return spFormatDate(date);
  }

  /// With [fillHeight] the card fills a bounded parent (tablet, sized by the
  /// chart beside it); otherwise the list gets the chart's height. Either way
  /// the list scrolls inside the card.
  Widget _buildRecentAlerts(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> users,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> establishments, {
    bool fillHeight = false,
  }) {
    final List<(_AlertItem, bool)> alerts = <(_AlertItem, bool)>[];

    for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in users) {
      final Map<String, dynamic> data = doc.data();
      final String name =
          '${(data['firstName'] as String?) ?? ''} ${(data['lastName'] as String?) ?? ''}'
              .trim();
      final String role = ((data['role'] as String?) ?? '').trim();
      alerts.add((
        _AlertItem(
          title: name.isEmpty ? 'New user registered' : name,
          subtitle: role.isEmpty ? 'New user registration' : 'New $role',
          createdAt:
              _parseDateTime(data['createdAt']) ??
              _parseDateTime(data['createdAtClient']),
        ),
        false,
      ));
    }

    for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
        in establishments) {
      final Map<String, dynamic> data = doc.data();
      alerts.add((
        _AlertItem(
          title: (data['name'] as String?) ?? 'Unnamed Establishment',
          subtitle: 'New establishment registration',
          createdAt:
              _parseDateTime(data['createdAt']) ??
              _parseDateTime(data['createdAtClient']),
        ),
        true,
      ));
    }

    final DateTime epoch = DateTime.fromMillisecondsSinceEpoch(0);
    alerts.sort(
      ((_AlertItem, bool) a, (_AlertItem, bool) b) =>
          (b.$1.createdAt ?? epoch).compareTo(a.$1.createdAt ?? epoch),
    );

    final Widget list = alerts.isEmpty
        ? const Center(
            child: SpEmptyState(boxed: false, message: 'No new activity yet.'),
          )
        : ListView.builder(
            padding: EdgeInsets.zero,
            itemCount: alerts.length,
            itemBuilder: (BuildContext context, int index) {
              final (_AlertItem item, bool isFacility) = alerts[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: (isFacility ? spEntryColor : spExitColor)
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        isFacility
                            ? Icons.storefront_rounded
                            : Icons.person_add_alt_1_rounded,
                        size: 18,
                        color: isFacility ? spEntryColor : spExitColor,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textDark,
                            ),
                          ),
                          Text(
                            item.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _relativeTime(item.createdAt),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              );
            },
          );

    return SpSectionCard(
      icon: Icons.notifications_active_outlined,
      title: 'Recent Activity',
      subtitle: 'Latest sign-ups and facility registrations.',
      expandChild: fillHeight,
      child: fillHeight
          ? list
          : SizedBox(height: _dashboardChartHeight, child: list),
    );
  }

  List<Widget> _buildDashboardTab({
    required int totalUsers,
    required int establishmentCount,
    required int pendingCount,
    required double commission,
    required _RevenueSeries dashboardCommission,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> users,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> establishments,
  }) {
    final DateTime now = DateTime.now();
    // Sign-up stores the display name as "First|Last".
    final String adminName =
        (FirebaseAuth.instance.currentUser?.displayName ?? '')
            .trim()
            .split(RegExp(r'[|\s]'))
            .first;
    final Widget? reviewButton = pendingCount > 0
        ? SpHeroButton(
            icon: Icons.fact_check_rounded,
            label:
                'Review $pendingCount pending facilit${pendingCount == 1 ? 'y' : 'ies'}',
            onPressed: () => setState(() => _selectedTab = _AdminTab.facility),
          )
        : null;
    final Widget usersTile = SpStatTile(
      icon: Icons.group_rounded,
      color: spExitColor,
      label: 'Users',
      caption: 'Drivers and owners',
      value: '$totalUsers',
    );
    final Widget establishmentsTile = SpStatTile(
      icon: Icons.apartment_rounded,
      color: spEntryColor,
      label: 'Establishments',
      caption: '$pendingCount pending review',
      value: '$establishmentCount',
    );
    final Widget commissionTile = SpStatTile(
      icon: Icons.payments_rounded,
      color: spInsideColor,
      label: 'Commission',
      caption: 'All time',
      value: spCompactPeso(commission),
    );
    final Widget commissionChart = _buildRevenueChartCard(
      series: dashboardCommission,
      title: 'Commission · Last 7 Days',
      subtitle: 'Platform commission earned per day.',
      color: spInsideColor,
    );
    final bool isTablet = _isTablet;

    return <Widget>[
      SpHeroBanner(
        title: adminName.isEmpty
            ? spGreeting(now)
            : '${spGreeting(now)}, $adminName',
        badge: 'Admin',
        details: <(IconData, String)>[
          (Icons.dashboard_rounded, 'Platform overview'),
          (Icons.calendar_today_rounded, spFormatDate(now)),
        ],
        // A full-width button reads as a stray bar across a tablet banner.
        action: isTablet && reviewButton != null
            ? Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: reviewButton,
                ),
              )
            : reviewButton,
      ),
      const SizedBox(height: 16),
      const SpSectionLabel('Overview'),
      const SizedBox(height: 10),
      if (isTablet) ...[
        SpGrid(
          columns: 3,
          spacing: 10,
          children: <Widget>[usersTile, establishmentsTile, commissionTile],
        ),
        const SizedBox(height: 20),
        // The row takes the chart card's height; the activity card is
        // positioned over that space, so it matches and scrolls within it.
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 3, child: commissionChart),
              const SizedBox(width: 20),
              Expanded(
                flex: 2,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: _buildRecentAlerts(
                        users,
                        establishments,
                        fillHeight: true,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ] else ...[
        SpStatRow(left: usersTile, right: establishmentsTile),
        const SizedBox(height: 10),
        commissionTile,
        const SizedBox(height: 16),
        commissionChart,
        const SizedBox(height: 16),
        _buildRecentAlerts(users, establishments),
      ],
    ];
  }

  List<Widget> _buildFacilityTab({
    required int establishmentCount,
    required int pendingCount,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> establishments,
  }) {
    return <Widget>[
      _buildTabHero(
        title: 'Facility Review',
        subtitle: 'Review establishments and process approvals.',
        icon: Icons.apartment_rounded,
      ),
      const SizedBox(height: 16),
      _buildFacilityMetricsRow(
        establishmentCount: establishmentCount,
        pendingCount: pendingCount,
      ),
      const SizedBox(height: 12),
      _buildFacilityReviewWorkflow(establishments),
    ];
  }

  List<Widget> _buildUsersTab({
    required int driverCount,
    required int parkingOwnerCount,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> users,
  }) {
    return <Widget>[
      _buildTabHero(
        title: 'Users',
        subtitle: 'Drivers and parking owners on the platform.',
        icon: Icons.group_rounded,
      ),
      const SizedBox(height: 16),
      SpStatRow(
        left: SpStatTile(
          icon: Icons.directions_car_rounded,
          color: spExitColor,
          label: 'Drivers',
          caption: 'Registered drivers',
          value: '$driverCount',
        ),
        right: SpStatTile(
          icon: Icons.storefront_rounded,
          color: spEntryColor,
          label: 'Parking Owners',
          caption: 'Registered owners',
          value: '$parkingOwnerCount',
        ),
      ),
      const SizedBox(height: 12),
      _buildUserDirectory(users),
    ];
  }

  List<Widget> _buildFinanceTab({
    required double totalRevenue,
    required double commission,
    required int paymentCount,
    required _RevenueSeries financeSeries,
  }) {
    final String rangeLabel = _financeRangeLabel();
    final Widget rangeControl = SpSegmentedControl<_FinanceRangeFilter>(
      options: const <(_FinanceRangeFilter, String)>[
        (_FinanceRangeFilter.month, '30D'),
        (_FinanceRangeFilter.quarter, '90D'),
        (_FinanceRangeFilter.year, '12M'),
        (_FinanceRangeFilter.all, 'All'),
      ],
      selected: _financeRange,
      onChanged: (_FinanceRangeFilter range) =>
          setState(() => _financeRange = range),
    );
    final Widget revenueTile = SpStatTile(
      icon: Icons.trending_up_rounded,
      color: spExitColor,
      label: 'Revenue',
      caption: rangeLabel,
      value: spCompactPeso(totalRevenue),
    );
    final Widget commissionTile = SpStatTile(
      icon: Icons.payments_rounded,
      color: spInsideColor,
      label: 'Commission',
      caption: rangeLabel,
      value: spCompactPeso(commission),
    );
    final Widget transactionsTile = SpStatTile(
      icon: Icons.receipt_long_rounded,
      color: spEntryColor,
      label: 'Transactions',
      caption: rangeLabel,
      value: '$paymentCount',
    );
    final Widget avgTicketTile = SpStatTile(
      icon: Icons.calculate_outlined,
      color: const Color(0xFF7C3AED),
      label: 'Avg. Ticket',
      caption: 'Revenue per transaction',
      value: spCompactPeso(paymentCount == 0 ? 0 : totalRevenue / paymentCount),
    );

    if (_isTablet) {
      return <Widget>[
        SpPageHeader(
          title: 'Finance',
          subtitle: 'Revenue, commission and transaction trends.',
          trailing: SizedBox(width: 340, child: rangeControl),
        ),
        const SizedBox(height: 20),
        SpGrid(
          columns: 4,
          spacing: 10,
          children: <Widget>[
            revenueTile,
            commissionTile,
            transactionsTile,
            avgTicketTile,
          ],
        ),
        const SizedBox(height: 20),
        _buildRevenueChartCard(
          series: financeSeries,
          title: 'Revenue · $rangeLabel',
          subtitle: 'Gross parking payments per ${financeSeries.bucketLabel}.',
        ),
      ];
    }

    return <Widget>[
      _buildTabHero(
        title: 'Finance',
        subtitle: 'Revenue, commission and transaction trends.',
        icon: Icons.payments_rounded,
      ),
      const SizedBox(height: 16),
      rangeControl,
      const SizedBox(height: 12),
      SpStatRow(left: revenueTile, right: commissionTile),
      const SizedBox(height: 10),
      SpStatRow(left: transactionsTile, right: avgTicketTile),
      const SizedBox(height: 16),
      _buildRevenueChartCard(
        series: financeSeries,
        title: 'Revenue · $rangeLabel',
        subtitle: 'Gross parking payments per ${financeSeries.bucketLabel}.',
      ),
    ];
  }

  List<Widget> _buildSettingsTab() {
    final String email = (FirebaseAuth.instance.currentUser?.email ?? '')
        .trim();
    final Widget accountCard = SpSectionCard(
      icon: Icons.admin_panel_settings_outlined,
      title: 'Admin Account',
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: AppTheme.accent.withValues(alpha: 0.3),
            child: const Icon(Icons.shield_rounded, color: AppTheme.textDark),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Administrator',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textDark,
                  ),
                ),
                if (email.isNotEmpty)
                  Text(
                    email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textMuted,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    final Widget signOutButton = SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _signOut,
        icon: const Icon(Icons.logout_rounded),
        label: const Text(
          'Sign Out',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(double.infinity, 48),
          foregroundColor: const Color(0xFFAF2E2E),
          side: const BorderSide(color: Color(0xFFF0C9C9)),
          backgroundColor: const Color(0xFFFFF6F6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );

    final Widget statsCard = SpSectionCard(
      icon: Icons.query_stats_rounded,
      title: 'Platform Statistics',
      subtitle:
          'Dashboard and Finance totals are kept on the server. Rebuild them '
          'from all payments if they ever look wrong.',
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _rebuildingStats ? null : _rebuildStats,
          icon: _rebuildingStats
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh_rounded),
          label: Text(
            _rebuildingStats ? 'Rebuilding...' : 'Rebuild statistics',
          ),
        ),
      ),
    );

    final Widget header = _buildTabHero(
      title: 'Settings',
      subtitle: 'Admin account and session.',
      icon: Icons.settings_rounded,
    );

    if (_isTablet) {
      return <Widget>[
        header,
        const SizedBox(height: 20),
        _adminTabletColumns(
          leftFlex: 3,
          rightFlex: 2,
          left: Column(
            children: [accountCard, const SizedBox(height: 16), statsCard],
          ),
          right: signOutButton,
        ),
      ];
    }

    return <Widget>[
      header,
      const SizedBox(height: 16),
      accountCard,
      const SizedBox(height: 12),
      statsCard,
      const SizedBox(height: 12),
      signOutButton,
    ];
  }

  List<Widget> _buildTabContent({
    required int totalUsers,
    required int driverCount,
    required int parkingOwnerCount,
    required int filteredUsersCount,
    required int establishmentCount,
    required int pendingCount,
    required double totalRevenue,
    required double commission,
    required int paymentCount,
    required _RevenueSeries dashboardCommission,
    required _RevenueSeries financeSeries,
    required double financeRevenue,
    required double financeCommission,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> users,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> establishments,
    required List<_DayStat> financePayments,
  }) {
    switch (_selectedTab) {
      case _AdminTab.dashboard:
        return _buildDashboardTab(
          totalUsers: totalUsers,
          establishmentCount: establishmentCount,
          pendingCount: pendingCount,
          commission: commission,
          dashboardCommission: dashboardCommission,
          users: users,
          establishments: establishments,
        );
      case _AdminTab.facility:
        return _buildFacilityTab(
          establishmentCount: establishmentCount,
          pendingCount: pendingCount,
          establishments: establishments,
        );
      case _AdminTab.users:
        return _buildUsersTab(
          driverCount: driverCount,
          parkingOwnerCount: parkingOwnerCount,
          users: users,
        );
      case _AdminTab.finance:
        return _buildFinanceTab(
          totalRevenue: financeRevenue,
          commission: financeCommission,
          paymentCount: _sumPayments(financePayments),
          financeSeries: financeSeries,
        );
      case _AdminTab.settings:
        return _buildSettingsTab();
    }
  }
}
