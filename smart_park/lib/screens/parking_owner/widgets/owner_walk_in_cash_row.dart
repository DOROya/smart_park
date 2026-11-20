import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../services/gate_cash.dart';
import '../../../services/sales_report.dart';
import '../../../widgets/smartpark_ui.dart';

/// Walk-in fees taken at the gate in [range], beside everything the
/// facility took in: SmartPark sales, overtime cash and walk-in cash.
/// Walk-in cash never goes through SmartPark and carries no commission.
class OwnerWalkInCashRow extends StatefulWidget {
  const OwnerWalkInCashRow({
    super.key,
    required this.facilityId,
    required this.range,
    required this.appCentavos,
  });

  final String facilityId;
  final FinanceRange range;

  /// SmartPark sales plus overtime cash in [range], in centavos.
  final int appCentavos;

  @override
  State<OwnerWalkInCashRow> createState() => _OwnerWalkInCashRowState();
}

class _OwnerWalkInCashRowState extends State<OwnerWalkInCashRow> {
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _fees =
      gateCashQueries(widget.facilityId)[1].snapshots();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _fees,
      builder: (context, snapshot) {
        final ({int centavos, int count}) walkIn = walkInCashIn(
          (snapshot.data?.docs ??
                  <QueryDocumentSnapshot<Map<String, dynamic>>>[])
              .map((d) => d.data()),
          widget.range,
        );
        if (walkIn.count == 0) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: SpStatRow(
            left: SpStatTile(
              icon: Icons.directions_walk_rounded,
              color: spEntryColor,
              label: 'Walk-in Cash',
              caption:
                  '${walkIn.count} walk-in${walkIn.count == 1 ? '' : 's'}, '
                  'no commission',
              value: formatSalesPeso(walkIn.centavos),
            ),
            right: SpStatTile(
              icon: Icons.summarize_rounded,
              color: spExitColor,
              label: 'All Takings',
              caption: 'App sales + all gate cash',
              value: formatSalesPeso(widget.appCentavos + walkIn.centavos),
            ),
          ),
        );
      },
    );
  }
}

/// Walk-in fees whose exit falls in [range]: total centavos and how many.
({int centavos, int count}) walkInCashIn(
  Iterable<Map<String, dynamic>> logs,
  FinanceRange range,
) {
  int centavos = 0;
  int count = 0;
  for (final Map<String, dynamic> log in logs) {
    final double fee = walkInFeeOf(log);
    final DateTime? at = spParseDateTime(log['timestamp']);
    if (fee <= 0 || at == null || !range.contains(at)) continue;
    centavos += (fee * 100).round();
    count++;
  }
  return (centavos: centavos, count: count);
}
