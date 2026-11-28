part of 'package:smart_park/screens/parking_owner/parking_owner_home_screen.dart';

DateTime? _parseDateTime(dynamic value) {
  if (value == null) return null;
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  return null;
}

/// A stored status for a chip: "PAID" -> "Paid", "PARTIALLY_REFUNDED" ->
/// "Partially refunded".
String _statusLabel(String status) {
  final String s = status.replaceAll('_', ' ').trim().toLowerCase();
  return s.isEmpty ? '' : '${s[0].toUpperCase()}${s.substring(1)}';
}

class _CommissionRecord {
  const _CommissionRecord({
    required this.id,
    required this.driverName,
    required this.grossAmount,
    required this.platformFee,
    required this.netToOwner,
    required this.status,
    this.refundPayback = 0,
    this.createdAt,
    this.overtimeHours = 0,
    this.overtimeAmount = 0,
    this.overtimeStatus = '',
    this.overtimeSettledAt,
  });

  final String id;
  final String driverName;
  final double grossAmount;
  final double platformFee;
  final double netToOwner;

  /// Part of the owner's share kept back to pay off a refund they owe
  /// (`refundRecoveryCentavos` on the split). Zero on most sales.
  final double refundPayback;

  /// PayMongo's (estimated) processing fee - whatever is left of the gross
  /// after SmartPark's commission, any refund payback and the payout.
  double get processingFee =>
      grossAmount - platformFee - refundPayback - netToOwner;
  final String status;
  final DateTime? createdAt;

  /// Overtime billed at the exit, paid in cash at the gate (outside
  /// PayMongo, so no commission). Zero when the stay had none.
  final int overtimeHours;
  final double overtimeAmount;

  /// The ticket's `overtimeStatus`: cash_due or collected.
  final String overtimeStatus;

  /// When the overtime cash was collected.
  final DateTime? overtimeSettledAt;

  /// The `transactions` doc; null for records known only from a payment
  /// split. Carries the driver, so the owner can report them.
  bool get hasOvertime => overtimeHours > 0 && overtimeAmount > 0;

  /// Latest money event on the ticket, so settling overtime brings the
  /// ticket back to the top of the list.
  DateTime? get lastActivityAt =>
      overtimeSettledAt != null &&
          (createdAt == null || overtimeSettledAt!.isAfter(createdAt!))
      ? overtimeSettledAt
      : createdAt;
}

class _CommissionsListContent extends StatefulWidget {
  const _CommissionsListContent({
    required this.facilityId,
    required this.ownerId,
    required this.formatShortDate,
  });

  final String facilityId;
  final String ownerId;
  final String Function(DateTime) formatShortDate;

  @override
  State<_CommissionsListContent> createState() =>
      _CommissionsListContentState();
}

