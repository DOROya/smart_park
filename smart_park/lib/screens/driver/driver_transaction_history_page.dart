import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/driver_transactions.dart';
import '../../services/parking_refunds.dart';
import '../../services/sales_report.dart' show kSalesMonthNames;
import '../../theme/app_theme.dart';
import '../../widgets/smartpark_ui.dart';
import '../../widgets/sp_connection.dart';
import '../../widgets/sp_loading.dart';

/// Every payment the driver made (tickets, extra hours, overtime) and every
/// refund they got, opened from the Tickets tab.
class DriverTransactionHistoryPage extends StatefulWidget {
  const DriverTransactionHistoryPage({super.key});

  @override
  State<DriverTransactionHistoryPage> createState() =>
      _DriverTransactionHistoryPageState();
}

enum _Filter { all, payments, refunds }

class _DriverTransactionHistoryPageState
    extends State<DriverTransactionHistoryPage>
    with SpStreamCache<DriverTransactionHistoryPage> {
  _Filter _filter = _Filter.all;

  Stream<QuerySnapshot<Map<String, dynamic>>> _mine(String collection) {
    final String uid = FirebaseAuth.instance.currentUser?.uid ?? '-';
    return cachedStream(
      '${collection}_$uid',
      () => FirebaseFirestore.instance
          .collection(collection)
          .where('driverId', isEqualTo: uid)
          .snapshots(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: const Text('Transaction History'),
      ),
      body: SpPullToRefresh(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _mine('transactions'),
          builder: (BuildContext context, ticketSnap) =>
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _mine('payments'),
                builder: (BuildContext context, paymentSnap) =>
                    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _mine('refunds'),
                      builder: (BuildContext context, refundSnap) {
                        if (ticketSnap.hasError) {
                          return const SpEmptyState(
                            icon: Icons.error_outline_rounded,
                            message: 'Unable to load your transactions now.',
                          );
                        }
                        if (!ticketSnap.hasData) {
                          return const Padding(
                            padding: EdgeInsets.all(24),
                            child: SpSkeletonList(),
                          );
                        }
                        return _list(
                          driverTransactions(
                            tickets: <String, Map<String, dynamic>>{
                              for (final QueryDocumentSnapshot<
                                    Map<String, dynamic>
                                  >
                                  d
                                  in ticketSnap.data!.docs)
                                d.id: d.data(),
                            },
                            payments: <Map<String, dynamic>>[
                              for (final QueryDocumentSnapshot<
                                    Map<String, dynamic>
                                  >
                                  d
                                  in paymentSnap.data?.docs ??
                                      <
                                        QueryDocumentSnapshot<
                                          Map<String, dynamic>
                                        >
                                      >[])
                                d.data(),
                            ],
                            refunds: refundsByTicket(refundSnap.data).values,
                          ),
                        );
                      },
                    ),
              ),
        ),
      ),
    );
  }

  Widget _list(List<DriverTransaction> all) {
    final int paid = all
        .where((DriverTransaction t) => !t.isRefund)
        .fold<int>(0, (int s, DriverTransaction t) => s + t.amountCentavos);
    final int refunded = all
        .where((DriverTransaction t) => t.isRefund)
        .fold<int>(0, (int s, DriverTransaction t) => s + t.amountCentavos);
    final List<DriverTransaction> shown = all
        .where(
          (DriverTransaction t) => switch (_filter) {
            _Filter.all => true,
            _Filter.payments => !t.isRefund,
            _Filter.refunds => t.isRefund,
          },
        )
        .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: SpStatTile(
                icon: Icons.payments_outlined,
                color: AppTheme.accentText,
                label: 'Total paid',
                value: spPeso(paid / 100),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SpStatTile(
                icon: Icons.currency_exchange_rounded,
                color: spEntryColor,
                label: 'Refunded',
                value: spPeso(refunded / 100),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          children: <Widget>[
            for (final (_Filter f, String label) in <(_Filter, String)>[
              (_Filter.all, 'All'),
              (_Filter.payments, 'Payments'),
              (_Filter.refunds, 'Refunds'),
            ])
              ChoiceChip(
                label: Text(label),
                selected: _filter == f,
                onSelected: (_) => setState(() => _filter = f),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (shown.isEmpty)
          SpEmptyState(
            icon: Icons.receipt_long_outlined,
            message: switch (_filter) {
              _Filter.refunds => 'No refunds yet.',
              _ =>
                'No payments yet. They show up here once you pay for a '
                    'ticket.',
            },
          )
        else
          SpShowMore(
            key: ValueKey<_Filter>(_filter),
            pageSize: 15,
            children: _withMonthHeaders(shown),
          ),
      ],
    );
  }
}

/// One row per transaction (newest first), with a "November 2026" heading
/// on the first row of each month. The heading rides on its row so "Show
/// more" still counts transactions, not headings.
List<Widget> _withMonthHeaders(List<DriverTransaction> shown) {
  final List<Widget> rows = <Widget>[];
  String? month;
  for (final DriverTransaction t in shown) {
    final DateTime? at = t.at;
    final String? key = at == null
        ? null
        : '${kSalesMonthNames[at.month - 1]} ${at.year}';
    final bool newMonth = key != null && key != month;
    if (key != null) month = key;
    rows.add(
      newMonth
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: EdgeInsets.only(
                    top: rows.isEmpty ? 0 : 12,
                    bottom: 8,
                  ),
                  child: SpSectionLabel(key),
                ),
                _TransactionRow(t: t),
              ],
            )
          : _TransactionRow(t: t),
    );
  }
  return rows;
}

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({required this.t});

  final DriverTransaction t;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color) = switch (t.kind) {
      DriverTransactionKind.ticket => (
        Icons.confirmation_number_outlined,
        AppTheme.accentText,
      ),
      DriverTransactionKind.extraHours => (
        Icons.more_time_rounded,
        AppTheme.accentText,
      ),
      DriverTransactionKind.overtime => (Icons.timer_outlined, spInsideColor),
      DriverTransactionKind.refund => (
        Icons.currency_exchange_rounded,
        spEntryColor,
      ),
    };
    final DateTime? at = t.at;
    final TextStyle muted = TextStyle(fontSize: 12, color: AppTheme.textMuted);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(color: spCardBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppTheme.radius),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        t.title,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textDark,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${t.isRefund ? '+' : '-'}'
                      '${spPeso(t.amountCentavos / 100)}',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: t.isRefund ? spEntryColor : AppTheme.textDark,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  t.facilityName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary,
                  ),
                ),
                if (t.detail.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(t.detail, style: muted),
                ],
                const SizedBox(height: 2),
                Text(
                  '${at == null ? 'Date unavailable' : '${spFormatDate(at)}, ${spFormatClockTime(at)}'}'
                  ' · ${t.method}',
                  style: muted,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
