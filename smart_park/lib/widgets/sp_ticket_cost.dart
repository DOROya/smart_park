import 'package:flutter/material.dart';

import '../services/parking_pricing.dart' show kBaseStayHours;
import '../services/parking_receipt.dart' show ParkingReceipt;
import '../theme/app_theme.dart';
import 'smartpark_ui.dart' show spPeso;

/// The package name and what it covers, e.g. ("Extended", "4 hours total"
/// over "2 base + 2 extra").
(String, String) spPackageParts(ParkingReceipt t) {
  final int n = t.duration < 1 ? 1 : t.duration;
  String count(int value, String unit) =>
      '$value $unit${value == 1 ? '' : 's'}';
  return switch (t.plan) {
    'extended' => (
      'Extended',
      '${count(kBaseStayHours + n, 'hour')} total\n'
          '$kBaseStayHours base + $n extra',
    ),
    'daily' => ('Daily', count(n, 'day')),
    'weekly' => ('Weekly', count(n, 'week')),
    'monthly' => ('Monthly', count(n, 'month')),
    _ => ('Base', count(kBaseStayHours, 'hour')),
  };
}

/// Package on the left, amount on the right, each under a small label.
class SpTicketCost extends StatelessWidget {
  const SpTicketCost({
    super.key,
    required this.ticket,
    required this.amountLabel,
    this.amountNote = '',
  });

  final ParkingReceipt ticket;

  /// e.g. "DUE AT THE GATE".
  final String amountLabel;

  /// Under the amount, e.g. "Pay with GCash".
  final String amountNote;

  @override
  Widget build(BuildContext context) {
    final (String name, String detail) = spPackageParts(ticket);
    Widget label(String text) => Text(
      text,
      style: TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.6,
        color: AppTheme.textMuted,
      ),
    );
    Widget small(String text, {TextAlign align = TextAlign.start}) => Text(
      text,
      textAlign: align,
      style: TextStyle(
        fontSize: 12,
        height: 1.3,
        color: AppTheme.textSecondary,
        fontWeight: FontWeight.w600,
      ),
    );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(AppTheme.radius),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                label('PACKAGE'),
                const SizedBox(height: 4),
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textDark,
                  ),
                ),
                const SizedBox(height: 2),
                small(detail),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              label(amountLabel),
              const SizedBox(height: 4),
              Text(
                spPeso(ticket.amountCentavos / 100),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textDark,
                ),
              ),
              if (amountNote.isNotEmpty) ...<Widget>[
                const SizedBox(height: 2),
                small(amountNote, align: TextAlign.end),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
