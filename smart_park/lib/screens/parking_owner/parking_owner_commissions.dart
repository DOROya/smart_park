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
    this.ticket,
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
  final Map<String, dynamic>? ticket;

  bool get canReportDriver =>
      ((ticket?['driverId'] as String?) ?? '').trim().isNotEmpty;

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
                    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      // The owner's own reports, one stream for every card.
                      stream: cachedStream(
                        'driver_reports_$_reporterId',
                        () => FirebaseFirestore.instance
                            .collection('driver_reports')
                            .where('reporterId', isEqualTo: _reporterId)
                            .snapshots(),
                      ),
                      builder: (BuildContext context, reportSnapshot) =>
                          _buildRecords(
                            context,
                            txSnapshot,
                            splitSnapshot,
                            reportSnapshot,
                          ),
                    );
                  },
            );
          },
    );
  }

  String get _reporterId => FirebaseAuth.instance.currentUser?.uid ?? ownerId;

  Widget _buildRecords(
    BuildContext context,
    AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> txSnapshot,
    AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> splitSnapshot,
    AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> reportSnapshot,
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
        ticket: data,
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

    final bool isTablet = spIsTablet(context);
    final Map<String, Map<String, dynamic>> reportsByTicket =
        <String, Map<String, dynamic>>{
          for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
              in reportSnapshot.data?.docs ??
                  <QueryDocumentSnapshot<Map<String, dynamic>>>[])
            ((doc.data()['transactionId'] as String?) ?? ''): doc.data(),
        };
    final List<Widget> transactionCards = <Widget>[
      for (final _CommissionRecord record in records.take(isTablet ? 24 : 12))
        _TransactionCard(
          record: record,
          dateText: record.createdAt == null
              ? 'Date unavailable'
              : formatShortDate(record.createdAt!),
          report: reportsByTicket[record.id],
        ),
    ];

    double totalCommission = 0;
    double totalPayout = 0;
    // Overtime is paid in cash at the gate, outside PayMongo,
    // so it has no commission and is tracked on the ticket.
    final SpOvertimeCash overtimeCash = SpOvertimeCash.from(
      txDocs.map((QueryDocumentSnapshot<Map<String, dynamic>> d) => d.data()),
    );

    for (final _CommissionRecord record in records) {
      totalCommission += record.platformFee;
      totalPayout += record.netToOwner;
    }

    return Column(
      children: [
        SpStatRow(
          left: SpStatTile(
            icon: Icons.account_balance_wallet_rounded,
            color: spEntryColor,
            label: 'Revenue',
            caption: 'Your payout',
            value: 'PHP ${totalPayout.toStringAsFixed(2)}',
          ),
          right: SpStatTile(
            icon: Icons.percent_rounded,
            color: spInsideColor,
            label: 'Commission',
            caption:
                '${(kPlatformFeeRate * 100).toStringAsFixed(0)}% SmartPark fee',
            value: 'PHP ${totalCommission.toStringAsFixed(2)}',
          ),
        ),
        if (!overtimeCash.isEmpty) ...[
          const SizedBox(height: 10),
          SpStatRow(
            left: SpStatTile(
              icon: Icons.payments_rounded,
              color: spEntryColor,
              label: 'Overtime Cash',
              caption: '${overtimeCash.collectedCount} collected at the gate',
              value: spPeso(overtimeCash.collectedAmount),
            ),
            right: SpStatTile(
              icon: Icons.pending_actions_rounded,
              color: overtimeCash.dueCount > 0
                  ? spInsideColor
                  : AppTheme.textMuted,
              label: 'Uncollected',
              caption:
                  '${overtimeCash.dueCount} exit${overtimeCash.dueCount == 1 ? '' : 's'} not confirmed',
              value: spPeso(overtimeCash.dueAmount),
            ),
          ),
        ],
        const SizedBox(height: 12),
        SpSectionCard(
          icon: Icons.receipt_long_rounded,
          title: 'Recent Transactions',
          trailing: records.isEmpty
              ? null
              : SpChip(label: '${records.length}', color: spExitColor),
          child: records.isEmpty
              ? const SpEmptyState(
                  boxed: false,
                  message: 'No transactions yet.',
                )
              : isTablet
              ? SpGrid(children: transactionCards)
              : Column(children: transactionCards),
        ),
      ],
    );
  }
}

class _TransactionCard extends StatelessWidget {
  const _TransactionCard({
    required this.record,
    required this.dateText,
    this.report,
  });

  final _CommissionRecord record;
  final String dateText;

  /// The owner's report on this ticket's driver, if they filed one.
  final Map<String, dynamic>? report;

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
          Text('PHP ${amount.toStringAsFixed(2)}', style: style),
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
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Overtime cash · ${formatParkingHours(record.overtimeHours)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textDark,
                  ),
                ),
                Text(
                  settled == null
                      ? label
                      : '$label ${spFormatDate(settled)}, '
                            '${spFormatClockTime(settled)}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
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
    );
  }

  /// Report the driver of this ticket, or where the owner's report stands.
  Widget _reportLine(BuildContext context) {
    final Map<String, dynamic>? existing = report;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: existing != null
          ? SpDriverReportChip(report: existing)
          : Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => showReportDriverDialog(
                  context,
                  ownerId: FirebaseAuth.instance.currentUser?.uid ?? '',
                  ticketId: record.id,
                  ticket: record.ticket!,
                ),
                icon: const Icon(Icons.flag_outlined, size: 16),
                label: const Text(
                  'Report driver',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.danger,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
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
                        'PHP ${record.grossAmount.toStringAsFixed(2)}',
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
                _line('Processing', record.processingFee),
                _line('Payout', record.netToOwner, strong: true),
                if (record.hasOvertime) _overtimeLine(),
                if (record.canReportDriver) _reportLine(context),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
