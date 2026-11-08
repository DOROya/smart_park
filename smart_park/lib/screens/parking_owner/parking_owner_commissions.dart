part of 'package:smart_park/screens/parking_owner/parking_owner_home_screen.dart';

DateTime? _parseDateTime(dynamic value) {
  if (value == null) return null;
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  return null;
}

class _CommissionRecord {
  const _CommissionRecord({
    required this.id,
    required this.driverName,
    required this.grossAmount,
    required this.platformFee,
    required this.netToOwner,
    required this.status,
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

  /// PayMongo's (estimated) processing fee - whatever is left of the gross
  /// after SmartPark's commission and the owner's payout.
  double get processingFee => grossAmount - platformFee - netToOwner;
  final String status;
  final DateTime? createdAt;

  /// Overtime billed at the exit, paid in cash at the gate (outside
  /// PayMongo, so no commission). Zero when the stay had none.
  final int overtimeHours;
  final double overtimeAmount;

  /// The ticket's `overtimeStatus`: cash_due, collected or waived.
  final String overtimeStatus;

  /// When the overtime cash was collected or waived.
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

  /// Whether the transaction list shows past its first page.
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
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
                    return _buildRecords(context, txSnapshot, splitSnapshot);
                  },
            );
          },
    );
  }

  Widget _buildRecords(
    BuildContext context,
    AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> txSnapshot,
    AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> splitSnapshot,
  ) {
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
                    platformFeeCentavosFor(grossCentavos))
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
        createdAt: createdAt,
        overtimeHours: ((data['overtimeHours'] as num?) ?? 0).toInt(),
        overtimeAmount: ((data['overtimeAmount'] as num?) ?? 0).toDouble(),
        overtimeStatus: spOvertimeStatus(data),
        overtimeSettledAt:
            _parseDateTime(data['overtimeCollectedAt']) ??
            (spOvertimeStatus(data) == kOvertimeWaived
                ? _parseDateTime(data['overtimeStatusAt'])
                : null),
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

        recordMap[txId] = _CommissionRecord(
          id: txId,
          driverName: 'Driver',
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

    final List<SalesEntry> entries = _salesEntries(records, txDocs);
    DateTime? earliest;
    for (final SalesEntry e in entries) {
      if (earliest == null || e.at.isBefore(earliest)) earliest = e.at;
    }
    final FinanceRange range = _range;
    final SalesReport report = SalesReport.forRange(entries, range);
    final SalesRow totals = report.totals;
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
    final int limit = isTablet ? 24 : 12;
    final List<Widget> transactionCards = <Widget>[
      for (final _CommissionRecord record
          in _showAll ? periodRecords : periodRecords.take(limit))
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
          onChanged: (FinanceRange r) => setState(() {
            _range = r;
            _showAll = false;
          }),
        ),
        const SizedBox(height: 12),
        SpStatRow(
          left: SpStatTile(
            icon: Icons.trending_up_rounded,
            color: spExitColor,
            label: 'Gross Sales',
            caption: 'Paid by drivers',
            value: formatSalesPeso(totals.grossCentavos),
          ),
          right: SpStatTile(
            icon: Icons.account_balance_wallet_rounded,
            color: spEntryColor,
            label: 'Payout',
            caption: 'After fees (estimate)',
            value: formatSalesPeso(totals.payoutCentavos),
          ),
        ),
        const SizedBox(height: 10),
        SpStatRow(
          left: SpStatTile(
            icon: Icons.percent_rounded,
            color: spInsideColor,
            label: 'Commission',
            caption:
                '${(kPlatformFeeRate * 100).toStringAsFixed(0)}% SmartPark fee',
            value: formatSalesPeso(totals.commissionCentavos),
          ),
          right: SpStatTile(
            icon: Icons.receipt_long_rounded,
            color: const Color(0xFF7C3AED),
            label: 'Transactions',
            caption: 'Paid in the app',
            value: '${totals.count}',
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
        const SizedBox(height: 12),
        _buildSalesReport(report),
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
                    if (!_showAll && periodRecords.length > limit)
                      TextButton(
                        onPressed: () => setState(() => _showAll = true),
                        child: Text(
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
            processingCentavos: centavos(r.processingFee),
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

  Widget _buildSalesReport(SalesReport report) {
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
  /// staff (or the owner) confirm it, then collected or waived.
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
      kOvertimeWaived => (
        'Waived',
        AppTheme.textMuted,
        AppTheme.surface,
        Icons.money_off_rounded,
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
                  color: record.overtimeStatus == kOvertimeWaived
                      ? AppTheme.textMuted
                      : AppTheme.textDark,
                  decoration: record.overtimeStatus == kOvertimeWaived
                      ? TextDecoration.lineThrough
                      : null,
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
                              '${spFormatClockTime(settled)}',
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
                    SpChip(label: record.status, color: statusColor),
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
