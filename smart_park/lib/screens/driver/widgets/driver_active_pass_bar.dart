import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../../widgets/smartpark_ui.dart' show spPeso;

/// A temporary QR the driver can still use, for the Home shortcut.
typedef ActivePass = ({String id, Map<String, dynamic> data});

/// The usable temporary QRs among [passes]: being paid now first (staff
/// are waiting), then the newest. Expired ones are left out.
List<ActivePass> usablePasses(Iterable<ActivePass> passes, DateTime now) {
  bool usable(ActivePass p) {
    final String status = (p.data['status'] as String?) ?? '';
    if (status == 'pending') return true;
    if (status != 'awaiting_gate') return false;
    final Object? expires = p.data['expiresAt'];
    return expires is! Timestamp || now.isBefore(expires.toDate());
  }

  int created(ActivePass p) {
    final Object? t = p.data['createdAt'];
    return t is Timestamp ? t.millisecondsSinceEpoch : 0;
  }

  return passes.where(usable).toList()..sort((ActivePass a, ActivePass b) {
    final bool pa = a.data['status'] == 'pending';
    final bool pb = b.data['status'] == 'pending';
    if (pa != pb) return pa ? -1 : 1;
    return created(b).compareTo(created(a));
  });
}

/// Under the Home search bar: the driver's temporary QRs, one tap from the
/// gate, so nobody hunts through Tickets with staff waiting.
class DriverActivePassBar extends StatelessWidget {
  const DriverActivePassBar({
    super.key,
    required this.passes,
    required this.onOpen,
  });

  /// From [usablePasses].
  final List<ActivePass> passes;
  final ValueChanged<String> onOpen;

  static const int _shown = 2;

  @override
  Widget build(BuildContext context) {
    if (passes.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final ActivePass p in passes.take(_shown))
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _PassRow(pass: p, onTap: () => onOpen(p.id)),
          ),
        if (passes.length > _shown)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Text(
              '+${passes.length - _shown} more under Tickets',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    );
  }
}

class _PassRow extends StatelessWidget {
  const _PassRow({required this.pass, required this.onTap});

  final ActivePass pass;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic> d = pass.data;
    final bool paying = d['status'] == 'pending';
    final String facility = ((d['establishmentName'] as String?) ?? '').trim();
    final String plate = ((d['vehiclePlate'] as String?) ?? '').trim();
    final double amount = ((d['amount'] as num?) ?? 0).toDouble();
    final Color fill = paying ? AppTheme.accent : AppTheme.surface;
    final Color text = paying ? AppTheme.onAccent : AppTheme.textDark;
    return Material(
      color: fill,
      elevation: 4,
      shadowColor: const Color(0x33000000),
      borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          child: Row(
            children: <Widget>[
              Icon(
                paying ? Icons.payments_rounded : Icons.qr_code_2_rounded,
                color: text,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      paying
                          ? 'Staff confirmed space'
                          : (facility.isEmpty
                                ? 'Your temporary QR'
                                : 'Your QR · $facility'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: text,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      paying
                          ? 'Tap to confirm ${spPeso(amount)}'
                          : 'Show at the gate${plate.isEmpty ? '' : ' · $plate'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: text.withValues(alpha: 0.8),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: text),
            ],
          ),
        ),
      ),
    );
  }
}