class _CommissionsListContentState extends State<_CommissionsListContent>
    with SpStreamCache<_CommissionsListContent> {
  String get facilityId => widget.facilityId;
  String get ownerId => widget.ownerId;
  String Function(DateTime) get formatShortDate => widget.formatShortDate;

  /// The week, month, quarter or year every figure on the tab covers.
  FinanceRange _range = FinanceRange.containing(
    FinancePeriod.month,
    DateTime.now(),
  );

  @override
  Widget build(BuildContext context) {
    // Same-width digits, so amounts line up down the page.
    return DefaultTextStyle.merge(
      style: spTabularFigures,
      child: _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      // Only this facility's records; owners may not read anyone else's.
      stream: cachedStream(
        'transactions_$facilityId',
        () => FirebaseFirestore.instance
            .collection('transactions')
            .where('establishmentId', isEqualTo: facilityId)
            .snapshots(),
      ),
      builder:
          (
            BuildContext context,
            AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> txSnapshot,
          ) {
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: cachedStream(
                'payment_splits_$facilityId',
                () => FirebaseFirestore.instance
                    .collection('payment_splits')
                    .where('establishmentId', isEqualTo: facilityId)
                    .snapshots(),
              ),
              builder:
                  (
                    BuildContext context,
                    AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>>
                    splitSnapshot,
                  ) {
                    // Walk-in fees and cash handovers, for the report.
                    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: cachedStream(
                        'walk_in_fees_$facilityId',
                        () => gateCashQueries(facilityId)[1].snapshots(),
                      ),
                      builder: (context, walkInSnapshot) {
                        return StreamBuilder<
                          QuerySnapshot<Map<String, dynamic>>
                        >(
                          stream: cachedStream(
                            'cash_handovers_$facilityId',
                            () => FirebaseFirestore.instance
                                .collection('cash_handovers')
                                .where('establishmentId', isEqualTo: facilityId)
                                .snapshots(),
                          ),
                          builder: (context, handoverSnapshot) {
                            return _buildRecords(
                              context,
                              txSnapshot,
                              splitSnapshot,
                              walkInLogs: <Map<String, dynamic>>[
                                for (final QueryDocumentSnapshot<
                                      Map<String, dynamic>
                                    >
                                    d
                                    in walkInSnapshot.data?.docs ??
                                        <
                                          QueryDocumentSnapshot<
                                            Map<String, dynamic>
                                          >
                                        >[])
                                  d.data(),
                              ],
                              handovers: <Map<String, dynamic>>[
                                for (final QueryDocumentSnapshot<
                                      Map<String, dynamic>
                                    >
                                    d
                                    in handoverSnapshot.data?.docs ??
                                        <
                                          QueryDocumentSnapshot<
                                            Map<String, dynamic>
                                          >
                                        >[])
                                  d.data(),
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

  Widget _buildRecords(
    BuildContext context,
    AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> txSnapshot,
    AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> splitSnapshot, {
    List<Map<String, dynamic>> walkInLogs = const <Map<String, dynamic>>[],
    List<Map<String, dynamic>> handovers = const <Map<String, dynamic>>[],
  }) {
    if (txSnapshot.hasError && splitSnapshot.hasError) {
      return const SpEmptyState(
        icon: Icons.error_outline_rounded,
        message: 'Unable to load transactions right now.',
      );
    }

    if (txSnapshot.connectionState == ConnectionState.waiting &&
        splitSnapshot.connectionState == ConnectionState.waiting) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: SpSkeletonList(),
      );
    }

    final List<QueryDocumentSnapshot<Map<String, dynamic>>> txDocs =
        txSnapshot.data?.docs ??
        <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    final List<QueryDocumentSnapshot<Map<String, dynamic>>> splitDocs =
        splitSnapshot.data?.docs ??
        <QueryDocumentSnapshot<Map<String, dynamic>>>[];

    final Map<String, Map<String, dynamic>> splitByTxId =
        <String, Map<String, dynamic>>{};
    for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in splitDocs) {
      final Map<String, dynamic> data = doc.data();
      final String estId =
          ((data['establishmentId'] as String?) ??
                  (data['establishmentID'] as String?) ??
                  '')
              .trim();
      final String destAcc = ((data['destinationAccountId'] as String?) ?? '')
          .trim();

      if (estId == facilityId ||
          (facilityId.isNotEmpty && estId == facilityId) ||
          (ownerId.isNotEmpty && destAcc == ownerId)) {
        final String txId = ((data['transactionId'] as String?) ?? doc.id)
            .trim();
        if (txId.isNotEmpty) {
          splitByTxId[txId] = data;
        }
      }
    }

    final Map<String, _CommissionRecord> recordMap =
        <String, _CommissionRecord>{};

    for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in txDocs) {
      final Map<String, dynamic> data = doc.data();
      final String txEstId =
          ((data['establishmentId'] as String?) ??
                  (data['establishmentID'] as String?) ??
                  '')
              .trim();
      final String txOwnerId = ((data['ownerId'] as String?) ?? '').trim();

      final bool matchesFacility =
          (txEstId == facilityId) ||
          (facilityId.isNotEmpty && txEstId == facilityId) ||
          (ownerId.isNotEmpty && txOwnerId == ownerId);

      // Walk-ins carry no payment; they only affect slots.
      if (!matchesFacility || data['source'] == 'walk_in') {
        continue;
      }

      final String txId = doc.id;
      final Map<String, dynamic>? matchingSplit = splitByTxId[txId];

      double grossAmount = 0;
      double platformFee = 0;
      double netToOwner = 0;
      double refundPayback = 0;
      String status =
          ((data['status'] as String?) ??
                  (data['paymentStatus'] as String?) ??
                  'paid')
              .toUpperCase();
      DateTime? createdAt =
          _parseDateTime(data['createdAt']) ??
          _parseDateTime(data['createdAtClient']);
      String driverName = ((data['driverName'] as String?) ?? '').trim();
      if (driverName.isEmpty) {
        driverName = ((data['driverEmail'] as String?) ?? 'Driver').trim();
      }

      if (matchingSplit != null) {
        grossAmount =
            ((matchingSplit['grossAmountCentavos'] as num?) ?? 0) / 100;
        platformFee =
            ((matchingSplit['platformFeeCentavos'] as num?) ?? 0) / 100;
        netToOwner = ((matchingSplit['netToOwnerCentavos'] as num?) ?? 0) / 100;
        refundPayback =
            ((matchingSplit['refundRecoveryCentavos'] as num?) ?? 0) / 100;
        if (matchingSplit['status'] != null) {
          status = (matchingSplit['status'] as String).toUpperCase();
        }
        if (matchingSplit['createdAt'] != null) {
          createdAt = _parseDateTime(matchingSplit['createdAt']);
        }
      } else {
        final double amount = ((data['amount'] as num?) ?? 0).toDouble();
        final int grossCentavos =
            ((data['grossAmountCentavos'] as num?) ?? (amount * 100)).round();
        final int feeCentavos =
            ((data['platformFeeCentavos'] as num?) ??
                    platformFeeCentavosFor(
                      grossCentavos,
                      rate: saleCommissionRate(data),
                    ))
                .round();
        final int processorCentavos =
            ((data['estimatedProcessorFeeCentavos'] as num?) ??
                    estimateProcessorFeeCentavos(
                      grossAmountCentavos: grossCentavos,
                      paymentMethodApiType:
                          (data['paymentMethod'] as String?) ?? '',
                    ))
                .round();
        final int netCentavos = grossCentavos - feeCentavos - processorCentavos;

        grossAmount = grossCentavos / 100;
        platformFee = feeCentavos / 100;
        netToOwner = netCentavos / 100;
      }

      recordMap[txId] = _CommissionRecord(
        id: txId,
        driverName: driverName,
        grossAmount: grossAmount,
        platformFee: platformFee,
        netToOwner: netToOwner,
        status: status,
        refundPayback: refundPayback,
        createdAt: createdAt,
        overtimeHours: ((data['overtimeHours'] as num?) ?? 0).toInt(),
        overtimeAmount: ((data['overtimeAmount'] as num?) ?? 0).toDouble(),
        overtimeStatus: spOvertimeStatus(data),
        overtimeSettledAt: spOvertimeStatus(data) == kOvertimeCollected
            ? _parseDateTime(data['overtimeCollectedAt'])
            : null,
      );
    }

    for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in splitDocs) {
      final Map<String, dynamic> data = doc.data();
      final String estId =
          ((data['establishmentId'] as String?) ??
                  (data['establishmentID'] as String?) ??
                  '')
              .trim();
      final String destAcc = ((data['destinationAccountId'] as String?) ?? '')
          .trim();
      final bool matchesFacility =
          (estId == facilityId) ||
          (facilityId.isNotEmpty && estId == facilityId) ||
          (ownerId.isNotEmpty && destAcc == ownerId);

      if (!matchesFacility) {
        continue;
      }

      final String txId = ((data['transactionId'] as String?) ?? doc.id).trim();
      if (!recordMap.containsKey(txId)) {
        final double grossAmount =
            ((data['grossAmountCentavos'] as num?) ?? 0) / 100;
        final double platformFee =
            ((data['platformFeeCentavos'] as num?) ?? 0) / 100;
        final double netToOwner =
            ((data['netToOwnerCentavos'] as num?) ?? 0) / 100;
        final String status = ((data['status'] as String?) ?? 'paid')
            .toUpperCase();
        final DateTime? createdAt = _parseDateTime(data['createdAt']);
        // Extra hours bought on a ticket: its own sale, named after the
        // ticket's driver.
        final String ticketId = ((data['ticketId'] as String?) ?? '').trim();
        final int extraHours = ((data['hours'] as num?) ?? 0).toInt();
        String driverName = 'Driver';
        for (final QueryDocumentSnapshot<Map<String, dynamic>> t in txDocs) {
          if (t.id != ticketId) continue;
          final String name = ((t.data()['driverName'] as String?) ?? '')
              .trim();
          if (name.isNotEmpty) driverName = name;
        }
        if (data['kind'] == 'extra_hours' && extraHours > 0) {
          driverName =
              '$driverName · Extra $extraHours '
              'hr${extraHours == 1 ? '' : 's'}';
        }

        recordMap[txId] = _CommissionRecord(
          id: txId,
          driverName: driverName,
          grossAmount: grossAmount,
          platformFee: platformFee,
          netToOwner: netToOwner,
          status: status,
          createdAt: createdAt,
        );
      }
    }

    final List<_CommissionRecord> records = recordMap.values.toList();
    records.sort((_CommissionRecord a, _CommissionRecord b) {
      final DateTime aDate =
          a.lastActivityAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final DateTime bDate =
          b.lastActivityAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });

    final List<SalesEntry> entries = <SalesEntry>[
      ..._salesEntries(records, txDocs),
      ...gateCashSalesEntries(walkInLogs, handovers),
    ];
    DateTime? earliest;
    for (final SalesEntry e in entries) {
      if (earliest == null || e.at.isBefore(earliest)) earliest = e.at;
    }
    final FinanceRange range = _range;
    final SalesReport report = SalesReport.forRange(entries, range);
    final SalesReport previous = SalesReport.prior(entries, range);
    final SalesRow totals = report.totals;
    final SalesRow prior = previous.totals;
    // "+12.5% vs last month"; nothing when last month had none to compare.
    // While the period runs, "last month" means its same days.
    String? trend(int now, int before) {
      final double? r = salesChange(now, before);
      return r == null
          ? null
          : range.period == FinancePeriod.custom
          ? '${formatSalesChange(r)} vs previous ${range.days} days'
          : '${formatSalesChange(r)} vs last ${range.period.name}';
    }

    final int cashCollections = entries
        .where((SalesEntry e) => e.cashCentavos > 0 && range.contains(e.at))
        .length;

    // Cash still owed is a to-do, not a period figure: it counts every
    // unconfirmed exit, whenever it happened.
    final SpOvertimeCash owed = SpOvertimeCash.from(
      txDocs.map((QueryDocumentSnapshot<Map<String, dynamic>> d) => d.data()),
    );

    // Tickets paid in the period, or whose overtime cash was settled in it.
    final List<_CommissionRecord> periodRecords = <_CommissionRecord>[
      for (final _CommissionRecord r in records)
        if ((r.createdAt != null && range.contains(r.createdAt!)) ||
            (r.overtimeSettledAt != null &&
                range.contains(r.overtimeSettledAt!)))
          r,
    ];
    final bool isTablet = spIsTablet(context);
    final int limit = isTablet ? 12 : 6;
    final List<Widget> transactionCards = <Widget>[
      for (final _CommissionRecord record in periodRecords.take(limit))
        _TransactionCard(
          record: record,
          dateText: record.createdAt == null
              ? 'Date unavailable'
              : formatShortDate(record.createdAt!),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SpFinancePeriodBar(
          range: range,
          earliest: earliest,
          onChanged: (FinanceRange r) => setState(() => _range = r),
        ),
        const SizedBox(height: 12),
        SpStatRow(
          left: SpStatTile(
            icon: Icons.trending_up_rounded,
            color: spExitColor,
            label: 'Gross Sales',
            caption: 'Paid by drivers',
            value: formatSalesPeso(totals.grossCentavos),
            trend: trend(totals.grossCentavos, prior.grossCentavos),
            trendRatio: salesChange(totals.grossCentavos, prior.grossCentavos),
          ),
          right: SpStatTile(
            icon: Icons.account_balance_wallet_rounded,
            color: spEntryColor,
            label: 'Payout',
            caption: 'After fees (estimate)',
            value: formatSalesPeso(totals.payoutCentavos),
            trend: trend(totals.payoutCentavos, prior.payoutCentavos),
            trendRatio: salesChange(
              totals.payoutCentavos,
              prior.payoutCentavos,
            ),
          ),
        ),
        const SizedBox(height: 10),
        SpStatRow(
          left: SpStatTile(
            icon: Icons.percent_rounded,
            color: spInsideColor,
            label: 'Commission',
            // The rate now, and a scheduled change with its date.
            caption: () {
              final PlatformCommissionSettings c = platformCommission.value;
              final String pending = c.hasPending
                  ? ' · ${commissionPercent(c.pendingRate!)} from '
                        '${spFormatDate(c.pendingEffectiveAt!)}'
                  : '';
              return 'Rate: ${commissionPercent(c.currentRate)}$pending';
            }(),
            value: formatSalesPeso(totals.commissionCentavos),
            trend: trend(totals.commissionCentavos, prior.commissionCentavos),
            trendRatio: salesChange(
              totals.commissionCentavos,
              prior.commissionCentavos,
            ),
            trendNeutral: true,
          ),
          right: SpStatTile(
            icon: Icons.receipt_long_rounded,
            color: const Color(0xFF7C3AED),
            label: 'Transactions',
            caption: 'Paid in the app',
            value: '${totals.count}',
            trend: trend(totals.count, prior.count),
            trendRatio: salesChange(totals.count, prior.count),
          ),
        ),
        if (totals.cashCentavos > 0 || owed.dueCount > 0) ...[
          const SizedBox(height: 10),
          SpStatRow(
            left: SpStatTile(
              icon: Icons.payments_rounded,
              color: spEntryColor,
              label: 'Overtime Cash',
              caption: '$cashCollections collected at the gate',
              value: formatSalesPeso(totals.cashCentavos),
            ),
            right: SpStatTile(
              icon: Icons.pending_actions_rounded,
              color: owed.dueCount > 0 ? spInsideColor : AppTheme.textMuted,
              label: 'Uncollected',
              caption:
                  '${owed.dueCount} exit${owed.dueCount == 1 ? '' : 's'}, '
                  'any date',
              value: spPeso(owed.dueAmount),
            ),
          ),
        ],
        // Walk-in fees staff took in cash, and the facility's whole takings.
        if (totals.walkInCount > 0) ...[
          const SizedBox(height: 10),
          SpStatRow(
            left: SpStatTile(
              icon: Icons.directions_walk_rounded,
              color: spEntryColor,
              label: 'Walk-in Cash',
              caption:
                  '${totals.walkInCount} walk-in'
                  '${totals.walkInCount == 1 ? '' : 's'}, no commission',
              value: formatSalesPeso(totals.walkInCentavos),
            ),
            right: SpStatTile(
              icon: Icons.summarize_rounded,
              color: spExitColor,
              label: 'All Takings',
              caption: 'App sales + all gate cash',
              value: formatSalesPeso(totals.takingsCentavos),
            ),
          ),
        ],
        const SizedBox(height: 12),
        _buildSalesReport(report, previous),
        const SizedBox(height: 12),
        SpSectionCard(
          icon: Icons.receipt_long_rounded,
          title: 'Transactions',
          subtitle: salesReportPeriod(report),
          trailing: periodRecords.isEmpty
              ? null
              : SpChip(label: '${periodRecords.length}', color: spExitColor),
          child: periodRecords.isEmpty
              ? SpEmptyState(
                  boxed: false,
                  message: 'No transactions in ${range.label}.',
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (isTablet)
                      SpGrid(equalHeight: true, children: transactionCards)
                    else
                      ...transactionCards,
                    if (periodRecords.length > limit)
                      TextButton.icon(
                        onPressed: () => Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) => _OwnerTransactionsPage(
                              records: periodRecords,
                              periodLabel: salesReportPeriod(report),
                              formatShortDate: formatShortDate,
                            ),
                          ),
                        ),
                        icon: const Icon(Icons.open_in_new_rounded, size: 18),
                        label: Text(
                          'Show all ${periodRecords.length} transactions',
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

extension on _CommissionsListContentState {
  /// One entry per paid ticket, plus overtime cash on the day it was
  /// collected at the gate.
  List<SalesEntry> _salesEntries(
    List<_CommissionRecord> records,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> txDocs,
  ) {
    int centavos(double amount) => (amount * 100).round();
    return <SalesEntry>[
      for (final _CommissionRecord r in records)
        if (r.status == 'PAID' && r.createdAt != null)
          SalesEntry(
            at: r.createdAt!,
            grossCentavos: centavos(r.grossAmount),
            commissionCentavos: centavos(r.platformFee),
            // The report has no payback column yet, so it stays with
            // processing there and the columns still add up.
            processingCentavos: centavos(r.processingFee + r.refundPayback),
            payoutCentavos: centavos(r.netToOwner),
          ),
      for (final QueryDocumentSnapshot<Map<String, dynamic>> doc in txDocs)
        if (spOvertimeStatus(doc.data()) == kOvertimeCollected)
          // Older tickets were marked collected before the collection time
          // was saved; date those by the exit (or last update) instead, so
          // the report still adds up.
          if (_parseDateTime(doc.data()['overtimeCollectedAt']) ??
                  _parseDateTime(doc.data()['overtimeStatusAt']) ??
                  _parseDateTime(doc.data()['exitAt']) ??
                  _parseDateTime(doc.data()['updatedAt']) ??
                  _parseDateTime(doc.data()['createdAt'])
              case final DateTime collectedAt)
            SalesEntry(
              at: collectedAt,
              count: 0,
              cashCentavos: centavos(
                ((doc.data()['overtimeAmount'] as num?) ?? 0).toDouble(),
              ),
            ),
    ];
  }

  Widget _buildSalesReport(SalesReport report, SalesReport previous) {
    // Sign-up stores the display name as "First|Last".
    final User? user = FirebaseAuth.instance.currentUser;
    final String displayName = (user?.displayName ?? '')
        .replaceAll('|', ' ')
        .trim();
    final String preparedBy = displayName.isNotEmpty
        ? displayName
        : (user?.email ?? '');

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: cachedStream(
        'facility_doc_$facilityId',
        () => FirebaseFirestore.instance
            .collection('establishments')
            .doc(facilityId)
            .snapshots(),
      ),
      builder:
          (
            BuildContext context,
            AsyncSnapshot<DocumentSnapshot<Map<String, dynamic>>> snapshot,
          ) {
            final String name =
                ((snapshot.data?.data()?['name'] as String?) ?? '').trim();
            return SpSalesReportCard(
              report: report,
              previous: previous,
              audience: SalesReportAudience.owner,
              scopeLabel: name.isEmpty ? 'Your facility' : name,
              preparedBy: preparedBy,
            );
          },
    );
  }
}

class _TransactionCard extends StatelessWidget {
  const _TransactionCard({required this.record, required this.dateText});

  final _CommissionRecord record;
  final String dateText;

  Widget _line(String label, double amount, {bool strong = false}) {
    final TextStyle style = TextStyle(
      fontSize: 12,
      fontWeight: strong ? FontWeight.w800 : FontWeight.w500,
      color: strong ? AppTheme.textDark : AppTheme.textMuted,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(spPeso(amount), style: style),
        ],
      ),
    );
  }

  /// Overtime cash for the stay, which follows the ticket live: owed until
  /// staff (or the owner) confirm it as collected.
  Widget _overtimeLine() {
    final DateTime? settled = record.overtimeSettledAt;
    final (
      String label,
      Color color,
      Color fill,
      IconData icon,
    ) = switch (record.overtimeStatus) {
      kOvertimeCollected => (
        'Collected',
        spEntryColor,
        AppTheme.successSoft,
        Icons.check_circle_rounded,
      ),
      _ => (
        'Not collected',
        spInsideColor,
        AppTheme.warningSoft,
        Icons.pending_actions_rounded,
      ),
    };
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Amount on the title line, so the duration and status below get
          // the full width instead of wrapping beside it.
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Overtime cash',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textDark,
                  ),
                ),
              ),
              Text(
                spPeso(record.overtimeAmount),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.only(left: 24),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${formatParkingHours(record.overtimeHours)} · ',
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                  TextSpan(
                    text: settled == null
                        ? label
                        : '$label ${spFormatDate(settled)}, '
                              // Keeps "1:23 PM" on one line.
                              '${spFormatClockTime(settled).replaceAll(' ', ' ')}',
                    style: TextStyle(color: color),
                  ),
                ],
              ),
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool paid = record.status == 'PAID';
    final Color statusColor = paid ? spEntryColor : spInsideColor;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppTheme.radius),
            ),
            child: Icon(Icons.receipt_rounded, color: statusColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        spPeso(record.grossAmount),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textDark,
                        ),
                      ),
                    ),
                    SpChip(
                      label: _statusLabel(record.status),
                      color: statusColor,
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  record.driverName.isEmpty
                      ? dateText
                      : '${record.driverName} · $dateText',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                ),
                Padding(
                  padding: EdgeInsets.only(top: 8, bottom: 2),
                  child: Divider(height: 1, color: AppTheme.border),
                ),
                _line('Commission', record.platformFee),
                if (record.refundPayback > 0)
                  _line('Refund payback', record.refundPayback),
                _line('Processing (est.)', record.processingFee),
                _line('Payout (est.)', record.netToOwner, strong: true),
                if (record.hasOvertime) _overtimeLine(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Every transaction in the chosen period on its own page, opened from
/// "Show all" so the Reports tab stays short: where the money went, a
/// driver search, filters, and the sales grouped by day like a statement.
class _OwnerTransactionsPage extends StatefulWidget {
  const _OwnerTransactionsPage({
    required this.records,
    required this.periodLabel,
    required this.formatShortDate,
  });

  final List<_CommissionRecord> records;
  final String periodLabel;
  final String Function(DateTime) formatShortDate;

  @override
  State<_OwnerTransactionsPage> createState() => _OwnerTransactionsPageState();
}

enum _TxFilter { all, extraHours, overtime, cashDue }

class _OwnerTransactionsPageState extends State<_OwnerTransactionsPage> {
  static const int _pageSize = 15;

  _TxFilter _filter = _TxFilter.all;
  String _query = '';
  int _limit = _pageSize;
  final Set<String> _open = <String>{};

  bool _cashDue(_CommissionRecord r) =>
      r.hasOvertime && r.overtimeStatus != kOvertimeCollected;

  /// "Isaiah Calamba · Extra 4 hrs" -> ("Isaiah Calamba", "Extra 4 hrs").
  static (String, String) _nameAndKind(_CommissionRecord r) {
    final int dot = r.driverName.indexOf(' · ');
    if (dot < 0) {
      return (r.driverName.isEmpty ? 'Driver' : r.driverName, 'Ticket');
    }
    return (r.driverName.substring(0, dot), r.driverName.substring(dot + 3));
  }

  static bool _isExtra(_CommissionRecord r) =>
      _nameAndKind(r).$2.startsWith('Extra');

  void _setFilter(_TxFilter f) => setState(() {
    _filter = f;
    _limit = _pageSize;
  });

  @override
  Widget build(BuildContext context) {
    final List<_CommissionRecord> all = widget.records;
    final List<_CommissionRecord> paid = all
        .where((_CommissionRecord r) => r.status == 'PAID')
        .toList();
    double sum(double Function(_CommissionRecord) f) =>
        paid.fold<double>(0, (double t, _CommissionRecord r) => t + f(r));
    final double gross = sum((_CommissionRecord r) => r.grossAmount);
    final double commission = sum((_CommissionRecord r) => r.platformFee);
    final double processing = sum((_CommissionRecord r) => r.processingFee);
    final double payback = sum((_CommissionRecord r) => r.refundPayback);
    final double payout = sum((_CommissionRecord r) => r.netToOwner);

    final int extraCount = all.where(_isExtra).length;
    final int overtimeCount = all
        .where((_CommissionRecord r) => r.hasOvertime)
        .length;
    final int cashDueCount = all.where(_cashDue).length;
    final String q = _query.trim().toLowerCase();
    final List<_CommissionRecord> shown = all
        .where(
          (_CommissionRecord r) => switch (_filter) {
            _TxFilter.all => true,
            _TxFilter.extraHours => _isExtra(r),
            _TxFilter.overtime => r.hasOvertime,
            _TxFilter.cashDue => _cashDue(r),
          },
        )
        .where(
          (_CommissionRecord r) =>
              q.isEmpty || r.driverName.toLowerCase().contains(q),
        )
        .toList();

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        surfaceTintColor: Colors.transparent,
        title: const Text('Transactions'),
      ),
      body: DefaultTextStyle.merge(
        style: spTabularFigures,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              children: <Widget>[
                _hero(
                  count: paid.length,
                  gross: gross,
                  payout: payout,
                  commission: commission,
                  processing: processing,
                  payback: payback,
                ),
                const SizedBox(height: 16),
                _search(),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: <Widget>[
                      for (final (_TxFilter f, String label, int n)
                          in <(_TxFilter, String, int)>[
                            (_TxFilter.all, 'All', all.length),
                            (_TxFilter.extraHours, 'Extra hours', extraCount),
                            (
                              _TxFilter.overtime,
                              'With overtime',
                              overtimeCount,
                            ),
                            (
                              _TxFilter.cashDue,
                              'Cash not collected',
                              cashDueCount,
                            ),
                          ])
                        if (f == _TxFilter.all || n > 0)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text('$label · $n'),
                              selected: _filter == f,
                              showCheckmark: false,
                              onSelected: (_) => _setFilter(f),
                            ),
                          ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                if (shown.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: SpEmptyState(
                      icon: Icons.receipt_long_outlined,
                      message: q.isNotEmpty
                          ? 'No transactions from a driver matching "$_query".'
                          : 'No transactions match this filter.',
                    ),
                  )
                else ...<Widget>[
                  ..._days(shown.take(_limit).toList(), shown),
                  if (shown.length > _limit)
                    Center(
                      child: TextButton.icon(
                        onPressed: () => setState(() => _limit += _pageSize),
                        icon: const Icon(Icons.expand_more_rounded),
                        label: Text(
                          'Show ${shown.length - _limit < _pageSize ? shown.length - _limit : _pageSize} more '
                          '(${shown.length - _limit} left)',
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Gross sales up top, then a bar and legend of where it went.
  Widget _hero({
    required int count,
    required double gross,
    required double payout,
    required double commission,
    required double processing,
    double payback = 0,
  }) {
    final Color payoutColor = spEntryColor;
    final Color commissionColor = AppTheme.accentText;
    final Color processingColor = AppTheme.textMuted;
    int flex(double v) => (v * 100).round();
    Widget legend(Color color, String label, double value) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            spPeso(value),
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: AppTheme.textDark,
            ),
          ),
        ],
      ),
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[AppTheme.accentSoft, AppTheme.surface],
        ),
        borderRadius: BorderRadius.circular(AppTheme.radiusXLarge),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.calendar_month_rounded,
                size: 16,
                color: AppTheme.accentText,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  widget.periodLabel,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.accentText,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Gross sales',
            style: TextStyle(fontSize: 12.5, color: AppTheme.textMuted),
          ),
          Text(
            spPeso(gross),
            style: TextStyle(
              fontSize: 30,
              height: 1.15,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            <String>[
              '$count paid transaction${count == 1 ? '' : 's'}',
              if (count > 0) 'Avg. ${spPeso(gross / count)}',
            ].joinDots(),
            style: TextStyle(fontSize: 12.5, color: AppTheme.textSecondary),
          ),
          if (gross > 0) ...<Widget>[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: SizedBox(
                height: 10,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    if (payout > 0)
                      Expanded(
                        flex: flex(payout),
                        child: ColoredBox(color: payoutColor),
                      ),
                    if (commission > 0) ...<Widget>[
                      const SizedBox(width: 2),
                      Expanded(
                        flex: flex(commission),
                        child: ColoredBox(color: commissionColor),
                      ),
                    ],
                    if (processing > 0) ...<Widget>[
                      const SizedBox(width: 2),
                      Expanded(
                        flex: flex(processing),
                        child: ColoredBox(color: processingColor),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                legend(payoutColor, 'Your payout', payout),
                legend(commissionColor, 'Commission', commission),
                legend(processingColor, 'Processing', processing),
              ],
            ),
            if (payback > 0) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                '${spPeso(payback)} of your share paid back refunds you '
                'owe. See Refunds for the balance.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _search() => TextField(
    onChanged: (String v) => setState(() {
      _query = v;
      _limit = _pageSize;
    }),
    decoration: InputDecoration(
      prefixIcon: const Icon(Icons.search_rounded),
      hintText: 'Search by driver',
      isDense: true,
      filled: true,
      fillColor: AppTheme.surface,
      contentPadding: const EdgeInsets.symmetric(vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(99),
        borderSide: BorderSide(color: AppTheme.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(99),
        borderSide: BorderSide(color: AppTheme.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(99),
        borderSide: BorderSide(color: AppTheme.accentText, width: 1.5),
      ),
    ),
  );

  /// [page] grouped by day, newest first: a heading with the day's total
  /// (over every matching sale that day, not just this page), then one
  /// card holding that day's rows.
  List<Widget> _days(
    List<_CommissionRecord> page,
    List<_CommissionRecord> matching,
  ) {
    String keyOf(_CommissionRecord r) {
      final DateTime? d = r.createdAt;
      return d == null ? '' : '${d.year}-${d.month}-${d.day}';
    }

    final Map<String, double> dayTotals = <String, double>{};
    for (final _CommissionRecord r in matching) {
      if (r.status != 'PAID') continue;
      dayTotals[keyOf(r)] = (dayTotals[keyOf(r)] ?? 0) + r.grossAmount;
    }
    final List<Widget> out = <Widget>[];
    int i = 0;
    while (i < page.length) {
      final String key = keyOf(page[i]);
      final List<_CommissionRecord> day = <_CommissionRecord>[];
      while (i < page.length && keyOf(page[i]) == key) {
        day.add(page[i]);
        i++;
      }
      out.add(_dayHeading(day.first.createdAt, dayTotals[key] ?? 0));
      out.add(
        Container(
          margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(
            children: <Widget>[
              for (int j = 0; j < day.length; j++) ...<Widget>[
                if (j > 0)
                  Divider(height: 1, indent: 64, color: AppTheme.border),
                _row(day[j]),
              ],
            ],
          ),
        ),
      );
    }
    return out;
  }

  Widget _dayHeading(DateTime? d, double total) {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    String label;
    if (d == null) {
      label = 'Date unavailable';
    } else {
      final DateTime day = DateTime(d.year, d.month, d.day);
      final int ago = today.difference(day).inDays;
      label = ago == 0
          ? 'Today'
          : ago == 1
          ? 'Yesterday'
          : '${const <String>['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d.weekday - 1]}, '
                '${widget.formatShortDate(d)}';
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppTheme.textDark,
              ),
            ),
          ),
          if (total > 0)
            Text(
              spPeso(total),
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppTheme.textMuted,
              ),
            ),
        ],
      ),
    );
  }

  /// One sale: who, what and when on the left; the price and the payout on
  /// the right. Tapping opens the fee breakdown.
  Widget _row(_CommissionRecord r) {
    final (String name, String kind) = _nameAndKind(r);
    final bool extra = kind.startsWith('Extra');
    final bool paid = r.status == 'PAID';
    final bool open = _open.contains(r.id);
    final Color tint = extra ? spExitColor : AppTheme.accentText;
    final DateTime? at = r.createdAt;
    final TextStyle small = TextStyle(fontSize: 12, color: AppTheme.textMuted);

    Widget line(
      String label,
      double v, {
      bool strong = false,
      bool minus = false,
      Color? color,
    }) => Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: strong ? FontWeight.w800 : FontWeight.w500,
                color: strong ? AppTheme.textDark : AppTheme.textSecondary,
              ),
            ),
          ),
          Text(
            minus ? '− ${spPeso(v)}' : spPeso(v),
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
              color: color ?? AppTheme.textDark,
            ),
          ),
        ],
      ),
    );

    return InkWell(
      onTap: () => setState(() => open ? _open.remove(r.id) : _open.add(r.id)),
      borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: tint.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    extra
                        ? Icons.more_time_rounded
                        : Icons.confirmation_number_outlined,
                    size: 20,
                    color: tint,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textDark,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        <String>[
                          kind,
                          if (at != null) spFormatClockTime(at),
                        ].joinDots(),
                        style: small,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Text(
                      spPeso(r.grossAmount),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    paid
                        ? Text(
                            'You get ${spPeso(r.netToOwner)}',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: spEntryColor,
                            ),
                          )
                        : SpChip(
                            label: _statusLabel(r.status),
                            color: spInsideColor,
                          ),
                  ],
                ),
              ],
            ),
            if (r.hasOvertime)
              Padding(
                padding: const EdgeInsets.only(left: 52, top: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SpChip(
                    label:
                        '${spPeso(r.overtimeAmount)} overtime cash · '
                        '${r.overtimeStatus == kOvertimeCollected ? 'Collected' : 'Not collected'}',
                    color: r.overtimeStatus == kOvertimeCollected
                        ? spEntryColor
                        : spInsideColor,
                  ),
                ),
              ),
            if (open)
              Container(
                margin: const EdgeInsets.only(left: 52, top: 10),
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceAlt,
                  borderRadius: BorderRadius.circular(AppTheme.radius),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    line('Paid by the driver', r.grossAmount),
                    line(
                      'SmartPark commission',
                      r.platformFee,
                      minus: true,
                      color: AppTheme.textSecondary,
                    ),
                    if (r.refundPayback > 0)
                      line(
                        'Refund payback',
                        r.refundPayback,
                        minus: true,
                        color: AppTheme.textSecondary,
                      ),
                    line(
                      'PayMongo processing (est.)',
                      r.processingFee,
                      minus: true,
                      color: AppTheme.textSecondary,
                    ),
                    Divider(height: 14, color: AppTheme.border),
                    line(
                      'Your payout (est.)',
                      r.netToOwner,
                      strong: true,
                      color: spEntryColor,
                    ),
                    if (paid) ...<Widget>[
                      const SizedBox(height: 6),
                      Text(
                        <String>[
                          if (r.refundPayback > 0)
                            'Refund payback is part of your share that went '
                                'to a refund you owe.',
                          'PayMongo sends your payout to your bank, not '
                              'SmartPark. Its fee is an estimate, so what '
                              'arrives can differ slightly.',
                        ].join(' '),
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.35,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ],
                    if (r.hasOvertime) ...<Widget>[
                      Divider(height: 14, color: AppTheme.border),
                      line(
                        'Overtime cash, ${formatParkingHours(r.overtimeHours)}',
                        r.overtimeAmount,
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      <String>[
                        if (at != null)
                          '${widget.formatShortDate(at)}, ${spFormatClockTime(at)}',
                        'Ref ${r.id}',
                      ].joinDots(),
                      style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
