// ignore_for_file: invalid_use_of_protected_member

part of 'admin_home_page.dart';

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
    Color? color,
  }) {
    color ??= spExitColor;
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
                        borderRadius: BorderRadius.circular(
                          AppTheme.radiusSmall,
                        ),
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
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textDark,
                            ),
                          ),
                          Text(
                            item.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
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
                      style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
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
      value: spPeso(commission),
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
        const SizedBox(height: 20),
        const AdminDriverReportsCard(),
      ] else ...[
        SpStatRow(left: usersTile, right: establishmentsTile),
        const SizedBox(height: 10),
        commissionTile,
        const SizedBox(height: 16),
        commissionChart,
        const SizedBox(height: 16),
        const AdminDriverReportsCard(),
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
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> establishments,
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
      _buildUserDirectory(users, establishments),
    ];
  }

  List<Widget> _buildFinanceTab({required List<_DayStat> allDays}) {
    // Commission is SmartPark's income; what drivers paid the lots is the
    // owners' business, so the admin's Finance tab shows commission only.
    final List<SalesEntry> entries = <SalesEntry>[
      for (final _DayStat d in allDays)
        SalesEntry(
          at: d.day,
          count: d.paymentCount,
          commissionCentavos: (d.commission * 100).round(),
        ),
    ];
    DateTime? earliest;
    for (final SalesEntry e in entries) {
      if (earliest == null || e.at.isBefore(earliest)) earliest = e.at;
    }
    final SalesReport report = SalesReport.forRange(entries, _financeRange);
    final SalesReport previous = SalesReport.prior(entries, _financeRange);
    final SalesRow totals = report.totals;
    final _RevenueSeries series = _commissionSeries(report);
    final String period = salesReportPeriod(report);

    final User? admin = FirebaseAuth.instance.currentUser;
    final Widget salesReport = SpSalesReportCard(
      report: report,
      previous: previous,
      audience: SalesReportAudience.platform,
      scopeLabel: 'All facilities',
      preparedBy: (admin?.email ?? '').trim(),
    );
    final Widget periodBar = SpFinancePeriodBar(
      range: _financeRange,
      earliest: earliest,
      onChanged: (FinanceRange range) => setState(() => _financeRange = range),
    );
    final Widget commissionTile = SpStatTile(
      icon: Icons.payments_rounded,
      color: spInsideColor,
      label: 'Commission',
      caption: "SmartPark's earnings",
      value: spPeso(totals.commissionCentavos / 100),
    );
    final Widget transactionsTile = SpStatTile(
      icon: Icons.receipt_long_rounded,
      color: spEntryColor,
      label: 'Transactions',
      caption: 'Paid in the app',
      value: '${totals.count}',
    );
    final Widget perTransactionTile = SpStatTile(
      icon: Icons.calculate_outlined,
      color: const Color(0xFF7C3AED),
      label: 'Per Transaction',
      caption: 'Average commission',
      value: totals.count == 0
          ? spPeso(0)
          : spPeso(totals.commissionCentavos / 100 / totals.count),
    );
    final Widget chart = _buildRevenueChartCard(
      series: series,
      // The period can be long ("Q4 2026 (Oct - Dec)"), so it goes in the
      // subtitle, which wraps, instead of the one-line title.
      title: 'Commission',
      subtitle: 'Earned per ${series.bucketLabel}, $period.',
      color: spInsideColor,
    );

    if (_isTablet) {
      return <Widget>[
        const SpPageHeader(
          title: 'Finance',
          subtitle: 'SmartPark commission and transactions.',
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: periodBar,
          ),
        ),
        const SizedBox(height: 16),
        SpGrid(
          columns: 3,
          spacing: 10,
          children: <Widget>[
            commissionTile,
            transactionsTile,
            perTransactionTile,
          ],
        ),
        const SizedBox(height: 20),
        chart,
        const SizedBox(height: 20),
        salesReport,
      ];
    }

    return <Widget>[
      _buildTabHero(
        title: 'Finance',
        subtitle: 'SmartPark commission and transactions.',
        icon: Icons.payments_rounded,
      ),
      const SizedBox(height: 16),
      periodBar,
      const SizedBox(height: 12),
      SpStatRow(left: commissionTile, right: transactionsTile),
      const SizedBox(height: 10),
      perTransactionTile,
      const SizedBox(height: 16),
      chart,
      const SizedBox(height: 16),
      salesReport,
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
            child: Icon(Icons.shield_rounded, color: AppTheme.textDark),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
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
                    style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
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
          foregroundColor: AppTheme.danger,
          side: BorderSide(color: AppTheme.dangerBorder),
          backgroundColor: AppTheme.dangerSoft,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radius),
          ),
        ),
      ),
    );

    final Widget statsCard = SpSectionCard(
      icon: Icons.build_circle_outlined,
      title: 'Maintenance',
      subtitle:
          'Server-side fixes. Dashboard and Finance totals can be rebuilt '
          'from all payments if they ever look wrong, and photos uploaded '
          'before compression existed can be shrunk for faster loading.',
      child: Column(
        children: [
          SizedBox(
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
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _compressingPhotos ? null : _compressExistingPhotos,
              icon: _compressingPhotos
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.compress_rounded),
              label: Text(
                _compressingPhotos
                    ? 'Compressing photos...'
                    : 'Compress existing photos',
              ),
            ),
          ),
        ],
      ),
    );

    final Widget header = _buildTabHero(
      title: 'Settings',
      subtitle: 'Admin account, security and appearance.',
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
            children: [
              accountCard,
              const SizedBox(height: 16),
              statsCard,
              const SizedBox(height: 16),
              const SpAppearanceCard(),
            ],
          ),
          // Sign Out is at the foot of the navigation rail on tablets.
          right: const SpChangePasswordCard(),
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
      const SpChangePasswordCard(),
      const SizedBox(height: 12),
      const SpAppearanceCard(),
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
    required double commission,
    required _RevenueSeries dashboardCommission,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> users,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> establishments,
    required List<_DayStat> allPayments,
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
          establishments: establishments,
        );
      case _AdminTab.finance:
        return _buildFinanceTab(allDays: allPayments);
      case _AdminTab.settings:
        return _buildSettingsTab();
    }
  }
}
