import 'package:flutter/material.dart';

import '../../services/gate_scan_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/sp_overtime.dart';
import '../../widgets/sp_vehicle_type.dart';

/// The outcome of the latest gate scan, under the scanner.
class GateResultCard extends StatelessWidget {
  const GateResultCard({
    super.key,
    required this.result,
    required this.onMarkCollected,
    this.marking = false,
    this.onWrongVehicle,
    this.refusing = false,
  });

  final GateScanResult result;
  final VoidCallback onMarkCollected;
  final bool marking;

  /// Turns away an admitted entry whose vehicle isn't the ticket's type.
  final VoidCallback? onWrongVehicle;
  final bool refusing;

  @override
  Widget build(BuildContext context) {
    final bool allowed = result.isAllowed;
    final Color accent = allowed ? AppTheme.success : AppTheme.danger;
    final Color bg = allowed ? AppTheme.successSoft : AppTheme.dangerSoft;
    final String title = allowed
        ? (result.scanType == 'exit' ? 'Exit allowed' : 'Entry allowed')
        : (result.decision == 'ERROR' ? 'Scan error' : 'Scan denied');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                allowed ? Icons.check_circle_rounded : Icons.cancel_rounded,
                color: accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: accent,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  result.decision,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: accent,
                  ),
                ),
              ),
            ],
          ),
          // Staff check the vehicle type against the car at the gate, so it
          // is the biggest thing on the card.
          if (result.vehicleType == null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              'Plate ${result.vehiclePlate} - ${result.scanType.toUpperCase()}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ] else ...<Widget>[
            // On its own line: beside the plate, "MOTORCYCLE" doesn't fit at
            // phone width.
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: SpVehicleTypeBadge(
                vehicleType: result.vehicleType,
                large: true,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: <Widget>[
                Text(
                  '${result.scanType.toUpperCase()} · PLATE  ',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    color: AppTheme.textMuted,
                  ),
                ),
                Flexible(
                  child: Text(
                    result.vehiclePlate,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                      color: AppTheme.textDark,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          if ((result.reason ?? '').isNotEmpty) ...<Widget>[
            const SizedBox(height: 4),
            Text(result.reason!),
          ],
          if (onWrongVehicle != null && result.canRefuseVehicle)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: refusing ? null : onWrongVehicle,
                style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
                icon: refusing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.block_rounded, size: 18),
                label: const Text(
                  'Wrong vehicle',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          if (result.scanType == 'exit' && result.elapsed != null) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              'Stay ${_formatStay(result.elapsed!)}'
              '${result.billableHours == null ? '' : ' - billed ${result.billableHours}h'}.',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
          if (result.hasOvertime) ...<Widget>[
            const SizedBox(height: 10),
            SpOvertimeBreakdown(
              overtimeHours: result.overtimeHours!.round(),
              amount: result.overtimeAmount!,
              elapsed: result.elapsed,
              rate: result.overtimeAmount! / result.overtimeHours!,
              status: result.overtimeCollected
                  ? kOvertimeCollected
                  : kOvertimeCashDue,
            ),
            if (!result.overtimeCollected) ...<Widget>[
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: marking ? null : onMarkCollected,
                icon: const Icon(Icons.check_rounded),
                label: Text(
                  marking
                      ? 'Saving...'
                      : 'Cash collected '
                            '(PHP ${result.overtimeAmount!.toStringAsFixed(2)})',
                ),
              ),
            ],
          ],
          if (result.transactionId != null &&
              result.transactionId!.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              'Ticket ${result.transactionId}',
              style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

String _formatStay(Duration elapsed) {
  final int hours = elapsed.inHours;
  final int minutes = elapsed.inMinutes.remainder(60);
  if (hours <= 0) {
    return '${minutes}m';
  }
  return '${hours}h ${minutes}m';
}
