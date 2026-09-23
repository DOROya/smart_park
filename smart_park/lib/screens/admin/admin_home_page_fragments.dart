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

class _SimpleLineChartPainter extends CustomPainter {
  _SimpleLineChartPainter({
    required this.points,
    required this.maxValue,
    required this.lineColor,
  });

  final List<int> points;
  final int maxValue;
  final Color lineColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) {
      return;
    }

    final Paint axisPaint = Paint()
      ..color = const Color(0xFFD7DAE2)
      ..strokeWidth = 1;
    final Paint linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2.6
      ..style = PaintingStyle.stroke;

    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, size.height),
      axisPaint,
    );

    final Path path = Path();
    for (int i = 0; i < points.length; i++) {
      final double x = points.length == 1
          ? size.width / 2
          : i * (size.width / (points.length - 1));
      final double y =
          size.height - ((points[i] / maxValue) * (size.height - 10));
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }

      canvas.drawCircle(Offset(x, y), 3.2, Paint()..color = lineColor);
    }

    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant _SimpleLineChartPainter oldDelegate) {
    return oldDelegate.points != points || oldDelegate.maxValue != maxValue;
  }
}

extension _AdminHomePageFragments on _AdminHomePageState {
  Widget _buildTabHero({
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFFFFEAA8), Color(0xFFF7C846)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 10,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0x35FFFFFF),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: const Color(0xFF2F3544), size: 26),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF1F2532),
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFF3D4658),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard(String title, String value) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4E7EF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x11000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
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
              fontSize: 22,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeeklyRevenueChart(List<int> weeklyRevenue) {
    final int maxValue = weeklyRevenue.fold<int>(
      0,
      (int p, int c) => c > p ? c : p,
    );
    final int normalizedMax = maxValue == 0 ? 1 : maxValue;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4E7EF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Weekly Revenue',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 150,
            child: CustomPaint(
              painter: _SimpleLineChartPainter(
                points: weeklyRevenue,
                maxValue: normalizedMax,
                lineColor: const Color(0xFF1E88E5),
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPeakHoursChart(List<int> hourlyCounts) {
    final int maxValue = hourlyCounts.fold<int>(
      0,
      (int p, int c) => c > p ? c : p,
    );
    final int normalizedMax = maxValue == 0 ? 1 : maxValue;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4E7EF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Peak Hours',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 150,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List<Widget>.generate(hourlyCounts.length, (int index) {
                final double ratio = hourlyCounts[index] / normalizedMax;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(
                          height: 110 * ratio + 8,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF2C335),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${(index * 3).toString().padLeft(2, '0')}h',
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentAlerts(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> users,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> establishments,
  ) {
    final List<_AlertItem> alerts = <_AlertItem>[];

    for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in users.take(5)) {
      final Map<String, dynamic> data = doc.data();
      alerts.add(
        _AlertItem(
          title: 'New user registration',
          subtitle:
              '${(data['firstName'] as String?) ?? ''} ${(data['lastName'] as String?) ?? ''}'
                  .trim(),
          createdAt:
              _parseDateTime(data['createdAt']) ??
              _parseDateTime(data['createdAtClient']),
        ),
      );
    }

    for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
        in establishments.take(5)) {
      final Map<String, dynamic> data = doc.data();
      alerts.add(
        _AlertItem(
          title: 'New establishment registration',
          subtitle: (data['name'] as String?) ?? 'Unnamed Establishment',
          createdAt:
              _parseDateTime(data['createdAt']) ??
              _parseDateTime(data['createdAtClient']),
        ),
      );
    }

    alerts.sort((_AlertItem a, _AlertItem b) {
      final DateTime aDate =
          a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final DateTime bDate =
          b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4E7EF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Recent Alerts',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          if (alerts.isEmpty)
            const Text(
              'No new alerts yet.',
              style: TextStyle(color: AppTheme.textMuted),
            )
          else
            ...alerts.take(6).map((_AlertItem item) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.notifications_active_rounded,
                      color: Color(0xFFF2C335),
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            item.subtitle,
                            style: const TextStyle(color: AppTheme.textMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }



  Widget _buildFacilityMetricsRow({
    required int establishmentCount,
    required int pendingCount,
  }) {
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE4E7EF)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x08000000),
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.apartment_rounded,
                    color: Color(0xFF059669),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        establishmentCount.toString(),
                        style: const TextStyle(
                          color: AppTheme.textDark,
                          fontWeight: FontWeight.w800,
                          fontSize: 20,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Total Facilities',
                        style: TextStyle(
                          color: AppTheme.textMuted,
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE4E7EF)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x08000000),
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.pending_actions_rounded,
                    color: Color(0xFFD97706),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pendingCount.toString(),
                        style: const TextStyle(
                          color: AppTheme.textDark,
                          fontWeight: FontWeight.w800,
                          fontSize: 20,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Pending Review',
                        style: TextStyle(
                          color: AppTheme.textMuted,
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFacilityReviewWorkflow(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> establishments,
  ) {
    return StatefulBuilder(
      builder: (BuildContext context, StateSetter setFacilityState) {
        final List<QueryDocumentSnapshot<Map<String, dynamic>>> filteredAll =
            _filteredEstablishments(establishments);
        final List<QueryDocumentSnapshot<Map<String, dynamic>>> filteredPending =
            _pendingEstablishments(filteredAll);
        final List<QueryDocumentSnapshot<Map<String, dynamic>>> filteredApproved =
            _approvedEstablishments(filteredAll);
        final List<QueryDocumentSnapshot<Map<String, dynamic>>> filteredRejected =
            filteredAll.where((doc) {
          final String status =
              ((_mergedEstablishmentData(doc)['status'] as String?) ?? 'pending')
                  .toLowerCase();
          return status == 'rejected';
        }).toList();

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE4E7EF)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Establishment Review Workflow',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
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
                        fillColor: const Color(0xFFF8F9FC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFFE3E5EA)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFFE3E5EA)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F9FC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE3E5EA)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.sort_rounded,
                          color: AppTheme.textMuted,
                          size: 20,
                        ),
                        const SizedBox(width: 4),
                        DropdownButtonHideUnderline(
                          child: DropdownButton<_FacilitySortOption>(
                            value: _facilitySort,
                            isDense: true,
                            style: const TextStyle(
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
                accentColor: const Color(0xFFD97706),
                icon: Icons.pending_actions_rounded,
                initExpanded: true,
              ),
              _buildCollapsibleFacilityPanel(
                title: 'Approved Facilities',
                facilities: filteredApproved,
                emptyText: 'No approved facilities found.',
                accentColor: const Color(0xFF059669),
                icon: Icons.check_circle_outline_rounded,
                initExpanded: false,
              ),
              _buildCollapsibleFacilityPanel(
                title: 'Rejected Facilities',
                facilities: filteredRejected,
                emptyText: 'No rejected facilities found.',
                accentColor: const Color(0xFFDC2626),
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
        color: const Color(0xFFF8F9FC),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0xFFE6E8EE)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: initExpanded,
            tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            leading: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: accentColor, size: 20),
            ),
            title: Row(
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textDark,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
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
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFEAECEF)),
                        ),
                        child: Text(
                          emptyText,
                          style: const TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 13,
                          ),
                        ),
                      )
                    : Column(
                        children: facilities.map((doc) => _buildFacilityCard(doc)).toList(),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFacilityCard(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final Map<String, dynamic> data = _mergedEstablishmentData(doc);
    final String status = ((data['status'] as String?) ?? 'pending').toLowerCase();
    final String ownerName =
        '${(data['ownerFirstName'] as String?) ?? ''} ${(data['ownerLastName'] as String?) ?? ''}'
            .trim();

    Color statusColor;
    String statusLabel;
    if (status == 'approved') {
      statusColor = const Color(0xFF059669);
      statusLabel = 'Approved';
    } else if (status == 'rejected') {
      statusColor = const Color(0xFFDC2626);
      statusLabel = 'Rejected';
    } else {
      statusColor = const Color(0xFFD97706);
      statusLabel = 'Pending';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE4E7EF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (data['name'] as String?) ?? 'Unnamed Establishment',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on_outlined,
                          size: 15,
                          color: AppTheme.textMuted,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            (data['address'] as String?) ?? 'No address',
                            style: const TextStyle(
                              color: AppTheme.textMuted,
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),

          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1, color: Color(0xFFF0F2F6)),
          ),

          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FC),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.person_outline_rounded,
                      size: 16,
                      color: AppTheme.textMuted,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Owner: ${ownerName.isEmpty ? 'Unknown Owner' : ownerName}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textDark,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(
                      Icons.email_outlined,
                      size: 16,
                      color: AppTheme.textMuted,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        (data['ownerEmail'] as String?) ?? 'N/A',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textMuted,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Divider(height: 1, color: Color(0xFFEAECEF)),
                ),
                Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          const Icon(
                            Icons.directions_car_outlined,
                            size: 16,
                            color: Color(0xFF2563EB),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Cars: ${(data['slotCounts']?['car'] as num?) ?? 0}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Row(
                        children: [
                          const Icon(
                            Icons.two_wheeler_outlined,
                            size: 16,
                            color: Color(0xFF059669),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Motorcycles: ${(data['slotCounts']?['motorcycle'] as num?) ?? 0}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          Row(
            children: [
              const Icon(
                Icons.sell_outlined,
                size: 15,
                color: AppTheme.textMuted,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Rates: ${_formatRates(data['rates'] ?? data['ratesByType'])}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textMuted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                await _showEstablishmentReviewDialog(doc);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: const Color(0xFF22252C),
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.fact_check_rounded, size: 18),
              label: const Text(
                'View Full Review',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserDirectory(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> users,
  ) {
    return StatefulBuilder(
      builder: (BuildContext context, StateSetter setDirectoryState) {
        final List<QueryDocumentSnapshot<Map<String, dynamic>>> sortedUsers =
            _filteredUsers(users);

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
              const Text(
                'Users',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              const Text(
                'Drivers and Parking Owners',
                style: TextStyle(color: AppTheme.textMuted),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _usersSearchController,
                onChanged: (String value) {
                  setDirectoryState(() {
                    _usersSearchQuery = value;
                  });
                },
                decoration: InputDecoration(
                  hintText: 'Search by name, email, or role',
                  prefixIcon: const Icon(Icons.search_rounded),
                  isDense: true,
                  filled: true,
                  fillColor: const Color(0xFFF8F9FC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE3E5EA)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE3E5EA)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ChoiceChip(
                      label: const Text('All'),
                      selected: _userRoleFilter == _UserRoleFilter.all,
                      onSelected: (_) {
                        setDirectoryState(() {
                          _userRoleFilter = _UserRoleFilter.all;
                        });
                      },
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('Driver'),
                      selected: _userRoleFilter == _UserRoleFilter.driver,
                      onSelected: (_) {
                        setDirectoryState(() {
                          _userRoleFilter = _UserRoleFilter.driver;
                        });
                      },
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('Owner'),
                      selected: _userRoleFilter == _UserRoleFilter.parkingOwner,
                      onSelected: (_) {
                        setDirectoryState(() {
                          _userRoleFilter = _UserRoleFilter.parkingOwner;
                        });
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              if (sortedUsers.isEmpty)
                const Text(
                  'No registered users yet.',
                  style: TextStyle(color: AppTheme.textMuted),
                )
              else
                ...sortedUsers.map((
                  QueryDocumentSnapshot<Map<String, dynamic>> doc,
                ) {
                  final Map<String, dynamic> data = doc.data();
                  final String firstName =
                      (data['firstName'] as String?)?.trim() ?? '';
                  final String lastName =
                      (data['lastName'] as String?)?.trim() ?? '';
                  final String fullName = '$firstName $lastName'.trim();

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: const Color(0xFFF8F9FC),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: Color(0xFFE8EAF0)),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 2,
                        ),
                        leading: const CircleAvatar(
                          backgroundColor: Color(0xFFF8F0CC),
                          child: Icon(Icons.person_rounded, color: AppTheme.textDark),
                        ),
                        title: Text(
                          fullName.isEmpty ? 'Unnamed User' : fullName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textDark,
                          ),
                        ),
                        trailing: const Icon(
                          Icons.chevron_right_rounded,
                          color: AppTheme.textMuted,
                        ),
                        onTap: () => _showUserDetailsDialog(doc),
                      ),
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showUserDetailsDialog(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final Map<String, dynamic> data = doc.data();
    final String firstName = (data['firstName'] as String?)?.trim() ?? '';
    final String lastName = (data['lastName'] as String?)?.trim() ?? '';
    final String fullName = '$firstName $lastName'.trim();
    final String email = _readText(data['email'], fallback: 'Not provided');
    final String rawRole = (data['role'] as String?)?.trim() ?? 'Unassigned';
    final String role = rawRole.toLowerCase() == 'parking owner'
        ? 'Parking Owner'
        : (rawRole.toLowerCase() == 'driver' ? 'Driver' : rawRole);
    final String phone =
        (data['phoneNumber'] ?? data['contactNumber'] ?? data['phone'])
            ?.toString()
            .trim() ??
        '';
    final DateTime? createdAt =
        _parseDateTime(data['createdAt']) ??
        _parseDateTime(data['createdAtClient']);

    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F0CC),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.person_rounded,
                  color: AppTheme.textDark,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'User Details',
                  style: TextStyle(
                    color: AppTheme.textDark,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildUserDetailRow(
                  icon: Icons.badge_outlined,
                  label: 'Full Name',
                  value: fullName.isEmpty ? 'Unnamed User' : fullName,
                ),
                const SizedBox(height: 10),
                _buildUserDetailRow(
                  icon: Icons.work_outline_rounded,
                  label: 'Role',
                  value: role,
                ),
                const SizedBox(height: 10),
                _buildUserDetailRow(
                  icon: Icons.email_outlined,
                  label: 'Email',
                  value: email,
                ),
                if (phone.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _buildUserDetailRow(
                    icon: Icons.phone_outlined,
                    label: 'Phone Number',
                    value: phone,
                  ),
                ],
                if (createdAt != null) ...[
                  const SizedBox(height: 10),
                  _buildUserDetailRow(
                    icon: Icons.calendar_today_outlined,
                    label: 'Joined',
                    value:
                        '${createdAt.year}-${createdAt.month.toString().padLeft(2, '0')}-${createdAt.day.toString().padLeft(2, '0')}',
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text(
                'Close',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textDark,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildUserDetailRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8EAF0)),
      ),
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
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
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

  Widget _buildGroupedMetricSection({
    required IconData icon,
    required Color iconColor,
    required Color iconBgColor,
    required String value,
    required String label,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: iconBgColor,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            color: iconColor,
            size: 18,
          ),
        ),
        const SizedBox(height: 8),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.textDark,
              fontWeight: FontWeight.w800,
              fontSize: 18,
              height: 1.1,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppTheme.textMuted,
            fontWeight: FontWeight.w600,
            fontSize: 11,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildGroupedMetricsCard({
    required int totalUsers,
    required int establishmentCount,
    required double commission,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4E7EF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildGroupedMetricSection(
              icon: Icons.group_rounded,
              iconColor: const Color(0xFF2563EB),
              iconBgColor: const Color(0xFFEFF6FF),
              value: totalUsers.toString(),
              label: 'Users',
            ),
          ),
          Container(
            height: 38,
            width: 1,
            color: const Color(0xFFE4E7EF),
          ),
          Expanded(
            child: _buildGroupedMetricSection(
              icon: Icons.apartment_rounded,
              iconColor: const Color(0xFF059669),
              iconBgColor: const Color(0xFFECFDF5),
              value: establishmentCount.toString(),
              label: 'Establishments',
            ),
          ),
          Container(
            height: 38,
            width: 1,
            color: const Color(0xFFE4E7EF),
          ),
          Expanded(
            child: _buildGroupedMetricSection(
              icon: Icons.payments_rounded,
              iconColor: const Color(0xFFD97706),
              iconBgColor: const Color(0xFFFFFBEB),
              value: 'PHP ${commission.toStringAsFixed(2)}',
              label: 'Commissions',
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildDashboardTab({
    required int totalUsers,
    required int establishmentCount,
    required double commission,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> users,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> establishments,
  }) {
    return <Widget>[
      _buildTabHero(
        title: 'Admin Dashboard',
        subtitle: 'Monitor your platform performance at a glance.',
        icon: Icons.dashboard_rounded,
      ),
      const SizedBox(height: 12),
      _buildGroupedMetricsCard(
        totalUsers: totalUsers,
        establishmentCount: establishmentCount,
        commission: commission,
      ),
      const SizedBox(height: 12),
      _buildRecentAlerts(users, establishments),
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
        subtitle: 'Review establishments and process approvals quickly.',
        icon: Icons.apartment_rounded,
      ),
      const SizedBox(height: 12),
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
        subtitle: 'Track drivers and parking owners in operations.',
        icon: Icons.group_rounded,
      ),
      const SizedBox(height: 12),
      GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.8,
        children: [
          _buildMetricCard('Drivers', driverCount.toString()),
          _buildMetricCard('Parking Owners', parkingOwnerCount.toString()),
        ],
      ),
      const SizedBox(height: 12),
      _buildUserDirectory(users),
    ];
  }

  List<Widget> _buildFinanceTab({
    required double totalRevenue,
    required double commission,
    required int paymentCount,
    required List<int> weeklyRevenue,
    required List<int> peakHourCounts,
  }) {
    return <Widget>[
      _buildTabHero(
        title: 'Finance Insights',
        subtitle: 'Commission earnings and transaction trends.',
        icon: Icons.payments_rounded,
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ChoiceChip(
            label: const Text('7D'),
            selected: _financeRange == _FinanceRangeFilter.week,
            onSelected: (_) {
              setState(() {
                _financeRange = _FinanceRangeFilter.week;
              });
            },
          ),
          ChoiceChip(
            label: const Text('30D'),
            selected: _financeRange == _FinanceRangeFilter.month,
            onSelected: (_) {
              setState(() {
                _financeRange = _FinanceRangeFilter.month;
              });
            },
          ),
          ChoiceChip(
            label: const Text('90D'),
            selected: _financeRange == _FinanceRangeFilter.quarter,
            onSelected: (_) {
              setState(() {
                _financeRange = _FinanceRangeFilter.quarter;
              });
            },
          ),
          ChoiceChip(
            label: const Text('12M'),
            selected: _financeRange == _FinanceRangeFilter.year,
            onSelected: (_) {
              setState(() {
                _financeRange = _FinanceRangeFilter.year;
              });
            },
          ),
          ChoiceChip(
            label: const Text('All'),
            selected: _financeRange == _FinanceRangeFilter.all,
            onSelected: (_) {
              setState(() {
                _financeRange = _FinanceRangeFilter.all;
              });
            },
          ),
        ],
      ),
      const SizedBox(height: 8),
      Text(
        'Finance Window: ${_financeRangeLabel()}',
        style: const TextStyle(
          color: AppTheme.textMuted,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: _buildMetricCard(
              'Commission',
              'PHP ${commission.toStringAsFixed(2)}',
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _buildMetricCard('Transactions', paymentCount.toString()),
          ),
        ],
      ),
      const SizedBox(height: 12),
      _buildWeeklyRevenueChart(weeklyRevenue),
    ];
  }

  List<Widget> _buildSettingsTab() {
    return <Widget>[
      _buildTabHero(
        title: 'Admin Settings',
        subtitle: 'Control account actions and platform preferences.',
        icon: Icons.settings_rounded,
      ),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE4E7EF)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Settings',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'Admin account and platform controls.',
              style: TextStyle(color: AppTheme.textMuted),
            ),
            const SizedBox(height: 14),
            Material(
              color: Colors.transparent,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.logout_rounded),
                title: const Text('Sign Out'),
                subtitle: const Text('Sign out of this admin account.'),
                onTap: _signOut,
              ),
            ),
          ],
        ),
      ),
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
    required List<int> weeklyRevenue,
    required List<int> peakHourCounts,
    required double financeRevenue,
    required double financeCommission,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> users,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> establishments,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> financePayments,
  }) {
    switch (_selectedTab) {
      case _AdminTab.dashboard:
        return _buildDashboardTab(
          totalUsers: totalUsers,
          establishmentCount: establishmentCount,
          commission: commission,
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
          paymentCount: financePayments.length,
          weeklyRevenue: weeklyRevenue,
          peakHourCounts: peakHourCounts,
        );
      case _AdminTab.settings:
        return _buildSettingsTab();
    }
  }
}
