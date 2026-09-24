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
                    if (txSnapshot.hasError && splitSnapshot.hasError) {
                      return const SpEmptyState(
                        icon: Icons.error_outline_rounded,
                        message: 'Unable to load transactions right now.',
                      );
                    }

                    if (txSnapshot.connectionState == ConnectionState.waiting &&
                        splitSnapshot.connectionState ==
                            ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }

                    final List<QueryDocumentSnapshot<Map<String, dynamic>>>
                    txDocs =
                        txSnapshot.data?.docs ??
                        <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                    final List<QueryDocumentSnapshot<Map<String, dynamic>>>
                    splitDocs =
                        splitSnapshot.data?.docs ??
                        <QueryDocumentSnapshot<Map<String, dynamic>>>[];

                    final Map<String, Map<String, dynamic>> splitByTxId =
                        <String, Map<String, dynamic>>{};
                    for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
                        in splitDocs) {
                      final Map<String, dynamic> data = doc.data();
                      final String estId =
                          ((data['establishmentId'] as String?) ??
                                  (data['establishmentID'] as String?) ??
                                  '')
                              .trim();
                      final String destAcc =
                          ((data['destinationAccountId'] as String?) ?? '')
                              .trim();

                      if (estId == facilityId ||
                          (facilityId.isNotEmpty && estId == facilityId) ||
                          (ownerId.isNotEmpty && destAcc == ownerId)) {
                        final String txId =
                            ((data['transactionId'] as String?) ?? doc.id)
                                .trim();
                        if (txId.isNotEmpty) {
                          splitByTxId[txId] = data;
                        }
                      }
                    }

                    final Map<String, _CommissionRecord> recordMap =
                        <String, _CommissionRecord>{};

                    for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
                        in txDocs) {
                      final Map<String, dynamic> data = doc.data();
                      final String txEstId =
                          ((data['establishmentId'] as String?) ??
                                  (data['establishmentID'] as String?) ??
                                  '')
                              .trim();
                      final String txOwnerId =
                          ((data['ownerId'] as String?) ?? '').trim();

                      final bool matchesFacility =
                          (txEstId == facilityId) ||
                          (facilityId.isNotEmpty && txEstId == facilityId) ||
                          (ownerId.isNotEmpty && txOwnerId == ownerId);

                      // Walk-ins carry no payment; they only affect slots.
                      if (!matchesFacility || data['source'] == 'walk_in') {
                        continue;
                      }

                      final String txId = doc.id;
                      final Map<String, dynamic>? matchingSplit =
                          splitByTxId[txId];

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
                      String driverName =
                          ((data['driverName'] as String?) ?? '').trim();
                      if (driverName.isEmpty) {
                        driverName =
                            ((data['driverEmail'] as String?) ?? 'Driver')
                                .trim();
                      }

                      if (matchingSplit != null) {
                        grossAmount =
                            ((matchingSplit['grossAmountCentavos'] as num?) ??
                                0) /
                            100;
                        platformFee =
                            ((matchingSplit['platformFeeCentavos'] as num?) ??
                                0) /
                            100;
                        netToOwner =
                            ((matchingSplit['netToOwnerCentavos'] as num?) ??
                                0) /
                            100;
                        if (matchingSplit['status'] != null) {
                          status = (matchingSplit['status'] as String)
                              .toUpperCase();
                        }
                        if (matchingSplit['createdAt'] != null) {
                          createdAt = _parseDateTime(
                            matchingSplit['createdAt'],
                          );
                        }
                      } else {
                        final double amount = ((data['amount'] as num?) ?? 0)
                            .toDouble();
                        final int grossCentavos =
                            ((data['grossAmountCentavos'] as num?) ??
                                    (amount * 100))
                                .round();
                        final int feeCentavos =
                            ((data['platformFeeCentavos'] as num?) ??
                                    platformFeeCentavosFor(grossCentavos))
                                .round();
                        final int processorCentavos =
                            ((data['estimatedProcessorFeeCentavos'] as num?) ??
                                    estimateProcessorFeeCentavos(
                                      grossAmountCentavos: grossCentavos,
                                      paymentMethodApiType:
                                          (data['paymentMethod'] as String?) ??
                                          '',
                                    ))
                                .round();
                        final int netCentavos =
                            grossCentavos - feeCentavos - processorCentavos;

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
                      );
                    }

                    for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
                        in splitDocs) {
                      final Map<String, dynamic> data = doc.data();
                      final String estId =
                          ((data['establishmentId'] as String?) ??
                                  (data['establishmentID'] as String?) ??
                                  '')
                              .trim();
                      final String destAcc =
                          ((data['destinationAccountId'] as String?) ?? '')
                              .trim();
                      final bool matchesFacility =
                          (estId == facilityId) ||
                          (facilityId.isNotEmpty && estId == facilityId) ||
                          (ownerId.isNotEmpty && destAcc == ownerId);

                      if (!matchesFacility) {
                        continue;
                      }

                      final String txId =
                          ((data['transactionId'] as String?) ?? doc.id).trim();
                      if (!recordMap.containsKey(txId)) {
                        final double grossAmount =
                            ((data['grossAmountCentavos'] as num?) ?? 0) / 100;
                        final double platformFee =
                            ((data['platformFeeCentavos'] as num?) ?? 0) / 100;
                        final double netToOwner =
                            ((data['netToOwnerCentavos'] as num?) ?? 0) / 100;
                        final String status =
                            ((data['status'] as String?) ?? 'paid')
                                .toUpperCase();
                        final DateTime? createdAt = _parseDateTime(
                          data['createdAt'],
                        );

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

                    final List<_CommissionRecord> records = recordMap.values
                        .toList();
                    records.sort((_CommissionRecord a, _CommissionRecord b) {
                      final DateTime aDate =
                          a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
                      final DateTime bDate =
                          b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
                      return bDate.compareTo(aDate);
                    });

                    final bool isTablet = spIsTablet(context);
                    final List<Widget> transactionCards = <Widget>[
                      for (final _CommissionRecord record in records.take(
                        isTablet ? 24 : 12,
                      ))
                        _TransactionCard(
                          record: record,
                          dateText: record.createdAt == null
                              ? 'Date unavailable'
                              : formatShortDate(record.createdAt!),
                        ),
                    ];

                    double totalCommission = 0;
                    double totalPayout = 0;

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
                        const SizedBox(height: 12),
                        SpSectionCard(
                          icon: Icons.receipt_long_rounded,
                          title: 'Recent Transactions',
                          trailing: records.isEmpty
                              ? null
                              : SpChip(
                                  label: '${records.length}',
                                  color: spExitColor,
                                ),
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
                  },
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
          Text('PHP ${amount.toStringAsFixed(2)}', style: style),
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
        color: const Color(0xFFF8F9FC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8EAF0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
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
                        style: const TextStyle(
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
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textMuted,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 8, bottom: 2),
                  child: Divider(height: 1, color: Color(0xFFE8EAF0)),
                ),
                _line('Commission', record.platformFee),
                _line('Processing', record.processingFee),
                _line('Payout', record.netToOwner, strong: true),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
